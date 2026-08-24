import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../base/components/custom_hover_select_menu.dart';
import '../../../../base/components/custom_bordered_icon_button.dart';
import '../../../../base/components/custom_expandable_search_bar.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../controller/ai_scenes_controller.dart';

class AiScenesTopBar extends StatelessWidget {
  final AiScenesController controller;
  const AiScenesTopBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isAdmin = CurrentUserController.instance.isAdmin;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final filter = Obx(() {
            final v = controller.statusFilter.value;
            return CustomHoverSelectMenu<String>(
              value: v,
              height: 44,
              buttonIcon: Icons.filter_alt_outlined,
              items: [
                CustomHoverSelectMenuItem(
                  value: 'visiable',
                  label: 'face_filter_visible'.tr,
                  icon: Icons.visibility,
                ),
                CustomHoverSelectMenuItem(
                  value: 'hide',
                  label: 'face_filter_hidden'.tr,
                  icon: Icons.visibility_off,
                ),
                CustomHoverSelectMenuItem(
                  value: 'all',
                  label: 'all'.tr,
                  icon: Icons.filter_alt_outlined,
                ),
              ],
              onSelected: controller.setStatusFilter,
            );
          });

          return Row(
            children: [
              filter,
              const Spacer(),
              if (isAdmin)
                CustomBorderedIconButton(
                  icon: Icons.clear_all,
                  tooltip: 'reset'.tr,
                  onTap: controller.confirmAndResetScenes,
                ),
              const SizedBox(width: 6),
              CustomBorderedIconButton(
                icon: Icons.refresh,
                tooltip: 'refresh'.tr,
                onTap: controller.refreshScenes,
              ),
              const SizedBox(width: 6),
              CustomExpandableSearchBar(
                controller: controller.searchController,
                hintText: 'scene_search_hint'.tr,
                onChanged: controller.updateKeyword,
                onClear: controller.clearKeyword,
              ),
            ],
          );
        },
      ),
    );
  }
}
