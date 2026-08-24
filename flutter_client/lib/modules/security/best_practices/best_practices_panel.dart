import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../home/views/pc_home_controller.dart';
import '../security_center_controller.dart';

class BestPracticesPanel extends StatelessWidget {
  final SecurityCenterController ctrl;
  const BestPracticesPanel({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Text(
            'security.best_practices'.tr,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          CustomGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(0),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'security.best_practices_desc'.tr,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildItem(
                      context,
                      number: '1',
                      text: 'security.best_practices_item1'.tr,
                    ),
                    const SizedBox(height: 16),
                    _buildItem(
                      context,
                      number: '2',
                      text: 'security.best_practices_item2'.tr,
                      trailing: _buildGoToUserButton(context),
                    ),
                    const SizedBox(height: 16),
                    _buildItem(
                      context,
                      number: '3',
                      text: 'security.best_practices_item3'.tr,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required String number,
    required String text,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: theme.textTheme.bodyMedium),
              if (trailing != null) ...[const SizedBox(height: 8), trailing],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoToUserButton(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'security.go_to_user'.tr,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                final homeCtrl = Get.find<PcHomeController>();
                homeCtrl.openApp(
                  windowId: 'user',
                  viewBuilder: homeCtrl.builtinAppViewBuilder('user'),
                  title: 'app_user'.tr,
                  icon: homeCtrl.buildAppIcon('user'),
                );
              },
          ),
        ],
      ),
    );
  }
}
