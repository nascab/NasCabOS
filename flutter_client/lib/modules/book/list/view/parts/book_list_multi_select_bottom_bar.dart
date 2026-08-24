import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../controller/book_list_controller.dart';

class BookListMultiSelectBottomBar extends StatelessWidget {
  final BookListController controller;
  const BookListMultiSelectBottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: customColors?.leftTreeBgColor),
      child: Obx(() {
        final count = controller.selectedItems.length;
        final allSelected = controller.isAllCurrentSelected;
        final disabled = count <= 0;
        return Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  CustomCheckbox(
                    value: allSelected,
                    onChanged: (_) => controller.toggleSelectAllCurrent(),
                    isCircle: false,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    allSelected
                        ? 'timeline_deselect_all'.tr
                        : 'timeline_select_all'.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$count ${'selected'.tr}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: controller.isSelectedAllFavorited
                      ? 'unfavorite'.tr
                      : 'favorites'.tr,
                  onPressed: disabled
                      ? null
                      : controller.toggleFavoriteSelected,
                  icon: Icon(
                    controller.isSelectedAllFavorited
                        ? Icons.favorite_border
                        : Icons.favorite,
                  ),
                ),
                IconButton(
                  tooltip: 'download'.tr,
                  onPressed: disabled ? null : controller.downloadSelected,
                  icon: const Icon(Icons.download_rounded),
                ),
                IconButton(
                  tooltip: 'delete'.tr,
                  onPressed: disabled ? null : controller.deleteSelected,
                  icon: Icon(
                    Icons.delete_outline,
                    color: disabled ? null : Colors.red,
                  ),
                ),
                IconButton(
                  tooltip: 'add_to_book_list'.tr,
                  onPressed: disabled ? null : controller.addToBookListSelected,
                  icon: const Icon(Icons.playlist_add),
                ),
                if (controller.isInCustomList)
                  IconButton(
                    tooltip: 'remove_from_book_list'.tr,
                    onPressed: disabled
                        ? null
                        : controller.removeFromBookListSelected,
                    icon: const Icon(Icons.playlist_remove),
                  ),
                IconButton(
                  tooltip: 'cancel'.tr,
                  onPressed: controller.exitMultiSelectMode,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
