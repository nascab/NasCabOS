import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/photo_map_models.dart';

class PhotoMapApiService extends BaseApiService {
  static PhotoMapApiService get instance =>
      Get.isRegistered<PhotoMapApiService>()
      ? Get.find<PhotoMapApiService>()
      : PhotoMapApiService();

  Future<ApiResponse<(PhotoMapZoomInfo, PhotoMapTileServer)>> getZoom() async {
    final res = await apiGet<Map<String, dynamic>>(
      '/api/mapApi/getZoom',
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure'.tr,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? <String, dynamic>{};
    final zoomInfo = PhotoMapZoomInfo.fromJson(
      (data['zoomInfo'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
    final tileServer = PhotoMapTileServer.fromJson(
      (data['tileServer'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
    );
    return ApiResponse.success(
      (zoomInfo, tileServer),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<List<PhotoMapTileServer>>> getTileServerList() async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/mapApi/getTileServerList',
      body: {},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure'.tr,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? <String, dynamic>{};
    final list =
        (data['tileServerList'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .map(PhotoMapTileServer.fromJson)
            .toList() ??
        <PhotoMapTileServer>[];
    return ApiResponse.success(
      list,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> setTileServer(PhotoMapTileServer server) async {
    final res = await apiPost<dynamic>(
      '/api/mapApi/setTileServer',
      body: {'tileServer': server.toJson()},
      showLoading: true,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure'.tr,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  /// [cancelFuture] 若在请求完成前 complete，会取消请求并通知 P2P 后端，避免积压
  Future<ApiResponse<List<PhotoMapIndexItem>>> getBoundsPhoto({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    required double zoom,
    Future<void>? cancelFuture,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/mapApi/getBoundsPhoto',
      body: {
        'minLat': minLat,
        'minLng': minLng,
        'maxLat': maxLat,
        'maxLng': maxLng,
        'zoom': zoom,
      },
      showLoading: false,
      cancelFuture: cancelFuture,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure'.tr,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? <String, dynamic>{};
    final list =
        (data['mapPhoto'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .map(PhotoMapIndexItem.fromJson)
            .where((e) => e.id > 0)
            .toList() ??
        <PhotoMapIndexItem>[];
    return ApiResponse.success(
      list,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<String>> getLocationStr({
    String? geohash,
    int? indexId,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/mapApi/getLocationStr',
      body: {if (geohash != null) 'geohash': geohash},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure'.tr,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? <String, dynamic>{};
    final geo = data['geo'];
    return ApiResponse.success(
      geo,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
