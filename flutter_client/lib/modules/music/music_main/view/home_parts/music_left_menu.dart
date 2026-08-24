import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/side_menu_two_level.dart';
import '../../controller/music_main_controller.dart';

class MusicLeftMenu extends StatelessWidget {
  final MusicMainController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const MusicLeftMenu({
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
        title: 'music_menu_library'.tr,
        icon: Icons.library_music_outlined,
        expanded: controller.isLibraryExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'music_menu_library_songs'.tr,
            key: 'library.songs',
            icon: Icons.music_note_outlined,
          ),

          TwoLevelSideMenuItem(
            title: 'favorites'.tr,
            key: 'library.favorite',
            icon: Icons.favorite_outline,
          ),
          TwoLevelSideMenuItem(
            title: 'music_menu_library_history'.tr,
            key: 'library.history',
            icon: Icons.history_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'music_menu_library_albums'.tr,
            key: 'library.albums',
            icon: Icons.album_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'music_menu_library_artists'.tr,
            key: 'library.artists',
            icon: Icons.people_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'photo_menu_all_file_view'.tr,
            key: 'library.file_view',
            icon: Icons.folder_outlined,
          ),
        ],
      ),
      SideMenuTwoLevelGroup(
        title: 'music_playlists'.tr,
        icon: Icons.library_music_outlined,
        expanded: controller.isPlaylistsExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'music_menu_library_playlists'.tr,
            key: 'library.playlists',
            icon: Icons.queue_music_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'music_collection_title'.tr,
            key: 'library.collection',
            icon: Icons.collections_bookmark_outlined,
          ),
        ],
      ),
      if (isAdmin || !DeviceUtils.isWeb)
        SideMenuTwoLevelGroup(
          title: 'setting'.tr,
          icon: Icons.settings_outlined,
          expanded: controller.isSettingsExpanded,
          items: [
            if (isAdmin)
              TwoLevelSideMenuItem(
                title: 'settings_source'.tr,
                key: 'settings.source',
                icon: Icons.folder_special_outlined,
              ),
            if (!DeviceUtils.isWeb)
              TwoLevelSideMenuItem(
                title: 'music_menu_settings_cache'.tr,
                key: 'settings.cache',
                icon: Icons.download_for_offline_outlined,
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
      topPlaceholderHeight: 45,
      headerTrailing: Obx(() {
        final songText = '${'music'.tr}:${controller.songCount.value}';
        final style = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(songText, style: style, textAlign: TextAlign.right),
            ],
          ),
        );
      }),
    );
  }
}
