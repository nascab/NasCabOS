import '../../../../core/api/base_api_service.dart';
import '../models/ai_scenes_models.dart';

class PhotoAiScenesApiService extends BaseApiService {
  Future<ApiResponse<AiSceneListResult>> listScenes({
    String status = 'visible',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/place/list',
      body: {'status': status},
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
      AiSceneListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> setSceneStatus({
    required String placeName,
    required bool isHide,
  }) async {
    final res = await apiPost<dynamic>(
      '/api/photo/place/status/set',
      body: {'place_name': placeName, 'is_hide': isHide},
      showLoading: false,
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

  Future<ApiResponse<bool>> resetScenes() async {
    final res = await apiPost<dynamic>(
      '/api/photo/place/reset',
      body: {},
      showLoading: false,
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
}
