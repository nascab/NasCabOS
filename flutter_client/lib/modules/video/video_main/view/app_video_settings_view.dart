import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/video/other_setting/view/video_other_settings_view.dart';
import 'package:NasCabOS/modules/video/source_setting/view/video_source_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppVideoSettingsView extends StatelessWidget {
  const AppVideoSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();

    return DefaultTabController(
      length: 2,
      child: ColoredBox(
        color: customColors?.mainContentBgColor ?? theme.colorScheme.surface,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: [
                    Tab(text: 'settings_source'.tr),
                    Tab(text: 'video_other_settings_title'.tr),
                  ],
                ),
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  KeyedSubtree(
                    key: ValueKey('app_video_settings_source'),
                    child: VideoSourceSettingsView(),
                  ),
                  KeyedSubtree(
                    key: ValueKey('app_video_settings_other'),
                    child: VideoOtherSettingsView(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
