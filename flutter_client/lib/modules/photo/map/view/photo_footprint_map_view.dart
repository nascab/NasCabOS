import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/local_web_asset_server.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../timeline/controller/photo_timeline_controller.dart';
import '../../timeline/view/app_photo_timeline_view.dart';
import '../../timeline/view/pc_photo_timeline.dart';
import '../../timeline/view/parts/app_photo_timeline_multiselect_bar.dart';
import '../cache/cached_map_tile_provider.dart';
import '../controller/photo_footprint_map_controller.dart';
import '../models/photo_map_models.dart';
import '../service/photo_map_api_service.dart';

class PhotoFootprintMapView extends StatefulWidget {
  const PhotoFootprintMapView({super.key});

  @override
  State<PhotoFootprintMapView> createState() => _PhotoFootprintMapViewState();
}

class _PhotoFootprintMapViewState extends State<PhotoFootprintMapView> {
  MapController _mapController = MapController();
  bool _initialFetchTriggered = false;
  bool _mapReady = false;
  bool _nearbyTimelineVisible = false;
  String _nearbyTitle = '';
  String? _nearbyGeohash;
  int _nearbyTimelineSeed = 0;
  int _lastMapRebuildSeed = -1;
  Uri? _localProxyBase;
  bool _localProxyAcquired = false;

  @override
  void dispose() {
    if (_localProxyAcquired) {
      LocalWebAssetServer.instance.release();
      _localProxyAcquired = false;
    }
    _mapController.dispose();
    super.dispose();
  }

  double _markerSizeForCount(int count, double zoom) {
    const minSize = 35.0;
    var maxSize = 85.0;
    const minCountForMax = 5;
    const maxCountForMin = 200;
    if (zoom < 5.0) {
      maxSize = 40.0;
    }
    if (zoom < 7.0) {
      maxSize = 60.0;
    }
    if (zoom < 8.0) {
      maxSize = 70.0;
    }
    if (count <= minCountForMax) return maxSize;
    if (count >= maxCountForMin) return minSize;

    final t =
        (count - minCountForMax) / (maxCountForMin - minCountForMax).toDouble();
    return (maxSize + (minSize - maxSize) * t).clamp(minSize, maxSize);
  }

  void _scheduleInitialFetch(PhotoFootprintMapController ctrl) {
    if (_initialFetchTriggered || !_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialFetchTriggered || !_mapReady) return;
      _initialFetchTriggered = true;
      final camera = _mapController.camera;
      ctrl.onMapChanged(
        bounds: camera.visibleBounds,
        zoomLevel: camera.zoom,
        mapCenter: camera.center,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PhotoFootprintMapController>(
      init: PhotoFootprintMapController(),
      builder: (ctrl) {
        return Obx(() {
          final isMobile = DeviceUtils.isMobile;
          final zi = ctrl.zoomInfo.value;
          final token = ApiController.instance.accessToken ?? '';
          final baseUrl = ApiController.instance.baseUrl;
          final isP2p = ApiController.instance.isP2pMode;

          if (isP2p && !DeviceUtils.isWeb && _localProxyBase == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted || _localProxyBase != null) return;
              final base = await LocalWebAssetServer.instance.acquire();
              if (!mounted) return;
              setState(() {
                _localProxyBase = base;
                _localProxyAcquired = true;
              });
            });
          }
          if (!isP2p && !DeviceUtils.isWeb && _localProxyBase != null) {
            _localProxyAcquired = false;
            _localProxyBase = null;
          }

          final rebuildSeed = ctrl.mapRebuildSeed?.value ?? 0;
          if (_lastMapRebuildSeed != rebuildSeed) {
            _lastMapRebuildSeed = rebuildSeed;
            // 清空 Flutter 内存图片缓存，防止切换瓦片服务器后旧类型瓦片短暂显示
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            final old = _mapController;
            _mapController = MapController();
            _mapReady = false;
            _initialFetchTriggered = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              old.dispose();
            });
          }

          final tileBase = isP2p
              ? (DeviceUtils.isWeb
                    ? '/__p2p__'
                    : (_localProxyBase?.toString() ?? ''))
              : baseUrl;
          final urlTemplate = tileBase.isEmpty
              ? ''
              : (token.isNotEmpty
                    ? '$tileBase/api/mapApi/tile?zoom={z}&x={x}&y={y}&seed=$rebuildSeed&accessToken=${Uri.encodeComponent(token)}'
                    : '$tileBase/api/mapApi/tile?zoom={z}&x={x}&y={y}&seed=$rebuildSeed');

          final minZoom = zi?.minZoom.toDouble() ?? 3.0;
          final maxZoom = zi?.maxZoom.toDouble() ?? 18.0;
          final switchButtonTop = 10.0;

          _scheduleInitialFetch(ctrl);
          final customColors = Theme.of(context).extension<CustomColors>();

          return Stack(
            fit: StackFit.expand,
            children: [
              FlutterMap(
                key: ValueKey('photo_footprint_map_$rebuildSeed'),
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: ctrl.center.value,
                  initialZoom: ctrl.zoom.value,
                  initialRotation: 0,
                  minZoom: minZoom,
                  maxZoom: maxZoom,
                  interactionOptions: InteractionOptions(
                    flags: isMobile
                        ? (InteractiveFlag.all & ~InteractiveFlag.rotate)
                        : InteractiveFlag.all,
                  ),
                  onMapReady: () {
                    _mapReady = true;
                    _scheduleInitialFetch(ctrl);
                  },
                  onPositionChanged: (pos, _) {
                    final b = pos.visibleBounds;
                    final c = pos.center;
                    final z = pos.zoom;
                    ctrl.onMapChanged(bounds: b, zoomLevel: z, mapCenter: c);
                  },
                ),
                children: [
                  if (urlTemplate.isNotEmpty)
                    TileLayer(
                      urlTemplate: urlTemplate,
                      userAgentPackageName: 'NasCabOS',
                      tileProvider: isP2p && !DeviceUtils.isWeb
                          ? CachedNetworkTileProvider()
                          : null,
                      tileBuilder: (context, tileWidget, tile) {
                        return Container(
                          color: Colors.grey.shade300,
                          child: tileWidget,
                        );
                      },
                    ),
                  MarkerLayer(
                    markers: ctrl.items
                        .map((e) => _markerFor(context, ctrl, e))
                        .toList(),
                  ),
                ],
              ),
              Positioned(
                top: switchButtonTop,
                right: 12,
                child: isMobile
                    ? _FloatingSwitchMapButton(
                        onTap: () => _openSwitchMapDialog(context, ctrl),
                        text: 'photo_map_switch'.tr,
                      )
                    : SafeArea(
                        child: _FloatingSwitchMapButton(
                          onTap: () => _openSwitchMapDialog(context, ctrl),
                          text: 'photo_map_switch'.tr,
                        ),
                      ),
              ),
              Positioned(
                left: 12,
                bottom: 12,
                child: _InfoBadge(
                  text:
                      '${'zoom_level'.tr}: ${ctrl.zoom.value.toStringAsFixed(1)}',
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _MapZoomButtons(
                  mapController: _mapController,
                  currentZoom: ctrl.zoom.value,
                  minZoom: minZoom,
                  maxZoom: maxZoom,
                  onZoomChanged: () {
                    final camera = _mapController.camera;
                    ctrl.onMapChanged(
                      bounds: camera.visibleBounds,
                      zoomLevel: camera.zoom,
                      mapCenter: camera.center,
                    );
                  },
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 40,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (ctrl.loading.value)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (ctrl.errorText.value.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 56,
                  child: _InfoBadge(text: ctrl.errorText.value),
                ),
              if (_nearbyTimelineVisible)
                Positioned.fill(
                  child: Material(
                    color: customColors?.mainContentBgColor,
                    child: SafeArea(
                      child: Column(
                        children: [
                          Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Get.theme.dividerColor,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'back'.tr,
                                  onPressed: () {
                                    setState(() {
                                      _nearbyTimelineVisible = false;
                                    });
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                                Expanded(
                                  child: Text(
                                    "${'location'.tr}-${_nearbyTitle.isNotEmpty ? _nearbyTitle : 'photo_map_location'.tr}",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Get.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: PcPhotoTimelineView(
                              key: ValueKey(
                                'map_nearby_timeline_$_nearbyTimelineSeed',
                              ),
                              listType: 'timeline',
                              geohash: _nearbyGeohash,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        });
      },
    );
  }

  static const double _markerBorderWidth = 2.0;

  String _formatYearMonth(int timestampMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${d.year}/${d.month}';
  }

  Marker _markerFor(
    BuildContext context,
    PhotoFootprintMapController ctrl,
    PhotoMapIndexItem item,
  ) {
    final p = ctrl.markerPosition(item);
    final fullpath = item.fullpath ?? '';
    final imageUrl = fullpath.isNotEmpty
        ? ApiController.instance.getTinyUrl(fullpath)
        : '';
    final theme = Theme.of(context);
    final markerSize = _markerSizeForCount(ctrl.items.length, ctrl.zoom.value);
    final outerRadius = (markerSize * 0.2).clamp(6.0, 14.0);
    final innerRadius = (outerRadius - 2).clamp(4.0, 12.0);
    final fallbackIconSize = (markerSize * 0.35).clamp(16.0, 26.0);
    // 日期条高度和字体随 marker 大小变化
    final barHeight = (markerSize * 0.24).clamp(10.0, 18.0);
    final barFontSize = (markerSize * 0.16).clamp(8.0, 13.0);
    // 底部圆角与 marker 的 innerRadius 一致
    final barBottomRadius = innerRadius;
    final hasDate = item.originalTime != null;

    return Marker(
      width: markerSize,
      height: markerSize,
      point: p,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openMarkerDetail(context, item),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(outerRadius),
              border: Border.all(
                color: Colors.white,
                width: _markerBorderWidth,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageUrl.isNotEmpty
                      ? CustomExtendedImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: innerRadius,
                          showLoading: false,
                        )
                      : Container(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Icon(
                            Icons.photo,
                            size: fallbackIconSize,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                  if (hasDate)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(barBottomRadius),
                            bottomRight: Radius.circular(barBottomRadius),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _formatYearMonth(item.originalTime!),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: barFontSize,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMarkerDetail(
    BuildContext context,
    PhotoMapIndexItem item,
  ) async {
    final geoRes = await PhotoMapApiService.instance.getLocationStr(
      geohash: item.geohash,
    );
    final geoName = geoRes.success ? geoRes.data?.toString() ?? '' : null;
    if (!context.mounted) return;

    final title =
        "${'location'.tr}-${(geoName ?? '').isNotEmpty ? geoName : 'photo_map_location'.tr}";
    if (DeviceUtils.isMobile) {
      await Get.to(
        () => AppPhotoFootprintNearbyTimelinePage(
          title: title,
          geohash: item.geohash,
        ),
      );
      return;
    }

    setState(() {
      _nearbyTitle = geoName ?? '';
      _nearbyGeohash = item.geohash;
      _nearbyTimelineVisible = true;
      _nearbyTimelineSeed += 1;
    });
  }

  Future<void> _openSwitchMapDialog(
    BuildContext context,
    PhotoFootprintMapController ctrl,
  ) async {
    await ctrl.refreshTileServerList();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('photo_map_switch_title'.tr),
          content: SizedBox(
            width: 520,
            child: Obx(() {
              final list = ctrl.tileServerList;
              if (list.isEmpty) {
                return Center(child: Text('no_data'.tr));
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: list.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = list[i];
                  final title = s.name;
                  final sub =
                      '${s.coordinate}  ${'zoom_level'.tr}:${s.maxLevel}';
                  return ListTile(
                    title: Text(title),
                    subtitle: Text(sub),
                    trailing: s.isCurrent
                        ? Icon(
                            Icons.check,
                            color: Theme.of(ctx).colorScheme.primary,
                          )
                        : null,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final ok = await ctrl.switchTileServer(s);
                      if (!context.mounted) return;
                      if (ok) {
                        final camera = _mapController.camera;
                        ctrl.onMapChanged(
                          bounds: camera.visibleBounds,
                          zoomLevel: camera.zoom,
                          mapCenter: camera.center,
                        );
                      }
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('operation_failed'.tr)),
                        );
                      }
                    },
                  );
                },
              );
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('cancel'.tr),
            ),
          ],
        );
      },
    );
  }
}

class AppPhotoFootprintNearbyTimelinePage extends StatefulWidget {
  final String title;
  final String? geohash;
  const AppPhotoFootprintNearbyTimelinePage({
    super.key,
    required this.title,
    required this.geohash,
  });

  @override
  State<AppPhotoFootprintNearbyTimelinePage> createState() =>
      _AppPhotoFootprintNearbyTimelinePageState();
}

class _AppPhotoFootprintNearbyTimelinePageState
    extends State<AppPhotoFootprintNearbyTimelinePage> {
  late final String _timelineTag;

  @override
  void initState() {
    super.initState();
    _timelineTag =
        'app_photo_map_geo_${widget.geohash ?? 'unknown'}_${UniqueKey()}';
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PhotoTimelineController>(
      init: PhotoTimelineController(
        initialListType: 'timeline',
        initialGeohash: widget.geohash,
      ),
      tag: _timelineTag,
      dispose: (_) {
        Get.delete<PhotoTimelineController>(tag: _timelineTag);
      },
      builder: (_) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            leading: IconButton(
              tooltip: 'back'.tr,
              onPressed: () => Get.back(),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: AppPhotoTimelineView(
            controllerTag: _timelineTag,
            showSearchAction: true,
          ),
          bottomNavigationBar: AppPhotoTimelineMultiSelectBottomBar(
            controllerTag: _timelineTag,
          ),
        );
      },
    );
  }
}

class _FloatingSwitchMapButton extends StatelessWidget {
  final VoidCallback onTap;
  final String text;

  const _FloatingSwitchMapButton({required this.onTap, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.layers_outlined, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Text(text, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapZoomButtons extends StatelessWidget {
  final MapController mapController;
  final double currentZoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback onZoomChanged;

  const _MapZoomButtons({
    required this.mapController,
    required this.currentZoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canZoomIn = currentZoom < maxZoom;
    final canZoomOut = currentZoom > minZoom;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.remove, color: theme.colorScheme.onSurface),
              onPressed: canZoomOut
                  ? () {
                      final camera = mapController.camera;
                      final newZoom = (currentZoom - 1).clamp(minZoom, maxZoom);
                      mapController.move(camera.center, newZoom);
                      onZoomChanged();
                    }
                  : null,
              tooltip: 'zoom_out'.tr,
            ),
            IconButton(
              icon: Icon(Icons.add, color: theme.colorScheme.onSurface),
              onPressed: canZoomIn
                  ? () {
                      final camera = mapController.camera;
                      final newZoom = (currentZoom + 1).clamp(minZoom, maxZoom);
                      mapController.move(camera.center, newZoom);
                      onZoomChanged();
                    }
                  : null,
              tooltip: 'zoom_in'.tr,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;

  const _InfoBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}
