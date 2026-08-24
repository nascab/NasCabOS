import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../modules/base/components.dart';
import './admin_create_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../../utils/dimens_util.dart';

/// 创建管理员界面 - 使用 GetX 重构
class AdminCreateView extends GetView<AdminCreateController> {
  const AdminCreateView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AdminCreateController>(
      init: AdminCreateController(),
      builder: (controller) {
        return Obx(() => _buildContent(context));
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return Theme(
      data: darkTheme,
      child: Builder(
        builder: (context) {
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
                      title: 'admin_create_title'.tr,
                      onBack: () => controller.goBack(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: controller.formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CustomTextField(
                              controller: controller.usernameController,
                              labelText: 'username'.tr,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'server_add_username_required'.tr;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: controller.passwordController,
                              labelText: 'password'.tr,
                              obscureText: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'server_add_password_required'.tr;
                                }
                                if (value.length < 6) {
                                  return 'auth_password_too_short'.tr;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomDropdownField<String>(
                                  value: controller.selectedQuestion.value,
                                  labelText:
                                      'admin_create_security_question_label'.tr,
                                  items: [
                                    ...controller.predefinedQuestions.map((
                                      questionKey,
                                    ) {
                                      return DropdownMenuItem<String>(
                                        value: questionKey,
                                        child: Text(
                                          controller.getLocalizedQuestion(
                                            questionKey,
                                          ),
                                        ),
                                      );
                                    }),
                                    DropdownMenuItem<String>(
                                      value: 'custom',
                                      child: Text(
                                        'admin_create_security_question_custom'
                                            .tr,
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) =>
                                      controller.toggleQuestionType(value),
                                  validator: (value) {
                                    if (value == null) {
                                      return 'admin_create_security_question_required'
                                          .tr;
                                    }
                                    return null;
                                  },
                                  filled: true,
                                ),
                                Column(
                                  children: [
                                    if (controller.isCustomQuestion.value)
                                      const SizedBox(height: 16),
                                    if (controller.isCustomQuestion.value)
                                      CustomTextField(
                                        controller: controller
                                            .securityQuestionController,
                                        labelText:
                                            'admin_create_security_question_custom'
                                                .tr,
                                        validator: (value) {
                                          if (controller
                                                  .isCustomQuestion
                                                  .value &&
                                              (value == null ||
                                                  value.isEmpty)) {
                                            return 'admin_create_security_question_required'
                                                .tr;
                                          }
                                          return null;
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              controller: controller.securityAnswerController,
                              labelText:
                                  'admin_create_security_answer_label'.tr,
                              obscureText: false,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'admin_create_security_answer_required'
                                      .tr;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 32),
                            CustomButton(
                              text: 'admin_create_button'.tr,
                              onPressed: controller.isLoading.value
                                  ? null
                                  : () => controller.handleSubmit(),
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
