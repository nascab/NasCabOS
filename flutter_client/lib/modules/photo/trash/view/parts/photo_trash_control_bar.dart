import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../modules/base/components/custom_expandable_search_bar.dart';
import '../../../../../modules/base/components/custom_bordered_icon_button.dart';
import '../../controller/photo_trash_controller.dart';
import '../../../../../modules/base/components/custom_popup_select_button.dart';

/// 回收站顶部控制栏组件
class PhotoTrashControlBar extends StatefulWidget {
  final PhotoTrashController controller;

  const PhotoTrashControlBar({super.key, required this.controller});

  @override
  State<PhotoTrashControlBar> createState() => _PhotoTrashControlBarState();
}

class _PhotoTrashControlBarState extends State<PhotoTrashControlBar> {
  PhotoTrashController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: [
            // 文件类型过滤
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
                onSelected: controller.changeFileType,
              ),
            ),
            const SizedBox(width: 4),
            // 排序选项
            Obx(
              () => CustomPopupSelectButton<String>(
                tooltip: 'sort'.tr,
                icon: Icons.sort_by_alpha,
                value:
                    '${controller.sortField.value}_${controller.sortOrder.value}',
                defaultValue: 'in_trash_time_desc',
                items: [
                  CustomPopupSelectItem(
                    value: 'in_trash_time_asc',
                    label: '${'delete_time'.tr} ↑',
                    icon: Icons.schedule,
                  ),
                  CustomPopupSelectItem(
                    value: 'in_trash_time_desc',
                    label: '${'delete_time'.tr} ↓',
                    icon: Icons.schedule,
                  ),
                  CustomPopupSelectItem(
                    value: 'filename_asc',
                    label: '${'name'.tr} ↑',
                    icon: Icons.sort_by_alpha,
                  ),
                  CustomPopupSelectItem(
                    value: 'filename_desc',
                    label: '${'name'.tr} ↓',
                    icon: Icons.sort_by_alpha,
                  ),
                ],
                onSelected: (value) {
                  final parts = value.split('_');
                  final order = parts.last;
                  final field = parts.sublist(0, parts.length - 1).join('_');
                  controller.toggleSortField(field);
                  if (controller.sortOrder.value != order) {
                    controller.toggleSortField(field);
                  }
                },
              ),
            ),
            // 缩略图大小调整按钮
            Padding(
              padding: const EdgeInsets.only(right: 4, left: 4),
              child: CustomBorderedIconButton(
                icon: Icons.zoom_out,
                enabled: controller.itemSize.value > controller.minItemSize,
                onTap: controller.zoomOut,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CustomBorderedIconButton(
                icon: Icons.zoom_in,
                enabled: controller.itemSize.value < controller.maxItemSize,
                onTap: controller.zoomIn,
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
                      hintText: 'search'.tr,
                      onChanged: controller.onSearch,
                      onClear: controller.clearSearch,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
