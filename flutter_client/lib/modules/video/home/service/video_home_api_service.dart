import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../base/beans/video_item_bean.dart';

class VideoHomeApiService extends BaseApiService {
  static VideoHomeApiService get instance =>
      Get.isRegistered<VideoHomeApiService>()
      ? Get.find<VideoHomeApiService>()
      : VideoHomeApiService();

  Future<ApiResponse<VideoHomeData>> getHomeData({
    int recommendLimit = 11,
    int recentPlayLimit = 20,
    int recentAddLimit = 20,
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/home/data',
      body: {
        'recommend_limit': recommendLimit,
        'recent_play_limit': recentPlayLimit,
        'recent_add_limit': recentAddLimit,
      },
      showLoading: showLoading,
    );

    if (!res.success) {
      return ApiResponse.failure(res.message ?? 'request_failed');
    }
    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(VideoHomeData.fromJson(data));
  }
}

class VideoHomeData {
  final List<Map<String, dynamic>> sourceList;
  final List<VideoHomeItemBean> recommend;
  final List<VideoHomeItemBean> recentPlay;
  final List<VideoHomeItemBean> recentAddMovie;
  final List<VideoHomeItemBean> recentAddTv;

  const VideoHomeData({
    required this.sourceList,
    required this.recommend,
    required this.recentPlay,
    required this.recentAddMovie,
    required this.recentAddTv,
  });

  const VideoHomeData.empty()
    : sourceList = const <Map<String, dynamic>>[],
      recommend = const <VideoHomeItemBean>[],
      recentPlay = const <VideoHomeItemBean>[],
      recentAddMovie = const <VideoHomeItemBean>[],
      recentAddTv = const <VideoHomeItemBean>[];

  factory VideoHomeData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parseMapList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }

    List<VideoHomeItemBean> parseList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => VideoHomeItemBean.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id > 0)
          .toList();
    }

    return VideoHomeData(
      sourceList: parseMapList(json['sourceList'] ?? json['source_list']),
      recommend: parseList(json['recommend']),
      recentPlay: parseList(json['recentPlay'] ?? json['recent_play']),
      recentAddMovie: parseList(
        json['recentAddMovie'] ?? json['recent_add_movie'],
      ),
      recentAddTv: parseList(json['recentAddTv'] ?? json['recent_add_tv']),
    );
  }
}
