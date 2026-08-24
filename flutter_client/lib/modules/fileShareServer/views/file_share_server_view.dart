import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import '../../../utils/device_utils.dart';
import '../../base/components.dart';
import '../../base/components/custom_glass_card.dart';
import '../../base/components/custom_switch.dart';
import '../../base/components/side_menu_two_level.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../user/components/custom_user_card.dart';
import '../controllers/file_share_server_controller.dart';
import 'quick_share_config_view.dart';
import '../../../utils/dialog_util.dart';
import '../../../core/user/current_user_controller.dart';
import '../../../core/services/mount_plugin_status_service.dart';
import '../../base/components/mount_plugin_not_ready_banner.dart';

part 'parts/file_share_server_type_panel.dart';
part 'parts/file_share_server_service_header.dart';
part 'parts/file_share_server_config_card.dart';
part 'parts/file_share_server_ports_settings_dialog.dart';
part 'parts/file_share_server_config_dialog_models.dart';
part 'parts/file_share_server_config_dialog.dart';
part 'parts/file_share_server_config_dialog_state.dart';
part 'parts/file_share_server_user_picker_dialog.dart';
part 'parts/file_share_server_root_path_row.dart';
part 'parts/file_share_server_user_share_folders_panel.dart';

class FileShareServerView extends GetView<FileShareServerController> {
  final String? initialPageKey;
  const FileShareServerView({super.key, this.initialPageKey});

  @override
  Widget build(BuildContext context) {
    MountPluginStatusService.ensure().ensurePolling();
    return GetBuilder<FileShareServerController>(
      init: FileShareServerController(initialPageKey: initialPageKey),
      builder: (ctrl) {
        final isMobile = DeviceUtils.isMobile;
        final isAdmin = CurrentUserController.instance.isAdmin;
        final initKeyRaw = initialPageKey?.toString().trim() ?? '';
        final args = Get.arguments;
        final argKeyRaw = args is Map
            ? (args['pageKey']?.toString().trim() ?? '')
            : '';
        final rawKey = initKeyRaw.isNotEmpty ? initKeyRaw : argKeyRaw;
        // 普通用户仅允许访问快速分享页面
        final desiredKey = (!isAdmin && rawKey != 'share.quick')
            ? 'share.quick'
            : rawKey;
        if (desiredKey.isNotEmpty &&
            desiredKey != ctrl.currentPageKey.value &&
            (desiredKey.startsWith('share.') ||
                desiredKey.startsWith('settings.'))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (desiredKey != ctrl.currentPageKey.value) {
              if (isMobile && desiredKey == 'settings.ports') {
                ctrl.openPortsSettingsOnInit.value = true;
                return;
              }
              ctrl.selectPage(desiredKey);
            }
          });
        }
        if (isMobile) {
          return _FileShareMobileScaffold(ctrl: ctrl);
        }
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;
          return Scaffold(
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: leftWidth,
                  child: _FileShareLeftMenu(
                    controller: ctrl,
                    collapsed: collapsed,
                    onToggleCollapse: () =>
                        ctrl.sidebarCollapsed.value = !collapsed,
                  ),
                ),
                Expanded(child: _buildRight(ctrl)),
              ],
            ),
          );
        });
      },
    );
  }
}

class _FileShareMobileScaffold extends StatelessWidget {
  final FileShareServerController ctrl;

  const _FileShareMobileScaffold({required this.ctrl});

  int _indexForKey(String key, bool isAdmin) {
    if (!isAdmin) return 0;
    switch (key) {
      case 'share.quick':
        return 0;
      case 'share.webdav':
        return 1;
      case 'share.ftp':
        return 2;
      case 'share.sftp':
        return 3;
      case 'share.user_folders':
        return 4;
    }
    return 0;
  }

  String _keyForIndex(int index, bool isAdmin) {
    if (!isAdmin) return 'share.quick';
    switch (index) {
      case 0:
        return 'share.quick';
      case 1:
        return 'share.webdav';
      case 2:
        return 'share.ftp';
      case 3:
        return 'share.sftp';
      case 4:
        return 'share.user_folders';
    }
    return 'share.webdav';
  }

  String _titleForKey(String key) {
    switch (key) {
      case 'share.quick':
        return 'quick_share_title'.tr;
      case 'share.ftp':
        return 'file_share_server_ftp'.tr;
      case 'share.sftp':
        return 'file_share_server_sftp'.tr;
      case 'share.user_folders':
        return 'user_share_folders_title'.tr;
      case 'share.webdav':
      default:
        return 'file_share_server_webdav'.tr;
    }
  }

  void _openPortsSettings() {
    Get.to(
      () => _FileSharePortsSettingsPage(ctrl: ctrl),
      transition: Transition.cupertino,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = CurrentUserController.instance.isAdmin;
    return Obx(() {
      final key = ctrl.currentPageKey.value;
      final idx = _indexForKey(key, isAdmin);

      if (ctrl.openPortsSettingsOnInit.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!ctrl.openPortsSettingsOnInit.value) return;
          ctrl.openPortsSettingsOnInit.value = false;
          _openPortsSettings();
        });
      }

      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(_titleForKey(key)),
          centerTitle: true,
          actions: [
            if (isAdmin)
              IconButton(
                tooltip: 'file_share_server_ports_settings'.tr,
                onPressed: _openPortsSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Obx(() {
                final plugin = MountPluginStatusService.ensure();
                final showBanner =
                    isAdmin &&
                    (key == 'share.webdav' ||
                        key == 'share.ftp' ||
                        key == 'share.sftp');
                return MountPluginNotReadyBanner(
                  ready: !showBanner || plugin.canUseFileServer,
                );
              }),
              Expanded(
                child: IndexedStack(
                  index: idx,
                  children: [
                    const QuickShareConfigView(showTitle: false),
                    if (isAdmin) ...[
                      _TypePanel(serverType: 'WebDav', ctrl: ctrl),
                      _TypePanel(serverType: 'FTP', ctrl: ctrl),
                      _TypePanel(serverType: 'SFTP', ctrl: ctrl),
                      _UserShareFoldersPanel(ctrl: ctrl),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: isAdmin
            ? BottomNavigationBar(
                currentIndex: idx,
                selectedItemColor: theme.colorScheme.primary,
                unselectedItemColor: theme.colorScheme.onSurfaceVariant,
                type: BottomNavigationBarType.fixed,
                onTap: (next) => ctrl.selectPage(_keyForIndex(next, isAdmin)),
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.link_outlined),
                    label: 'quick_share_title'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.cloud_sync_outlined),
                    label: 'file_share_server_webdav'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.cloud_sync_outlined),
                    label: 'file_share_server_ftp'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.cloud_done_outlined),
                    label: 'file_share_server_sftp'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.folder_shared_outlined),
                    label: 'user_share_folders_title'.tr,
                  ),
                ],
              )
            : null,
      );
    });
  }
}

class _FileSharePortsSettingsPage extends StatelessWidget {
  final FileShareServerController ctrl;

  const _FileSharePortsSettingsPage({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('file_share_server_ports_settings'.tr),
        centerTitle: true,
      ),
      body: SafeArea(top: false, child: _PortsSettingsView(ctrl: ctrl)),
    );
  }
}

class _FileShareLeftMenu extends StatelessWidget {
  final FileShareServerController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const _FileShareLeftMenu({
    required this.controller,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    final groups = <SideMenuTwoLevelGroup>[
      SideMenuTwoLevelGroup(
        title: 'app_share'.tr,
        icon: Icons.share_outlined,
        expanded: controller.isShareManageExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'quick_share_title'.tr,
            key: 'share.quick',
            icon: Icons.link_outlined,
          ),
          if (isAdmin) ...[
            TwoLevelSideMenuItem(
              title: 'user_share_folders_title'.tr,
              key: 'share.user_folders',
              icon: Icons.folder_shared_outlined,
            ),
            TwoLevelSideMenuItem(
              title: 'file_share_server_webdav'.tr,
              key: 'share.webdav',
              icon: Icons.cloud_sync_outlined,
            ),
            TwoLevelSideMenuItem(
              title: 'file_share_server_ftp'.tr,
              key: 'share.ftp',
              icon: Icons.cloud_sync_outlined,
            ),
            TwoLevelSideMenuItem(
              title: 'file_share_server_sftp'.tr,
              key: 'share.sftp',
              icon: Icons.cloud_done_outlined,
            ),
          ],
        ],
      ),
      if (isAdmin)
        SideMenuTwoLevelGroup(
          title: 'setting'.tr,
          icon: Icons.settings_outlined,
          expanded: controller.isSettingsExpanded,
          items: [
            TwoLevelSideMenuItem(
              title: 'file_share_server_ports_settings'.tr,
              key: 'settings.ports',
              icon: Icons.settings_ethernet_outlined,
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
    );
  }
}

Widget _buildRight(FileShareServerController ctrl) {
  final plugin = MountPluginStatusService.ensure();
  return Obx(() {
    final key = ctrl.currentPageKey.value;
    final showBanner =
        key == 'share.webdav' || key == 'share.ftp' || key == 'share.sftp';
    Widget body;
    if (key == 'share.user_folders') {
      body = KeyedSubtree(
        key: const ValueKey('share_user_folders'),
        child: _UserShareFoldersPanel(ctrl: ctrl),
      );
    } else if (key == 'share.webdav') {
      body = KeyedSubtree(
        key: const ValueKey('share_webdav'),
        child: _TypePanel(serverType: 'WebDav', ctrl: ctrl),
      );
    } else if (key == 'share.ftp') {
      body = KeyedSubtree(
        key: const ValueKey('share_ftp'),
        child: _TypePanel(serverType: 'FTP', ctrl: ctrl),
      );
    } else if (key == 'share.sftp') {
      body = KeyedSubtree(
        key: const ValueKey('share_sftp'),
        child: _TypePanel(serverType: 'SFTP', ctrl: ctrl),
      );
    } else if (key == 'settings.ports') {
      body = KeyedSubtree(
        key: const ValueKey('settings_ports'),
        child: _PortsSettingsView(ctrl: ctrl),
      );
    } else if (key == 'share.quick') {
      body = const KeyedSubtree(
        key: ValueKey('share_quick'),
        child: QuickShareConfigView(),
      );
    } else {
      body = Center(child: Text('not_implemented_yet'.tr));
    }
    return Column(
      children: [
        MountPluginNotReadyBanner(
          ready: !showBanner || plugin.canUseFileServer,
        ),
        Expanded(child: body),
      ],
    );
  });
}
