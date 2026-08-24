import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/service_main_controller.dart';
import '../../account/view/nascab_account_view.dart';
import 'home_parts/service_left_menu.dart';
import 'service_remote_access_view.dart';
import 'service_ddns_view.dart';
import '../../account/view/service_contact_us_view.dart';
import '../../../base/components/custom_container.dart';

class ServiceMainView extends StatelessWidget {
  final String? initialPageKey;
  const ServiceMainView({super.key, this.initialPageKey});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ServiceMainController>(
      init: ServiceMainController(),
      builder: (ctrl) {
        final initKey = initialPageKey?.trim() ?? '';
        if (initKey.isNotEmpty && initKey != ctrl.currentPageKey.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (initKey != ctrl.currentPageKey.value) {
              ctrl.selectPage(initKey);
            }
          });
        }
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;

          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: leftWidth,
                child: ServiceLeftMenu(
                  controller: ctrl,
                  collapsed: collapsed,
                  onToggleCollapse: () =>
                      ctrl.sidebarCollapsed.value = !collapsed,
                ),
              ),
              Expanded(child: _buildRight(ctrl)),
            ],
          );
        });
      },
    );
  }

  Widget _buildRight(ServiceMainController ctrl) {
    return Obx(() {
      final key = ctrl.currentPageKey.value;
      if (key == 'account.nascab') {
        return const CustomContainer(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.zero,
          child: NasCabAccountView(),
        );
      }
      if (key == 'account.remote_access') {
        return CustomContainer(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.zero,
          child: ServiceRemoteAccessView(controller: ctrl),
        );
      }
      if (key == 'account.ddns') {
        return CustomContainer(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.zero,
          child: ServiceDdnsView(controller: ctrl),
        );
      }
      if (key == 'contact_us') {
        return const ServiceContactUsView();
      }
      return Center(child: Text('not_implemented_yet'.tr));
    });
  }
}
