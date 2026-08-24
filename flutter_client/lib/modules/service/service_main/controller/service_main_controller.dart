import 'dart:async';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../account/service/nascab_account_api_service.dart';
import '../../../../core/languages/language_service.dart';
import '../../../../utils/toast_util.dart';
import '../../../../core/config/nascab_endpoints.dart';

class ServiceMainController extends GetxController {
  final NasCabAccountApiService _api = NasCabAccountApiService.instance;

  final RxString currentPageKey = 'account.nascab'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isAccountExpanded = true.obs;
  final RxBool isContactExpanded = true.obs;

  final RxBool remoteAccessEnabled = false.obs;
  final RxString pairCode = ''.obs;
  final RxString p2pErrorCode = ''.obs;
  final RxString p2pConnectedDomain = ''.obs;
  final RxString p2pFixNodeDomain = ''.obs;
  final RxList<Map<String, String>> p2pServers = <Map<String, String>>[].obs;
  final RxBool remoteAccessLoading = false.obs;
  final RxBool nascabLoggedIn = false.obs;

  final RxBool ddnsEnabled = false.obs;
  final RxnString ddnsType = RxnString();
  final RxnString ddnsTypeDraft = RxnString();
  final RxString ddnsDomain = ''.obs;
  final RxString ddnsBase = ''.obs;
  final RxString ddnsFullDomain = ''.obs;
  final RxString ddnsPublicIp = ''.obs;
  final RxString ddnsLastIp = ''.obs;
  final RxString ddnsLastTime = ''.obs;
  final RxString ddnsLastError = ''.obs;
  final RxString ddnsDeviceId = ''.obs;
  final RxBool ddnsLoading = false.obs;
  final RxBool ddnsStatusReady = false.obs;
  final RxBool ddnsStatusLoadFailed = false.obs;

  Timer? _pairCodePollTimer;
  bool _pairCodePollingActive = false;

  /// 远程访问页调用：打开页面后每3秒刷新一次二维码状态
  void startPairCodePolling() {
    if (_pairCodePollingActive) return;
    _pairCodePollingActive = true;
    _scheduleNextPairCodePoll();
  }

  void stopPairCodePolling() {
    _pairCodePollingActive = false;
    _pairCodePollTimer?.cancel();
    _pairCodePollTimer = null;
  }

  /// 只要页面打开就持续定时刷新
  void _scheduleNextPairCodePoll() {
    if (!_pairCodePollingActive) return;
    _pairCodePollTimer?.cancel();
    _pairCodePollTimer = Timer(const Duration(seconds: 3), () async {
      if (!_pairCodePollingActive) return;
      await refreshRemoteAccess(showLoading: false);
      if (_pairCodePollingActive) {
        _scheduleNextPairCodePoll();
      }
    });
  }

  void selectPage(String key) {
    currentPageKey.value = key;
  }

  @override
  void onInit() {
    super.onInit();
    refreshRemoteAccess();
  }

  Future<void> refreshDdnsStatus({
    bool showLoading = true,
    bool force = false,
  }) async {
    if (ddnsLoading.value && !force) return;
    final shouldToggleLoading =
        (showLoading || !ddnsStatusReady.value) && !ddnsLoading.value;
    if (shouldToggleLoading) ddnsLoading.value = true;
    ddnsStatusLoadFailed.value = false;
    var requestSucceeded = false;
    try {
      final userRes = await _api.query();
      if (!userRes.success) return;
      final userData = userRes.success ? (userRes.data ?? const {}) : const {};
      final loggedIn = userData.isNotEmpty;
      nascabLoggedIn.value = loggedIn;
      if (!loggedIn) {
        ddnsEnabled.value = false;
        ddnsType.value = null;
        ddnsTypeDraft.value = null;
        ddnsDomain.value = '';
        ddnsBase.value = '';
        ddnsFullDomain.value = '';
        ddnsPublicIp.value = '';
        ddnsLastIp.value = '';
        ddnsLastTime.value = '';
        ddnsLastError.value = '';
        ddnsDeviceId.value = '';
        requestSucceeded = true;
        return;
      }
      final res = await _api.getDdnsStatus();
      if (!res.success) return;
      final data = res.data ?? const {};
      ddnsEnabled.value = data['enabled'] == true;
      final nextType = data['ddnsType']?.toString().trim() ?? '';
      ddnsType.value = nextType.isEmpty ? null : nextType;
      ddnsDomain.value = data['ddnsDomain']?.toString().trim() ?? '';
      ddnsBase.value = data['ddnsBase']?.toString().trim() ?? '';
      ddnsFullDomain.value = data['ddnsFullDomain']?.toString().trim() ?? '';
      ddnsPublicIp.value = data['publicIp']?.toString().trim() ?? '';
      ddnsLastIp.value = data['ddnsLastIp']?.toString().trim() ?? '';
      ddnsLastTime.value = data['ddnsLastTime']?.toString().trim() ?? '';
      ddnsLastError.value = data['ddnsLastError']?.toString().trim() ?? '';
      ddnsDeviceId.value = data['deviceId']?.toString().trim() ?? '';
      requestSucceeded = true;
    } finally {
      if (requestSucceeded) {
        ddnsStatusReady.value = true;
        ddnsStatusLoadFailed.value = false;
      } else if (!ddnsStatusReady.value) {
        ddnsStatusLoadFailed.value = true;
      }
      if (shouldToggleLoading) ddnsLoading.value = false;
    }
  }

  Future<bool> ensureDdnsTypeDefault({bool refresh = false}) async {
    if (ddnsLoading.value) return false;
    ddnsLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success ? (userRes.data ?? const {}) : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return false;

      final currentType = ddnsType.value?.trim() ?? '';
      if (currentType.isNotEmpty) {
        ddnsTypeDraft.value = null;
        return true;
      }

      final nextType = (ddnsTypeDraft.value?.trim().isNotEmpty ?? false)
          ? ddnsTypeDraft.value!.trim()
          : 'ipv4';
      final res = await _api.setDdnsType(nextType);
      if (!res.success) return false;

      ddnsType.value = nextType;
      ddnsTypeDraft.value = null;
      if (refresh) {
        await refreshDdnsStatus(showLoading: false, force: true);
      }
      return true;
    } finally {
      ddnsLoading.value = false;
    }
  }

  Future<bool> setDdnsEnabled(bool enabled) async {
    if (ddnsLoading.value) return false;
    ddnsLoading.value = true;
    try {
      if (enabled) {
        if (!nascabLoggedIn.value) {
          final userRes = await _api.query();
          final userData = userRes.success
              ? (userRes.data ?? const {})
              : const {};
          nascabLoggedIn.value = userData.isNotEmpty;
        }
        if (!nascabLoggedIn.value) return false;
        if (ddnsDomain.value.trim().isEmpty) return false;
        if ((ddnsType.value?.trim() ?? '').isEmpty) {
          final typeRes = await _api.setDdnsType('ipv4');
          if (!typeRes.success) return false;
          ddnsType.value = 'ipv4';
          ddnsTypeDraft.value = null;
        }
      }
      final res = await _api.setDdnsEnabled(enabled);
      if (!res.success) return false;
      ddnsEnabled.value = enabled;
      await refreshDdnsStatus(showLoading: false, force: true);
      if (enabled) {
        Future.delayed(const Duration(seconds: 2), () {
          refreshDdnsStatus(showLoading: false, force: true);
        });
        Future.delayed(const Duration(seconds: 6), () {
          refreshDdnsStatus(showLoading: false, force: true);
        });
      }
      return true;
    } finally {
      ddnsLoading.value = false;
    }
  }

  Future<bool> setDdnsTypeValue(String nextType) async {
    if (ddnsLoading.value) return false;
    ddnsLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success
            ? (userRes.data ?? const {})
            : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return false;
      final res = await _api.setDdnsType(nextType.trim());
      if (!res.success) return false;
      ddnsTypeDraft.value = null;
      await refreshDdnsStatus(showLoading: false, force: true);
      return true;
    } finally {
      ddnsLoading.value = false;
    }
  }

  Future<bool> setDdnsDomainPrefix({required String ddnsDomainPrefix}) async {
    if (ddnsLoading.value) return false;
    ddnsLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success
            ? (userRes.data ?? const {})
            : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return false;
      final res = await _api.setDdnsDomain(ddnsDomain: ddnsDomainPrefix.trim());
      if (!res.success) {
        final raw = res.rawResponse;
        final errKey = raw is Map ? raw['code']?.toString().trim() ?? '' : '';
        final resMsg = (res.message ?? '').trim();
        if (errKey.isNotEmpty) {
          final trMsg = errKey.tr;
          if (trMsg != errKey) {
            ToastUtil.show(trMsg);
          } else if (resMsg.isNotEmpty) {
            ToastUtil.show(resMsg);
          } else {
            ToastUtil.show(errKey);
          }
        } else if (resMsg.isNotEmpty) {
          ToastUtil.show(resMsg);
        } else {
          ToastUtil.show('operation_failed'.tr);
        }
        return false;
      }
      if ((ddnsType.value?.trim() ?? '').isEmpty) {
        final typeRes = await _api.setDdnsType('ipv4');
        if (typeRes.success) {
          ddnsType.value = 'ipv4';
          ddnsTypeDraft.value = null;
        }
      }
      await refreshDdnsStatus(showLoading: false, force: true);
      return true;
    } finally {
      ddnsLoading.value = false;
    }
  }

  Future<void> refreshRemoteAccess({bool showLoading = true}) async {
    if (remoteAccessLoading.value) return;
    if (showLoading) remoteAccessLoading.value = true;
    try {
      final userRes = await _api.query();
      final userData = userRes.success ? (userRes.data ?? const {}) : const {};
      final loggedIn = userData.isNotEmpty;
      nascabLoggedIn.value = loggedIn;
      if (!loggedIn) {
        remoteAccessEnabled.value = false;
        pairCode.value = '';
        p2pErrorCode.value = '';
        p2pConnectedDomain.value = '';
        p2pFixNodeDomain.value = '';
        p2pServers.clear();
        return;
      }
      final res = await _api.getP2pRemoteAccess();
      if (res.success) {
        final data = res.data ?? const {};
        final enabled = data['enabled'];
        remoteAccessEnabled.value = enabled == true;
        final code = data['pairCode']?.toString().trim() ?? '';
        pairCode.value = code;
        final errCode = data['errorCode']?.toString().trim() ?? '';
        p2pErrorCode.value = errCode;
        p2pConnectedDomain.value =
            data['p2pConnectedDomain']?.toString().trim() ?? '';
        p2pFixNodeDomain.value =
            data['p2pFixNodeDomain']?.toString().trim() ?? '';
        final rawServers = data['p2pServers'];
        if (rawServers is List) {
          p2pServers.value = rawServers
              .map(
                (e) => {
                  'chinese_name': e is Map
                      ? e['chinese_name']?.toString().trim() ?? ''
                      : '',
                  'english_name': e is Map
                      ? e['english_name']?.toString().trim() ?? ''
                      : '',
                  'name': e is Map ? e['name']?.toString().trim() ?? '' : '',
                  'host': e is Map ? e['host']?.toString().trim() ?? '' : '',
                  'domain': e is Map
                      ? e['domain']?.toString().trim() ?? ''
                      : '',
                },
              )
              .where((e) => (e['domain'] ?? '').isNotEmpty)
              .toList();
        } else {
          p2pServers.clear();
        }
      }
    } finally {
      if (showLoading) remoteAccessLoading.value = false;
    }
  }

  Future<bool> setRemoteAccessEnabled(bool enabled) async {
    if (remoteAccessLoading.value) return false;
    remoteAccessLoading.value = true;
    try {
      if (enabled) {
        if (!nascabLoggedIn.value) {
          final userRes = await _api.query();
          final userData = userRes.success
              ? (userRes.data ?? const {})
              : const {};
          nascabLoggedIn.value = userData.isNotEmpty;
        }
        if (!nascabLoggedIn.value) return false;
      }
      final res = await _api.setP2pRemoteAccess(enabled);
      if (!res.success) return false;
      remoteAccessEnabled.value = enabled;
      await refreshRemoteAccess();
      return true;
    } finally {
      remoteAccessLoading.value = false;
    }
  }

  Future<bool> resetPairCode() async {
    if (remoteAccessLoading.value) return false;
    remoteAccessLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success
            ? (userRes.data ?? const {})
            : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return false;

      final res = await _api.resetP2pPairCode();
      if (!res.success) return false;
      final data = res.data ?? const {};
      final code = data['pairCode']?.toString().trim() ?? '';
      if (code.isEmpty) return false;
      pairCode.value = code;
      return true;
    } finally {
      remoteAccessLoading.value = false;
    }
  }

  Future<bool> customPairCode(String nextPairCode) async {
    if (remoteAccessLoading.value) return false;
    remoteAccessLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success
            ? (userRes.data ?? const {})
            : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return false;

      final res = await _api.customP2pPairCode(nextPairCode);
      if (!res.success) {
        final raw = res.rawResponse;
        final errKey = raw is Map ? raw['code']?.toString().trim() ?? '' : '';
        final resMsg = (res.message ?? '').trim();
        if (errKey.isNotEmpty) {
          final trMsg = errKey.tr;
          if (trMsg != errKey) {
            ToastUtil.show(trMsg);
          } else if (resMsg.isNotEmpty) {
            ToastUtil.show(resMsg);
          } else {
            ToastUtil.show(errKey);
          }
        } else if (resMsg.isNotEmpty) {
          ToastUtil.show(resMsg);
        } else {
          ToastUtil.show('operation_failed'.tr);
        }
        return false;
      }

      final data = res.data ?? const {};
      final code = data['pairCode']?.toString().trim() ?? '';
      if (code.isEmpty) return false;
      pairCode.value = code;
      return true;
    } finally {
      remoteAccessLoading.value = false;
    }
  }

  Future<bool> setP2pNodePreference(String domain) async {
    if (remoteAccessLoading.value) return false;
    remoteAccessLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success
            ? (userRes.data ?? const {})
            : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return false;
      final res = await _api.setP2pNodePreference(domain);
      if (!res.success) return false;
      p2pFixNodeDomain.value = domain.trim();
      await refreshRemoteAccess(showLoading: false);
      return true;
    } finally {
      remoteAccessLoading.value = false;
    }
  }

  /// 绑定当前设备到 NasCab 账号（用于 P2P 远程连接）
  /// 返回 Map: {'success': bool, 'errorCode': String?}
  Future<Map<String, dynamic>> bindP2pDevice() async {
    if (remoteAccessLoading.value) return {'success': false};
    remoteAccessLoading.value = true;
    try {
      if (!nascabLoggedIn.value) {
        final userRes = await _api.query();
        final userData = userRes.success
            ? (userRes.data ?? const {})
            : const {};
        nascabLoggedIn.value = userData.isNotEmpty;
      }
      if (!nascabLoggedIn.value) return {'success': false};
      final res = await _api.bindP2pDevice();
      if (!res.success) {
        final raw = res.rawResponse;
        final errCode = raw is Map ? raw['code']?.toString().trim() ?? '' : '';
        return {'success': false, 'errorCode': errCode};
      }
      await _api.refresh();
      await refreshRemoteAccess();
      return {'success': true};
    } finally {
      remoteAccessLoading.value = false;
    }
  }

  /// 打开「我的设备」页面（与账号页的「我的设备」一致）
  Future<void> openMyDevicesUrl() async {
    if (!nascabLoggedIn.value) {
      ToastUtil.show('service_nascab_not_logged_in'.tr);
      return;
    }
    try {
      final res = await _api.getTempCode();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final code = res.data?['code']?.toString().trim() ?? '';
      if (code.isEmpty) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      final language = LanguageService.to.currentLocale;
      final uri = Uri.parse(
        '${NasCabEndpoints.websiteBaseUrl}/user/devices?code=$code&language=$language',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ToastUtil.show('operation_failed'.tr);
      }
    } catch (e) {
      ToastUtil.show('network_failure'.tr);
    }
  }
}
