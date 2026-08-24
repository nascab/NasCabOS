import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class VideoScrapeApiService extends BaseApiService {
  static VideoScrapeApiService get instance =>
      Get.isRegistered<VideoScrapeApiService>()
      ? Get.find<VideoScrapeApiService>()
      : VideoScrapeApiService();

  Future<ApiResponse<Map<String, dynamic>>> startScrape({
    required int indexId,
    int? tmdbId,
    String? mode,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/scrape/start',
      body: {
        'index_id': indexId,
        if (tmdbId != null && tmdbId > 0) 'tmdb_id': tmdbId,
        if (mode != null && mode.trim().isNotEmpty) 'mode': mode.trim(),
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> cleanupScrape({
    required int indexId,
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/scrape/cleanup',
      body: {'index_id': indexId},
      showLoading: showLoading,
    );
  }
}
