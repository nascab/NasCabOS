import 'dart:async';
import 'package:get/get.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../../../utils/cache_manager.dart';
import '../cache/map_tile_cache.dart'
    if (dart.library.io) '../cache/map_tile_cache_io.dart'
    as map_tile_cache;
import '../models/photo_map_models.dart';
import '../service/photo_map_api_service.dart';
import '../utils/coordinate_transform.dart';

class PhotoFootprintMapController extends GetxController {
  final RxBool loading = false.obs;
  final RxString errorText = ''.obs;

  final Rx<PhotoMapZoomInfo?> zoomInfo = Rx<PhotoMapZoomInfo?>(null);
  final Rx<PhotoMapTileServer?> tileServer = Rx<PhotoMapTileServer?>(null);
  final RxList<PhotoMapTileServer> tileServerList = <PhotoMapTileServer>[].obs;

  final RxList<PhotoMapIndexItem> items = <PhotoMapIndexItem>[].obs;
  final Rx<LatLng> center = const LatLng(34.0, 108.0).obs;
  final RxDouble zoom = 5.0.obs;

  RxInt? mapRebuildSeed;

  Timer? _debounceTimer;
  fm.LatLngBounds? _lastFetchedBoundsWgs84;
  int? _lastFetchedZoom;
  Completer<void>? _boundsCancel;

  @override
  void onInit() {
    super.onInit();
    mapRebuildSeed ??= 0.obs;
    final cached = CacheManager().getJson(CacheKeys.photoFootprintMapState);
    if (cached is Map) {
      final lat = cached['lat'];
      final lng = cached['lng'];
      final z = cached['zoom'];
      if (lat is num && lng is num) {
        center.value = LatLng(lat.toDouble(), lng.toDouble());
      }
      if (z is num) {
        zoom.value = z.toDouble();
      }
    }
    initData();
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    _boundsCancel?.complete();
    _boundsCancel = null;
    super.onClose();
  }

  String get mapCoordinate =>
      (tileServer.value?.coordinate ?? 'WGS-84').toString();

  Future<void> initData() async {
    loading.value = true;
    errorText.value = '';
    try {
      final zoomRes = await PhotoMapApiService.instance.getZoom();
      if (zoomRes.success && zoomRes.data != null) {
        final (zi, ts) = zoomRes.data!;
        zoomInfo.value = zi;
        tileServer.value = ts;
        zoom.value = zoom.value.clamp(
          zi.minZoom.toDouble(),
          zi.maxZoom.toDouble(),
        );
      }

      final listRes = await PhotoMapApiService.instance.getTileServerList();
      if (listRes.success) {
        tileServerList.assignAll(listRes.data ?? <PhotoMapTileServer>[]);
      }
    } catch (e) {
      errorText.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  void onMapChanged({
    required fm.LatLngBounds bounds,
    required double zoomLevel,
    required LatLng mapCenter,
  }) {
    center.value = mapCenter;
    zoom.value = zoomLevel;

    // 立即取消当前进行中的 bounds 请求，避免 P2P 通道被上一批大响应占满导致卡死
    _boundsCancel?.complete();
    _boundsCancel = null;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 650), () {
      _boundsCancel = Completer<void>();
      final cancelFuture = _boundsCancel!.future;
      fetchBounds(bounds, zoomLevel, cancelFuture: cancelFuture);
      CacheManager().setJson(CacheKeys.photoFootprintMapState, {
        'lat': center.value.latitude,
        'lng': center.value.longitude,
        'zoom': zoom.value,
      });
    });
  }

  Future<void> fetchBounds(
    fm.LatLngBounds mapBounds,
    double zoomLevel, {
    Future<void>? cancelFuture,
  }) async {
    final coord = mapCoordinate;
    final swWgs = _toWgs84(mapBounds.southWest, coord);
    final neWgs = _toWgs84(mapBounds.northEast, coord);
    final b = fm.LatLngBounds(swWgs, neWgs);
    final zInt = zoomLevel.round();

    if (_lastFetchedBoundsWgs84 != null &&
        _lastFetchedZoom != null &&
        _boundsSimilar(_lastFetchedBoundsWgs84!, b) &&
        _lastFetchedZoom == zInt) {
      return;
    }

    try {
      final res = await PhotoMapApiService.instance.getBoundsPhoto(
        minLat: b.southWest.latitude,
        minLng: b.southWest.longitude,
        maxLat: b.northEast.latitude,
        maxLng: b.northEast.longitude,
        zoom: zoomLevel,
        cancelFuture: cancelFuture,
      );
      if (res.success) {
        _lastFetchedBoundsWgs84 = b;
        _lastFetchedZoom = zInt;
        items.assignAll(res.data ?? <PhotoMapIndexItem>[]);
      }
    } catch (e) {
      final s = e.toString();
      if (!s.contains('p2p_canceled') && !s.contains('cancel')) {
        errorText.value = s;
      }
    }
  }

  Future<void> refreshTileServerList() async {
    final res = await PhotoMapApiService.instance.getTileServerList();
    if (res.success) {
      tileServerList.assignAll(res.data ?? <PhotoMapTileServer>[]);
      final current = tileServerList.firstWhereOrNull((e) => e.isCurrent);
      if (current != null) {
        tileServer.value = current;
      }
    }
  }

  Future<bool> switchTileServer(PhotoMapTileServer server) async {
    final res = await PhotoMapApiService.instance.setTileServer(server);
    if (!res.success) return false;

    final zoomRes = await PhotoMapApiService.instance.getZoom();
    if (zoomRes.success && zoomRes.data != null) {
      final (zi, ts) = zoomRes.data!;
      zoomInfo.value = zi;
      tileServer.value = ts;
      zoom.value = zoom.value.clamp(
        zi.minZoom.toDouble(),
        zi.maxZoom.toDouble(),
      );
    }

    await refreshTileServerList();
    _lastFetchedBoundsWgs84 = null;
    _lastFetchedZoom = null;
    // 清空磁盘瓦片缓存，避免新旧瓦片混显
    await map_tile_cache.clearMapTileCache();
    mapRebuildSeed ??= 0.obs;
    mapRebuildSeed!.value += 1;
    return true;
  }

  LatLng markerPosition(PhotoMapIndexItem item) {
    final coord = mapCoordinate;
    final (lat, lng) = CoordinateTransform.toMapCoordinate(
      coord,
      item.latitude,
      item.longitude,
    );
    return LatLng(lat, lng);
  }

  LatLng _toWgs84(LatLng p, String coordinate) {
    final (lat, lng) = CoordinateTransform.fromMapCoordinate(
      coordinate,
      p.latitude,
      p.longitude,
    );
    return LatLng(lat, lng);
  }

  bool _boundsSimilar(fm.LatLngBounds a, fm.LatLngBounds b) {
    const eps = 0.0008;
    final da =
        (a.southWest.latitude - b.southWest.latitude).abs() +
        (a.southWest.longitude - b.southWest.longitude).abs() +
        (a.northEast.latitude - b.northEast.latitude).abs() +
        (a.northEast.longitude - b.northEast.longitude).abs();
    return da < eps;
  }
}
