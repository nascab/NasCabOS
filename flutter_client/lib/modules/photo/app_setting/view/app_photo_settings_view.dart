import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/device_utils.dart';
import '../../ai_setting/view/photo_ai_settings_view.dart';
import '../../preview_setting/view/photo_preview_settings_view.dart';
import '../../source_setting/view/photo_source_settings_view.dart';

class AppPhotoSettingsView extends StatelessWidget {
  final int initialTabIndex;
  const AppPhotoSettingsView({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.surface;

    final isAdmin = CurrentUserController.instance.isAdmin;
    final showOnlyPreview = DeviceUtils.isPhone(context) && !isAdmin;

    if (showOnlyPreview) {
      return Scaffold(
        appBar: AppBar(title: Text('setting'.tr)),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: barColor,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: barColor,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarDividerColor: barColor,
          ),
          child: const PhotoPreviewSettingsView(),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(title: Text('setting'.tr)),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: barColor,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: barColor,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarDividerColor: barColor,
          ),
          child: const TabBarView(
            children: [
              PhotoSourceSettingsView(),
              PhotoPreviewSettingsView(),
              PhotoAiSettingsView(),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          color: barColor,
          child: SafeArea(
            top: false,
            child: TabBar(
              dividerColor: Colors.transparent,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              tabs: [
                Tab(
                  icon: Icon(Icons.folder_outlined),
                  text: 'settings_source'.tr,
                ),
                Tab(
                  icon: Icon(Icons.tune_outlined),
                  text: 'photo_preview_settings_title'.tr,
                ),
                Tab(
                  icon: Icon(Icons.auto_awesome_outlined),
                  text: 'photo_ai_settings_title'.tr,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
