import '../../../../core/api/base_api_service.dart';
import '../models/app_photo_ai_models.dart';

class AppPhotoAiApiService extends BaseApiService {
  Future<ApiResponse<AppPhotoAiOverviewResult>> fetchOverview({
    int limit = 20,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/app_ai/overview',
      body: {'limit': limit <= 0 ? 20 : limit},
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
      AppPhotoAiOverviewResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
