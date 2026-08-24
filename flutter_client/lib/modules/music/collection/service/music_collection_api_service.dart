import '../../../../core/api/base_api_service.dart';
import '../models/music_collection_model.dart';

class MusicCollectionApiService extends BaseApiService {
  Future<ApiResponse<MusicCollectionListResult>> listCollections({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    String sortField = 'create_time',
    String sortOrder = 'desc',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/collection/list',
      body: {
        'page': page,
        'pageSize': pageSize,
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword': keyword.trim(),
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
      MusicCollectionListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<MusicCollectionItem>> getCollection(int id) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/collection/get',
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
      MusicCollectionItem.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<int>> createCollection({
    required String name,
    required List<String> pathList,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/collection/create',
      body: {'name': name, 'path_list': pathList},
      showLoading: true,
    );

    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    final data = res.data ?? <String, dynamic>{};
    final id = (data['id'] as num?)?.toInt() ?? 0;
    return ApiResponse.success(
      id,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> updateCollection({
    required int id,
    required String name,
    required List<String> pathList,
  }) async {
    final res = await apiPost<dynamic>(
      '/api/music/collection/update',
      body: {'id': id, 'name': name, 'path_list': pathList},
      showLoading: true,
    );

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
  }

  Future<ApiResponse<int>> deleteCollection(int id) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/collection/delete',
      body: {'id': id},
      showLoading: true,
    );

    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    final data = res.data ?? <String, dynamic>{};
    final affected = (data['affected'] as num?)?.toInt() ?? 0;

    return ApiResponse.success(
      affected,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
