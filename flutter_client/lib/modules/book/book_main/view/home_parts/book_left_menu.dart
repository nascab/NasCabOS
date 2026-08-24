import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/side_menu_two_level.dart';
import '../../controller/book_main_controller.dart';

class BookLeftMenu extends StatelessWidget {
  final BookMainController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const BookLeftMenu({
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
        title: 'book_menu_library'.tr,
        icon: Icons.local_library_outlined,
        expanded: controller.isLibraryExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'book_menu_library_book'.tr,
            key: 'library.book',
            icon: Icons.book_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'book_menu_library_comic'.tr,
            key: 'library.comic',
            icon: Icons.auto_stories_outlined,
          ),

          TwoLevelSideMenuItem(
            title: 'favorites'.tr,
            key: 'library.favorite',
            icon: Icons.favorite_border,
          ),
          TwoLevelSideMenuItem(
            title: 'book_menu_library_history'.tr,
            key: 'library.history',
            icon: Icons.history,
          ),
          TwoLevelSideMenuItem(
            title: 'photo_menu_all_file_view'.tr,
            key: 'library.file_view',
            icon: Icons.folder_outlined,
          ),
        ],
      ),
      SideMenuTwoLevelGroup(
        title: 'book_menu_book_list'.tr,
        icon: Icons.playlist_play_outlined,
        expanded: controller.isBookListExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'book_menu_book_list_custom'.tr,
            key: 'book_list.custom',
            icon: Icons.playlist_add_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'book_collection_title'.tr,
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
                title: 'book_menu_settings_cache_download'.tr,
                key: 'settings.cache_download',
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
      headerTrailing: Obx(() {
        final bookText =
            '${'book_menu_library_book'.tr}:${controller.bookCount.value}';
        final comicText =
            '${'book_menu_library_comic'.tr}:${controller.comicCount.value}';
        final style = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bookText, style: style, textAlign: TextAlign.right),
              Text(comicText, style: style, textAlign: TextAlign.right),
            ],
          ),
        );
      }),
    );
  }
}
