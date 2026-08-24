import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/user/current_user_controller.dart';
import '../../utils/dialog_util.dart';
import '../../utils/toast_util.dart';
import 'security_api_service.dart';

class SecurityCenterController extends GetxController {
  final SecurityApiService _api = SecurityApiService.instance;

  final RxString currentPageKey = 'security.best_practices'.obs;
  final RxBool sidebarCollapsed = false.obs;
  final RxDouble leftWidth = 220.0.obs;

  final TextEditingController maxFailedAttemptsController =
      TextEditingController(text: '5');
  final TextEditingController banMinutesController = TextEditingController(
    text: '1',
  );
  final RxBool banEnabled = true.obs;
  final RxBool bypassLanAuth = true.obs;

  final RxList<Map<String, dynamic>> blacklist = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> devices = <Map<String, dynamic>>[].obs;

  Worker? _banEnabledWorker;
  Worker? _bypassLanAuthWorker;
  bool _autoSaveEnabled = false;
  bool _hydrating = false;
  bool _autoSaving = false;
  bool _pendingAutoSave = false;

  bool get _isAdmin => CurrentUserController.instance.isAdmin;

  void selectPage(String key) {
    if (!_isAdmin &&
        key != 'security.devices') {
      currentPageKey.value = 'security.devices';
      return;
    }
    currentPageKey.value = key;
    if (key == 'security.devices') {
      loadDevices(showLoading: false);
    }
  }

  @override
  void onInit() {
    super.onInit();
    if (!_isAdmin) {
      currentPageKey.value = 'security.devices';
      loadDevices(showLoading: false);
      return;
    }
    _setupAutoSave();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await loadConfig(showLoading: false);
    _autoSaveEnabled = true;
    await loadBlacklist(showLoading: false);
  }

  void _setupAutoSave() {
    _banEnabledWorker = debounce<bool>(
      banEnabled,
      (_) => _autoSaveConfig(),
      time: const Duration(milliseconds: 450),
    );
    _bypassLanAuthWorker = debounce<bool>(
      bypassLanAuth,
      (_) => _autoSaveConfig(),
      time: const Duration(milliseconds: 450),
    );
  }

  Future<void> _autoSaveConfig() async {
    if (!_autoSaveEnabled) return;
    if (_hydrating) return;
    if (_autoSaving) {
      _pendingAutoSave = true;
      return;
    }

    _autoSaving = true;
    try {
      final maxFailedAttempts = _parsePositiveInt(
        maxFailedAttemptsController.text,
        fallback: 5,
      );
      final banMinutes = _parsePositiveInt(
        banMinutesController.text,
        fallback: 1,
      );
      final res = await _api.setConfig(
        banEnabled: banEnabled.value,
        maxFailedAttempts: maxFailedAttempts,
        banMinutes: banMinutes,
        bypassLanAuth: bypassLanAuth.value,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      await loadConfig(showLoading: false);
    } finally {
      _autoSaving = false;
      if (_pendingAutoSave) {
        _pendingAutoSave = false;
        _autoSaveConfig();
      }
    }
  }

  @override
  void onClose() {
    _banEnabledWorker?.dispose();
    _bypassLanAuthWorker?.dispose();
    maxFailedAttemptsController.dispose();
    banMinutesController.dispose();
    super.onClose();
  }

  int _parsePositiveInt(String input, {required int fallback}) {
    final v = int.tryParse(input.trim());
    if (v == null) return fallback;
    if (v <= 0) return fallback;
    return v;
  }

  Future<void> loadConfig({required bool showLoading}) async {
    _hydrating = true;
    try {
      final res = await _api.getConfig(showLoading: showLoading);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = (res.data ?? const {}).cast<String, dynamic>();
      final enabled = data['banEnabled'];
      final maxFailedAttempts = data['maxFailedAttempts'];
      final banMinutes = data['banMinutes'];
      final bypass = data['bypassLanAuth'];
      if (enabled != null) {
        banEnabled.value = enabled == true;
      }
      if (maxFailedAttempts != null) {
        maxFailedAttemptsController.text = maxFailedAttempts.toString();
      }
      if (banMinutes != null) {
        banMinutesController.text = banMinutes.toString();
      }
      if (bypass != null) {
        bypassLanAuth.value = bypass == true;
      }
    } finally {
      _hydrating = false;
    }
  }

  Future<void> saveConfig() async {
    final maxFailedAttempts = _parsePositiveInt(
      maxFailedAttemptsController.text,
      fallback: 5,
    );
    final banMinutes = _parsePositiveInt(
      banMinutesController.text,
      fallback: 1,
    );
    final res = await _api.setConfig(
      banEnabled: banEnabled.value,
      maxFailedAttempts: maxFailedAttempts,
      banMinutes: banMinutes,
      bypassLanAuth: bypassLanAuth.value,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await loadConfig(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> loadBlacklist({required bool showLoading}) async {
    final res = await _api.listIpBlacklist(showLoading: showLoading);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    final items = (res.data ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    blacklist.assignAll(items);
  }

  Future<void> loadDevices({required bool showLoading}) async {
    final res = await _api.listDevices(showLoading: showLoading);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    final items = (res.data ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    devices.assignAll(items);
  }

  Future<void> kickDevice(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'confirm'.tr,
      content: 'security.device_kick_confirm'.tr,
    );
    if (ok != true) return;
    final res = await _api.kickDevice(id);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await loadDevices(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> deleteIp(String ip) async {
    final p = ip.trim();
    if (p.isEmpty) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'confirm'.tr,
      content: 'delete'.tr,
    );
    if (ok != true) return;
    final res = await _api.deleteIpBlacklist(p);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await loadBlacklist(showLoading: false);
    ToastUtil.show('delete_success'.tr);
  }

  Future<void> clearBlacklist() async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'tip'.tr,
      content: "${'task_clear_all'.tr} ?",
    );
    if (ok != true) return;
    final res = await _api.clearIpBlacklist();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await loadBlacklist(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }
}
