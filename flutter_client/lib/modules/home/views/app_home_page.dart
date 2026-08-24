import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app_home_controller.dart';
import '../../../core/user/current_user_controller.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/routes/app_routes.dart';
import 'components/session_wallpaper_background.dart';
import 'app_components/app_home_top_area.dart';
import 'app_components/app_monitor_card.dart';
import 'app_components/app_apps_grid.dart';

/// App端主页
/// App Home Page
class AppHomePage extends StatelessWidget {
  const AppHomePage({super.key});

  /// 本地无登录状态时显示占位页，避免空白或异常
  Widget _buildSessionExpiredPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'service_nascab_session_expired'.tr,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    CurrentUserController.instance.clear();
                    ApiController.instance.clearAuthInfo();
                    AppRoutes.toLogin();
                  },
                  child: Text('ok'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageBackground(BuildContext context) {
    final theme = Theme.of(context);
    return SessionWallpaperBackground(
      fit: BoxFit.cover,
      placeholder: ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!CurrentUserController.instance.isLoggedIn ||
        !ApiController.instance.state.isAuthenticated) {
      return _buildSessionExpiredPlaceholder(context);
    }
    final controller = Get.put(AppHomeController());
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPageBackground(context),
          Column(
            children: [
              AppHomeTopArea(controller: controller),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    12,
                    0,
                    MediaQuery.of(context).padding.bottom + 20,
                  ),
                  children: [
                    const AppMonitorCard(),
                    const SizedBox(height: 12),
                    AppAppsGrid(controller: controller),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
