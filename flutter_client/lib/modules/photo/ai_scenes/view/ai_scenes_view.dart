import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/app_custom_search_dialog.dart';
import '../../../../utils/device_utils.dart';
import '../controller/ai_scenes_controller.dart';
import 'parts/ai_scene_timeline_overlay.dart';
import 'parts/ai_scenes_grid.dart';
import 'parts/ai_scenes_top_bar.dart';

class AiScenesView extends StatelessWidget {
  const AiScenesView({super.key});

  static void _showStatusFilterSheet(
      BuildContext context, AiScenesController ctrl) {
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
    const tag = 'photo_ai_scenes';
    final customColors = Theme.of(context).extension<CustomColors>();
    return GetBuilder<AiScenesController>(
      init: AiScenesController(),
      tag: tag,
      dispose: (_) => Get.delete<AiScenesController>(tag: tag),
      builder: (ctrl) {
        if (DeviceUtils.isMobile) {
          return Scaffold(
            backgroundColor: customColors?.mainContentBgColor,
            appBar: AppBar(
              title: Text('photo_menu_ai_scene'.tr),
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
                      hintText: 'scene_search_hint'.tr,
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
                  onPressed: ctrl.refreshScenes,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: AiScenesGrid(controller: ctrl),
          );
        }
        return Container(
          color: customColors?.mainContentBgColor,
          child: Stack(
            children: [
              Column(
                children: [
                  AiScenesTopBar(controller: ctrl),
                  Expanded(child: AiScenesGrid(controller: ctrl)),
                ],
              ),
              AiSceneTimelineOverlay(controller: ctrl),
            ],
          ),
        );
      },
    );
  }
}
