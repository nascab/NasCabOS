import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class VideoTmdbSettingsApiService extends BaseApiService {
  static VideoTmdbSettingsApiService get instance =>
      Get.isRegistered<VideoTmdbSettingsApiService>()
      ? Get.find<VideoTmdbSettingsApiService>()
      : VideoTmdbSettingsApiService();

  Future<ApiResponse<Map<String, dynamic>>> getTmdbConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getTmdbConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setTmdbConfig({
    required String accessToken,
    required bool proxyEnable,
    required String proxyUrl,
    required String language,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setTmdbConfig',
      body: {
        'accessToken': accessToken,
        'proxyEnable': proxyEnable ? 1 : 0,
        'proxyUrl': proxyUrl,
        'language': language,
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getTranscodeConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getTranscodeConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getSubtitleConfig({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/getSubtitleConfig',
      body: {},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setSubtitleConfig({
    required bool preExtractEnable,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setSubtitleConfig',
      body: {
        'preExtractEnable': preExtractEnable ? 1 : 0,
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setTranscodeConfig({
    required String tempDir,
    required String preferredHwDecoder,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/setTranscodeConfig',
      body: {
        'tempDir': tempDir,
        'preferredHwDecoder': preferredHwDecoder,
      },
      showLoading: showLoading,
    );
  }
}
