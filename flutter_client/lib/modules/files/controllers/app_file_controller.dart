import 'package:get/get.dart';
import '../../../utils/toast_util.dart';
import 'file_controller.dart';
import '../service/file_api_service.dart';

export 'file_controller.dart';

class AppFileController extends FileController {
  AppFileController({
    super.autoLoadRoot = true,
    super.initialSourceType,
    super.listApiPath = '/api/file/list',
    super.searchApiPath = '/api/file/search',
    super.showRootCustomPathEntry = true,
  });

  final isMultiSelectMode = false.obs;
  final indexEnabled = false.obs;
  final indexIntervalHours = 72.obs;
  final indexConfigLoading = false.obs;
  final indexConfigSaving = false.obs;

  void enterMultiSelectMode(String firstSelectedPath) {
    isMultiSelectMode.value = true;
    if (firstSelectedPath.isNotEmpty) {
      selectOnly(firstSelectedPath);
    }
  }

  void exitMultiSelectMode() {
    isMultiSelectMode.value = false;
    clearSelect();
  }

  Future<void> loadIndexConfig({required bool showLoading}) async {
    if (indexConfigLoading.value) return;
    indexConfigLoading.value = true;
    try {
      final res = await FileApiService.instance.getIndexSettings(
        showLoading: showLoading,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = (res.data ?? {}).cast<String, dynamic>();
      indexEnabled.value = data['enabled'] == true;
      final v = int.tryParse(data['intervalHours']?.toString() ?? '');
      indexIntervalHours.value = v != null && v > 0 ? v : 72;
    } finally {
      indexConfigLoading.value = false;
    }
  }

  Future<bool> saveIndexConfig({
    required bool enabled,
    required int intervalHours,
  }) async {
    if (indexConfigSaving.value) return false;
    indexConfigSaving.value = true;
    try {
      final res = await FileApiService.instance.saveIndexSettings(
        enabled: enabled,
        intervalHours: intervalHours,
        showLoading: true,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      final data = (res.data ?? {}).cast<String, dynamic>();
      indexEnabled.value = data['enabled'] == true;
      final v = int.tryParse(data['intervalHours']?.toString() ?? '');
      indexIntervalHours.value = v != null && v > 0 ? v : intervalHours;
      ToastUtil.show('operation_success'.tr);
      return true;
    } finally {
      indexConfigSaving.value = false;
    }
  }

  Future<bool> resetIndex() async {
    final res = await FileApiService.instance.resetIndex(showLoading: true);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    ToastUtil.show('operation_success'.tr);
    await loadIndexConfig(showLoading: false);
    return true;
  }
}
