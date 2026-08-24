import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../app_home_controller.dart';
import '../components/user_info_dialog.dart';
import 'app_wallpaper_picker_view.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../core/api/api_controller.dart';
import '../../../base/components/custom_divider.dart';
import '../../../message/views/message_center_view.dart';
import '../../../../utils/device_utils.dart';

class AppServerInfoCard extends StatelessWidget {
  final AppHomeController controller;
  final EdgeInsetsGeometry? margin;

  const AppServerInfoCard({super.key, required this.controller, this.margin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Get.dialog(const UserInfoDialog());
        },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Obx(() {
                    final server = controller.currentServer;
                    final platform =
                        server?.serverPlatform.toLowerCase() ?? 'linux';
                    String iconPath = 'assets/home/server_linux.png';
                    if (platform.contains('win')) {
                      iconPath = 'assets/home/server_windows.png';
                    }
                    if (platform.contains('mac') ||
                        platform.contains('darwin')) {
                      iconPath = 'assets/home/server_mac.png';
                    }

                    return Image.asset(
                      iconPath,
                      width: 48,
                      height: 48,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.dns, size: 48),
                    );
                  }),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Obx(() {
                      final server = controller.currentServer;
                      final user = CurrentUserController.instance.current;
                      final api = ApiController.instance;
                      api.connectChannelRevision.value;
                      final channelValue = api.connectChannelDisplayValue;
                      final unknown = 'home_unknown'.tr;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${server?.getPlatformFriendlyName() ?? unknown} - ${server == null ? 'home_server_default'.tr : server.displayHostName}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.username ?? unknown,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (DeviceUtils.isMobile) ...[
                                if (api.connectChannelRefreshing.value)
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  )
                                else
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      api.refreshConnectChannel();
                                    },
                                    child: Icon(
                                      Icons.refresh,
                                      size: 14,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  channelValue,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.wallpaper_outlined,
                      color: theme.colorScheme.onSurface,
                      size: 22,
                    ),
                    tooltip: 'home_desktop_change_wallpaper'.tr,
                    onPressed: () {
                      final size = MediaQuery.sizeOf(context);
                      Get.dialog(
                        Dialog(
                          insetPadding: EdgeInsets.zero,
                          backgroundColor: theme.scaffoldBackgroundColor,
                          child: Container(
                            width: size.width,
                            height: size.height,
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const AppWallpaperPickerView(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CustomDivider(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  Get.to(
                    () => MessageCenterView(showAppBar: DeviceUtils.isMobile),
                  );
                },
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_none,
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Obx(() {
                        final msg = controller.serverMessage.value;
                        return Text(
                          msg.isEmpty ? 'home_no_message'.tr : msg,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      }),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (margin == null) return card;
    return Padding(padding: margin!, child: card);
  }
}
