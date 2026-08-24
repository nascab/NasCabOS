import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/services/video_item_sync_service.dart';
import '../../video_main/view/app_video_settings_view.dart';
import '../service/video_home_api_service.dart';

class AppVideoHomePageController extends GetxController {
  /// 未配置来源路径时是否提示管理员（仅影音首页应开启）。
  final bool alertWhenNoSourcePath;

  AppVideoHomePageController({this.alertWhenNoSourcePath = false});

  final RxList<VideoHomeItemBean> recommend = <VideoHomeItemBean>[].obs;
  final RxList<VideoHomeItemBean> recentPlay = <VideoHomeItemBean>[].obs;
  final RxList<VideoHomeItemBean> recentAddMovie = <VideoHomeItemBean>[].obs;
  final RxList<VideoHomeItemBean> recentAddTv = <VideoHomeItemBean>[].obs;

  final RxBool loading = false.obs;
  bool _sourceEmptyDialogShown = false;
  StreamSubscription<int>? _deletedSubscription;

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

      // 仅当接口成功且未设置来源时提示，避免网络失败时误弹
      if (data.sourceList.isEmpty && CurrentUserController.instance.isAdmin) {
        if (alertWhenNoSourcePath && !_sourceEmptyDialogShown) {
          _sourceEmptyDialogShown = true;
          DialogUtil.showInfoDialog(
            title: 'tip'.tr,
            content: 'path_no_set'.tr,
            buttonText: 'ok'.tr,
            onPressed: () {
              Get.to(
                () => Scaffold(
                  appBar: AppBar(title: Text('setting'.tr)),
                  body: const AppVideoSettingsView(),
                ),
                preventDuplicates: false,
              );
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
