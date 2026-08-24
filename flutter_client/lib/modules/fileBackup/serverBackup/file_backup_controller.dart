import 'dart:async';
import 'package:get/get.dart';
import '../../../core/user/current_user_controller.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import 'file_backup_api_service.dart';

class FileBackupController extends GetxController {
  final _api = FileBackupApiService();

  final RxString currentPageKey = 'backup.disk'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isBackupExpanded = true.obs;

  final RxList<Map<String, dynamic>> tasks = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;
  final opLoadingById = <int, bool>{}.obs;

  Timer? _pollTimer;
  Completer<void>? _refreshCompleter;

  @override
  void onInit() {
    super.onInit();
    // 非管理员（子用户）无“磁盘间备份”权限，默认进入“本地备份”
    if (!CurrentUserController.instance.isAdmin) {
      currentPageKey.value = 'backup.local';
    }
    refreshList(showLoading: false, clearOnFail: true, waitIfBusy: false);
    _startPolling();
  }

  @override
  void onClose() {
    _stopPolling();
    super.onClose();
  }

  void selectPage(String key) {
    currentPageKey.value = key;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      refreshList(showLoading: false, clearOnFail: false, waitIfBusy: false);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refreshList({
    bool showLoading = true,
    bool clearOnFail = true,
    bool waitIfBusy = true,
  }) async {
    final inflight = _refreshCompleter;
    if (inflight != null && !inflight.isCompleted) {
      if (!waitIfBusy) return;
      await inflight.future;
    }
    _refreshCompleter = Completer<void>();
    isLoading.value = true;
    errorText.value = '';
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.list(page: 1);
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        if (clearOnFail) tasks.assignAll(const []);
        return;
      }

      final items = (res.data ?? const <String, dynamic>{})['items'];
      final list = (items is List ? items : const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      tasks.assignAll(list);
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
      if (clearOnFail) tasks.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      isLoading.value = false;
      _refreshCompleter?.complete();
    }
  }

  Future<bool> upsert({
    int? id,
    required List<String> sourcePathList,
    required String type,
    required String targetPath,
    required int frenquence,
    required List<String> excludeList,
    Map<String, dynamic>? taskConfig,
  }) async {
    final sources = sourcePathList
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final target = targetPath.trim();
    final t = type.trim();
    if (sources.isEmpty || target.isEmpty || frenquence <= 0) {
      ToastUtil.show('file_backup_required'.tr);
      return false;
    }
    if (t != 'copy' && t != 'sync') {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }

    final excludes = excludeList
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final res = await _api.upsert(
      id: id,
      sourcePathList: sources,
      type: t,
      targetPath: target,
      frenquence: frenquence,
      excludeList: excludes,
      taskConfig: taskConfig,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false, clearOnFail: true, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
    return true;
  }

  Future<bool> remove({required int id}) async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'file_backup_delete_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return false;

    final res = await _api.delete(id: id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false, clearOnFail: true, waitIfBusy: true);
    ToastUtil.show('delete_success'.tr);
    return true;
  }

  Future<void> start({required int id}) async {
    opLoadingById[id] = true;
    opLoadingById.refresh();
    final res = await _api.start(id: id);
    opLoadingById[id] = false;
    opLoadingById.refresh();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      await refreshList(
        showLoading: false,
        clearOnFail: false,
        waitIfBusy: true,
      );
      return;
    }
    await refreshList(showLoading: false, clearOnFail: false, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
  }

  Future<Map<String, dynamic>?> fetchBackupRecords({
    required int taskId,
    int page = 1,
    int pageSize = 100,
  }) async {
    final res = await _api.listRecords(
      taskId: taskId,
      page: page,
      pageSize: pageSize,
    );
    if (!res.success) return null;
    return res.data;
  }

  Future<void> stop({required int id}) async {
    opLoadingById[id] = true;
    opLoadingById.refresh();
    final res = await _api.stop(id: id);
    opLoadingById[id] = false;
    opLoadingById.refresh();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      await refreshList(
        showLoading: false,
        clearOnFail: false,
        waitIfBusy: true,
      );
      return;
    }
    await refreshList(showLoading: false, clearOnFail: false, waitIfBusy: true);
    ToastUtil.show('operation_success'.tr);
  }
}
