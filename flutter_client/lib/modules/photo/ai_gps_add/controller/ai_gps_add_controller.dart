import 'dart:async';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import '../../../../modules/gallery/controllers/custom_gallery_controller.dart';
import '../../../../modules/gallery/views/custom_gallery.dart';
import '../../../../modules/home/views/pc_home_controller.dart';
import '../../../../modules/photo/timeline/service/photo_timeline_api_service.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../models/ai_gps_add_models.dart';
import '../service/photo_ai_gps_add_api_service.dart';

class AiGpsAddController extends GetxController {
  final PhotoAiGpsAddApiService _api = PhotoAiGpsAddApiService();

  final RxBool loading = false.obs;
  final RxBool running = false.obs;
  final RxBool allCompleted = false.obs;
  final RxBool submitting = false.obs;
  final Rxn<AiGpsAddBatch> currentBatch = Rxn<AiGpsAddBatch>();
  final RxnString errorText = RxnString();
  final Rx<LatLng> selectedPoint = const LatLng(34.0, 108.0).obs;
  final RxInt selectedReferenceId = 0.obs;
  final RxSet<int> selectedPendingIds = <int>{}.obs;

  Timer? _pollTimer;

  bool get hasBatch => currentBatch.value != null;
  List<AiGpsAddPhotoItem> get visibleReferencePhotos =>
      (currentBatch.value?.referencePhotos ?? const <AiGpsAddPhotoItem>[])
          .take(20)
          .toList(growable: false);

  AiGpsAddPhotoItem? get selectedReferencePhoto {
    final refs = visibleReferencePhotos;
    for (final item in refs) {
      if (item.id == selectedReferenceId.value) return item;
    }
    return refs.isNotEmpty ? refs.first : null;
  }

  int get selectedPendingCount => selectedPendingIds.length;

  @override
  void onInit() {
    super.onInit();
    refreshStatus();
  }

  @override
  void onClose() {
    _stopPolling();
    super.onClose();
  }

  Future<void> refreshStatus() async {
    loading.value = true;
    errorText.value = null;
    try {
      final res = await _api.getStatus();
      if (!res.success || res.data == null) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        return;
      }
      _applyStatus(res.data!);
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
    } finally {
      loading.value = false;
    }
  }

  Future<void> startScan() async {
    if (submitting.value) return;
    submitting.value = true;
    errorText.value = null;
    try {
      await _continueSearchIfNeeded(forceStart: true, showToastOnError: true);
    } finally {
      submitting.value = false;
    }
  }

  Future<void> applyGps() async {
    final batch = currentBatch.value;
    if (batch == null || submitting.value) return;
    final targetIds = batch.pendingPhotos
        .map((e) => e.id)
        .where((id) => selectedPendingIds.contains(id))
        .toList(growable: false);
    if (targetIds.isEmpty) {
      ToastUtil.show('photo_ai_gps_add_select_photos_first'.tr);
      return;
    }
    submitting.value = true;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.applyGps(
        batchId: batch.id,
        latitude: selectedPoint.value.latitude,
        longitude: selectedPoint.value.longitude,
        photoIds: targetIds,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show(
        'photo_ai_gps_add_success'.trParams({
          'count': '${res.data ?? targetIds.length}',
        }),
      );
      await _refreshAndMaybeContinueSearch();
    } finally {
      DialogUtil.dismissLoading();
      submitting.value = false;
    }
  }

  Future<void> skipBatch() async {
    final batch = currentBatch.value;
    if (batch == null || submitting.value) return;
    submitting.value = true;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.skipBatch(batchId: batch.id);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
      await _refreshAndMaybeContinueSearch();
    } finally {
      DialogUtil.dismissLoading();
      submitting.value = false;
    }
  }

  Future<void> resetAndRescan() async {
    if (submitting.value) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'photo_ai_gps_add_reset_confirm'.tr,
      confirmText: 'reset'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    submitting.value = true;
    errorText.value = null;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final resetRes = await _api.resetAndRescan();
      if (!resetRes.success || resetRes.data == null) {
        ToastUtil.show(resetRes.message ?? 'operation_failed'.tr);
        return;
      }
      _applyStatus(resetRes.data!);
      await _continueSearchIfNeeded(forceStart: true, showToastOnError: true);
    } finally {
      DialogUtil.dismissLoading();
      submitting.value = false;
    }
  }

  void updateSelectedPoint(LatLng point) {
    selectedPoint.value = point;
    selectedPoint.refresh();
    update();
  }

  void setSelectedLatLng(double latitude, double longitude) {
    selectedPoint.value = LatLng(latitude, longitude);
    selectedPoint.refresh();
    update();
  }

  void selectReferencePhoto(AiGpsAddPhotoItem photo) {
    selectedReferenceId.value = photo.id;
    if (photo.hasGps) {
      selectedPoint.value = LatLng(photo.latitude, photo.longitude);
      selectedPoint.refresh();
    }
    selectedReferenceId.refresh();
    update();
  }

  bool isReferenceSelected(AiGpsAddPhotoItem photo) {
    return selectedReferenceId.value == photo.id;
  }

  void togglePendingSelection(AiGpsAddPhotoItem photo) {
    final ids = {...selectedPendingIds};
    if (ids.contains(photo.id)) {
      ids.remove(photo.id);
    } else {
      ids.add(photo.id);
    }
    selectedPendingIds
      ..clear()
      ..addAll(ids);
    selectedPendingIds.refresh();
    update();
  }

  bool isPendingSelected(AiGpsAddPhotoItem photo) {
    return selectedPendingIds.contains(photo.id);
  }

  int? _photoIdOfGalleryItem(Map<String, dynamic> item) {
    final v = item['photoId'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  void _removeTrashedPhotoFromCurrentBatch(int photoId) {
    final batch = currentBatch.value;
    if (batch == null) return;

    final nextReference =
        batch.referencePhotos.where((e) => e.id != photoId).toList(growable: false);
    final nextPending =
        batch.pendingPhotos.where((e) => e.id != photoId).toList(growable: false);

    if (nextReference.length == batch.referencePhotos.length &&
        nextPending.length == batch.pendingPhotos.length) {
      return;
    }

    final nextBatch = batch.copyWith(
      referencePhotos: nextReference,
      pendingPhotos: nextPending,
    );

    currentBatch.value = nextBatch;
    currentBatch.refresh();

    if (selectedReferenceId.value == photoId) {
      final visibleRefs = nextReference.take(20).toList(growable: false);
      AiGpsAddPhotoItem? selected =
          visibleRefs.where((e) => e.hasGps).cast<AiGpsAddPhotoItem?>().firstOrNull;
      selected ??= visibleRefs.isNotEmpty ? visibleRefs.first : null;
      selectedReferenceId.value = selected?.id ?? 0;
      selectedReferenceId.refresh();

      if (selected != null && selected.hasGps) {
        selectedPoint.value = LatLng(selected.latitude, selected.longitude);
      } else {
        selectedPoint.value = LatLng(nextBatch.latitude, nextBatch.longitude);
      }
      selectedPoint.refresh();
    }

    final pendingIds = nextPending.map((e) => e.id).toSet();
    final nextSelectedPendingIds = {...selectedPendingIds};
    nextSelectedPendingIds.remove(photoId);
    nextSelectedPendingIds.removeWhere((id) => !pendingIds.contains(id));
    selectedPendingIds
      ..clear()
      ..addAll(nextSelectedPendingIds);
    selectedPendingIds.refresh();

    update();

    if (nextReference.isEmpty || nextPending.isEmpty) {
      Future.microtask(() => skipBatch());
    }
  }

  Future<bool> _confirmTrashedByStatus(int photoId) async {
    try {
      final res = await _api.getStatus();
      if (!res.success) return false;
      final batch = res.data?.batch;
      if (batch == null) return true;
      final existsInRefs = batch.referencePhotos.any((e) => e.id == photoId);
      final existsInPending = batch.pendingPhotos.any((e) => e.id == photoId);
      return !(existsInRefs || existsInPending);
    } catch (_) {
      return false;
    }
  }

  Future<bool> trashPhotoFromGallery(Map<String, dynamic> item) async {
    final photoId = _photoIdOfGalleryItem(item);
    if (photoId == null || photoId <= 0) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }

    try {
      final res = await PhotoTimelineApiService().batchTrash([photoId]);
      if (res.success) {
        _removeTrashedPhotoFromCurrentBatch(photoId);
        ToastUtil.show('photo_trashed_success'.tr);
        return true;
      }

      final confirmed = await _confirmTrashedByStatus(photoId);
      if (confirmed) {
        await _refreshAndMaybeContinueSearch();
        ToastUtil.show('photo_trashed_success'.tr);
        return true;
      }

      ToastUtil.show(
        (res.code == 403 ? 'permission_denied' : 'operation_failed').tr,
      );
      return false;
    } catch (_) {
      final confirmed = await _confirmTrashedByStatus(photoId);
      if (confirmed) {
        await _refreshAndMaybeContinueSearch();
        ToastUtil.show('photo_trashed_success'.tr);
        return true;
      }
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  Future<void> openPhotoPreview(
    AiGpsAddPhotoItem clicked,
    List<AiGpsAddPhotoItem> photos,
  ) async {
    final images = photos
        .where((e) => e.type != 2)
        .map(
          (e) => <String, dynamic>{
            'type': 'image',
            'path': e.fullpath,
            'name': e.filename,
            'photoId': e.id,
            'width': e.width,
            'height': e.height,
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

    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      Get.find<PcHomeController>().openImageViewer(
        images,
        index,
        deleteHandler: (item, _) => trashPhotoFromGallery(item),
      );
      return;
    }

    if (!Get.isRegistered<CustomGalleryController>()) {
      Get.put(CustomGalleryController());
    }
    final galleryCtrl = CustomGalleryController.instance;
    galleryCtrl.configure(deleteHandler: (item, _) => trashPhotoFromGallery(item));
    galleryCtrl.isControlsVisible.value = true;
    galleryCtrl.galleryItems = images;
    galleryCtrl.galleryInitialIndex.value = index;
    Get.to(() => const CustomGallery());
  }

  void _applyStatus(AiGpsAddStatus status) {
    final oldBatchId = currentBatch.value?.id;
    final oldSelectedReferenceId = selectedReferenceId.value;
    final oldPendingSelectedIds = {...selectedPendingIds};
    running.value = status.running;
    allCompleted.value = status.allCompleted;
    currentBatch.value = status.batch;
    final batch = status.batch;
    if (batch != null) {
      final refs = batch.referencePhotos.take(20).toList(growable: false);
      AiGpsAddPhotoItem? selected;
      if (oldBatchId == batch.id) {
        for (final item in refs) {
          if (item.id == oldSelectedReferenceId) {
            selected = item;
            break;
          }
        }
      }
      selected ??= refs.where((e) => e.hasGps).cast<AiGpsAddPhotoItem?>().firstOrNull;
      selected ??= refs.isNotEmpty ? refs.first : null;
      selectedReferenceId.value = selected?.id ?? 0;
      if (selected != null && selected.hasGps) {
        selectedPoint.value = LatLng(selected.latitude, selected.longitude);
      } else {
        selectedPoint.value = LatLng(batch.latitude, batch.longitude);
      }
      final currentIds = batch.pendingPhotos.map((e) => e.id).toSet();
      if (oldBatchId == batch.id) {
        final keepIds = oldPendingSelectedIds.where(currentIds.contains).toSet();
        selectedPendingIds
          ..clear()
          ..addAll(keepIds.isEmpty ? currentIds : keepIds);
      } else {
        selectedPendingIds
          ..clear()
          ..addAll(currentIds);
      }
      selectedReferenceId.refresh();
      selectedPoint.refresh();
      selectedPendingIds.refresh();
    } else {
      selectedReferenceId.value = 0;
      selectedPendingIds.clear();
      selectedReferenceId.refresh();
      selectedPendingIds.refresh();
    }
    if (status.running) {
      _startPolling();
    } else {
      _stopPolling();
    }
    update();
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) async {
      final res = await _api.getStatus();
      if (!res.success || res.data == null) return;
      _applyStatus(res.data!);
    });
  }

  Future<void> _refreshAndMaybeContinueSearch() async {
    final res = await _api.getStatus();
    if (!res.success || res.data == null) {
      await refreshStatus();
      return;
    }
    final status = res.data!;
    _applyStatus(status);
    await _continueSearchIfNeeded(forceStart: false, showToastOnError: false, status: status);
  }

  Future<void> _continueSearchIfNeeded({
    required bool forceStart,
    required bool showToastOnError,
    AiGpsAddStatus? status,
  }) async {
    final currentStatus = status;
    final shouldStart = forceStart ||
        (currentStatus != null &&
            !currentStatus.running &&
            currentStatus.batch == null &&
            !currentStatus.allCompleted);

    if (!shouldStart) {
      if (currentStatus?.running == true) {
        _startPolling();
      }
      return;
    }

    running.value = true;
    allCompleted.value = false;
    currentBatch.value = null;
    running.refresh();
    allCompleted.refresh();
    update();
    _startPolling();
    await _triggerScan(showToastOnError: showToastOnError);
  }

  Future<void> _triggerScan({required bool showToastOnError}) async {
    final res = await _api.startScan();
    if (!res.success || res.data == null) {
      if (showToastOnError) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
      await refreshStatus();
      return;
    }
    final status = res.data!;
    if (!status.running && status.batch == null && !status.allCompleted) {
      return;
    }
    _applyStatus(status);
    _startPolling();
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
