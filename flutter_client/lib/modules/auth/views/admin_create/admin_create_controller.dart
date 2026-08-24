import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../beans/server_info_bean.dart';
import '../../service/auth_api_service.dart';
import '../../service/server_storage_service.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../core/api/api_controller.dart';
import '../server_list/server_list_controller.dart';

/// 创建管理员界面 - 使用 GetX 重构
class AdminCreateController extends GetxController {
  // 表单字段
  final username = ''.obs;
  final password = ''.obs;
  final securityQuestion = ''.obs;
  final securityAnswer = ''.obs;
  final selectedQuestion = Rx<String?>(null);
  final isCustomQuestion = false.obs;

  // 状态管理
  final isLoading = false.obs;
  final formKey = GlobalKey<FormState>();

  // TextEditingController
  late final TextEditingController usernameController;
  late final TextEditingController passwordController;
  late final TextEditingController securityQuestionController;
  late final TextEditingController securityAnswerController;

  // 服务器信息
  late final ServerInfoBean serverInfo;

  // 预定义的密保问题列表
  final List<String> predefinedQuestions = [
    'admin_create_security_question_option1',
    'admin_create_security_question_option2',
    'admin_create_security_question_option3',
  ];

  AdminCreateController();

  @override
  void onInit() {
    super.onInit();

    // 尝试拿到列表的controller，如果未注册则走参数或baseUrl兜底
    final hasServerList = Get.isRegistered<ServerListController>();
    final ServerListController? serverListController = hasServerList
        ? Get.find<ServerListController>()
        : null;
    if (serverListController?.selectedServerRx.value != null) {
      serverInfo = serverListController!.selectedServerRx.value!;
    } else {
      final args = Get.arguments;
      if (args is ServerInfoBean) {
        serverInfo = args;
      } else {
        final baseUrl = ApiController.instance.baseUrl;
        ApiController.instance.setBaseUrl(baseUrl);
        serverInfo = ServerInfoBean(
          serverId: '',
          serverUrl: baseUrl,
          serverName: 'NasCabServer',
          serverHost: Uri.parse(baseUrl).host,
          serverPortHttp: '',
          serverPortHttps: '',
          serverHostName: 'unknown',
          serverPlatform: 'unknown',
          isAutoScanned: false,
          isLocalServer: false,
        );
        AuthApiService.instance.checkServerStatus(false).then((status) {
          serverInfo.serverId =
              status.serverData?['serverId'] ?? serverInfo.serverId;
          serverInfo.serverPortHttp =
              status.serverData?['httpPort']?.toString() ??
              serverInfo.serverPortHttp;
          serverInfo.serverPortHttps =
              status.serverData?['httpsPort']?.toString() ??
              serverInfo.serverPortHttps;
          serverInfo.serverHostName =
              status.serverData?['hostname'] ?? serverInfo.serverHostName;
          serverInfo.serverPlatform =
              status.serverData?['platform'] ?? serverInfo.serverPlatform;
        });
      }
    }
    // 初始化 TextEditingController
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    securityQuestionController = TextEditingController();
    securityAnswerController = TextEditingController();

    // 监听 TextEditingController 变化
    usernameController.addListener(() {
      username.value = usernameController.text;
    });
    passwordController.addListener(() {
      password.value = passwordController.text;
    });
    securityQuestionController.addListener(() {
      securityQuestion.value = securityQuestionController.text;
    });
    securityAnswerController.addListener(() {
      securityAnswer.value = securityAnswerController.text;
    });
  }

  @override
  void onClose() {
    // 清理 TextEditingController
    usernameController.dispose();
    passwordController.dispose();
    securityQuestionController.dispose();
    securityAnswerController.dispose();
    super.onClose();
  }

  /// 切换密保问题类型
  void toggleQuestionType(String? value) {
    selectedQuestion.value = value;
    isCustomQuestion.value = value == 'custom';
    if (!isCustomQuestion.value) {
      securityQuestionController.clear();
    }
  }

  /// 获取本地化的密保问题
  String getLocalizedQuestion(String questionKey) {
    switch (questionKey) {
      case 'admin_create_security_question_option1':
        return 'admin_create_security_question_option1'.tr;
      case 'admin_create_security_question_option2':
        return 'admin_create_security_question_option2'.tr;
      case 'admin_create_security_question_option3':
        return 'admin_create_security_question_option3'.tr;
      default:
        return questionKey;
    }
  }

  /// 处理表单提交
  Future<void> handleSubmit() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    isLoading.value = true;

    try {
      // 获取密保问题
      final question = isCustomQuestion.value
          ? securityQuestionController.text
          : getLocalizedQuestion(selectedQuestion.value!);

      // 调用创建管理员API
      ApiController.instance.setBaseUrl(serverInfo.serverUrl);
      final createResult = await AuthApiService.instance.createSuperAdmin(
        username: usernameController.text,
        password: passwordController.text,
        securityQuestion: question,
        securityAnswer: securityAnswerController.text,
      );

      if (!createResult.success) {
        _showErrorDialog(createResult.message ?? 'admin_create_failure'.tr);
        return;
      }

      // 更新服务器信息中的令牌信息
      final updatedServerInfo = ServerInfoBean(
        serverId: serverInfo.serverId,
        serverUrl: serverInfo.serverUrl,
        serverName: serverInfo.serverName,
        serverHost: serverInfo.serverHost,
        serverPortHttp: serverInfo.serverPortHttp,
        serverPortHttps: serverInfo.serverPortHttps,
        serverHostName: serverInfo.serverHostName,
        serverPlatform: serverInfo.serverPlatform,
        isAutoScanned: false,
        isLocalServer: false,
        username: usernameController.text,
        password: passwordController.text,
        accessToken: createResult.accessToken,
        refreshToken: createResult.refreshToken,
        lastLoginTime: DateTime.now(),
      );

      // 保存服务器信息到本地数据库
      final saveResult = await ServerStorageService.addServer(
        updatedServerInfo,
      );
      if (!saveResult) {
        _showErrorDialog('server_add_save_failure'.tr);
        return;
      }

      // 显示成功提示
      _showSuccessDialog();
    } catch (e) {
      // 显示错误提示
      _showErrorDialog('${'admin_create_failure'.tr}: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// 显示错误对话框
  void _showErrorDialog(String message) {
    if (Get.overlayContext == null) return;
    DialogUtil.showErrorDialog(
      message: message,
      title: 'admin_create_failure'.tr,
    );
  }

  void goBack() {
    if (Get.isRegistered<ServerListController>()) {
      final serverListController = Get.find<ServerListController>();
      serverListController.showCreateAdminView.value = false;
    } else {
      Get.back();
    }
  }

  void refreshServerList() {
    if (Get.isRegistered<ServerListController>()) {
      final serverListController = Get.find<ServerListController>();
      serverListController.refreshSavedServers();
    }
  }

  /// 显示成功对话框
  void _showSuccessDialog() {
    if (Get.context == null) return;
    DialogUtil.showConfirmDialog(
      title: 'admin_create_success'.tr,
      content: 'admin_create_success_message'.tr,
      onConfirm: () {
        refreshServerList();
        goBack();
      },
      confirmText: 'ok'.tr,
      cancelText: '',
    );
  }
}
