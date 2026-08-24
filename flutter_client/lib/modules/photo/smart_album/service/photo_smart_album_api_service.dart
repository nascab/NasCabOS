import '../../../../core/api/base_api_service.dart';
import '../models/photo_smart_album_model.dart';

class PhotoSmartAlbumApiService extends BaseApiService {
  Future<ApiResponse<PhotoSmartAlbumListResult>> listSmartAlbums({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    String type = 'all',
    String sortField = 'create_time',
    String sortOrder = 'desc',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/smart_album/list',
      body: {
        'page': page,
        'pageSize': pageSize,
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword': keyword.trim(),
        if (type.isNotEmpty && type != 'all') 'type': type,
        'sortField': sortField,
        'sortOrder': sortOrder,
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
      PhotoSmartAlbumListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<PhotoSmartAlbumDetail>> getSmartAlbum(int id) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/smart_album/get',
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
      PhotoSmartAlbumDetail.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createSmartAlbum({
    required String name,
    required String type,
    required Map<String, dynamic> filterContent,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/smart_album/create',
      body: {'name': name, 'type': type, 'filter_content': filterContent},
      showLoading: true,
    );
  }

  Future<ApiResponse<bool>> updateSmartAlbum({
    required int id,
    String? name,
    String? type,
    Map<String, dynamic>? filterContent,
  }) {
    final body = <String, dynamic>{
      'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (filterContent != null) 'filter_content': filterContent,
    };
    return apiPost<dynamic>(
      '/api/photo/smart_album/update',
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
      '/api/photo/smart_album/delete',
      body: {'id': id},
      showLoading: true,
    );
  }
}
