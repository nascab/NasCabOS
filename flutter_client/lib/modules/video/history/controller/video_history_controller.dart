import 'dart:async';

import 'package:get/get.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/services/video_item_sync_service.dart';
import '../service/video_history_api_service.dart';

class VideoHistoryController extends GetxController {
  final RxList<VideoHomeItemBean> items = <VideoHomeItemBean>[].obs;
  final RxBool loading = false.obs;
  StreamSubscription<int>? _deletedSubscription;

  @override
  void onInit() {
    super.onInit();
    _deletedSubscription = VideoItemSyncService.deletedStream.listen(
      _handleExternalDelete,
    );
    refreshList(showLoading: true);
  }

  @override
  void onClose() {
    _deletedSubscription?.cancel();
    super.onClose();
  }

  Future<void> refreshList({bool showLoading = false}) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final list = await VideoHistoryApiService.instance.listHistory(
        showLoading: showLoading,
      );
      items.assignAll(list);
    } finally {
      loading.value = false;
    }
  }

  Future<int> clearAll({bool showLoading = false}) async {
    final deleted = await VideoHistoryApiService.instance.clearHistory(
      showLoading: showLoading,
    );
    await refreshList(showLoading: false);
    return deleted;
  }

  void _handleExternalDelete(int indexId) {
    if (indexId <= 0) return;
    items.removeWhere((e) => e.id == indexId);
  }
}
