import 'dart:async';

import 'package:get/get.dart';

import '../../utils/toast_util.dart';
import '../api/api_controller.dart';
import '../api/base_api_service.dart';

class MountPluginApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> getStatus() {
    return apiPost<Map<String, dynamic>>(
      '/api/plugin/mountLibsStatus',
      body: const {},
      dataParser: (json, code) => Map<String, dynamic>.from(json as Map),
      showLoading: false,
    );
  }
}

class MountPluginStatusService extends GetxController {
  static MountPluginStatusService ensure() {
    if (Get.isRegistered<MountPluginStatusService>()) {
      return Get.find<MountPluginStatusService>();
    }
    return Get.put(MountPluginStatusService(), permanent: true);
  }

  /// 引入 /api/plugin/mountLibsStatus 的最低服务端版本
  static const int _minServerVersionForPluginCheck = 10;

  final _api = MountPluginApiService();
  final RxBool statusKnown = false.obs;
  final RxBool remoteAssetsEnabled = false.obs;
  final RxBool fileMountReady = false.obs;
  final RxBool openlistMountReady = false.obs;
  final RxBool fileServerReady = false.obs;
  final RxBool syncing = false.obs;
  Timer? _pollTimer;
  int _pollCount = 0;

  /// 是否需要轮询插件状态；旧版服务端使用内置插件，无需检查
  bool get _shouldCheckPlugin {
    return ApiController.instance.isServerVersionAtLeast(
      _minServerVersionForPluginCheck,
      unknownAsSupported: false,
    );
  }

  bool get canUseFileMount {
    if (!_shouldCheckPlugin) return true;
    return statusKnown.value &&
        (!remoteAssetsEnabled.value || fileMountReady.value);
  }

  bool get canUseOpenlistMount {
    if (!_shouldCheckPlugin) return true;
    return statusKnown.value &&
        (!remoteAssetsEnabled.value || openlistMountReady.value);
  }

  bool get canUseFileServer {
    if (!_shouldCheckPlugin) return true;
    return statusKnown.value &&
        (!remoteAssetsEnabled.value || fileServerReady.value);
  }

  static bool _readBool(dynamic value) {
    if (value == true || value == 1) return true;
    final s = value?.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
  }

  @override
  void onInit() {
    super.onInit();
    startPolling();
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  void _applyStatus(Map<String, dynamic> data) {
    statusKnown.value = true;
    remoteAssetsEnabled.value = _readBool(data['enabled']);
    if (!remoteAssetsEnabled.value) {
      fileMountReady.value = true;
      openlistMountReady.value = true;
      fileServerReady.value = true;
      syncing.value = false;
      return;
    }
    fileMountReady.value = _readBool(data['fileMountReady']);
    openlistMountReady.value = _readBool(data['openlistMountReady']);
    fileServerReady.value = _readBool(data['fileServerReady']);
    syncing.value = _readBool(data['syncing']);
  }

  Future<void> refreshStatus() async {
    if (!_shouldCheckPlugin) return;
    final res = await _api.getStatus();
    if (!res.success || res.data == null) return;
    _applyStatus(res.data!);
  }

  void showNotReadyToast() {
    ToastUtil.show('mount_share_plugin_not_ready'.tr);
  }

  void startPolling({bool forceRestart = false}) {
    if (!_shouldCheckPlugin) {
      // 旧版服务端使用内置插件，无需轮询，直接标记就绪
      _pollTimer?.cancel();
      _pollTimer = null;
      statusKnown.value = true;
      remoteAssetsEnabled.value = false;
      fileMountReady.value = true;
      openlistMountReady.value = true;
      fileServerReady.value = true;
      syncing.value = false;
      return;
    }
    if (forceRestart) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _pollCount = 0;
    }
    if (_pollTimer != null) return;
    unawaited(refreshStatus());
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      _pollCount += 1;
      await refreshStatus();
      final allReady =
          fileMountReady.value &&
          openlistMountReady.value &&
          fileServerReady.value;
      if (allReady && !syncing.value) {
        _pollTimer?.cancel();
        _pollTimer = null;
      } else if (_pollCount > 600) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    });
  }

  void ensurePolling() {
    startPolling(forceRestart: _pollTimer == null);
    unawaited(refreshStatus());
  }
}
