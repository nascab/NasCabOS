import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../../../core/api/api_controller.dart';

class VideoDetailApiService extends BaseApiService {
  static VideoDetailApiService get instance =>
      Get.isRegistered<VideoDetailApiService>()
      ? Get.find<VideoDetailApiService>()
      : VideoDetailApiService();

  Future<ApiResponse<Map<String, dynamic>>> getDetail(
    int indexId, {
    bool showLoading = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/video/detail',
      queryParams: {'index_id': indexId.toString()},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getEpisodes(
    int indexId, {
    int page = 1,
    int pageSize = 50,
    String sortOrder = 'asc',
    bool showLoading = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/video/episodes',
      queryParams: {
        'index_id': indexId.toString(),
        'page': page.toString(),
        'page_size': pageSize.toString(),
        'sort_order': sortOrder,
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getTvPlayInfo(
    int indexId, {
    bool showLoading = false,
    String loadingMsg = '',
  }) {
    if (loadingMsg.isEmpty) {
      loadingMsg = 'loading_episodes'.tr;
    }
    return apiGet<Map<String, dynamic>>(
      '/api/video/tvPlayInfo',
      queryParams: {'index_id': indexId.toString()},
      showLoading: showLoading,
      loadingMsg: loadingMsg,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setOpenSkip(
    int indexId, {
    required int openSkipStartSec,
    required int openSkipEndSec,
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/detail/open_skip/set',
      body: {
        'index_id': indexId,
        'open_skip_start_sec': openSkipStartSec,
        'open_skip_end_sec': openSkipEndSec,
      },
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getDiscContents(
    int indexId, {
    bool showLoading = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/video/discContents',
      queryParams: {'index_id': indexId.toString()},
      showLoading: showLoading,
    );
  }

  String getDiscContentThumbUrl({
    required int indexId,
    required String internalPath,
    int size = 320,
  }) {
    final api = ApiController.instance;
    final params = <String, String>{
      'index_id': indexId.toString(),
      'internal_path': internalPath,
      'size': size.toString(),
    };
    final token = (api.accessToken ?? '').trim();
    if (token.isNotEmpty) {
      params['accessToken'] = token;
    }
    final uri = Uri.parse('${api.baseUrl}/api/video/discContents/thumb').replace(
      queryParameters: params,
    );
    return uri.toString();
  }
}
