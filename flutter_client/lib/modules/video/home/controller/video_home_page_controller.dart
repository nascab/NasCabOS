import 'dart:async';

import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:get/get.dart';
import '../../../../utils/dialog_util.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/services/video_item_sync_service.dart';
import '../../source_setting/view/video_source_settings_view.dart';
import '../../video_main/controller/video_main_controller.dart';
import '../service/video_home_api_service.dart';

class VideoHomePageController extends GetxController {
  /// 未配置来源路径时是否提示管理员（仅影音首页应开启）。
  final bool alertWhenNoSourcePath;

  VideoHomePageController({this.alertWhenNoSourcePath = false});

  final RxList<VideoHomeItemBean> recommend = <VideoHomeItemBean>[].obs;
  final RxList<VideoHomeItemBean> recentPlay = <VideoHomeItemBean>[].obs;
  final RxList<VideoHomeItemBean> recentAddMovie = <VideoHomeItemBean>[].obs;
  final RxList<VideoHomeItemBean> recentAddTv = <VideoHomeItemBean>[].obs;

  final RxBool loading = false.obs;
  bool _sourceEmptyDialogShown = false;
  bool _sourceUnavailableDialogShown = false;
  StreamSubscription<int>? _deletedSubscription;

  bool _isSourceAvailable(Map<String, dynamic> source) {
    final v = source['avaliable'] ?? source['available'] ?? source['exists'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return true;
  }

  String _getSourcePath(Map<String, dynamic> source) {
    final p = source['path'];
    if (p is String) return p.trim();
    return '';
  }

  void _openSourceSettings() {
    if (Get.isRegistered<VideoMainController>()) {
      Get.find<VideoMainController>().selectPage('settings.source');
      return;
    }
    if (DeviceUtils.isMobile) {
      Get.to(() => const VideoSourceSettingsView());
    }
  }

  void _checkUnavailableSources(List<Map<String, dynamic>> sourceList) {
    final unavailable = sourceList
        .where((e) => !_isSourceAvailable(e))
        .toList();
    if (unavailable.isEmpty) {
      _sourceUnavailableDialogShown = false;
      return;
    }

    if (_sourceUnavailableDialogShown) return;
    _sourceUnavailableDialogShown = true;

    final first = unavailable.first;
    final p = _getSourcePath(first);
    final content = "source_invalid".trParams({'path': p});

    if (CurrentUserController.instance.isAdmin) {
      DialogUtil.showConfirmDialog(
        title: 'tip'.tr,
        content: content,
        cancelText: 'ok'.tr,
        confirmText: 'perm_view'.tr,
        onConfirm: _openSourceSettings,
      );
    } else {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: content,
        buttonText: 'ok'.tr,
      );
    }
  }

  Future<void> refreshAll({
    int recommendLimit = 11,
    int recentPlayLimit = 20,
    int recentAddLimit = 20,
    bool showLoading = false,
  }) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final res = await VideoHomeApiService.instance.getHomeData(
        recommendLimit: recommendLimit,
        recentPlayLimit: recentPlayLimit,
        recentAddLimit: recentAddLimit,
        showLoading: showLoading,
      );
      if (!res.success) return;
      final data = res.data!;
      recommend.assignAll(data.recommend);
      recentPlay.assignAll(data.recentPlay);
      recentAddMovie.assignAll(data.recentAddMovie);
      recentAddTv.assignAll(data.recentAddTv);

      _checkUnavailableSources(data.sourceList);

      // 仅当接口成功且未设置来源时提示，避免网络失败时误弹
      if (data.sourceList.isEmpty && CurrentUserController.instance.isAdmin) {
        if (alertWhenNoSourcePath && !_sourceEmptyDialogShown) {
          _sourceEmptyDialogShown = true;
          DialogUtil.showInfoDialog(
            title: 'tip'.tr,
            content: 'path_no_set'.tr,
            buttonText: 'ok'.tr,
            onPressed: () {
              _openSourceSettings();
            },
          );
        }
      } else {
        _sourceEmptyDialogShown = false;
      }
    } finally {
      loading.value = false;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _deletedSubscription = VideoItemSyncService.deletedStream.listen(
      _handleExternalDelete,
    );
    refreshAll(showLoading: false);
  }

  @override
  void onClose() {
    _deletedSubscription?.cancel();
    super.onClose();
  }

  void _handleExternalDelete(int indexId) {
    if (indexId <= 0) return;
    recommend.removeWhere((e) => e.id == indexId);
    recentPlay.removeWhere((e) => e.id == indexId);
    recentAddMovie.removeWhere((e) => e.id == indexId);
    recentAddTv.removeWhere((e) => e.id == indexId);
  }
}
