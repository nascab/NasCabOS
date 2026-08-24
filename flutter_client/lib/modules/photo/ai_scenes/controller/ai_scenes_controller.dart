import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/toast_util.dart';
import '../../ai_setting/service/photo_ai_settings_api_service.dart';
import '../../timeline/view/app_photo_timeline_view.dart';
import '../models/ai_scenes_models.dart';
import '../service/photo_ai_scenes_api_service.dart';

class AiScenesController extends GetxController {
  final PhotoAiScenesApiService _api = PhotoAiScenesApiService();
  final PhotoAiSettingsApiService _settingsApi =
      PhotoAiSettingsApiService.instance;

  final RxBool isLoading = false.obs;
  final RxBool hasMore = false.obs;
  final RxList<AiSceneItem> items = <AiSceneItem>[].obs;
  final RxList<AiSceneItem> allItems = <AiSceneItem>[].obs;
  final Rxn<AiSceneItem> activeScene = Rxn<AiSceneItem>();
  final RxBool placeEnabled = true.obs;

  final RxString statusFilter = 'visiable'.obs;
  final RxString keyword = ''.obs;
  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

  final ScrollController scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    refreshScenes();
  }

  @override
  void onClose() {
    scrollController.dispose();
    searchController.dispose();
    _searchDebounce?.cancel();
    super.onClose();
  }

  Future<void> refreshScenes() async {
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listScenes(status: 'all');
      if (!res.success || res.data == null) return;
      final data = res.data!;
      placeEnabled.value = data.placeEnable;
      if (!placeEnabled.value) {
        activeScene.value = null;
        allItems.clear();
        items.clear();
        return;
      }
      allItems.assignAll(data.items);
      _applyFilter();
    } finally {
      isLoading.value = false;
    }
  }

  void _applyFilter() {
    final filter = statusFilter.value;
    final q = keyword.value.trim().toLowerCase();

    bool matchStatus(AiSceneItem e) {
      if (filter == 'all') return true;
      if (filter == 'hide' || filter == 'hidden') return e.isHide;
      return !e.isHide;
    }

    bool matchKeyword(AiSceneItem e) {
      if (q.isEmpty) return true;
      return e.placeName.toLowerCase().contains(q);
    }

    final next = allItems.where((e) => matchStatus(e) && matchKeyword(e));
    items.assignAll(next);
  }

  void setStatusFilter(String status) {
    if (statusFilter.value == status) return;
    statusFilter.value = status;
    closeScene();
    _applyFilter();
  }

  void updateKeyword(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (keyword.value == next) return;
      keyword.value = next;
      closeScene();
      _applyFilter();
    });
  }

  void clearKeyword() {
    searchController.clear();
    if (keyword.value.isEmpty) return;
    keyword.value = '';
    closeScene();
    _applyFilter();
  }

  Future<void> enableSceneRecognition() async {
    if (!CurrentUserController.instance.isAdmin) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final res = await _settingsApi.setAiPlaceEnable(true, showLoading: true);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
    await refreshScenes();
  }

  Future<void> setSceneHidden(AiSceneItem scene, bool hide) async {
    final res = await _api.setSceneStatus(
      placeName: scene.placeNameRaw,
      isHide: hide,
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    for (int i = 0; i < allItems.length; i++) {
      final e = allItems[i];
      if (e.placeNameRaw != scene.placeNameRaw) continue;
      allItems[i] = AiSceneItem(
        placeName: e.placeName,
        placeNameRaw: e.placeNameRaw,
        photoCount: e.photoCount,
        isHide: hide,
        cover: e.cover,
      );
    }
    closeScene();
    _applyFilter();
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> confirmAndResetScenes() async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'scene_reset_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    void dismissLoading() {
      final ctx = Get.overlayContext;
      if (ctx == null) return;
      try {
        final nav = Navigator.of(ctx, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      } catch (_) {}
    }

    DialogUtil.showLoadingDialog(
      message: 'scene_reset_loading'.tr,
      barrierDismissible: false,
    );
    await Future.delayed(Duration.zero);

    try {
      final res = await _api.resetScenes();
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      activeScene.value = null;
      await refreshScenes();
      ToastUtil.show('operation_success'.tr);
    } finally {
      dismissLoading();
    }
  }

  void openScene(BuildContext context, AiSceneItem scene) {
    if (DeviceUtils.isMobile) {
      final name = scene.placeName.trim();
      final displayName = name.isNotEmpty ? name : 'scene_unnamed'.tr;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppPhotoTimelineRoutePage(
            title: "${"photo_menu_ai_scene".tr}-$displayName",
            listType: 'timeline',
            placeName: scene.placeNameRaw,
          ),
        ),
      );
      return;
    }
    activeScene.value = scene;
  }

  void closeScene() {
    activeScene.value = null;
  }
}
