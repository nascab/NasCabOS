import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../base/components.dart';
import '../../core/user/current_user_controller.dart';
import '../base/views/app_base_page.dart';
import 'black_ip/ip_blacklist_panel.dart';
import 'best_practices/best_practices_panel.dart';
import 'security_center_controller.dart';
import 'security_set/security_settings_panel.dart';
import 'device_manage/device_manage_panel.dart';

/// 与安全中心控制器绑定的 tag，用于 Get.put/Get.delete，保证控制器随页面销毁。
const String _securityCenterTag = 'security_center';

/// 包装安全中心页面，在 [initState] 中注册 [SecurityCenterController]，在 [dispose] 中销毁，
/// 使控制器与组件生命周期一致，每次进入都会新建控制器并刷新列表。
class SecurityCenterScope extends StatefulWidget {
  const SecurityCenterScope({super.key, required this.child});
  final Widget child;

  @override
  State<SecurityCenterScope> createState() => _SecurityCenterScopeState();
}

class _SecurityCenterScopeState extends State<SecurityCenterScope> {
  @override
  void initState() {
    super.initState();
    Get.put(SecurityCenterController(), tag: _securityCenterTag);
  }

  @override
  void dispose() {
    Get.delete<SecurityCenterController>(tag: _securityCenterTag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SecurityCenterView extends GetView<SecurityCenterController> {
  const SecurityCenterView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SecurityCenterController>(
      tag: _securityCenterTag,
      builder: (ctrl) {
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;
          final customColors = Theme.of(context).extension<CustomColors>();

          return Scaffold(
            backgroundColor: customColors?.mainContentBgColor,
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: leftWidth,
                  child: _LeftMenu(
                    controller: ctrl,
                    collapsed: collapsed,
                    onToggleCollapse: () =>
                        ctrl.sidebarCollapsed.value = !collapsed,
                  ),
                ),
                Expanded(child: _RightPanel(ctrl: ctrl)),
              ],
            ),
          );
        });
      },
    );
  }
}

class _LeftMenu extends StatelessWidget {
  final SecurityCenterController controller;
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
          title: 'security.menu_best_practices'.tr,
          key: 'security.best_practices',
          icon: Icons.verified_user_outlined,
        ),
      if (isAdmin)
        OneLevelSideMenuItem(
          title: 'security.menu_settings'.tr,
          key: 'security.settings',
          icon: Icons.security_outlined,
        ),
      if (isAdmin)
        OneLevelSideMenuItem(
          title: 'security.menu_ip_blacklist'.tr,
          key: 'security.ip_blacklist',
          icon: Icons.gpp_bad_outlined,
        ),
      OneLevelSideMenuItem(
        title: 'security.menu_devices'.tr,
        key: 'security.devices',
        icon: Icons.devices_outlined,
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

class _RightPanel extends StatelessWidget {
  final SecurityCenterController ctrl;
  const _RightPanel({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final key = ctrl.currentPageKey.value;
      final isAdmin = CurrentUserController.instance.isAdmin;
      if (!isAdmin &&
          key != 'security.devices' &&
          key != 'security.best_practices') {
        return BestPracticesPanel(ctrl: ctrl);
      }
      if (key == 'security.best_practices') {
        return BestPracticesPanel(ctrl: ctrl);
      }
      if (key == 'security.settings') {
        return SecuritySettingsPanel(ctrl: ctrl);
      }
      if (key == 'security.ip_blacklist') {
        return IpBlacklistPanel(ctrl: ctrl);
      }
      if (key == 'security.devices') {
        return DeviceManagePanel(ctrl: ctrl);
      }
      return Center(child: Text('not_implemented_yet'.tr));
    });
  }
}

class AppSecurityCenterPage extends StatelessWidget {
  const AppSecurityCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SecurityCenterController>(
      tag: _securityCenterTag,
      builder: (ctrl) {
        return Obx(() {
          final isAdmin = CurrentUserController.instance.isAdmin;

          if (!isAdmin) {
            return AppBasePage(
              title: 'app_security'.tr,
              body: DeviceManagePanel(ctrl: ctrl, appMode: true),
              actions: [
                IconButton(
                  tooltip: 'refresh'.tr,
                  onPressed: () => ctrl.loadDevices(showLoading: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            );
          }

          final tabs = <({String key, IconData icon, String label})>[
            (
              key: 'security.settings',
              icon: Icons.security_outlined,
              label: 'security.menu_settings'.tr,
            ),
            (
              key: 'security.ip_blacklist',
              icon: Icons.gpp_bad_outlined,
              label: 'security.menu_ip_blacklist'.tr,
            ),
            (
              key: 'security.devices',
              icon: Icons.devices_outlined,
              label: 'security.menu_devices'.tr,
            ),
          ];

          final currentKey = ctrl.currentPageKey.value;
          final idx = tabs.indexWhere((e) => e.key == currentKey);
          final currentIndex = idx >= 0 ? idx : 0;
          if (idx < 0 && tabs.isNotEmpty) {
            Future.microtask(() => ctrl.selectPage(tabs.first.key));
          }

          Widget body;
          final key = tabs.isEmpty ? '' : tabs[currentIndex].key;
          if (key == 'security.settings') {
            body = SecuritySettingsPanel(ctrl: ctrl, appMode: true);
          } else if (key == 'security.ip_blacklist') {
            body = IpBlacklistPanel(ctrl: ctrl, appMode: true);
          } else {
            body = DeviceManagePanel(ctrl: ctrl, appMode: true);
          }

          final List<Widget>? actions;
          if (key == 'security.ip_blacklist') {
            actions = [
              IconButton(
                tooltip: 'refresh'.tr,
                onPressed: () => ctrl.loadBlacklist(showLoading: true),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'task_clear_all'.tr,
                onPressed: ctrl.clearBlacklist,
                icon: Icon(Icons.delete_outline),
              ),
            ];
          } else if (key == 'security.devices') {
            actions = [
              IconButton(
                tooltip: 'refresh'.tr,
                onPressed: () => ctrl.loadDevices(showLoading: true),
                icon: const Icon(Icons.refresh),
              ),
            ];
          } else {
            actions = null;
          }

          return AppBasePage(
            title: 'app_security'.tr,
            body: body,
            actions: actions,
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: (next) {
                if (next < 0 || next >= tabs.length) return;
                ctrl.selectPage(tabs[next].key);
              },
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              type: BottomNavigationBarType.fixed,
              items: tabs
                  .map(
                    (e) => BottomNavigationBarItem(
                      icon: Icon(e.icon),
                      label: e.label,
                    ),
                  )
                  .toList(),
            ),
          );
        });
      },
    );
  }
}
