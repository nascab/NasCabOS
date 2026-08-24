import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../service/auth_api_service.dart';
import '../../../../utils/dialog_util.dart';

class RecoverPasswordController extends GetxController {
  final username = ''.obs;
  final answer = ''.obs;
  final newPassword = ''.obs;
  final isLoading = false.obs;
  final securityQuestion = ''.obs;
  final showUsernameField = true.obs;
  final hasRecoverInfo = false.obs;
  final formKey = GlobalKey<FormState>();

  late final TextEditingController usernameController;
  late final TextEditingController answerController;
  late final TextEditingController newPasswordController;

  @override
  void onInit() {
    super.onInit();
    usernameController = TextEditingController();
    answerController = TextEditingController();
    newPasswordController = TextEditingController();

    usernameController.addListener(() {
      username.value = usernameController.text;
    });
    answerController.addListener(() {
      answer.value = answerController.text;
    });
    newPasswordController.addListener(() {
      newPassword.value = newPasswordController.text;
    });

    // 初始进入页面仅显示用户名输入，不主动请求
  }

  /// 根据用户名获取找回密码信息
  Future<void> fetchRecoverInfo() async {
    final u = usernameController.text.trim();
    if (u.isEmpty) {
      _showErrorDialog('server_add_username_required'.tr);
      return;
    }
    isLoading.value = true;
    try {
      final result = await AuthApiService.instance.getRecoverInfo(username: u);
      if (result.success && result.question != null) {
        securityQuestion.value = result.question!;
        hasRecoverInfo.value = true;
        // 固定用户名，避免误改
        usernameController.text = u;
        showUsernameField.value = true;
      } else {
        hasRecoverInfo.value = false;
        _showErrorDialog(result.message ?? 'auth_recover_info_failure'.tr);
      }
    } catch (e) {
      hasRecoverInfo.value = false;
      _showErrorDialog('auth_recover_info_failure'.tr);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> handleRecover() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    isLoading.value = true;
    try {
      final result = await AuthApiService.instance.recoverAdminPassword(
        username: username.value,
        answer: answer.value,
        newPassword: newPassword.value,
      );
      if (!result.success) {
        _showErrorDialog(result.message ?? 'recover_failure'.tr);
        return;
      }
      _showSuccessDialog();
    } catch (e) {
      _showErrorDialog('recover_failure'.tr);
    } finally {
      isLoading.value = false;
    }
  }

  void goBack() {
    Get.back();
  }

  void _showSuccessDialog() {
    if (Get.overlayContext == null) return;
    DialogUtil.showConfirmDialog(
      title: 'recover_success'.tr,
      content: 'recover_success_message'.tr,
      onConfirm: () {
        Get.back();
      },
      confirmText: 'ok'.tr,
      cancelText: '',
    );
  }

  void _showErrorDialog(String message) {
    if (Get.overlayContext == null) return;
    DialogUtil.showErrorDialog(message: message, title: 'recover_failure'.tr);
  }

  @override
  void onClose() {
    usernameController.dispose();
    answerController.dispose();
    newPasswordController.dispose();
    super.onClose();
  }
}
