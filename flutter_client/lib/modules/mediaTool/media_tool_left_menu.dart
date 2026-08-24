import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/user/current_user_controller.dart';
import '../base/components/side_menu_two_level.dart';
import 'media_tool_controller.dart';

class MediaToolLeftMenu extends StatelessWidget {
  final MediaToolController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const MediaToolLeftMenu({
    super.key,
    required this.controller,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    final groups = <SideMenuTwoLevelGroup>[
      SideMenuTwoLevelGroup(
        title: 'media_tool_menu_image'.tr,
        icon: Icons.image_outlined,
        expanded: controller.isImageExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'media_tool_menu_image_compress'.tr,
            key: 'image.compress',
            icon: Icons.compress_outlined,
          ),
          if (isAdmin)
            TwoLevelSideMenuItem(
              title: 'media_tool_menu_image_batch_compress'.tr,
              key: 'image.batch_compress',
              icon: Icons.batch_prediction_outlined,
            ),
        ],
      ),
      if (isAdmin) ...[
        SideMenuTwoLevelGroup(
          title: 'media_tool_menu_video'.tr,
          icon: Icons.movie_outlined,
          expanded: controller.isVideoExpanded,
          items: [
            TwoLevelSideMenuItem(
              title: 'media_tool_menu_video_trans'.tr,
              key: 'video.trans',
              icon: Icons.transform_outlined,
            ),
          ],
        ),
        SideMenuTwoLevelGroup(
          title: 'media_tool_menu_audio'.tr,
          icon: Icons.audiotrack_outlined,
          expanded: controller.isAudioExpanded,
          items: [
            TwoLevelSideMenuItem(
              title: 'media_tool_menu_audio_trans'.tr,
              key: 'audio.trans',
              icon: Icons.graphic_eq_outlined,
            ),
          ],
        ),
        SideMenuTwoLevelGroup(
          title: 'media_tool_menu_other'.tr,
          icon: Icons.more_horiz_outlined,
          expanded: controller.isOtherExpanded,
          items: [
            TwoLevelSideMenuItem(
              title: 'media_tool_menu_media_arrange'.tr,
              key: 'other.media_arrange',
              icon: Icons.folder_copy_outlined,
            ),
          ],
        ),
      ],
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
    );
  }
}
