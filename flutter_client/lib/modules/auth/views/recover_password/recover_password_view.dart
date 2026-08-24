import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../modules/base/components.dart';
import 'recover_password_controller.dart';
import '../../../../core/bg/background_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../../utils/dimens_util.dart';
import '../../../../utils/dialog_util.dart';

/// 密码恢复界面
class RecoverView extends GetView<RecoverPasswordController> {
  const RecoverView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<RecoverPasswordController>(
      init: RecoverPasswordController(),
      builder: (controller) {
        return _buildContent(context, controller);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    RecoverPasswordController controller,
  ) {
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: Obx(
              () => Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(BackgroundController.instance.loginBgUrl),
                    fit: BoxFit.cover,
                  ),
                ),
                child: _buildCenterView(context),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCenterView(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = DeviceUtils.isPhone(context);

    return Center(
      child: Container(
        height: isMobile ? double.infinity : null,
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 500,
          maxHeight: isMobile ? double.infinity : 800,
        ),
        margin: isMobile
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(
            DimensUtil.authCenterCardRadius(context),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomAuthHeader(
                title: 'recover_title'.tr,
                onBack: controller.goBack,
                actions: [
                  // 帮助
                  CustomIconButton(
                    icon: Icons.help_rounded,
                    tooltip: 'tip'.tr,
                    onPressed: () => {
                      DialogUtil.showInfoDialog(
                        title: 'tip'.tr,
                        content: 'auth_recover_tip'.tr,
                      ),
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 用户名输入框（输入框尾部提供“找回”按钮）
                      CustomTextField(
                        controller: controller.usernameController,
                        labelText: 'username'.tr,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'server_add_username_required'.tr;
                          }
                          return null;
                        },
                        suffixIcon: TextButton(
                          onPressed: controller.isLoading.value
                              ? null
                              : controller.fetchRecoverInfo,
                          child: Text('recover_button'.tr),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 密保问题与后续组件，仅在成功获取找回信息后显示
                      Obx(
                        () => controller.hasRecoverInfo.value
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'auth_recover_security_question_label'.tr,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.dividerColor.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      controller.securityQuestion.value,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  CustomTextField(
                                    controller: controller.answerController,
                                    labelText: 'recover_answer_label'.tr,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'recover_answer_required'.tr;
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  CustomTextField(
                                    controller:
                                        controller.newPasswordController,
                                    labelText: 'recover_new_password_label'.tr,
                                    obscureText: true,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'server_add_password_required'
                                            .tr;
                                      }
                                      if (value.length < 6) {
                                        return 'auth_password_too_short'.tr;
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  CustomButton(
                                    text: 'recover_button'.tr,
                                    onPressed: controller.isLoading.value
                                        ? null
                                        : controller.handleRecover,
                                    isDisabled: controller.isLoading.value,
                                    icon: controller.isLoading.value
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
