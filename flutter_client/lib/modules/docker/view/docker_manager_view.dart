import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/theme/custom_colors.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/toast_util.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../base/components.dart';
import '../../base/components/custom_glass_card.dart';
import '../../base/components/custom_no_data.dart';
import '../controller/docker_controller.dart';

part 'parts/docker_shared_widgets.dart';
part 'parts/docker_tabs.dart';
part 'parts/docker_dialogs.dart';

class DockerManagerView extends StatelessWidget {
  final bool appMode;

  const DockerManagerView({super.key, this.appMode = false});

  @override
  Widget build(BuildContext context) {
    return DockerManagerContent(appMode: appMode);
  }
}

class DockerManagerContent extends StatelessWidget {
  static const double _desktopTopInset = 40;
  final bool appMode;
  final bool embedded;

  const DockerManagerContent({
    super.key,
    this.appMode = false,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final useAppMode = appMode || DeviceUtils.isPhone(context);
    return GetBuilder<DockerController>(
      init: DockerController(),
      builder: (ctrl) {
        return Obx(() {
          final currentTab = ctrl.currentTab.value;
          final theme = Theme.of(context);
          if (useAppMode) {
            if (embedded) {
              return _DockerEmbeddedBody(controller: ctrl, appMode: true);
            }
            return Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: Text('app_docker'.tr),
                actions: [
                  IconButton(
                    tooltip: 'refresh'.tr,
                    onPressed: () => ctrl.refreshAll(showLoading: false),
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                ],
              ),
              body: _DockerBody(controller: ctrl, appMode: true),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _mobileIndex(currentTab),
                onTap: (index) {
                  ctrl.currentTab.value = _tabForMobileIndex(index);
                },
                selectedItemColor: theme.colorScheme.primary,
                unselectedItemColor: theme.colorScheme.onSurfaceVariant,
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.dashboard_outlined),
                    label: 'docker_tab_overview'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.layers_outlined),
                    label: 'docker_tab_images'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.view_in_ar_outlined),
                    label: 'docker_tab_containers'.tr,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: 'docker_tab_tasks'.tr,
                  ),
                ],
              ),
            );
          }

          if (embedded) {
            return _DockerEmbeddedBody(controller: ctrl, appMode: false);
          }

          return Scaffold(
            body: Row(
              children: [
                _DockerSidebar(controller: ctrl),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _DockerBody(controller: ctrl, appMode: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  int _mobileIndex(String tab) {
    switch (tab) {
      case 'images':
        return 1;
      case 'containers':
        return 2;
      case 'tasks':
        return 3;
      case 'overview':
      default:
        return 0;
    }
  }

  String _tabForMobileIndex(int index) {
    switch (index) {
      case 1:
        return 'images';
      case 2:
        return 'containers';
      case 3:
        return 'tasks';
      default:
        return 'overview';
    }
  }
}

class _DockerSidebar extends StatelessWidget {
  final DockerController controller;

  const _DockerSidebar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('overview', Icons.dashboard_outlined, 'docker_tab_overview'),
      ('images', Icons.layers_outlined, 'docker_tab_images'),
      ('containers', Icons.view_in_ar_outlined, 'docker_tab_containers'),
      ('tasks', Icons.receipt_long_outlined, 'docker_tab_tasks'),
      // ('settings', Icons.settings_outlined, 'setting'),
    ];

    return SizedBox(
      width: 220,
      child: OneLevelSideMenu(
        currentKey: controller.currentTab,
        onSelect: (key) => controller.currentTab.value = key,
        items: tabs
            .map(
              (tab) => OneLevelSideMenuItem(
                title: tab.$3.tr,
                key: tab.$1,
                icon: tab.$2,
              ),
            )
            .toList(growable: false),
        showCollapseToggle: false,
        topPlaceholderHeight: DockerManagerContent._desktopTopInset,
      ),
    );
  }
}

class _DockerTopBar extends StatelessWidget {
  final DockerController controller;
  final double topPadding;

  const _DockerTopBar({required this.controller, this.topPadding = 18});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, topPadding, 20, 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              CustomButton(
                text: 'refresh'.tr,
                icon: const Icon(Icons.refresh_outlined),
                isPrimary: false,
                onPressed: () => controller.refreshAll(showLoading: false),
              ),
              CustomButton(
                text: 'docker_pull_image'.tr,
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _showPullImageDialog(context, controller),
              ),
              CustomButton(
                text: 'docker_import_image'.tr,
                icon: const Icon(Icons.upload_file_outlined),
                isPrimary: false,
                onPressed: () => _showImportImageDialog(context, controller),
              ),
              CustomButton(
                text: 'docker_create_container'.tr,
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () =>
                    _showCreateContainerDialog(context, controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockerBody extends StatelessWidget {
  final DockerController controller;
  final bool appMode;

  const _DockerBody({required this.controller, required this.appMode});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      color: customColors?.mainContentBgColor,
      child: Obx(() {
        final errorText = controller.errorText.value.trim();
        final currentTab = controller.currentTab.value;
        return Column(
          children: [
            if (errorText.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  appMode ? 12 : 20,
                  12,
                  appMode ? 12 : 20,
                  0,
                ),
                child: _ErrorBanner(text: errorText),
              ),
            const SizedBox(height: 12),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: switch (currentTab) {
                  'images' => _ImagesTab(
                    controller: controller,
                    appMode: appMode,
                  ),
                  'containers' => _ContainersTab(
                    controller: controller,
                    appMode: appMode,
                  ),
                  'tasks' => _TasksTab(
                    controller: controller,
                    appMode: appMode,
                  ),
                  'settings' when appMode => _OverviewTab(
                    controller: controller,
                    appMode: true,
                  ),
                  'settings' => _SettingsTab(controller: controller),
                  _ => _OverviewTab(controller: controller, appMode: appMode),
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _DockerEmbeddedBody extends StatelessWidget {
  final DockerController controller;
  final bool appMode;

  const _DockerEmbeddedBody({required this.controller, required this.appMode});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!appMode)
          const SizedBox(height: DockerManagerContent._desktopTopInset),
        if (appMode) ...[
          _DockerTopBar(controller: controller, topPadding: 18),
          const Divider(height: 1),
        ],
        Expanded(
          child: _DockerBody(controller: controller, appMode: appMode),
        ),
      ],
    );
  }
}
