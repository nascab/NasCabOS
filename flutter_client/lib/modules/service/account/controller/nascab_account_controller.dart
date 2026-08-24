import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/core/languages/language_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../utils/dialog_util.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../../core/config/nascab_endpoints.dart';
import '../service/nascab_account_api_service.dart';
import '../service/nascab_desktop_oauth_stub.dart'
    if (dart.library.io) '../service/nascab_desktop_oauth_io.dart';
import '../../service_main/controller/service_main_controller.dart';

import '../../../../core/web/nascab_auth_stub.dart'
    if (dart.library.html) '../../../../core/web/nascab_auth_web.dart';

class NasCabAccountController extends GetxController {
  final NasCabAccountApiService _api = NasCabAccountApiService.instance;

  final Rxn<Map<String, dynamic>> user = Rxn<Map<String, dynamic>>();
  final RxBool isLoading = false.obs;
  final RxString errorText = ''.obs;

  bool get isLoggedIn =>
      user.value != null && (user.value?.isNotEmpty ?? false);

  @override
  void onInit() {
    super.onInit();
    refreshUser();
  }

  Future<void> refreshUser() async {
    isLoading.value = true;
    errorText.value = '';
    try {
      final res = await _api.query();
      if (!res.success) {
        errorText.value = res.message ?? 'network_failure'.tr;
        user.value = null;
        return;
      }

      final data = res.data ?? {};
      print("data: $data");
      if (data.isEmpty) {
        user.value = null;
        return;
      }
      user.value = Map<String, dynamic>.from(data);
    } catch (e) {
      errorText.value = 'network_failure'.tr;
      user.value = null;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshAccount() async {
    isLoading.value = true;
    errorText.value = '';
    try {
      final res = await _api.refresh();
      if (res.code == 401) {
        errorText.value = 'service_nascab_session_expired'.tr;
        user.value = null;
        return;
      }
      if (!res.success) {
        errorText.value = res.message ?? 'network_failure'.tr;
        return;
      }
      final data = res.data ?? {};
      if (data.isEmpty) {
        user.value = null;
        return;
      }
      user.value = Map<String, dynamic>.from(data);
      if (Get.isRegistered<ServiceMainController>()) {
        final main = Get.find<ServiceMainController>();
        await main.refreshRemoteAccess();
      }
    } catch (e) {
      errorText.value = 'network_failure'.tr;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    if (ApiController.instance.isP2pMode) {
      final p2pConfirmed = await DialogUtil.showConfirmDialog(
        title: 'tip'.tr,
        content: 'service_nascab_p2p_logout_switch_confirm'.tr,
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (p2pConfirmed != true) return;
    }

    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'service_nascab_logout_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirmed != true) return;

    DialogUtil.showLoading(message: 'service_nascab_logging_out'.tr);
    try {
      await ApiController.instance.disconnectP2p().catchError((_) {});
      final res = await _api.logout();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final cache = CacheManager();
      await cache.remove(CacheKeys.nascabOsJwt);
      user.value = null;
      if (Get.isRegistered<ServiceMainController>()) {
        final main = Get.find<ServiceMainController>();
        await main.refreshRemoteAccess();
      }
      ToastUtil.show('service_nascab_logged_out'.tr);
    } catch (e) {
      ToastUtil.show('network_failure'.tr);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> login() async {
    if (DeviceUtils.isMobile) {
      ToastUtil.show('service_nascab_app_not_supported'.tr);
      return;
    }

    dynamic authResult;
    if (kIsWeb) {
      final authUrl = _buildAuthUrl();
      authResult = await openNasCabAuthPopup(
        authUrl,
        timeout: const Duration(minutes: 2),
      );
    } else {
      NasCabDesktopOAuthSession? oauth;
      try {
        oauth = await startNasCabDesktopOAuthSession(
          language: LanguageService.to.currentLocale,
        );
        final authUrl = _buildAuthUrlWithRedirect(oauth.redirectUrl);
        final uri = Uri.parse(authUrl);
        if (!await canLaunchUrl(uri)) {
          ToastUtil.show('operation_failed'.tr);
          return;
        }
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          ToastUtil.show('operation_failed'.tr);
          return;
        }
        authResult = await oauth.result;
      } finally {
        await oauth?.shutdown();
      }
    }

    final code = authResult != null && authResult['code'] != null
        ? authResult['code']!.trim()
        : '';
    final jwt = authResult != null && authResult['jwt'] != null
        ? authResult['jwt']!.trim()
        : '';
    if (code.isEmpty && jwt.isEmpty) {
      ToastUtil.show('service_nascab_login_cancelled'.tr);
      return;
    }

    DialogUtil.showLoading(message: 'service_nascab_logging_in'.tr);
    try {
      final res = code.isNotEmpty
          ? await _api.loginWithCode(code)
          : await _api.login(jwt);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      if (jwt.isNotEmpty) {
        await CacheManager().setString(CacheKeys.nascabOsJwt, jwt);
      }
      final u = res.data ?? {};
      user.value = u.isEmpty ? null : Map<String, dynamic>.from(u);
      if (!kIsWeb) {
        await refreshUser();
      }
      if (Get.isRegistered<ServiceMainController>()) {
        final main = Get.find<ServiceMainController>();
        await main.refreshRemoteAccess();
      }
      ToastUtil.show('service_nascab_logged_in'.tr);
    } catch (e) {
      ToastUtil.show('network_failure'.tr);
    } finally {
      DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> switchAccount() async {
    if (ApiController.instance.isP2pMode) {
      final p2pConfirmed = await DialogUtil.showConfirmDialog(
        title: 'tip'.tr,
        content: 'service_nascab_p2p_logout_switch_confirm'.tr,
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (p2pConfirmed != true) return;
    }
    await login();
  }

  String _buildRedirectUrl() {
    if (kIsWeb) {
      // 使用不带 hash 的静态 HTML 回调页，避免 Chrome 从 HTTPS(nas.cab)
      // 导航到 http://localhost 时剥离 hash 和 query 参数导致回调丢失
      return '${Uri.base.origin}/nascab-callback.html';
    }
    return '${ApiController.signalApiBaseUrl}/nascab-callback';
  }

  String _buildAuthUrlWithRedirect(String redirectUrl) {
    final encoded = Uri.encodeComponent(redirectUrl);
    final language = LanguageService.to.currentLocale;
    return '${ApiController.signalApiBaseUrl}/user?redirect_url=$encoded&needCode=1&newLogin=1&language=$language';
  }

  String _buildAuthUrl() {
    return _buildAuthUrlWithRedirect(_buildRedirectUrl());
  }

  /// 打开购买会员页面，先获取 tempCode 再跳转。iOS 设备不支持购买，会弹窗提示并返回 false。
  /// 返回 true 表示已成功打开购买页，调用方可据此决定是否展示“购买完成后请刷新”的提示。
  Future<bool> openPurchaseUrl() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      DialogUtil.showInfoDialog(
        title: 'tip'.tr,
        content: 'service_nascab_purchase_ios_unsupported'.tr,
      );
      return false;
    }
    return _openUrlWithTempCode('order');
  }

  /// 带 tempCode 和 language 打开 nas.cab/user/[path]，成功打开返回 true，否则返回 false。
  Future<bool> _openUrlWithTempCode(String path) async {
    if (!isLoggedIn) {
      ToastUtil.show('service_nascab_not_logged_in'.tr);
      return false;
    }
    try {
      final res = await _api.getTempCode();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      final code = res.data?['code']?.toString().trim() ?? '';
      if (code.isEmpty) {
        ToastUtil.show('operation_failed'.tr);
        return false;
      }
      final language = LanguageService.to.currentLocale;
      final uri = Uri.parse(
        '${NasCabEndpoints.websiteBaseUrl}/user/$path?code=$code&language=$language',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        ToastUtil.show('operation_failed'.tr);
        return false;
      }
    } catch (e) {
      ToastUtil.show('network_failure'.tr);
      return false;
    }
  }

  /// 个人中心
  Future<void> openUserCenterUrl() async => _openUrlWithTempCode('userCenter');

  /// 我的设备
  Future<void> openMyDevicesUrl() async => _openUrlWithTempCode('devices');

  /// 推广页
  Future<void> openPromotionUrl() async => _openUrlWithTempCode('promotion');

  /// 版本区别（无需 code）
  Future<void> openVipDiffUrl() async {
    final language = LanguageService.to.currentLocale;
    final uri = Uri.parse(
      '${NasCabEndpoints.websiteBaseUrl}/others/vipDiff.html?language=$language',
    );
    try {
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
