import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../../utils/dialog_util.dart';
import '../../controllers/file_controller.dart';

class AppFileToolbar extends StatelessWidget {
  const AppFileToolbar({
    super.key,
    required this.ctrl,
    required this.onSortPressed,
    required this.onFilterPressed,
    required this.onViewPressed,
  });

  final FileController ctrl;
  final VoidCallback onSortPressed;
  final VoidCallback onFilterPressed;
  final VoidCallback onViewPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Obx(() {
            final isRecent = ctrl.currentModule.value == 'recent';
            final label = isRecent
                ? 'recent_clear'.tr
                : _sortLabel(ctrl.sortMode.value);
            final labelStyle = theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            );
            final iconColor = theme.colorScheme.onSurfaceVariant;
            // 清除最近访问记录
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                if (isRecent) {
                  final confirmed = await DialogUtil.showConfirmDialog(
                    title: 'need_confirm'.tr,
                    content: 'recent_clear_confirm'.tr,
                    confirmText: 'ok'.tr,
                    cancelText: 'cancel'.tr,
                  );
                  if (confirmed ?? false) {
                    final ok = await ctrl.clearRecent();
                    if (!ok) {
                      DialogUtil.showErrorDialog(
                        message: 'operation_failed'.tr,
                      );
                    }
                  }
                  return;
                }
                onSortPressed();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (isRecent) ...[
                      Icon(
                        Icons.delete_sweep_outlined,
                        size: 18,
                        color: iconColor,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(label, style: labelStyle),
                    if (!isRecent) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: iconColor,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const Spacer(),
          Obx(
            () => Tooltip(
              message: ctrl.showHidden.value
                  ? 'file_tooltip_hide_hidden'.tr
                  : 'file_tooltip_show_hidden'.tr,
              child: _roundIconBtn(
                context,
                icon: ctrl.showHidden.value
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                tooltip: '',
                onTap: () => ctrl.toggleShowHidden(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Obx(
            () => _roundIconBtn(
              context,
              icon: Icons.filter_alt_outlined,
              tooltip: 'filter'.tr,
              onTap: onFilterPressed,
              active: ctrl.filterType.value != 'all',
            ),
          ),
          const SizedBox(width: 10),
          Obx(
            () => _roundIconBtn(
              context,
              icon: _viewIcon(ctrl.viewMode.value),
              tooltip: 'folder_view'.tr,
              onTap: onViewPressed,
            ),
          ),
        ],
      ),
    );
  }

  IconData _viewIcon(String mode) {
    switch (mode) {
      case 'list':
        return Icons.view_list_outlined;
      case 'large_grid':
        return Icons.grid_view_rounded;
      case 'grid':
      default:
        return Icons.grid_on_outlined;
    }
  }

  String _sortLabel(String mode) {
    switch (mode) {
      case 'name_asc':
        return 'folder_picker_sort_name_asc'.tr;
      case 'name_desc':
        return 'folder_picker_sort_name_desc'.tr;
      case 'size_asc':
        return 'folder_picker_sort_size_asc'.tr;
      case 'size_desc':
        return 'folder_picker_sort_size_desc'.tr;
      case 'type_asc':
        return 'folder_picker_sort_type_asc'.tr;
      case 'type_desc':
        return 'folder_picker_sort_type_desc'.tr;
      case 'mtime_asc':
        return 'folder_picker_sort_mtime_asc'.tr;
      case 'mtime_desc':
      default:
        return 'folder_picker_sort_mtime_desc'.tr;
    }
  }

  Widget _roundIconBtn(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return CustomBorderedIconButton(
      icon: icon,
      tooltip: tooltip,
      onTap: onTap,
      active: active,
    );
  }
}
