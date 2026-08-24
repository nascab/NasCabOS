import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../base/components/custom_checkbox.dart';
import '../../controllers/file_controller.dart';

class FolderPickerRecentTab extends StatelessWidget {
  const FolderPickerRecentTab({
    super.key,
    required this.ctrl,
    required this.recentFolders,
    required this.multiSelect,
  });

  final FileController ctrl;
  final RxList<String> recentFolders;
  final bool multiSelect;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);

      if (recentFolders.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icons/no_data.png', width: 150, height: 150),
              const SizedBox(height: 16),
              Text(
                'folder_picker_no_recent'.tr,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      void toggle(String folder) {
        if (multiSelect) {
          ctrl.toggleSelect(folder);
        } else {
          ctrl.selected.clear();
          ctrl.toggleSelect(folder);
        }
      }

      return ListView.builder(
        itemCount: recentFolders.length,
        itemBuilder: (_, i) {
          final folder = recentFolders[i];
          return ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => CustomCheckbox(
                    value: ctrl.selected.contains(folder),
                    onChanged: (_) => toggle(folder),
                  ),
                ),
                const SizedBox(width: 6),
                Image.asset(
                  'assets/icons/file/folder.png',
                  width: 24,
                  height: 24,
                ),
                const SizedBox(width: 6),
              ],
            ),
            title: Text(folder.split('/').last),
            subtitle: Text(folder),
            onTap: () => toggle(folder),
          );
        },
      );
    });
  }
}
