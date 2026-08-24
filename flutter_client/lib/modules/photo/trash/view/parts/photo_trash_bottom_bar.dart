import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../core/theme/custom_colors.dart';
import '../../../../../utils/device_utils.dart';
import '../../controller/photo_trash_controller.dart';

/// 回收站底部操作栏组件
class PhotoTrashBottomBar extends StatelessWidget {
  final PhotoTrashController controller;

  const PhotoTrashBottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    final applyBottomSafeArea =
        !(DeviceUtils.isDesktop ||
            (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context)));
    final bgColor =
        customColors?.oprationBarBgColor ?? Get.theme.colorScheme.surface;

    return Obx(() {
      final isMultiSelect = controller.isMultiSelectMode.value;
      return Container(
        color: bgColor,
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: applyBottomSafeArea ? 5 : 0),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(
                  color: Get.theme.dividerColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isMultiSelect
                      ? 'items_selected'.trParams({
                          'count': controller.selectedItems.length.toString(),
                        })
                      : 'total_count'.trParams({
                          'count': controller.photoItems.length.toString(),
                        }),
                ),
                Row(
                  children: isMultiSelect
                      ? [
                          TextButton(
                            onPressed: controller.restoreSelected,
                            child: Text('restore'.tr),
                          ),
                          TextButton(
                            onPressed: controller.deleteSelected,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: Text('delete'.tr),
                          ),
                          TextButton(
                            onPressed: () {
                              controller.isMultiSelectMode.value = false;
                              controller.selectedItems.clear();
                            },
                            child: Text('cancel'.tr),
                          ),
                        ]
                      : [
                          TextButton(
                            onPressed: controller.restoreAll,
                            child: Text('restore_all'.tr),
                          ),
                          TextButton(
                            onPressed: controller.emptyTrash,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: Text('empty_trash'.tr),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
