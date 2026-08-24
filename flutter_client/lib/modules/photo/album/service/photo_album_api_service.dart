import '../../../../core/api/base_api_service.dart';
import '../models/photo_album_model.dart';
import '../models/photo_album_overview_model.dart';

class PhotoAlbumApiService extends BaseApiService {
  Future<ApiResponse<PhotoAlbumListResult>> listAlbums({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    String type = 'all',
    String sortField = 'create_time',
    String sortOrder = 'desc',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/album/list',
      body: {
        'page': page,
        'pageSize': pageSize,
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword': keyword.trim(),
        if (type.isNotEmpty) 'type': type,
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
      PhotoAlbumListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<PhotoAlbumOverviewResult>> getAlbumOverview({
    int limit = 6,
  }) async {
    final safeLimit = limit.clamp(1, 12);
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/album/overview',
      body: {'limit': safeLimit},
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
      PhotoAlbumOverviewResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<PhotoAlbumDetail>> getAlbum(int id) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/album/get',
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
      PhotoAlbumDetail.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createAlbum({
    required String name,
    bool isPublic = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/album/create',
      body: {'name': name, 'is_public': isPublic ? 1 : 0, 'shares': []},
      showLoading: true,
    );
  }

  Future<ApiResponse<bool>> updateAlbum({
    required int id,
    String? name,
    bool? isPublic,
    List<Map<String, dynamic>>? shares,
  }) {
    final body = <String, dynamic>{
      'id': id,
      if (name != null) 'name': name,
      if (isPublic != null) 'is_public': isPublic ? 1 : 0,
      if (shares != null) 'shares': shares,
    };
    return apiPost<dynamic>(
      '/api/photo/album/update',
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

  Future<ApiResponse<Map<String, dynamic>>> deleteAlbum(int id) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/album/delete',
      body: {'id': id},
      showLoading: true,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> addAlbumIndexes({
    required int albumId,
    required List<String> fileHashes,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/album/index/add',
      body: {'album_id': albumId, 'file_hashes': fileHashes},
      showLoading: true,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> removeAlbumIndexes({
    required int albumId,
    required List<String> fileHashes,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/album/index/remove',
      body: {'album_id': albumId, 'file_hashes': fileHashes},
      showLoading: true,
    );
  }

  Future<ApiResponse<bool>> setAlbumCover({
    required int albumId,
    required String fileHash,
  }) {
    return apiPost<bool>(
      '/api/photo/album/cover/set',
      body: {'album_id': albumId, 'file_hash': fileHash},
      showLoading: true,
    );
  }
}
