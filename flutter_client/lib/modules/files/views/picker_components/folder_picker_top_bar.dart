import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../base/components/custom_icon_button.dart';
import '../../controllers/file_controller.dart';

class FolderPickerTopBar extends StatelessWidget {
  const FolderPickerTopBar({
    super.key,
    required this.ctrl,
    required this.onClose,
  });

  final FileController ctrl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Obx(
            () => DropdownButton<String>(
              underline: const SizedBox.shrink(),
              value: ctrl.sortMode.value,
              items: [
                DropdownMenuItem(
                  value: 'name_asc',
                  child: Text('folder_picker_sort_name_asc'.tr),
                ),
                DropdownMenuItem(
                  value: 'name_desc',
                  child: Text('folder_picker_sort_name_desc'.tr),
                ),
                DropdownMenuItem(
                  value: 'size_asc',
                  child: Text('folder_picker_sort_size_asc'.tr),
                ),
                DropdownMenuItem(
                  value: 'size_desc',
                  child: Text('folder_picker_sort_size_desc'.tr),
                ),
                DropdownMenuItem(
                  value: 'mtime_asc',
                  child: Text('folder_picker_sort_mtime_asc'.tr),
                ),
                DropdownMenuItem(
                  value: 'mtime_desc',
                  child: Text('folder_picker_sort_mtime_desc'.tr),
                ),
                DropdownMenuItem(
                  value: 'type_asc',
                  child: Text('folder_picker_sort_type_asc'.tr),
                ),
                DropdownMenuItem(
                  value: 'type_desc',
                  child: Text('folder_picker_sort_type_desc'.tr),
                ),
              ],
              onChanged: (v) {
                if (v != null) ctrl.setSortMode(v);
              },
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'user_mgmt_select_dir'.tr,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
          CustomIconButton(
            icon: Icons.close_outlined,
            onPressed: onClose,
            tooltip: 'cancel'.tr,
          ),
        ],
      ),
    );
  }
}
