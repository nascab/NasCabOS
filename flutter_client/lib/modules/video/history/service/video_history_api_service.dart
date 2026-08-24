import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../base/beans/video_item_bean.dart';

class VideoHistoryApiService extends BaseApiService {
  static VideoHistoryApiService get instance =>
      Get.isRegistered<VideoHistoryApiService>()
      ? Get.find<VideoHistoryApiService>()
      : VideoHistoryApiService();

  Future<List<VideoHomeItemBean>> listHistory({
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/history/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return const <VideoHomeItemBean>[];
    final data = res.data ?? <String, dynamic>{};
    final raw = data['items'];
    final list = raw is List ? raw : const <dynamic>[];
    return list
        .whereType<Map>()
        .map((e) => VideoHomeItemBean.fromJson(e.cast<String, dynamic>()))
        .where((e) => e.id > 0)
        .toList();
  }

  Future<int> clearHistory({bool showLoading = false}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/history/clear',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return 0;
    final data = res.data ?? <String, dynamic>{};
    return (data['deleted'] as num?)?.toInt() ?? 0;
  }
}
