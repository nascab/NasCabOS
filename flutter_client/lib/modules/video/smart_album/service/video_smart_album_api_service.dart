import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/video_smart_album_model.dart';

class VideoSmartAlbumApiService extends BaseApiService {
  static VideoSmartAlbumApiService get instance =>
      Get.isRegistered<VideoSmartAlbumApiService>()
      ? Get.find<VideoSmartAlbumApiService>()
      : VideoSmartAlbumApiService();

  Future<ApiResponse<VideoSmartAlbumListResult>> listSmartAlbums({
    required int page,
    required int pageSize,
    String? keyword,
    String? sortField,
    String? sortOrder,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/smart_album/list',
      body: {
        'page': page,
        'pageSize': pageSize,
        if (keyword != null) 'keyword': keyword,
        if (sortField != null) 'sortField': sortField,
        if (sortOrder != null) 'sortOrder': sortOrder,
      },
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(
      VideoSmartAlbumListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<VideoSmartAlbumDetail>> getSmartAlbum(int id) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/smart_album/get',
      body: {'id': id},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(
      VideoSmartAlbumDetail.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createSmartAlbum({
    required String name,
    required Map<String, dynamic> filterContent,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/smart_album/create',
      body: {
        'name': name,
        'type': 'condition',
        'filter_content': filterContent,
      },
      showLoading: true,
    );
  }

  Future<ApiResponse<bool>> updateSmartAlbum({
    required int id,
    required String name,
    required Map<String, dynamic> filterContent,
  }) {
    final body = <String, dynamic>{
      'id': id,
      'name': name,
      'type': 'condition',
      'filter_content': filterContent,
    };
    return apiPost<dynamic>(
      '/api/video/smart_album/update',
      body: body,
      showLoading: true,
    ).then((res) {
      if (!res.success) {
        return ApiResponse.failure(
          res.message ?? 'network_failure',
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
    });
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSmartAlbum(int id) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/smart_album/delete',
      body: {'id': id},
      showLoading: true,
    );
  }
}
