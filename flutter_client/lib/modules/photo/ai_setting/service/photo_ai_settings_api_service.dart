import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class PhotoAiSettingsApiService extends BaseApiService {
  static PhotoAiSettingsApiService get instance =>
      Get.isRegistered<PhotoAiSettingsApiService>()
      ? Get.find<PhotoAiSettingsApiService>()
      : PhotoAiSettingsApiService();

  Future<ApiResponse<Map<String, dynamic>>> getAiConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/getAiConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiOcrEnable(
    bool enable, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiOcrEnable',
      body: {'enable': enable ? 1 : 0},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiPetEnable(
    bool enable, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiPetEnable',
      body: {'enable': enable ? 1 : 0},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiFaceEnable(
    bool enable, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiFaceEnable',
      body: {'enable': enable ? 1 : 0},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiPlaceEnable(
    bool enable, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiPlaceEnable',
      body: {'enable': enable ? 1 : 0},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiSimilarEnable(
    bool enable, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiSimilarEnable',
      body: {'enable': enable ? 1 : 0},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiGpuPrefer(
    bool enable, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiGpuPrefer',
      body: {'enable': enable ? 1 : 0},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> resetSimilar({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/similar/reset',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAiFaceMinShowCount(
    int minShowCount, {
    bool showLoading = false,
  }) {
    final v = minShowCount < 0 ? 0 : minShowCount;
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setAiFaceMinShowCount',
      body: {'min_show_count': v},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getPreviewConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/getPreviewConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setPreviewSize(
    String size, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/setPreviewSize',
      body: {'size': size},
      showLoading: showLoading,
    );
  }
}
