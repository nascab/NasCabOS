import 'package:get/get.dart';
import '../service/photo_ai_settings_api_service.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';

class PhotoAiSettingsController extends GetxController {
  final RxBool loading = false.obs;

  final RxBool ocrEnabled = false.obs;
  final RxBool petEnabled = false.obs;
  final RxBool faceEnabled = false.obs;
  final RxBool placeEnabled = false.obs;
  final RxBool similarEnabled = false.obs;
  final RxBool gpuPrefer = true.obs; // 默认开启
  final RxInt faceMinShowCount = 0.obs;

  final RxInt ocrProgress = 0.obs;
  final RxInt placeProgress = 0.obs;
  final RxInt faceProgress = 0.obs;
  final RxInt similarScanProgress = 0.obs;
  final RxInt similarCompareProgress = 0.obs;

  bool get canEdit => CurrentUserController.instance.isAdmin;

  final _api = PhotoAiSettingsApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchSettings(showLoading: false);
  }

  Future<void> fetchSettings({bool showLoading = true}) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final res = await _api.getAiConfig(showLoading: showLoading);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'network_failure'.tr);
        return;
      }

      int parseInt(dynamic v) {
        if (v is int) return v;
        if (v is double) return v.floor();
        if (v is String) return int.tryParse(v) ?? 0;
        return 0;
      }

      final data = res.data ?? <String, dynamic>{};
      ocrEnabled.value = data['ocrEnable'] == 1 || data['ocrEnable'] == '1';
      petEnabled.value = data['petEnable'] == 1 || data['petEnable'] == '1';
      faceEnabled.value = data['faceEnable'] == 1 || data['faceEnable'] == '1';
      placeEnabled.value =
          data['placeEnable'] == 1 || data['placeEnable'] == '1';
      similarEnabled.value =
          data['similarEnable'] == 1 || data['similarEnable'] == '1';
      gpuPrefer.value =
          data['gpuPrefer'] == 1 || data['gpuPrefer'] == '1';
      final minCount = parseInt(data['faceMinShowCount']);
      faceMinShowCount.value = minCount > 0 ? minCount : 0;

      final aiProgress = data['aiProgress'];
      if (aiProgress is Map) {
        final face = aiProgress['face'];
        final place = aiProgress['place'];
        final ocr = aiProgress['ocr'];
        if (face is Map) {
          faceProgress.value = parseInt(face['percent']).clamp(0, 100);
        }
        if (place is Map) {
          placeProgress.value = parseInt(place['percent']).clamp(0, 100);
        }
        if (ocr is Map) {
          ocrProgress.value = parseInt(ocr['percent']).clamp(0, 100);
        }
      } else {
        faceProgress.value = 0;
        placeProgress.value = 0;
        ocrProgress.value = 0;
      }

      final similarProgress = data['similarProgress'];
      if (similarProgress is Map) {
        final scan = similarProgress['scan'];
        final compare = similarProgress['compare'];
        if (scan is Map) {
          similarScanProgress.value = parseInt(scan['percent']).clamp(0, 100);
        } else {
          similarScanProgress.value = 0;
        }
        if (compare is Map) {
          similarCompareProgress.value = parseInt(
            compare['percent'],
          ).clamp(0, 100);
        } else {
          similarCompareProgress.value = 0;
        }
      } else {
        similarScanProgress.value = 0;
        similarCompareProgress.value = 0;
      }
    } finally {
      loading.value = false;
    }
  }

  Future<void> toggleOcr(bool value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final prev = ocrEnabled.value;
    ocrEnabled.value = value;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiOcrEnable(value, showLoading: false);
      if (!res.success) {
        ocrEnabled.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> togglePet(bool value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final prev = petEnabled.value;
    petEnabled.value = value;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiPetEnable(value, showLoading: false);
      if (!res.success) {
        petEnabled.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> toggleFace(bool value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final prev = faceEnabled.value;
    faceEnabled.value = value;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiFaceEnable(value, showLoading: false);
      if (!res.success) {
        faceEnabled.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> togglePlace(bool value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final prev = placeEnabled.value;
    placeEnabled.value = value;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiPlaceEnable(value, showLoading: false);
      if (!res.success) {
        placeEnabled.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> toggleSimilar(bool value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final prev = similarEnabled.value;
    similarEnabled.value = value;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiSimilarEnable(value, showLoading: false);
      if (!res.success) {
        similarEnabled.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> resetSimilar() async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'photo_ai_similar_reset_confirm'.tr,
      onConfirm: () async {
        try {
          DialogUtil.showLoading(message: 'loading'.tr);
          final res = await _api.resetSimilar(showLoading: false);
          if (!res.success) {
            ToastUtil.show(res.message ?? 'network_failure'.tr);
            return;
          }
          ToastUtil.show('operation_success'.tr);
        } finally {
          DialogUtil.dismissLoading();
        }
      },
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
  }

  Future<void> setFaceMinShowCount(int value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final next = value < 0 ? 0 : value;
    final prev = faceMinShowCount.value;
    faceMinShowCount.value = next;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiFaceMinShowCount(next, showLoading: false);
      if (!res.success) {
        faceMinShowCount.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  Future<void> toggleGpu(bool value) async {
    if (!canEdit) {
      ToastUtil.show('photo_ai_admin_only'.tr);
      return;
    }
    final prev = gpuPrefer.value;
    gpuPrefer.value = value;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setAiGpuPrefer(value, showLoading: false);
      if (!res.success) {
        gpuPrefer.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
      }
    } finally {
      DialogUtil.dismissLoading();
    }
  }
}
