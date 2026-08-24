import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import '../../../../core/user/current_user_controller.dart';

class PcFileLeftTree extends StatelessWidget {
  PcFileLeftTree({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;
  // 使用GetX的Rx变量管理折叠状态
  final RxBool _isServerSectionExpanded = true.obs;
  final RxBool _isQuickAccessSectionExpanded = true.obs;
  final RxBool _isSharingSectionExpanded = true.obs;
  final RxBool _isSettingsSectionExpanded = true.obs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = CurrentUserController.instance.isAdmin;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _serverSection(theme),
              const SizedBox(height: 8),
              _quickAccessSection(theme),
              const SizedBox(height: 8),
              if (isAdmin) _sharingSection(context, theme),
              const SizedBox(height: 8),
              if (isAdmin) _settingsSection(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    ThemeData theme,
    String title,
    IconData icon,
    bool isExpanded,
    VoidCallback onToggle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              Icon(
                isExpanded
                    ? Icons.expand_more_outlined
                    : Icons.chevron_right_outlined,
                size: 16,
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serverSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(
          () => _sectionHeader(
            theme,
            'folder_server'.tr,
            Icons.storage_outlined,
            _isServerSectionExpanded.value,
            () {
              _isServerSectionExpanded.value = !_isServerSectionExpanded.value;
            },
          ),
        ),
        Obx(() {
          if (!_isServerSectionExpanded.value) return Container();
          // 只使用服务端根目录列表，始终显示固定的根目录
          final roots = ctrl.serverRoots.toList();
          if (roots.isEmpty) {
            final atRoot = (ctrl.currentPath.value ?? '') == '';
            final loadingRoot =
                ctrl.loading.value &&
                ctrl.currentModule.value == 'normal' &&
                atRoot;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(loadingRoot ? '加载中...' : '无'),
            );
          }
          return Column(
            children: roots.map((e) {
              final name = e['name']?.toString() ?? '';
              final path = e['path']?.toString() ?? '';
              return ListTile(
                dense: true,
                horizontalTitleGap: 4,
                leading: const Icon(Icons.folder_outlined, size: 18),
                title: Text(name),
                onTap: () {
                  ctrl.exitSearchMode();
                  ctrl.openFilePanel();
                  ctrl.listDirectory(path, null);
                },
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _quickAccessSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(
          () => _sectionHeader(
            theme,
            'folder_quick_access'.tr,
            Icons.push_pin_outlined,
            _isQuickAccessSectionExpanded.value,
            () => _isQuickAccessSectionExpanded.value =
                !_isQuickAccessSectionExpanded.value,
          ),
        ),
        Obx(() {
          if (!_isQuickAccessSectionExpanded.value) return Container();
          return Column(
            children: [
              // 最近
              Obx(
                () => ListTile(
                  dense: true,
                  horizontalTitleGap: 4,
                  leading: const Icon(Icons.history_outlined, size: 18),
                  title: Text('recent'.tr),
                  selected: ctrl.currentModule.value == 'recent',
                  onTap: () async {
                    ctrl.exitSearchMode();
                    ctrl.openFilePanel();
                    await ctrl.listDirectory('', 'recent');
                  },
                ),
              ),
              // 收藏
              Obx(
                () => ListTile(
                  dense: true,
                  horizontalTitleGap: 4,
                  leading: const Icon(Icons.favorite_outline, size: 18),
                  title: Text('favorites'.tr),
                  selected: ctrl.currentModule.value == 'favorites',
                  onTap: () async {
                    ctrl.exitSearchMode();
                    ctrl.openFilePanel();
                    await ctrl.listDirectory('', 'favorites');
                  },
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _sharingSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(
          () => _sectionHeader(
            theme,
            'folder_sharing'.tr,
            Icons.share_outlined,
            _isSharingSectionExpanded.value,
            () => _isSharingSectionExpanded.value =
                !_isSharingSectionExpanded.value,
          ),
        ),
        Obx(() {
          if (!_isSharingSectionExpanded.value) return Container();
          return Column(
            children: [
              ListTile(
                dense: true,
                horizontalTitleGap: 4,
                leading: const Icon(Icons.ios_share_outlined, size: 18),
                title: Text('folder_sharing_quick'.tr),
                onTap: () {
                  ctrl.exitSearchMode();
                  ctrl.openShareManage(pageKey: 'share.quick');
                },
              ),
              ListTile(
                dense: true,
                horizontalTitleGap: 4,
                leading: const Icon(Icons.folder_shared_outlined, size: 18),
                title: Text('user_share_folders_title'.tr),
                onTap: () {
                  ctrl.exitSearchMode();
                  ctrl.openShareManage(pageKey: 'share.user_folders');
                },
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _settingsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(
          () => _sectionHeader(
            theme,
            'setting'.tr,
            Icons.settings_outlined,
            _isSettingsSectionExpanded.value,
            () => _isSettingsSectionExpanded.value =
                !_isSettingsSectionExpanded.value,
          ),
        ),
        Obx(() {
          if (!_isSettingsSectionExpanded.value) return Container();
          final selected = ctrl.rightPanel.value == 'index_settings';
          return Column(
            children: [
              ListTile(
                dense: true,
                horizontalTitleGap: 4,
                leading: const Icon(Icons.manage_search_outlined, size: 18),
                title: Text('file_index_settings'.tr),
                selected: selected,
                onTap: () {
                  ctrl.exitSearchMode();
                  ctrl.openIndexSettings();
                },
              ),
            ],
          );
        }),
      ],
    );
  }
}
