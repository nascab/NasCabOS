import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../transfer/views/app_task_center_page.dart';

class AppFileTopActionsBar extends StatelessWidget {
  const AppFileTopActionsBar({
    super.key,
    required this.onBackPressed,
    required this.onClosePressed,
    required this.showClose,
    required this.onCreatePressed,
    required this.title,
    this.showBack = true,
  });

  final VoidCallback onBackPressed;
  final VoidCallback onClosePressed;
  final bool showClose;
  final bool showBack;
  final VoidCallback onCreatePressed;
  final String title;

  @override
  Widget build(BuildContext context) {
    final showLeadingCreate = !showBack;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        children: [
          if (showLeadingCreate)
            _roundIconBtn(
              context,
              icon: Icons.add,
              tooltip: 'folder_action_new'.tr,
              onTap: onCreatePressed,
            ),
          if (showBack)
            _roundIconBtn(
              context,
              icon: Icons.arrow_back_ios_new_rounded,
              tooltip: 'back'.tr,
              onTap: onBackPressed,
            ),
          if (showClose) ...[
            if (showBack) const SizedBox(width: 10),
            _roundIconBtn(
              context,
              icon: Icons.close_rounded,
              tooltip: 'home_window_close'.tr,
              onTap: onClosePressed,
            ),
          ],
          Expanded(
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (!showLeadingCreate) ...[
            _roundIconBtn(
              context,
              icon: Icons.add,
              tooltip: 'folder_action_new'.tr,
              onTap: onCreatePressed,
            ),
            const SizedBox(width: 10),
          ],
          _roundIconBtn(
            context,
            icon: Icons.task_outlined,
            tooltip: 'home_task_center'.tr,
            onTap: () => Get.to(() => const AppTaskCenterPage()),
          ),
        ],
      ),
    );
  }

  Widget _roundIconBtn(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    // final theme = Theme.of(context);
    return CustomBorderedIconButton(icon: icon, tooltip: tooltip, onTap: onTap);
  }
}
