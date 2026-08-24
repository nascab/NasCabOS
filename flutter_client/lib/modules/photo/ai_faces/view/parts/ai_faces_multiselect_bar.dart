import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/ai_faces_controller.dart';
import '../../../../../core/user/current_user_controller.dart';

class AiFacesMultiSelectBottomBar extends StatelessWidget {
  final AiFacesController controller;
  const AiFacesMultiSelectBottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.selectionMode.value) return const SizedBox();
      final filter = controller.statusFilter.value;
      final isAll = filter == 'all';
      final isHideList = filter == 'hide' || filter == 'hidden';
      final selectedCount = controller.selectedFaceIds.length;
      final isAdmin = CurrentUserController.instance.isAdmin;
      final customColors = Theme.of(context).extension<CustomColors>();

      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: customColors?.leftTreeBgColor,
            border: Border(
              top: BorderSide(color: Get.theme.dividerColor, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'face_selected_count'.trParams({'count': '$selectedCount'}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAdmin) ...[
                if (isAll) ...[
                  TextButton(
                    onPressed: () => controller.batchSetHidden(false),
                    child: Text('face_action_show'.tr),
                  ),
                  TextButton(
                    onPressed: () => controller.batchSetHidden(true),
                    child: Text('face_action_hide'.tr),
                  ),
                ] else
                  TextButton(
                    onPressed: () => controller.batchSetHidden(!isHideList),
                    child: Text(
                      (isHideList ? 'face_action_show' : 'face_action_hide').tr,
                    ),
                  ),
                TextButton(
                  onPressed: selectedCount >= 2
                      ? controller.confirmAndMergeSelected
                      : null,
                  child: Text('face_action_merge'.tr),
                ),
              ],
              TextButton(
                onPressed: controller.downloadSelectedFaces,
                child: Text('download'.tr),
              ),
              TextButton(
                onPressed: controller.exitSelectionMode,
                child: Text('cancel'.tr),
              ),
            ],
          ),
        ),
      );
    });
  }
}
