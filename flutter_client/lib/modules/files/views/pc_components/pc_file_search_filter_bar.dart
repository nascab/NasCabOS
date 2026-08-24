import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../base/components/custom_hover_select_menu.dart';
import '../../controllers/pc_file_explorer_controller.dart';

class PcFileSearchFilterBar extends StatelessWidget {
  const PcFileSearchFilterBar({super.key, required this.ctrl});

  final PcFileExplorerController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Obx(() {
            final scope = ctrl.searchScope.value;
            final loading = ctrl.globalSearchLoading.value;
            int selected = 0;
            if (scope == 'subtree') selected = 1;
            if (scope == 'global') selected = 2;

            Widget tabLabel(String label, bool showLoading) {
              if (!showLoading) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(label),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ToggleButtons(
              isSelected: [selected == 0, selected == 1, selected == 2],
              onPressed: (i) {
                if (loading) return;
                if (i == 0) {
                  ctrl.trySetSearchScope('current');
                } else if (i == 1) {
                  ctrl.trySetSearchScope('subtree');
                } else {
                  ctrl.trySetSearchScope('global');
                }
              },
              borderRadius: BorderRadius.circular(8),
              constraints: const BoxConstraints(minHeight: 30, minWidth: 92),
              children: [
                tabLabel('file_search_scope_current_dir'.tr, false),
                tabLabel(
                  'file_search_scope_current_dir_subtree'.tr,
                  selected == 1 && loading,
                ),
                tabLabel(
                  'file_search_scope_global'.tr,
                  selected == 2 && loading,
                ),
              ],
            );
          }),
          const Spacer(),
          _SearchTypeDropdown(ctrl: ctrl),
        ],
      ),
    );
  }
}

class _SearchTypeDropdown extends StatelessWidget {
  const _SearchTypeDropdown({required this.ctrl});

  final PcFileExplorerController ctrl;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final value = ctrl.filterType.value;
      return CustomHoverSelectMenu<String>(
        height: 40,
        value: value,
        items: [
          CustomHoverSelectMenuItem(
            value: 'all',
            label: 'all'.tr,
            icon: Icons.filter_alt_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'dir',
            label: 'dir'.tr,
            icon: Icons.folder_open_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'document',
            label: 'folder_filter_document'.tr,
            icon: Icons.description_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'video',
            label: 'folder_filter_video'.tr,
            icon: Icons.videocam_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'audio',
            label: 'folder_filter_audio'.tr,
            icon: Icons.audiotrack_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'image',
            label: 'folder_filter_image'.tr,
            icon: Icons.image_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'archive',
            label: 'folder_filter_archive'.tr,
            icon: Icons.archive_outlined,
          ),
          CustomHoverSelectMenuItem(
            value: 'file',
            label: 'file'.tr,
            icon: Icons.insert_drive_file_outlined,
          ),
        ],
        onSelected: ctrl.setFilterType,
        buttonIcon: Icons.filter_alt,
        radius: 6,
        buttonPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      );
    });
  }
}
