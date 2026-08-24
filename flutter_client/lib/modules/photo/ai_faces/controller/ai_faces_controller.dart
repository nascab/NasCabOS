import 'dart:async';
import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_dropdown_field.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/toast_util.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../ai_setting/service/photo_ai_settings_api_service.dart';
import '../../timeline/view/app_photo_timeline_view.dart';
import '../models/ai_faces_models.dart';
import '../service/photo_ai_faces_api_service.dart';

class AiFacesController extends GetxController {
  final PhotoAiFacesApiService _api = PhotoAiFacesApiService();
  final PhotoAiSettingsApiService _settingsApi =
      PhotoAiSettingsApiService.instance;

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxList<AiFaceItem> items = <AiFaceItem>[].obs;
  final RxInt page = 1.obs;
  final RxInt pageSize = 60.obs;
  final RxInt total = 0.obs;
  final Rxn<AiFaceItem> activeFace = Rxn<AiFaceItem>();
  final RxBool faceEnabled = true.obs;

  final RxString statusFilter = 'visiable'.obs;
  final RxString keyword = ''.obs;
  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

  final RxBool selectionMode = false.obs;
  final RxSet<int> selectedFaceIds = <int>{}.obs;

  final ScrollController scrollController = ScrollController();

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    refreshFaces();
  }

  @override
  void onClose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.dispose();
    _searchDebounce?.cancel();
    super.onClose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent - 200) {
      loadMore();
    }
  }

  Future<void> refreshFaces() async {
    ApiController.instance.refreshFaceImageTimestamp();
    hasMore.value = true;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    await _loadFaces(pageNumber: 1, append: false);
  }

  Future<void> _loadFaces({
    required int pageNumber,
    required bool append,
  }) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listFaces(
        page: pageNumber,
        pageSize: pageSize.value,
        status: statusFilter.value,
        keyword: keyword.value,
      );
      if (!res.success || res.data == null) return;
      final data = res.data!;
      faceEnabled.value = data.faceEnable;
      if (!faceEnabled.value) {
        activeFace.value = null;
        exitSelectionMode();
        items.clear();
        total.value = 0;
        page.value = 1;
        hasMore.value = false;
        return;
      }
      if (append) {
        final existingIds = items.map((e) => e.faceId).toSet();
        final next = data.items.where((e) => !existingIds.contains(e.faceId));
        items.addAll(next);
      } else {
        items.assignAll(data.items);
      }
      total.value = data.total;
      page.value = data.page;
      pageSize.value = data.pageSize <= 0 ? pageSize.value : data.pageSize;

      final size = pageSize.value <= 0 ? 60 : pageSize.value;
      final maxPage = total.value <= 0
          ? 1
          : ((total.value + size - 1) / size).floor();
      hasMore.value = page.value < maxPage;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value) return;
    if (!hasMore.value) return;
    await _loadFaces(pageNumber: page.value + 1, append: true);
  }

  void setStatusFilter(String status) {
    if (statusFilter.value == status) return;
    statusFilter.value = status;
    exitSelectionMode();
    refreshFaces();
  }

  void updateKeyword(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (keyword.value == next) return;
      keyword.value = next;
      exitSelectionMode();
      refreshFaces();
    });
  }

  void clearKeyword() {
    searchController.clear();
    if (keyword.value.isEmpty) return;
    keyword.value = '';
    exitSelectionMode();
    refreshFaces();
  }

  Future<void> enableFaceRecognition() async {
    if (!CurrentUserController.instance.isAdmin) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final res = await _settingsApi.setAiFaceEnable(true, showLoading: true);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
    await refreshFaces();
  }

  void enterSelectionMode() {
    selectionMode.value = true;
  }

  void exitSelectionMode() {
    selectionMode.value = false;
    selectedFaceIds.clear();
  }

  void toggleSelected(int faceId) {
    if (faceId <= 0) return;
    if (!selectionMode.value) selectionMode.value = true;
    if (selectedFaceIds.contains(faceId)) {
      selectedFaceIds.remove(faceId);
      if (selectedFaceIds.isEmpty) selectionMode.value = false;
    } else {
      selectedFaceIds.add(faceId);
    }
  }

  Future<void> downloadFaces(List<int> faceIds) async {
    final ids = faceIds.where((e) => e > 0).toSet().toList();
    if (ids.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handlePhotoDownload(
      albumType: 'face',
      ids: ids,
    );
  }

  Future<void> downloadSelectedFaces() async {
    final ids = selectedFaceIds.toList();
    if (ids.isEmpty) return;
    await downloadFaces(ids);
    exitSelectionMode();
  }

  Future<void> renameFace(AiFaceItem face, String name) async {
    final v = name.trim();
    if (v.isEmpty || v.length > 30) return;
    final res = await _api.updateFaceName(faceId: face.faceId, name: v);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    final idx = items.indexWhere((e) => e.faceId == face.faceId);
    if (idx >= 0) {
      items[idx] = AiFaceItem(
        faceId: face.faceId,
        faceCount: face.faceCount,
        coverFileHash: face.coverFileHash,
        name: v,
        isHide: face.isHide,
      );
    }
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> setFaceHidden(AiFaceItem face, bool hide) async {
    final res = await _api.setFaceStatus(faceId: face.faceId, isHide: hide);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    exitSelectionMode();
    await refreshFaces();
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> batchSetHidden(bool hide) async {
    final ids = selectedFaceIds.toList();
    if (ids.isEmpty) return;
    final futures = ids.map(
      (id) => _api.setFaceStatus(faceId: id, isHide: hide),
    );
    final results = await Future.wait(futures);
    if (results.any((e) => !e.success)) {
      ToastUtil.show('operation_failed'.tr);
    } else {
      ToastUtil.show('operation_success'.tr);
    }
    exitSelectionMode();
    await refreshFaces();
  }

  Future<void> confirmAndMergeSelected() async {
    final ids = selectedFaceIds.toList();
    if (ids.length < 2) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'face_merge_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;
    final res = await _api.mergeFaces(faceIds: ids);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    exitSelectionMode();
    await refreshFaces();
    ToastUtil.show('operation_success'.tr);
  }

  String faceDisplayName(AiFaceItem face) {
    final name = (face.name ?? '').trim();
    return name.isNotEmpty ? name : '(${'face_unnamed'.tr})';
  }

  Future<AiFaceItem?> _pickTargetFace({
    required int excludeFaceId,
    required String title,
  }) async {
    final res = await _api.listFaces(
      page: 1,
      pageSize: 500,
      status: 'all',
      keyword: '',
    );
    if (!res.success || res.data == null) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return null;
    }

    final candidates = res.data!.items
        .where((e) => e.faceId > 0 && e.faceId != excludeFaceId)
        .toList(growable: false);
    if (candidates.isEmpty) {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'face_move_target_empty'.tr,
      );
      return null;
    }

    final ctx = Get.overlayContext ?? Get.context;
    if (ctx == null || !ctx.mounted) return null;

    if (DeviceUtils.isMobile) {
      return showModalBottomSheet<AiFaceItem>(
        context: ctx,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: _AiFaceTargetPickerContent(
            title: title,
            controller: this,
            items: candidates,
            isMobile: true,
          ),
        ),
      );
    }

    return showDialog<AiFaceItem>(
      context: ctx,
      builder: (context) {
        return DialogUtil.createAlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: _AiFaceTargetPickerContent(
              title: title,
              controller: this,
              items: candidates,
              isMobile: false,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('cancel'.tr),
            ),
          ],
        );
      },
    );
  }

  Future<void> moveFaceToOther(AiFaceItem face) async {
    if (!CurrentUserController.instance.isAdmin) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }

    final target = await _pickTargetFace(
      excludeFaceId: face.faceId,
      title: 'face_move_to_other_face'.tr,
    );
    if (target == null) return;

    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'face_move_confirm'.trParams({
        'from': faceDisplayName(face),
        'to': faceDisplayName(target),
      }),
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    final res = await _api.moveFaceToOther(
      fromFaceId: face.faceId,
      toFaceId: target.faceId,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }

    if (activeFace.value?.faceId == face.faceId) {
      activeFace.value = null;
    }
    exitSelectionMode();
    await refreshFaces();
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> confirmAndResetFaces() async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'face_reset_confirm'.tr,
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
      message: 'face_reset_loading'.tr,
      barrierDismissible: false,
    );
    await Future.delayed(Duration.zero);

    try {
      final res = await _api.resetFaces();
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      activeFace.value = null;
      exitSelectionMode();
      await refreshFaces();
      ToastUtil.show('operation_success'.tr);
    } finally {
      dismissLoading();
    }
  }

  Future<void> openAutoHideSettings() async {
    if (!CurrentUserController.instance.isAdmin) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }

    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.floor();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    void dismissLoading() {
      final ctx = Get.overlayContext;
      if (ctx == null) return;
      try {
        final nav = Navigator.of(ctx, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      } catch (_) {}
    }

    DialogUtil.showLoadingDialog(
      message: 'loading'.tr,
      barrierDismissible: false,
    );
    await Future.delayed(Duration.zero);

    int current = 0;
    try {
      final res = await _settingsApi.getAiConfig(showLoading: false);
      if (res.success) {
        final data = res.data ?? <String, dynamic>{};
        final parsed = parseInt(data['faceMinShowCount']);
        if (parsed > 0) current = parsed;
      }
    } catch (_) {
      current = 0;
    } finally {
      dismissLoading();
    }

    int selected = current;
    final ctx = Get.overlayContext;
    if (ctx == null) return;
    if (!ctx.mounted) return;

    final picked = await showDialog<int>(
      context: ctx,
      builder: (context) {
        final theme = Theme.of(context);
        final subtitleBase = theme.textTheme.bodySmall;
        final subtitleColor =
            (subtitleBase?.color ?? theme.colorScheme.onSurface).withOpacity(
              0.8,
            );
        return StatefulBuilder(
          builder: (context, setState) {
            return DialogUtil.createAlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'photo_ai_auto_hide_face_album'.tr,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'photo_ai_auto_hide_face_album_subtitle'.tr,
                    style: subtitleBase?.copyWith(color: subtitleColor),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: SizedBox(
                  height: 44,
                  child: CustomDropdownField<int>(
                    value: selected,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    items: const [0, 3, 5, 10]
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: e,
                            child: Text(
                              'photo_ai_auto_hide_face_album_option_$e'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => selected = v);
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return;
    if (picked == current) return;

    DialogUtil.showLoadingDialog(
      message: 'loading'.tr,
      barrierDismissible: false,
    );
    await Future.delayed(Duration.zero);
    try {
      final res = await _settingsApi.setAiFaceMinShowCount(
        picked,
        showLoading: false,
      );
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      await refreshFaces();
      ToastUtil.show('operation_success'.tr);
    } finally {
      dismissLoading();
    }
  }

  void openFace(BuildContext context, AiFaceItem face) {
    if (DeviceUtils.isMobile) {
      final name = (face.name ?? '').trim();
      final displayName = name.isNotEmpty ? name : '(${'face_unnamed'.tr})';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppPhotoTimelineRoutePage(
            title: "${"photo_menu_ai_face".tr}-$displayName",
            listType: 'timeline',
            faceId: face.faceId,
          ),
        ),
      );
      return;
    }
    activeFace.value = face;
  }

  void closeFace() {
    activeFace.value = null;
  }
}

class _AiFaceTargetPickerContent extends StatefulWidget {
  final String title;
  final AiFacesController controller;
  final List<AiFaceItem> items;
  final bool isMobile;

  const _AiFaceTargetPickerContent({
    required this.title,
    required this.controller,
    required this.items,
    required this.isMobile,
  });

  @override
  State<_AiFaceTargetPickerContent> createState() =>
      _AiFaceTargetPickerContentState();
}

class _AiFaceTargetPickerContentState
    extends State<_AiFaceTargetPickerContent> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((face) {
          final keyword = _keyword.trim().toLowerCase();
          if (keyword.isEmpty) return true;
          final name = widget.controller.faceDisplayName(face).toLowerCase();
          return name.contains(keyword) ||
              face.faceId.toString().contains(keyword);
        })
        .toList(growable: false);

    final content = ListView.separated(
      shrinkWrap: true,
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final face = filtered[index];
        return ListTile(
          leading: ClipOval(
            child: CustomExtendedImage(
              cache: false,
              imageUrl: ApiController.instance.getFaceImageUrl(
                faceId: face.faceId,
                size: 120,
                quality: 85,
              ),
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              borderRadius: 18,
              showLoading: false,
            ),
          ),
          title: Text(
            widget.controller.faceDisplayName(face),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            'total_count'.trParams({'count': '${face.faceCount}'}),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(face),
        );
      },
    );

    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _keyword = value),
        decoration: InputDecoration(
          hintText: 'search'.tr,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );

    final listContent = filtered.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: Text('no_data'.tr)),
          )
        : content;

    if (widget.isMobile) {
      return SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            searchBar,
            Expanded(child: listContent),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          searchBar,
          Flexible(child: listContent),
        ],
      ),
    );
  }
}
