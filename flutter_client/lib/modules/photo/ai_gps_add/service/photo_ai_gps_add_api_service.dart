import '../../../../core/api/base_api_service.dart';
import '../models/ai_gps_add_models.dart';

class PhotoAiGpsAddApiService extends BaseApiService {
  Future<ApiResponse<AiGpsAddStatus>> getStatus() async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/gps_add/status',
      body: const {},
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
      AiGpsAddStatus.fromJson(res.data ?? const <String, dynamic>{}),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<AiGpsAddStatus>> startScan() async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/gps_add/start_scan',
      body: const {},
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
      AiGpsAddStatus.fromJson(res.data ?? const <String, dynamic>{}),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<int>> applyGps({
    required int batchId,
    required double latitude,
    required double longitude,
    List<int> photoIds = const [],
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/gps_add/apply',
      body: {
        'batchId': batchId,
        'latitude': latitude,
        'longitude': longitude,
        'photoIds': photoIds,
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

    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse.success(
      int.tryParse('${data['affected']}') ?? 0,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> skipBatch({required int batchId}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/gps_add/skip',
      body: {'batchId': batchId},
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

  Future<ApiResponse<AiGpsAddStatus>> resetAndRescan() async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/gps_add/reset',
      body: const {},
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
      AiGpsAddStatus.fromJson(res.data ?? const <String, dynamic>{}),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
