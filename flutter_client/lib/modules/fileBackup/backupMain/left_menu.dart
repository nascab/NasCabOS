part of 'file_backup_view.dart';

class _LeftMenu extends StatelessWidget {
  final FileBackupController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const _LeftMenu({
    required this.controller,
    required this.collapsed,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    final items = <OneLevelSideMenuItem>[
      if (isAdmin)
        OneLevelSideMenuItem(
          title: 'file_backup_menu_disk'.tr,
          key: 'backup.disk',
          icon: Icons.swap_horiz_outlined,
        ),
      if (!DeviceUtils.isWeb && !DeviceUtils.isMobile)
        OneLevelSideMenuItem(
          title: 'local_backup_menu'.tr,
          key: 'backup.local',
          icon: Icons.cloud_upload_outlined,
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
