import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../base/components/app_custom_search_dialog.dart';
import '../../../../utils/device_utils.dart';
import '../controller/ai_faces_controller.dart';
import 'parts/ai_face_timeline_overlay.dart';
import 'parts/ai_faces_grid.dart';
import 'parts/ai_faces_multiselect_bar.dart';
import 'parts/ai_faces_top_bar.dart';

class AiFacesView extends StatelessWidget {
  const AiFacesView({super.key});

  static void _showStatusFilterSheet(
      BuildContext context, AiFacesController ctrl) {
    final items = [
      ('visiable', 'face_filter_visible'.tr, Icons.visibility),
      ('hide', 'face_filter_hidden'.tr, Icons.visibility_off),
      ('all', 'all'.tr, Icons.filter_alt_outlined),
    ];
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final current = ctrl.statusFilter.value;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: items.map((item) {
              final (value, label, icon) = item;
              final isSelected = current == value;
              return ListTile(
                leading: Icon(icon),
                title: Text(
                  label,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing:
                    isSelected ? const Icon(Icons.check, size: 20) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  ctrl.setStatusFilter(value);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const tag = 'photo_ai_faces';
    final customColors = Theme.of(context).extension<CustomColors>();
    return GetBuilder<AiFacesController>(
      init: AiFacesController(),
      tag: tag,
      dispose: (_) => Get.delete<AiFacesController>(tag: tag),
      builder: (ctrl) {
        if (DeviceUtils.isMobile) {
          final isAdmin = CurrentUserController.instance.isAdmin;
          return Scaffold(
            backgroundColor: customColors?.mainContentBgColor,
            appBar: AppBar(
              title: Text('photo_menu_ai_face'.tr),
              actions: [
                IconButton(
                  tooltip: 'filter'.tr,
                  icon: const Icon(Icons.filter_alt_outlined),
                  onPressed: () => _showStatusFilterSheet(context, ctrl),
                ),
                Obx(() {
                  final hasKeyword = ctrl.keyword.value.isNotEmpty;
                  return IconButton(
                    tooltip: 'search'.tr,
                    onPressed: () => AppCustomSearchDialog.show(
                      context: context,
                      hintText: 'face_search_hint'.tr,
                      controller: ctrl.searchController,
                      onChanged: ctrl.updateKeyword,
                      onClear: ctrl.clearKeyword,
                    ),
                    icon: hasKeyword
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.search),
                              Positioned(
                                top: -2,
                                right: -2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const Icon(Icons.search),
                  );
                }),
                IconButton(
                  tooltip: 'refresh'.tr,
                  onPressed: ctrl.refreshFaces,
                  icon: const Icon(Icons.refresh),
                ),
                if (isAdmin)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'settings') {
                        ctrl.openAutoHideSettings();
                      } else if (v == 'reset') {
                        ctrl.confirmAndResetFaces();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'settings',
                        child: Text('setting'.tr),
                      ),
                      PopupMenuItem(value: 'reset', child: Text('reset'.tr)),
                    ],
                    icon: const Icon(Icons.more_vert),
                  ),
              ],
            ),
            body: Stack(
              children: [
                AiFacesGrid(controller: ctrl),
                AiFacesMultiSelectBottomBar(controller: ctrl),
              ],
            ),
          );
        }
        return Container(
          color: customColors?.mainContentBgColor,
          child: Stack(
            children: [
              Column(
                children: [
                  AiFacesTopBar(controller: ctrl),
                  Expanded(child: AiFacesGrid(controller: ctrl)),
                ],
              ),
              AiFacesMultiSelectBottomBar(controller: ctrl),
              AiFaceTimelineOverlay(controller: ctrl),
            ],
          ),
        );
      },
    );
  }
}
