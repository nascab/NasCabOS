import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../gallery/controllers/custom_gallery_controller.dart';
import '../../../gallery/views/custom_gallery.dart';
import '../../../home/views/pc_home_controller.dart';
import '../../ai_setting/service/photo_ai_settings_api_service.dart';
import '../../timeline/models/photo_timeline_model.dart';
import '../../timeline/service/photo_timeline_api_service.dart';
import '../models/ai_similar_models.dart';
import '../service/photo_ai_similar_api_service.dart';

class AiSimilarController extends GetxController {
  final PhotoAiSimilarApiService _api = PhotoAiSimilarApiService();
  final PhotoTimelineApiService _timelineApi = PhotoTimelineApiService();
  final PhotoAiSettingsApiService _settingsApi =
      PhotoAiSettingsApiService.instance;

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxInt page = 1.obs;
  final RxInt pageSize = 20.obs;
  final RxInt total = 0.obs;
  final RxBool similarEnabled = true.obs;

  final RxList<AiSimilarGroupItem> groups = <AiSimilarGroupItem>[].obs;

  final RxSet<int> selectedPhotoIds = <int>{}.obs;
  final RxMap<int, int> photoSizeById = <int, int>{}.obs;
  final RxSet<int> _defaultAppliedGroupIds = <int>{}.obs;
  final RxSet<int> _manuallyToggledPhotoIds = <int>{}.obs;

  final ScrollController scrollController = ScrollController();

  bool get canEdit => CurrentUserController.instance.isAdmin;

  @override
  void onInit() {
    super.onInit();
    refreshGroups(showLoading: false);
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }

  Future<void> refreshGroups({bool showLoading = true}) async {
    await _loadGroups(pageNumber: 1, append: false, showLoading: showLoading);
    await _loadNextPageIfEmpty(showLoading: showLoading);
  }

  Future<void> loadMore() async {
    if (isLoading.value) return;
    if (!hasMore.value) return;
    await _loadGroups(
      pageNumber: page.value + 1,
      append: true,
      showLoading: false,
    );
  }

  Future<void> _loadNextPageIfEmpty({required bool showLoading}) async {
    var tries = 0;
    while (groups.isEmpty &&
        similarEnabled.value &&
        hasMore.value &&
        tries < 8) {
      tries += 1;
      await _loadGroups(
        pageNumber: page.value + 1,
        append: false,
        showLoading: showLoading,
      );
    }
  }

  void setPageSize(int next) {
    final v = next <= 0 ? 20 : next;
    if (pageSize.value == v) return;
    pageSize.value = v;
    clearSelection();
    refreshGroups(showLoading: false);
  }

  Future<void> _loadGroups({
    required int pageNumber,
    required bool append,
    required bool showLoading,
  }) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listSimilarGroups(
        page: pageNumber,
        pageSize: pageSize.value,
      );
      if (!res.success || res.data == null) return;

      final data = res.data!;
      similarEnabled.value = data.similarEnable;
      if (!similarEnabled.value) {
        clearSelection();
        groups.clear();
        total.value = 0;
        page.value = 1;
        hasMore.value = false;
        return;
      }

      final nextItems = data.items;
      if (append) {
        final existingIds = groups.map((e) => e.id).toSet();
        final filtered = nextItems.where((e) => !existingIds.contains(e.id));
        groups.addAll(filtered);
        _initGroups(filtered);
      } else {
        groups.assignAll(nextItems);
        selectedPhotoIds.clear();
        _defaultAppliedGroupIds.clear();
        _manuallyToggledPhotoIds.clear();
        _initGroups(nextItems);
      }

      total.value = data.pagination.total;
      page.value = data.pagination.page <= 0
          ? pageNumber
          : data.pagination.page;
      final size = data.pagination.pageSize > 0
          ? data.pagination.pageSize
          : pageSize.value;
      pageSize.value = size;

      final maxPage = total.value <= 0
          ? 1
          : ((total.value + size - 1) / size).floor();
      hasMore.value = page.value < maxPage;
    } finally {
      isLoading.value = false;
      if (showLoading) update();
    }
  }

  Future<void> enableSimilarRecognition() async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final res = await _settingsApi.setAiSimilarEnable(true, showLoading: true);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
    await refreshGroups(showLoading: false);
  }

  void clearSelection() {
    selectedPhotoIds.clear();
    _manuallyToggledPhotoIds.clear();
  }

  void togglePhotoSelection(int id) {
    _manuallyToggledPhotoIds.add(id);
    if (selectedPhotoIds.contains(id)) {
      selectedPhotoIds.remove(id);
    } else {
      selectedPhotoIds.add(id);
    }
  }

  Future<void> trashSelectedPhotos() async {
    final ids = selectedPhotoIds.toList();
    if (ids.isEmpty) return;

    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _timelineApi.batchTrash(ids);
      if (!res.success) {
        ToastUtil.show((res.code == 403 ? 'permission_denied' : 'operation_failed').tr);
        return;
      }
      ToastUtil.show('photo_trashed_success'.tr);
      clearSelection();
      await refreshGroups(showLoading: false);
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<bool> resetSimilarScan() async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return false;
    }
    final res = await _settingsApi.resetSimilar(showLoading: false);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    return true;
  }

  int? _photoIdOfGalleryItem(Map<String, dynamic> item) {
    final value = item['photoId'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  void _removePhotosFromMemory(Iterable<int> ids) {
    final idSet = ids.where((e) => e > 0).toSet();
    if (idSet.isEmpty) return;

    selectedPhotoIds.removeWhere((id) => idSet.contains(id));
    _manuallyToggledPhotoIds.removeWhere((id) => idSet.contains(id));
    for (final id in idSet) {
      photoSizeById.remove(id);
    }

    final nextGroups = <AiSimilarGroupItem>[];
    final groupsToReapply = <AiSimilarGroupItem>[];

    for (final group in groups) {
      final remaining = group.photos
          .where((photo) => !idSet.contains(photo.id))
          .toList(growable: false);

      if (remaining.length == group.photos.length) {
        nextGroups.add(group);
        continue;
      }

      _defaultAppliedGroupIds.remove(group.id);
      if (remaining.length <= 1) {
        continue;
      }

      final updated = AiSimilarGroupItem(
        id: group.id,
        indexId: group.indexId,
        photos: remaining,
        createTime: group.createTime,
      );
      nextGroups.add(updated);
      groupsToReapply.add(updated);
    }

    groups.assignAll(nextGroups);
    for (final group in groupsToReapply) {
      _applyDefaultSelectionForGroup(group);
    }

    if (groups.isEmpty && hasMore.value && !isLoading.value) {
      unawaited(_loadNextPageIfEmpty(showLoading: false));
    }
  }

  Future<bool> trashPhotoFromGallery(Map<String, dynamic> item) async {
    final photoId = _photoIdOfGalleryItem(item);
    if (photoId == null || photoId <= 0) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }

    try {
      final res = await _timelineApi.batchTrash([photoId]);
      if (!res.success) {
        ToastUtil.show(
          (res.code == 403 ? 'permission_denied' : 'operation_failed').tr,
        );
        return false;
      }
      _removePhotosFromMemory([photoId]);
      ToastUtil.show('photo_trashed_success'.tr);
      return true;
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  void _initGroups(Iterable<AiSimilarGroupItem> items) {
    for (final g in items) {
      _initGroup(g);
    }
  }

  Future<void> _initGroup(AiSimilarGroupItem group) async {
    if (group.photos.length <= 1) return;
    if (_defaultAppliedGroupIds.contains(group.id)) return;

    for (final p in group.photos) {
      final s = p.size;
      if (s > 0) {
        photoSizeById[p.id] = s;
      }
    }

    await _ensurePhotoSizes(group.photos);
    _applyDefaultSelectionForGroup(group);
  }

  Future<void> _ensurePhotoSizes(List<TimelinePhotoItem> photos) async {
    for (final p in photos) {
      final existing = photoSizeById[p.id] ?? 0;
      if (existing > 0) continue;
      if (p.size > 0) {
        photoSizeById[p.id] = p.size;
        continue;
      }

      final res = await _timelineApi.getPhotoProperties(
        p.fullpath,
        showLoading: false,
      );
      if (!res.success || res.data == null) continue;
      final data = res.data!;
      final v = data['size'];
      final size = (v is int) ? v : int.tryParse(v?.toString() ?? '') ?? 0;
      if (size > 0) {
        photoSizeById[p.id] = size;
      }
    }
  }

  void _applyDefaultSelectionForGroup(AiSimilarGroupItem group) {
    if (_defaultAppliedGroupIds.contains(group.id)) return;
    final ids = group.photos.map((e) => e.id).toList(growable: false);
    if (ids.any(_manuallyToggledPhotoIds.contains)) return;

    int? keepId;
    int keepSize = -1;
    for (final p in group.photos) {
      final s = photoSizeById[p.id] ?? p.size;
      if (s > keepSize) {
        keepSize = s;
        keepId = p.id;
      }
    }
    keepId ??= group.photos.first.id;

    selectedPhotoIds.removeWhere(ids.contains);
    for (final id in ids) {
      if (id == keepId) continue;
      selectedPhotoIds.add(id);
    }
    _defaultAppliedGroupIds.add(group.id);
  }

  Future<void> openGroupPreview({
    required AiSimilarGroupItem group,
    required TimelinePhotoItem clicked,
  }) async {
    final images = group.photos
        .where((e) => e.type != 2)
        .map(
          (e) => <String, dynamic>{
            'type': 'image',
            'path': e.fullpath,
            'name': e.filename,
            'photoId': e.id,
            'isLvp': e.isLvp,
            'isMergeLvp': e.isMergeLvp,
            'liveFilename': e.liveFilename,
            'rawFilename': e.rawFilename,
          },
        )
        .toList(growable: false);
    if (images.isEmpty) return;

    final index = images.indexWhere((e) => e['path'] == clicked.fullpath);
    if (index < 0) return;

    Future<bool> deleteHandler(Map<String, dynamic> item, int _) {
      return trashPhotoFromGallery(item);
    }

    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      final homeController = Get.find<PcHomeController>();
      homeController.openImageViewer(
        images,
        index,
        deleteHandler: deleteHandler,
      );
      return;
    }

    if (!Get.isRegistered<CustomGalleryController>()) {
      Get.put(CustomGalleryController());
    }

    final galleryCtrl = CustomGalleryController.instance;
    galleryCtrl.configure(deleteHandler: deleteHandler);
    galleryCtrl.isControlsVisible.value = true;
    galleryCtrl.galleryItems = images;
    galleryCtrl.galleryInitialIndex.value = index;
    Get.to(() => const CustomGallery());
  }
}
