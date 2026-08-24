import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/video_source.dart';

class VideoSourceApiService extends BaseApiService {
  static VideoSourceApiService get instance =>
      Get.isRegistered<VideoSourceApiService>()
      ? Get.find<VideoSourceApiService>()
      : VideoSourceApiService();

  Future<List<VideoSource>> listSources({bool showLoading = false}) async {
    final res = await apiPost<List<dynamic>>(
      '/api/video/source/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return <VideoSource>[];

    final raw = res.data ?? <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => VideoSource.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ApiResponse<Map<String, dynamic>>> addSource(
    String path, {
    required String mediaType,
    required int matchNfo,
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/add',
      body: {'path': path, 'media_type': mediaType, 'match_nfo': matchNfo},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateSource(
    int id,
    Map<String, dynamic> payload, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/update/$id',
      body: payload,
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateMediaType(
    int id,
    String mediaType, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/media_type/$id',
      body: {'media_type': mediaType},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateMatchNfo(
    int id,
    int matchNfo, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/match_nfo/$id',
      body: {'match_nfo': matchNfo},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSource(
    int id, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/delete',
      body: {'id': id},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> relocateSource(
    int id,
    String newPath, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/relocate/$id',
      body: {'new_path': newPath},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> scanSource(
    String path, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/scan',
      body: {'path': path},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> scanIndex(
    int indexId, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/source/scan_index',
      body: {'index_id': indexId},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> preGenerateThumbnails({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/source/regenerate_thumbnails',
      body: {},
      showLoading: showLoading,
    );
  }
}
