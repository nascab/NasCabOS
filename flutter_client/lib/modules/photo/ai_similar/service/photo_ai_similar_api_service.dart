import '../../../../core/api/base_api_service.dart';
import '../models/ai_similar_models.dart';

class PhotoAiSimilarApiService extends BaseApiService {
  Future<ApiResponse<AiSimilarListResult>> listSimilarGroups({
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/similar/list',
      body: {'page': page, 'pageSize': pageSize},
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
      AiSimilarListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<int>> batchDeleteGroups(List<int> ids) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/similar/delete',
      body: {'ids': ids},
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
    final deleted = (data['deleted'] is int)
        ? data['deleted'] as int
        : int.tryParse('${data['deleted']}') ?? 0;
    return ApiResponse.success(
      deleted,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
