part of '../file_mount_view.dart';

class _LeftMenu extends StatelessWidget {
  final FileMountController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const _LeftMenu({
    required this.controller,
    required this.collapsed,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final items = <OneLevelSideMenuItem>[
      OneLevelSideMenuItem(
        title: 'file_mount_menu_manage'.tr,
        key: 'mount.list',
        icon: Icons.folder_special_outlined,
      ),
      OneLevelSideMenuItem(
        title: 'file_mount_menu_openlist'.tr,
        key: 'mount.openlist',
        icon: Icons.cloud_outlined,
      ),
    ];
    return OneLevelSideMenu(
      currentKey: controller.currentPageKey,
      onSelect: controller.selectPage,
      items: items,
      collapsed: collapsed,
      onToggleCollapse: onToggleCollapse,
      toggleExpandTooltip: 'sidebar_expand'.tr,
      toggleCollapseTooltip: 'sidebar_collapse'.tr,
      topPlaceholderHeight: 45,
    );
  }
}
