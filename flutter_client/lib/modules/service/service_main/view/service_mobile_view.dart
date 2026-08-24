import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../account/view/nascab_account_view.dart';
import '../controller/service_main_controller.dart';
import 'service_remote_access_view.dart';
import 'service_ddns_view.dart';

class ServiceMobileView extends StatelessWidget {
  const ServiceMobileView({super.key});

  int _indexForKey(String key) {
    switch (key) {
      case 'account.remote_access':
        return 1;
      case 'account.ddns':
        return 2;
      case 'account.nascab':
      default:
        return 0;
    }
  }

  String _titleForIndex(int index) {
    if (index == 2) return 'service_menu_remote_access_ddns'.tr;
    if (index == 1) return 'service_menu_remote_access'.tr;
    return 'service_menu_account_nascab'.tr;
  }

  String _keyForIndex(int index) {
    if (index == 2) return 'account.ddns';
    if (index == 1) return 'account.remote_access';
    return 'account.nascab';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!Get.isRegistered<ServiceMainController>()) {
      Get.put<ServiceMainController>(ServiceMainController(), permanent: true);
    }
    return GetBuilder<ServiceMainController>(
      builder: (ctrl) {
        return Obx(() {
          final idx = _indexForKey(ctrl.currentPageKey.value);
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: AppBar(title: Text(_titleForIndex(idx)), centerTitle: true),
            body: SafeArea(
              top: false,
              child: IndexedStack(
                index: idx,
                children: [
                  const NasCabAccountView(showTitle: false),
                  ServiceRemoteAccessView(controller: ctrl, showTitle: false),
                  ServiceDdnsView(controller: ctrl, showTitle: false),
                ],
              ),
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: idx,
              onTap: (next) => ctrl.selectPage(_keyForIndex(next)),
              selectedItemColor: theme.colorScheme.primary,
              unselectedItemColor: theme.colorScheme.onSurfaceVariant,
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.account_circle_outlined),
                  label: 'service_menu_account_nascab'.tr,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.public_outlined),
                  label: 'service_menu_remote_access'.tr,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.dns_outlined),
                  label: 'service_menu_remote_access_ddns'.tr,
                ),
              ],
            ),
          );
        });
      },
    );
  }
}
