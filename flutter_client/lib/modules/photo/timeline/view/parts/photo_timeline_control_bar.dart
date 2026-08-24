import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../../../base/components/custom_popup_select_button.dart';
import '../../../../../utils/popup_menu_util.dart';

class PhotoTimelineControlBar extends GetView<PhotoTimelineController> {
  final String? controllerTag;
  PhotoTimelineControlBar({super.key, this.controllerTag});

  @override
  String? get tag => controllerTag;

  final _pathFilterKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Obx(
            () => CustomPopupSelectButton<String>(
              tooltip: 'type'.tr,
              icon: Icons.filter_alt_outlined,
              value: controller.fileType.value,
              defaultValue: 'all',
              items: [
                CustomPopupSelectItem(
                  value: 'all',
                  label: 'all'.tr,
                  icon: Icons.filter_alt_outlined,
                ),
                CustomPopupSelectItem(
                  value: 'photo',
                  label: 'timeline_photos'.tr,
                  icon: Icons.image_outlined,
                ),
                CustomPopupSelectItem(
                  value: 'video',
                  label: 'timeline_videos'.tr,
                  icon: Icons.video_file_outlined,
                ),
                CustomPopupSelectItem(
                  value: 'livephoto',
                  label: 'timeline_live_photos'.tr,
                  icon: Icons.motion_photos_on_outlined,
                ),
              ],
              onSelected: controller.setFileType,
            ),
          ),

          Obx(() {
            if (controller.baseGeohash.value.isEmpty) {
              return const SizedBox(width: 0);
            }
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CustomPopupSelectButton<int>(
                tooltip: 'distance'.tr,
                icon: Icons.place_outlined,
                value: controller.nearbyRangeKm.value,
                defaultValue: 2,
                items: const [
                  CustomPopupSelectItem(value: 2, label: '2km'),
                  CustomPopupSelectItem(value: 5, label: '5km'),
                  CustomPopupSelectItem(value: 10, label: '10km'),
                  CustomPopupSelectItem(value: 50, label: '50km'),
                  CustomPopupSelectItem(value: 80, label: '80km'),
                ],
                onSelected: controller.setNearbyRangeKm,
              ),
            );
          }),
          // 来源文件夹筛选按钮
          Padding(
            key: _pathFilterKey,
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Obx(
              () => CustomBorderedIconButton(
                tooltip: 'timeline_path_filter'.tr,
                icon: Icons.source_outlined,
                active: controller.selectedPaths.isNotEmpty,
                onTap: () {
                  PopupMenuUtil.showBelowButton<void>(
                    context: context,
                    buttonKey: _pathFilterKey,
                    items: [
                      PopupMenuItem(
                        enabled: false,
                        padding: EdgeInsets.zero,
                        child: Container(
                          width: 350,
                          constraints: const BoxConstraints(maxHeight: 500),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'timeline_path_filter'.tr,
                                      style: Get.textTheme.titleSmall,
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        controller.clearSourcePathSelection();
                                        Navigator.of(context).pop();
                                      },
                                      child: Text('reset'.tr),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              Flexible(
                                child: Obx(() {
                                  if (controller.availablePaths.isEmpty) {
                                    return Padding(
                                      padding: EdgeInsets.all(20),
                                      child: Text('no_path'.tr),
                                    );
                                  }
                                  return ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: controller.availablePaths.length,
                                    itemBuilder: (ctx, index) {
                                      final item =
                                          controller.availablePaths[index];
                                      final path = item.path;
                                      return Obx(() {
                                        final isSelected = controller
                                            .selectedPaths
                                            .contains(path);
                                        return CheckboxListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                              ),
                                          dense: true,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  path,
                                                  style:
                                                      Get.textTheme.bodySmall,
                                                ),
                                              ),
                                              if (item.valid)
                                                const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                  size: 16,
                                                )
                                              else
                                                const Icon(
                                                  Icons.cancel,
                                                  color: Colors.red,
                                                  size: 16,
                                                ),
                                            ],
                                          ),
                                          value: isSelected,
                                          onChanged: (val) {
                                            controller.setSourcePathSelected(
                                              path,
                                              val == true,
                                            );
                                          },
                                        );
                                      });
                                    },
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Obx(
              () => CustomBorderedIconButton(
                icon: controller.sortOrder.value == 'desc'
                    ? Icons.rotate_left
                    : Icons.rotate_right,
                onTap: controller.toggleSortOrder,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Obx(() {
              final isMin = controller.itemSize.value <= controller.minItemSize;
              return CustomBorderedIconButton(
                icon: Icons.zoom_out,
                enabled: !isMin,
                onTap: () => controller.changeItemSize(-60),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Obx(() {
              final isMax = controller.itemSize.value >= controller.maxItemSize;
              return CustomBorderedIconButton(
                icon: Icons.zoom_in,
                enabled: !isMax,
                onTap: () => controller.changeItemSize(60),
              );
            }),
          ),
          Obx(
            () => CustomBorderedIconButton(
              tooltip: 'zoom_mode'.tr,
              icon: controller.isCoverMode.value ? Icons.crop : Icons.grid_view,
              onTap: controller.toggleCoverMode,
            ),
          ),

          ///
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: CustomExpandableSearchBar(
                    controller: controller.searchController,
                    hintText: 'search'.tr,
                    onChanged: controller.onSearchChanged,
                    onClear: controller.clearSearch,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
