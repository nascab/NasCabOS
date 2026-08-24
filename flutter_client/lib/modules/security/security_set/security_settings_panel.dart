import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../base/components.dart';
import '../security_center_controller.dart';

class SecuritySettingsPanel extends StatelessWidget {
  final SecurityCenterController ctrl;
  final bool appMode;
  const SecuritySettingsPanel({
    super.key,
    required this.ctrl,
    this.appMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = appMode
        ? const EdgeInsets.fromLTRB(18, 10, 18, 16)
        : const EdgeInsets.all(12);
    return Padding(
      padding: padding,
      child: ListView(
        padding: EdgeInsets.zero,
        primary: false,
        physics: const ClampingScrollPhysics(),
        children: [
          if (!appMode)
            Text(
              'security.title'.tr,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          if (!appMode) const SizedBox(height: 12),
          CustomGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'security.ip_ban_rules'.tr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Obx(() {
                    return SwitchListTile(
                      activeColor: theme.colorScheme.primary,
                      value: ctrl.banEnabled.value,
                      onChanged: (v) => ctrl.banEnabled.value = v,
                      title: Text('security.enable_ip_ban'.tr),
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          controller: ctrl.maxFailedAttemptsController,
                          labelText: 'security.failed_attempts'.tr,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomTextField(
                          controller: ctrl.banMinutesController,
                          labelText: 'security.ban_minutes'.tr,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      CustomButton(text: 'save'.tr, onPressed: ctrl.saveConfig),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Obx(() {
                    return SwitchListTile(
                      activeColor: theme.colorScheme.primary,
                      value: ctrl.bypassLanAuth.value,
                      onChanged: (v) => ctrl.bypassLanAuth.value = v,
                      title: Text('security.bypass_lan_auth'.tr),
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
