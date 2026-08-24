import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/side_menu_two_level.dart';
import '../../controller/video_main_controller.dart';

class VideoLeftMenu extends StatelessWidget {
  final VideoMainController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const VideoLeftMenu({
    super.key,
    required this.controller,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = CurrentUserController.instance.isAdmin;
    final groups = <SideMenuTwoLevelGroup>[
      SideMenuTwoLevelGroup(
        title: 'video_menu_library'.tr,
        icon: Icons.movie_outlined,
        expanded: controller.isLibraryExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'video_menu_library_home'.tr,
            key: 'library.home',
            icon: Icons.home_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'video_home_type_movie'.tr,
            key: 'library.movie',
            icon: Icons.movie_filter_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'video_home_type_tv'.tr,
            key: 'library.tv',
            icon: Icons.tv_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'video_menu_library_history'.tr,
            key: 'library.history',
            icon: Icons.history,
          ),
          TwoLevelSideMenuItem(
            title: 'favorites'.tr,
            key: 'library.favorites',
            icon: Icons.favorite_outline,
          ),
          TwoLevelSideMenuItem(
            title: 'photo_menu_all_file_view'.tr,
            key: 'library.file_view',
            icon: Icons.folder_outlined,
          ),
        ],
      ),
      SideMenuTwoLevelGroup(
        title: 'video_menu_albums'.tr,
        icon: Icons.collections_bookmark_outlined,
        expanded: controller.isAlbumExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'video_custom_album_title'.tr,
            key: 'albums.album',
            icon: Icons.video_collection_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'video_smart_album_title'.tr,
            key: 'albums.smart',
            icon: Icons.auto_awesome_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'video_collection_title'.tr,
            key: 'albums.collection',
            icon: Icons.collections_bookmark_outlined,
          ),
        ],
      ),
      if (isAdmin)
        SideMenuTwoLevelGroup(
          title: 'setting'.tr,
          icon: Icons.settings_outlined,
          expanded: controller.isSettingsExpanded,
          items: [
            TwoLevelSideMenuItem(
              title: 'settings_source'.tr,
              key: 'settings.source',
              icon: Icons.folder_special_outlined,
            ),
            TwoLevelSideMenuItem(
              title: 'video_menu_settings_other'.tr,
              key: 'settings.other',
              icon: Icons.tune_outlined,
            ),
          ],
        ),
    ];
    return TwoLevelSideMenu(
      currentKey: controller.currentPageKey,
      onSelect: controller.selectPage,
      groups: groups,
      collapsed: collapsed,
      onToggleCollapse: onToggleCollapse,
      toggleExpandTooltip: 'sidebar_expand'.tr,
      toggleCollapseTooltip: 'sidebar_collapse'.tr,
      topPlaceholderHeight: 30,
      headerTrailing: Obx(() {
        final movieText =
            '${'video_home_type_movie'.tr}:${controller.movieCount.value}';
        final tvText = '${'video_home_type_tv'.tr}:${controller.tvCount.value}';
        final style = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(movieText, style: style, textAlign: TextAlign.right),
              Text(tvText, style: style, textAlign: TextAlign.right),
            ],
          ),
        );
      }),
    );
  }
}
