import 'dart:convert';

import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/routes/app_routes.dart';
import '../../base/components.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../home/views/pc_home_controller.dart';
import '../controllers/file_mount_controller.dart';
import '../controllers/openlist_mount_controller.dart';
import '../utils/openlist_driver_i18n.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/toast_util.dart';
import '../../../core/services/mount_plugin_status_service.dart';
import '../../base/components/mount_plugin_not_ready_banner.dart';

part 'parts/left_menu.dart';
part 'parts/mount_list_panel.dart';
part 'parts/mount_dialog.dart';
part 'parts/openlist_mount_list_panel.dart';
part 'parts/openlist_mount_dialog.dart';

class FileMountView extends GetView<FileMountController> {
  const FileMountView({super.key});

  OpenlistMountController get _openlistCtrl {
    if (!Get.isRegistered<OpenlistMountController>()) {
      Get.put(OpenlistMountController());
    }
    return Get.find<OpenlistMountController>();
  }

  @override
  Widget build(BuildContext context) {
    MountPluginStatusService.ensure().ensurePolling();
    return GetBuilder<FileMountController>(
      init: FileMountController(),
      builder: (ctrl) {
        if (!DeviceUtils.isDesktopOrWeb) {
          return Obx(() {
            final pageKey = ctrl.currentPageKey.value;
            final isOpenlist = pageKey == 'mount.openlist';
            return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: Text(
                isOpenlist ? 'file_mount_menu_openlist'.tr : 'file_mount_menu_manage'.tr,
              ),
              actions: [
                IconButton(
                  tooltip: isOpenlist
                      ? 'openlist_mount_help_tooltip'.tr
                      : 'file_mount_help_tooltip'.tr,
                  onPressed: () {
                    DialogUtil.showInfoDialog(
                      title: isOpenlist
                          ? 'file_mount_menu_openlist'.tr
                          : 'file_mount_menu_manage'.tr,
                      content: isOpenlist
                          ? 'openlist_mount_help_tooltip'.tr
                          : 'file_mount_help_tooltip'.tr,
                    );
                  },
                  icon: const Icon(Icons.help_outline),
                ),
                IconButton(
                  tooltip: 'refresh'.tr,
                  onPressed: () {
                    if (isOpenlist) {
                      _openlistCtrl.refreshList(showLoading: true);
                    } else {
                      ctrl.refreshList(showLoading: true);
                    }
                  },
                  icon: const Icon(Icons.refresh_outlined),
                ),
                IconButton(
                  tooltip: 'create'.tr,
                  onPressed: () async {
                    if (isOpenlist) {
                      final allowed = await _openlistCtrl.ensureWinfspReady();
                      if (!allowed) return;
                      await _openlistCtrl.loadDrivers();
                      await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _OpenlistMountDialog(ctrl: _openlistCtrl),
                      );
                      return;
                    }
                    final allowed = await ctrl.ensureWinfspReady();
                    if (!allowed) return;
                    await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _MountDialog(ctrl: ctrl),
                    );
                  },
                  icon: const Icon(Icons.add_outlined),
                ),
              ],
            ),
            body: Column(
              children: [
                Obx(() {
                  final plugin = MountPluginStatusService.ensure();
                  final pageReady = isOpenlist
                      ? plugin.canUseOpenlistMount
                      : plugin.canUseFileMount;
                  return MountPluginNotReadyBanner(ready: pageReady);
                }),
                Expanded(
                  child: isOpenlist
                      ? _OpenlistMountListPanel(ctrl: _openlistCtrl, showHeader: false)
                      : _MountListPanel(ctrl: ctrl, showHeader: false),
                ),
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: pageKey == 'mount.openlist' ? 1 : 0,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.folder_special_outlined),
                  label: 'file_mount_menu_manage'.tr,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.cloud_outlined),
                  label: 'file_mount_menu_openlist'.tr,
                ),
              ],
              onTap: (index) {
                ctrl.selectPage(index == 1 ? 'mount.openlist' : 'mount.list');
              },
            ),
          );
          });
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
                  child: _LeftMenu(
                    controller: ctrl,
                    collapsed: collapsed,
                    onToggleCollapse: () =>
                        ctrl.sidebarCollapsed.value = !collapsed,
                  ),
                ),
                Expanded(child: _buildRight(context, ctrl)),
              ],
            ),
          );
        });
      },
    );
  }
}

Widget _buildRight(BuildContext context, FileMountController ctrl) {
  final openlistCtrl = Get.isRegistered<OpenlistMountController>()
      ? Get.find<OpenlistMountController>()
      : Get.put(OpenlistMountController());
  final plugin = MountPluginStatusService.ensure();
  final customColors = Theme.of(context).extension<CustomColors>();
  return Obx(() {
    final key = ctrl.currentPageKey.value;
    final pageReady = key == 'mount.openlist'
        ? plugin.canUseOpenlistMount
        : plugin.canUseFileMount;
    Widget body;
    if (key == 'mount.list') {
      body = _MountListPanel(ctrl: ctrl);
    } else if (key == 'mount.openlist') {
      body = _OpenlistMountListPanel(ctrl: openlistCtrl);
    } else {
      body = Center(child: Text('not_implemented_yet'.tr));
    }
    return Column(
      children: [
        MountPluginNotReadyBanner(ready: pageReady),
        Expanded(
          child: Container(
            color: customColors?.mainContentBgColor,
            child: body,
          ),
        ),
      ],
    );
  });
}
