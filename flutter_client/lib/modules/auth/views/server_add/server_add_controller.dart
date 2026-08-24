import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../beans/server_info_bean.dart';
import '../../service/auth_api_service.dart';
import '../../service/server_storage_service.dart';
import '../../../../utils/dialog_util.dart';
import '../server_list/server_list_controller.dart';
import '../login/login_twofa_dialog.dart';
import '../../service/response/login_response.dart';

/// 添加服务器界面 - 使用 GetX 重构
class ServerAddController extends GetxController {
  // 表单字段
  final serverName = ''.obs;
  final serverUrl = ''.obs;
  final username = ''.obs;
  final password = ''.obs;
  final protocol = 'http'.obs;
  final needInputPwdEveryTime = false.obs;

  // 状态管理
  final isLoading = false.obs;
  final formKey = GlobalKey<FormState>();

  // TextEditingController
  late final TextEditingController serverNameController;
  late final TextEditingController serverUrlController;
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  late final TextEditingController pairCodeController;

  // TV 端地址栏焦点节点
  final FocusNode serverUrlFocusNode = FocusNode();

  // 预填充信息
  ServerInfoBean? prefillServerInfo;

  ServerAddController();

  bool get isP2pMode => prefillServerInfo?.isP2p == true;

  @override
  void onInit() {
    super.onInit();
    //拿到列表的controller 如果有选中的 则直接使用回填信息
    ServerListController serverListController =
        Get.find<ServerListController>();
    if (serverListController.selectedServerRx.value != null) {
      prefillServerInfo = serverListController.selectedServerRx.value;
    }

    // 初始化 TextEditingController
    serverNameController = TextEditingController();
    serverUrlController = TextEditingController();
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    pairCodeController = TextEditingController();
    // 移除自动焦点请求，避免干扰 TV 端返回按钮事件处理
    // if (!isP2pMode) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     serverUrlFocusNode.requestFocus();
    //   });
    // }

    // 根据预填充信息初始化表单
    if (prefillServerInfo != null) {
      _initializeFromPrefill();
    } else {
      serverName.value = 'NasCabServer';
      serverNameController.text = 'NasCabServer';
    }

    // 监听 TextEditingController 变化
    serverNameController.addListener(() {
      serverName.value = serverNameController.text;
    });
    serverUrlController.addListener(() {
      serverUrl.value = serverUrlController.text;
    });
    usernameController.addListener(() {
      username.value = usernameController.text;
    });
    passwordController.addListener(() {
      password.value = passwordController.text;
    });
  }

  /// 根据预填充信息初始化表单
  void _initializeFromPrefill() {
    if (prefillServerInfo != null) {
      final serverInfo = prefillServerInfo!;
      if (serverInfo.isP2p) {
        protocol.value = 'http';
        serverName.value = serverInfo.serverName.isNotEmpty
            ? serverInfo.serverName
            : 'P2P';
        serverUrl.value = '';
        username.value = serverInfo.username ?? '';
        password.value = serverInfo.password ?? '';
        needInputPwdEveryTime.value = serverInfo.needInputPwdEveryTime;
        pairCodeController.text = (serverInfo.pairCode ?? '').trim();

        serverNameController.text = serverName.value;
        serverUrlController.text = '';
        usernameController.text = serverInfo.username ?? '';
        passwordController.text = serverInfo.password ?? '';
        return;
      }

      final uri = Uri.parse(serverInfo.serverUrl);

      protocol.value = uri.scheme;
      serverName.value = serverInfo.serverName;
      serverUrl.value = '${uri.host}:${uri.port}';
      username.value = serverInfo.username ?? '';
      password.value = serverInfo.password ?? '';
      needInputPwdEveryTime.value = serverInfo.needInputPwdEveryTime;

      // 更新 TextEditingController
      serverNameController.text = serverInfo.serverName;
      serverUrlController.text = '${uri.host}:${uri.port}';
      usernameController.text = serverInfo.username ?? '';
      passwordController.text = serverInfo.password ?? '';
    }
  }

  /// 处理表单提交
  Future<void> handleSubmit() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    isLoading.value = true;

    try {
      final ServerInfoBean serverInfo;
      if (isP2pMode) {
        final code = (prefillServerInfo?.pairCode ?? '').trim();
        if (code.isEmpty) {
          _showErrorDialog('server_pair_code_empty'.tr);
          return;
        }
        serverInfo = ServerInfoBean(
          serverId: (prefillServerInfo?.serverId ?? '').trim(),
          serverUrl: (prefillServerInfo?.serverUrl ?? '').trim(),
          userInputUrl: (prefillServerInfo?.userInputUrl ?? '').trim(),
          serverName: serverName.value,
          serverHost: '',
          serverPortHttp: '',
          serverPortHttps: '',
          serverHostName: serverName.value,
          serverPlatform: 'unknown',
          isAutoScanned: false,
          isLocalServer: false,
          isP2p: (prefillServerInfo?.serverUrl.trim().isEmpty ?? true),
          pairCode: code,
          username: username.value,
          password: password.value,
          needInputPwdEveryTime: needInputPwdEveryTime.value,
        );
      } else {
        // 构建完整的服务器URL
        final fullServerUrl = '${protocol.value}://${serverUrl.value}';

        // 构建服务器信息
        serverInfo = ServerInfoBean(
          serverId: '',
          serverUrl: fullServerUrl,
          userInputUrl: fullServerUrl,
          serverName: serverName.value,
          serverHost: _extractHostFromUrl(fullServerUrl),
          serverPortHttp: _extractPortFromUrl(fullServerUrl),
          serverPortHttps: '',
          serverHostName: serverName.value,
          serverPlatform: 'unknown',
          isAutoScanned: false,
          isLocalServer: false,
          username: username.value,
          password: password.value,
          needInputPwdEveryTime: needInputPwdEveryTime.value,
        );
      }

      // 检查是否为NasCab服务器
      if (isP2pMode) {
        final code = (serverInfo.pairCode ?? '').trim();
        await ApiController.instance.connectP2pByPairCode(code);
        ApiController.instance.setBaseUrl(ApiController.p2pBaseUrl);
      } else {
        ApiController.instance.setBaseUrl(serverInfo.serverUrl);
      }
      final serverStatus = await AuthApiService.instance.checkServerStatus(
        true,
      );
      if (!serverStatus.isNasCabServer) {
        _showErrorDialog('server_add_invalid_server'.tr);
        return;
      }
      serverInfo.serverId =
          serverStatus.serverData?['serverId']?.toString() ??
          serverInfo.serverId;
      serverInfo.serverPortHttp =
          serverStatus.serverData?['httpPort']?.toString() ??
          serverInfo.serverPortHttp;
      serverInfo.serverPortHttps =
          serverStatus.serverData?['httpsPort']?.toString() ??
          serverInfo.serverPortHttps;
      serverInfo.serverHostName =
          serverStatus.serverData?['hostname']?.toString() ??
          serverInfo.serverHostName;
      serverInfo.serverPlatform =
          serverStatus.serverData?['platform']?.toString() ??
          serverInfo.serverPlatform;

      // 调用登录API
      final loginResult = await AuthApiService.instance.loginToServer(
        serverInfo,
      );

      if (!loginResult.success) {
        _showErrorDialog(loginResult.message ?? 'auth_login_failure'.tr);
        return;
      }

      if (loginResult.twoFactorRequired == true &&
          (loginResult.tempToken ?? '').isNotEmpty) {
        isLoading.value = false;
        _showTwofaDialog(serverInfo, loginResult.tempToken!);
        return;
      }

      await _handleLoginSuccess(serverInfo, loginResult);
    } catch (e) {
      _showErrorDialog(
        isP2pMode
            ? ApiController.formatP2pConnectError(e)
            : 'server_add_failure'.tr,
      );
    } finally {
      isLoading.value = false;
    }
  }

  void _showTwofaDialog(ServerInfoBean serverInfo, String tempToken) {
    if (Get.overlayContext == null) return;
    showDialog(
      context: Get.overlayContext!,
      barrierDismissible: false,
      builder: (_) => TwofaCodeDialog(
        onVerify: (code) {
          Get.back();
          _submitTwoFactor(serverInfo, tempToken, code);
        },
      ),
    );
  }

  Future<void> _submitTwoFactor(
    ServerInfoBean serverInfo,
    String tempToken,
    String code,
  ) async {
    DialogUtil.showLoadingDialog(
      message: 'auth_login_loading'.tr,
      barrierDismissible: false,
    );
    try {
      final verifyResult = await AuthApiService.instance.verifyTwoFactorLogin(
        tempToken: tempToken,
        code: code,
      );
      Get.back();
      if (!verifyResult.success) {
        _showErrorDialog(verifyResult.message ?? 'auth_login_failure'.tr);
        return;
      }
      await _handleLoginSuccess(serverInfo, verifyResult);
    } catch (e) {
      Get.back();
      _showErrorDialog('${'auth_login_failure'.tr}: $e');
    }
  }

  Future<void> _handleLoginSuccess(
    ServerInfoBean serverInfo,
    LoginResponse loginResult,
  ) async {
    final pair = (loginResult.pairCode ?? '').trim();
    final mergedPair = pair.isNotEmpty ? pair : serverInfo.pairCode;
    final lan = (loginResult.lanIpv4 ?? '').trim();
    String refreshedUrl = serverInfo.serverUrl;
    if (lan.isNotEmpty) {
      final currentUrl = serverInfo.serverUrl.trim();
      if (currentUrl.isEmpty) {
        refreshedUrl = _buildLanServerUrl(
          lan,
          loginResult.httpPort?.toString(),
          loginResult.httpsPort?.toString(),
        );
      }
    }
    final preservedInputUrl = (serverInfo.userInputUrl ?? '').trim();
    final identityUrl = preservedInputUrl.isNotEmpty
        ? serverInfo.userInputUrl
        : ((mergedPair ?? '').trim().isEmpty && refreshedUrl.trim().isNotEmpty
              ? refreshedUrl
              : serverInfo.userInputUrl);

    final updatedServerInfo = ServerInfoBean(
      serverId: loginResult.serverId ?? "",
      serverUrl: refreshedUrl,
      userInputUrl: identityUrl,
      lanIpv4: lan.isNotEmpty ? lan : serverInfo.lanIpv4,
      lanHttpPort: loginResult.httpPort?.toString() ?? serverInfo.lanHttpPort,
      lanHttpsPort:
          loginResult.httpsPort?.toString() ?? serverInfo.lanHttpsPort,
      serverName: serverInfo.serverName,
      serverHost: serverInfo.serverHost,
      serverPortHttp: loginResult.httpPort?.toString() ?? '9000',
      serverPortHttps: loginResult.httpsPort?.toString() ?? '9443',
      serverPlatform: loginResult.platform ?? 'unknown',
      serverHostName: loginResult.hostname ?? 'unknown',
      isAutoScanned: false,
      isLocalServer: false,
      isP2p:
          refreshedUrl.trim().isEmpty && (mergedPair ?? '').trim().isNotEmpty,
      pairCode: mergedPair,
      username: serverInfo.username,
      password: serverInfo.needInputPwdEveryTime ? '' : serverInfo.password,
      accessToken: loginResult.accessToken,
      refreshToken: loginResult.refreshToken,
      lastLoginTime: DateTime.now(),
      needInputPwdEveryTime: serverInfo.needInputPwdEveryTime,
    );

    await ServerStorageService.addServer(updatedServerInfo);
    _showSuccessDialog();
  }

  String _buildLanServerUrl(
    String lanIpv4,
    String? httpPort,
    String? httpsPort,
  ) {
    final lan = lanIpv4.trim();
    if (lan.isEmpty) return '';
    final port = (httpPort ?? '').trim().isNotEmpty
        ? httpPort!.trim()
        : ((httpsPort ?? '').trim().isNotEmpty ? httpsPort!.trim() : '9000');
    return 'http://$lan:$port';
  }

  /// 从URL中提取主机名
  String _extractHostFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  /// 从URL中提取端口
  String _extractPortFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.port.toString();
    } catch (e) {
      return '80';
    }
  }

  void goBack() {
    ServerListController serverListController =
        Get.find<ServerListController>();
    serverListController.showAddServerView.value = false;
  }

  Future<void> confirmGoBack() async {
    if (Get.overlayContext == null) {
      goBack();
      return;
    }
    final result = await DialogUtil.showConfirmDialog(
      title: 'server_add_exit_title'.tr,
      content: 'server_add_exit_content'.tr,
      onConfirm: goBack,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
      barrierDismissible: false,
    );
    if (result != true) return;
  }

  void refreshServerList() {
    ServerListController serverListController =
        Get.find<ServerListController>();
    serverListController.refreshSavedServers();
  }

  ///添加成功提示
  void _showSuccessDialog() {
    if (Get.overlayContext == null) return;
    DialogUtil.showConfirmDialog(
      title: 'server_add_success'.tr,
      content: 'server_add_success_message'.tr,
      onConfirm: () {
        refreshServerList();
        goBack();
      },
      confirmText: 'ok'.tr,
      cancelText: '',
      barrierDismissible: false,
    );
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    if (Get.overlayContext == null) return;
    DialogUtil.showErrorDialog(
      message: message,
      title: 'server_add_failure'.tr,
    );
  }

  /// 切换协议
  void toggleProtocol(String newProtocol) {
    protocol.value = newProtocol;
  }

  void toggleNeedInputPwdEveryTime(bool value) {
    needInputPwdEveryTime.value = value;
  }

  @override
  void onClose() {
    serverNameController.dispose();
    serverUrlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    pairCodeController.dispose();
    serverUrlFocusNode.dispose();
    super.onClose();
  }
}
