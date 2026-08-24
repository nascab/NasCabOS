import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../core/bg_task/hw_metrics_controller.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../utils/dimens_util.dart';
import '../pc_home_controller.dart';
import '../components/user_info_dialog.dart';

class PcHomeStatusBar extends StatelessWidget implements PreferredSizeWidget {
  final double height;
  const PcHomeStatusBar({super.key, this.height = 36});

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userCtrl = CurrentUserController.instance;
    final hwCtrl = HwMetricsController.instance;
    final username = userCtrl.current?.username ?? '-';

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: user dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              onTap: () {
                Get.dialog(const UserInfoDialog());
              },
              child: Row(
                children: [
                  Text(username, style: theme.textTheme.titleSmall),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: theme.colorScheme.onSurface,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Right: metrics and icons
          Obx(() {
            // cpu ram 网速等
            final m = hwCtrl.metrics;
            final cpuUsage = (m?['cpu']?['usage'] ?? '-').toString();
            final memUsage = (m?['memory']?['usage'] ?? '-').toString();
            final netDown = (m?['network']?['downloadSpeed'] ?? '-').toString();
            final netUp = (m?['network']?['uploadSpeed'] ?? '-').toString();
            return Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CPU: ${cpuUsage == '-' ? '-' : '$cpuUsage%'}',
                      style: TextStyle(fontSize: Dimens.t8),
                    ),
                    Text(
                      '${'status_net_up'.tr}: $netUp',
                      style: TextStyle(fontSize: Dimens.t8),
                    ),
                  ],
                ),
                const SizedBox(width: 8),

                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAM: ${memUsage == '-' ? '-' : '$memUsage%'}',
                      style: TextStyle(fontSize: Dimens.t8),
                    ),
                    Text(
                      '${'status_net_down'.tr}: $netDown',
                      style: TextStyle(fontSize: Dimens.t8),
                    ),
                  ],
                ),
              ],
            );
          }),

          const SizedBox(width: 16),
          _iconWithTooltip(
            context,
            Icons.monitor_heart,
            'home_status_monitor'.tr,
            () {
              final ctrl = PcHomeController.instance;
              final desktopRect = ctrl.getDeskRect();
              const size = Size(320, 620);
              ctrl.openApp(
                windowId: 'monitor',
                viewBuilder: ctrl.builtinAppViewBuilder('monitor'),
                title: 'app_monitor'.tr,
                icon: ctrl.buildAppIcon('monitor'),
                showTitle: false,
                resizable: false,
                maximizable: false,
                minimizable: false,
                minSize: size,
                initialSize: size,
                initialPosition: Offset(
                  desktopRect.right - size.width,
                  desktopRect.top,
                ),
              );
            },
          ),
          _iconWithTooltip(
            context,
            Icons.notifications_none,
            'home_status_message'.tr,
            () {},
          ),
          _iconWithTooltip(
            context,
            Icons.playlist_add_check_circle,
            'home_status_bg_tasks'.tr,
            () {
              final ctrl = PcHomeController.instance;
              final desktopRect = ctrl.getDeskRect();
              final w = ctrl.windows.defaultWindowWidth;
              final h = ctrl.windows.defaultWindowHeight;
              ctrl.openApp(
                windowId: 'task_center',
                viewBuilder: ctrl.builtinAppViewBuilder('task_center'),
                title: 'app_task_center'.tr,
                icon: ctrl.buildAppIcon('task_center'),
                initialSize: Size(w, h),
                initialPosition: Offset(desktopRect.right - w, desktopRect.top),
              );
            },
          ),
          _iconWithTooltip(context, Icons.settings, 'setting'.tr, () {
            AppRoutes.toSettings();
          }),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _iconWithTooltip(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
