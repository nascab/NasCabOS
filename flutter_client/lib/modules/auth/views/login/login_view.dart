import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../modules/base/components.dart';
import '../../../../core/theme/dark_theme.dart';
import 'login_controller.dart';
import '../../../../core/bg/background_controller.dart';
import '../../../../utils/dimens_util.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/nascab_endpoints.dart';

/// 配对码登录视图：先输入配对码连接，成功后再显示账号密码登录；底部为隐私政策/用户协议；支持语言切换
class LoginView extends GetView<LoginController> {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LoginController>(
      init: LoginController(),
      builder: (controller) {
        return _buildContent(context, controller);
      },
    );
  }

  Widget _buildContent(BuildContext context, LoginController controller) {
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
                child: Column(
                  children: [
                    Expanded(child: _buildCenterView(context)),
                    _buildFooter(context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const String _privacyBase =
      '${NasCabEndpoints.websiteBaseUrl}/others/privacy.html';
  static const String _agreementBase =
      '${NasCabEndpoints.websiteBaseUrl}/others/agreement.html';
  static const String _helpBase =
      '${NasCabEndpoints.websiteBaseUrl}/others/helpP2p.html';

  static String _languageQuery() {
    final locale = Get.locale;
    if (locale == null) return 'en-US';
    final lang = locale.languageCode;
    final country = locale.countryCode?.isNotEmpty == true
        ? locale.countryCode!
        : '';
    return country.isNotEmpty ? '$lang-$country' : lang;
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final lang = _languageQuery();
    final privacyUrl = '$_privacyBase?language=$lang';
    final agreementUrl = '$_agreementBase?language=$lang';
    final helpUrl = '$_helpBase?language=$lang';
    final controller = Get.find<LoginController>();

    final separatorStyle = TextStyle(
      fontSize: 12,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    const linkStyle = TextStyle(fontSize: 12, color: Colors.white);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Obx(
          () => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () async {
                  final u = Uri.tryParse(privacyUrl);
                  if (u != null)
                    await launchUrl(u, mode: LaunchMode.platformDefault);
                },
                child: Text('auth_privacy_policy'.tr, style: linkStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('·', style: separatorStyle),
              ),
              GestureDetector(
                onTap: () async {
                  final u = Uri.tryParse(agreementUrl);
                  if (u != null)
                    await launchUrl(u, mode: LaunchMode.platformDefault);
                },
                child: Text('auth_user_agreement'.tr, style: linkStyle),
              ),
              if (controller.isCompanySite.value) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('·', style: separatorStyle),
                ),
                GestureDetector(
                  onTap: () async {
                    final u = Uri.tryParse(helpUrl);
                    if (u != null)
                      await launchUrl(u, mode: LaunchMode.platformDefault);
                  },
                  child: Text('auth_help'.tr, style: linkStyle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterView(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = DeviceUtils.isPhone(context);
    final controller = Get.find<LoginController>();

    return Center(
      child: Container(
        height: isMobile ? double.infinity : null,
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 500,
          maxHeight: isMobile ? double.infinity : 500,
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
                title: controller.welcomeTitle.value.isNotEmpty
                    ? controller.welcomeTitle.value
                    : 'auth_welcome_title'.tr,
                subtitle: controller.connectedHostName.value.isNotEmpty
                    ? 'auth_connected_host'.trParams({
                        'host': controller.connectedHostName.value,
                      })
                    : null,
                actions: kIsWeb
                    ? [
                        CustomLanguageSelector(
                          iconColor: theme.colorScheme.onSurface.withValues(
                            alpha: 0.8,
                          ),
                          tooltip: 'language'.tr,
                        ),
                      ]
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: AutofillGroup(
                  child: Form(
                    key: controller.formKey,
                    child: Obx(() {
                      final showOnlyPairCode =
                          controller.showPairCodeInput.value &&
                          controller.connectedHostName.value.isEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (controller.showPairCodeInput.value) ...[
                            CustomTextField(
                              controller: controller.pairCodeController,
                              labelText: 'auth_pair_code_label'.tr,
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: controller.isPairCodeConnecting.value
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : TextButton(
                                        onPressed:
                                            controller.connectP2pByPairCode,
                                        child: Text(
                                          'auth_pair_code_connect'.tr,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (!showOnlyPairCode) ...[
                            CustomTextField(
                              controller: controller.usernameController,
                              labelText: 'username'.tr,
                              autofillHints: const [AutofillHints.username],
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
                              autofillHints: const [AutofillHints.password],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'server_add_password_required'.tr;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            if (!controller.isCompanySite.value)
                              Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: () => controller.goToRecover(),
                                  child: Text(
                                    'auth_forgot_password'.tr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                            CustomButton(
                              text: 'auth_login_button'.tr,
                              onPressed: controller.isLoading.value
                                  ? null
                                  : controller.handleLogin,
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
                        ],
                      );
                    }),
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
