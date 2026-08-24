import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../modules/base/components.dart';
import './server_add_controller.dart';
import '../../../../core/theme/dark_theme.dart';
import '../../../../utils/dimens_util.dart';

/// 添加服务器界面 - 使用 GetX 重构
class ServerAddView extends GetView<ServerAddController> {
  const ServerAddView({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取路由参数
    return GetBuilder<ServerAddController>(
      init: ServerAddController(),
      builder: (controller) {
        return _buildContent(context);
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
                      title: 'server_add'.tr,
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
                              controller: controller.serverNameController,
                              labelText: 'server_add_name_label'.tr,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'server_add_name_required'.tr;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            if (controller.isP2pMode) ...[
                              CustomTextField(
                                controller: controller.pairCodeController,
                                labelText: 'server_pair_code_label'.tr,
                                readOnly: true,
                                enabled: false,
                              ),
                              const SizedBox(height: 16),
                            ] else ...[
                              Row(
                                children: [
                                  Text(
                                    'server_add_protocol'.tr,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Obx(
                                    () => Row(
                                      children: [
                                        Radio<String>(
                                          value: 'http',
                                          groupValue: controller.protocol.value,
                                          onChanged: (String? value) {
                                            if (value != null) {
                                              controller.toggleProtocol(value);
                                            }
                                          },
                                        ),
                                        GestureDetector(
                                          onTap: () =>
                                              controller.toggleProtocol('http'),
                                          child: Text(
                                            'HTTP',
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Radio<String>(
                                          value: 'https',
                                          groupValue: controller.protocol.value,
                                          onChanged: (String? value) {
                                            if (value != null) {
                                              controller.toggleProtocol(value);
                                            }
                                          },
                                        ),
                                        GestureDetector(
                                          onTap: () => controller
                                              .toggleProtocol('https'),
                                          child: Text(
                                            'HTTPS',
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Obx(
                                () => CustomTextField(
                                  controller: controller.serverUrlController,
                                  labelText: 'server_add_address_label'.tr,
                                  hintText: 'server_add_address_hint'.tr,
                                  prefixText: '${controller.protocol.value}://',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'server_add_address_required'.tr;
                                    }
                                    final pattern = r'^[a-zA-Z0-9.-]+(:\d+)?$';
                                    if (!RegExp(pattern).hasMatch(value)) {
                                      return 'server_add_address_invalid'.tr;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
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
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            Obx(
                              () => CheckboxListTile(
                                value: controller.needInputPwdEveryTime.value,
                                onChanged: (value) =>
                                    controller.toggleNeedInputPwdEveryTime(
                                      value ?? false,
                                    ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  'server_need_input_password_every_time'.tr,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Obx(
                              () => CustomButton(
                                text: 'server_add_button'.tr,
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
