import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../service/file_mount_api_service.dart';
import '../../../core/services/mount_plugin_status_service.dart';

class FileMountController extends GetxController {
  final _api = FileMountApiService();
  Map<String, dynamic>? _winfspStatusCache;
  DateTime? _winfspStatusCacheAt;

  final RxString currentPageKey = 'mount.list'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isManageExpanded = true.obs;

  final RxList<Map<String, dynamic>> mounts = <Map<String, dynamic>>[].obs;
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;
  final opLoadingById = <int, bool>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refreshList(showLoading: false);
  }

  void selectPage(String key) {
    currentPageKey.value = key;
  }

  Future<void> refreshList({bool showLoading = true}) async {
    isLoading.value = true;
    errorText.value = '';
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _api.list();
      if (!res.success) {
        errorText.value = res.message ?? 'operation_failed'.tr;
        mounts.assignAll(const []);
        return;
      }
      final raw = res.data ?? const [];
      final list = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      mounts.assignAll(list);
    } catch (_) {
      errorText.value = 'operation_failed'.tr;
      mounts.assignAll(const []);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      isLoading.value = false;
    }
  }

  Future<bool> upsert({
    int? id,
    required String name,
    required String mountPath,
    required String remote,
    Map<String, dynamic>? config,
  }) async {
    final n = name.trim();
    final mp = mountPath.trim();
    final r = remote.trim();
    if (n.isEmpty || mp.isEmpty || r.isEmpty) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
    final res = await _api.upsert(
      id: id,
      name: n,
      mountPath: mp,
      remote: r,
      config: config,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false);
    ToastUtil.show('operation_success'.tr);
    return true;
  }

  Future<bool> remove({required int id}) async {
    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'file_mount_delete_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return false;

    final res = await _api.delete(id: id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'delete_failed'.tr);
      return false;
    }
    await refreshList(showLoading: false);
    ToastUtil.show('delete_success'.tr);
    return true;
  }

  Future<void> start({required int id}) async {
    final plugin = MountPluginStatusService.ensure();
    if (!plugin.canUseFileMount) {
      plugin.showNotReadyToast();
      return;
    }
    final allowed = await ensureWinfspReady();
    if (!allowed) return;
    opLoadingById[id] = true;
    opLoadingById.refresh();
    final res = await _api.start(id: id);
    opLoadingById[id] = false;
    opLoadingById.refresh();
    if (!res.success) {
      final msg = (res.apiErrorKey == 'mountShare.PLUGIN_NOT_READY')
          ? 'mount_share_plugin_not_ready'.tr
          : (res.message ?? 'operation_failed'.tr);
      ToastUtil.show(msg);
      await refreshList(showLoading: false);
      return;
    }
    await refreshList(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<bool> ensureWinfspReady({bool force = false}) async {
    try {
      final now = DateTime.now();
      if (!force &&
          _winfspStatusCache != null &&
          _winfspStatusCacheAt != null &&
          now.difference(_winfspStatusCacheAt!) < const Duration(seconds: 30)) {
        return _handleWinfspStatus(_winfspStatusCache!);
      }

      DialogUtil.showLoading(message: 'file_mount_checking_winfsp'.tr);
      final res = await _api.checkWinfsp();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      final status = Map<String, dynamic>.from(res.data ?? const {});
      _winfspStatusCache = status;
      _winfspStatusCacheAt = now;
      return _handleWinfspStatus(status);
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  bool _handleWinfspStatus(Map<String, dynamic> status) {
    final isWindows = status['isWindows'] == true;
    final available = status['available'] == true;
    if (!isWindows || available) return true;
    DialogUtil.showInfoDialog(
      title: 'file_mount_winfsp_required_title'.tr,
      content: 'file_mount_winfsp_required_content'.tr,
    );
    return false;
  }

  Future<void> stop({required int id}) async {
    opLoadingById[id] = true;
    opLoadingById.refresh();
    final res = await _api.stop(id: id);
    opLoadingById[id] = false;
    opLoadingById.refresh();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      await refreshList(showLoading: false);
      return;
    }
    await refreshList(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  static Map<String, dynamic>? tryParseConfigObject(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      final v = jsonDecode(t);
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String prettyJson(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '';
    }
  }
}
