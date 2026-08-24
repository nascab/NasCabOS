import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../ai_setting/service/photo_ai_settings_api_service.dart';

class PhotoPreviewSettingsController extends GetxController {
  static const List<String> allowedSizes = [
    'origin',
    '8000',
    '7000',
    '6000',
    '5000',
    '4000',
    '3000',
    '2000',
    '1000',
  ];

  final RxBool loading = false.obs;
  final RxString previewSize = 'origin'.obs;
  final RxBool wifiOriginalEnabled = false.obs;

  final _api = PhotoAiSettingsApiService.instance;

  @override
  void onInit() {
    super.onInit();
    fetchSettings(showLoading: false);
    wifiOriginalEnabled.value =
        CacheManager().getBool(CacheKeys.photoPreviewWifiOriginal) ?? false;
  }

  void setWifiOriginalEnabled(bool value) {
    wifiOriginalEnabled.value = value;
    CacheManager().setBool(CacheKeys.photoPreviewWifiOriginal, value);
  }

  Future<void> fetchSettings({bool showLoading = true}) async {
    if (loading.value) return;
    loading.value = true;
    try {
      final res = await _api.getPreviewConfig(showLoading: showLoading);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'network_failure'.tr);
        return;
      }
      final data = res.data ?? <String, dynamic>{};
      final raw = data['previewSize'];
      final s = raw == null ? '' : raw.toString().trim();
      previewSize.value = allowedSizes.contains(s) ? s : 'origin';
    } finally {
      loading.value = false;
    }
  }

  Future<void> updatePreviewSize(String next) async {
    final normalized = allowedSizes.contains(next) ? next : 'origin';
    final prev = previewSize.value;
    previewSize.value = normalized;
    try {
      DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.setPreviewSize(normalized, showLoading: false);
      if (!res.success) {
        previewSize.value = prev;
        ToastUtil.show(res.message ?? 'network_failure'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
    } finally {
      DialogUtil.dismissLoading();
    }
  }
}
