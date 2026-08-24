import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/side_menu_two_level.dart';
import '../../controller/service_main_controller.dart';

class ServiceLeftMenu extends StatelessWidget {
  final ServiceMainController controller;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;

  const ServiceLeftMenu({
    super.key,
    required this.controller,
    this.collapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <SideMenuTwoLevelGroup>[
      SideMenuTwoLevelGroup(
        title: 'service_menu_account'.tr,
        icon: Icons.account_circle_outlined,
        expanded: controller.isAccountExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'service_menu_account_nascab'.tr,
            key: 'account.nascab',
            icon: Icons.person_outline,
          ),
          TwoLevelSideMenuItem(
            title: 'service_menu_remote_access'.tr,
            key: 'account.remote_access',
            icon: Icons.public_outlined,
          ),
          TwoLevelSideMenuItem(
            title: 'service_menu_remote_access_ddns'.tr,
            key: 'account.ddns',
            icon: Icons.dns_outlined,
          ),
        ],
      ),
      SideMenuTwoLevelGroup(
        title: 'service_menu_contact_us'.tr,
        icon: Icons.mail_outline,
        expanded: controller.isContactExpanded,
        items: [
          TwoLevelSideMenuItem(
            title: 'service_contact_us_title'.tr,
            key: 'contact_us',
            icon: Icons.email_outlined,
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
      topPlaceholderHeight: 40,
    );
  }
}
