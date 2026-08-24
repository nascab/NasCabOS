import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../controllers/file_controller.dart';
import 'folder_picker_extension_util.dart';

class FolderPickerConfirmBar extends StatelessWidget {
  const FolderPickerConfirmBar({
    super.key,
    required this.ctrl,
    required this.onSaveRecentFolder,
    this.allowFileSelect = false,
    this.allowedExtensions,
  });

  final FileController ctrl;
  final Future<void> Function(String folder) onSaveRecentFolder;
  final bool allowFileSelect;
  final List<String>? allowedExtensions;

  bool get _requireFileExtension =>
      allowFileSelect &&
      allowedExtensions != null &&
      allowedExtensions!.isNotEmpty;

  bool _isDirectoryPath(String path) {
    for (final it in ctrl.items) {
      final itPath = it['path']?.toString() ?? '';
      if (itPath != path) continue;
      return it['type']?.toString() == 'dir';
    }
    return false;
  }

  bool _validateSelectedPaths(List<String> selected) {
    if (!_requireFileExtension) return true;
    final allowed = allowedExtensions!;
    final allowedLabel = folderPickerAllowedExtensionsLabel(allowed);
    for (final path in selected) {
      if (_isDirectoryPath(path)) {
        ToastUtil.show('folder_picker_select_file_required'.tr);
        return false;
      }
      if (!folderPickerPathMatchesExtension(path, allowed)) {
        final ext = p.extension(path);
        ToastUtil.show(
          'folder_picker_invalid_extension'.trParams({
            'ext': ext.isEmpty ? '-' : ext,
            'allowed': allowedLabel,
          }),
        );
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final selected = ctrl.getSelected();
              if (selected.isEmpty) {
                if (_requireFileExtension) {
                  ToastUtil.show('folder_picker_select_file_required'.tr);
                  return;
                }
                final currentDir = ctrl.currentPath.value;
                if (currentDir == "") return;

                final confirmed = await DialogUtil.showConfirmDialog(
                  title: 'folder_picker_confirm'.tr,
                  content: 'folder_picker_confirm_current_dir'.trParams({
                    'dir': currentDir ?? '',
                  }),
                  confirmText: 'yes'.tr,
                  cancelText: 'no'.tr,
                );
                if (confirmed ?? false) {
                  await onSaveRecentFolder(currentDir ?? '');
                  if (!context.mounted) return;
                  Navigator.pop(context, <String>[currentDir ?? '']);
                }
              } else {
                if (!_validateSelectedPaths(selected)) return;
                // 只保存文件夹
                bool shouldSaveToRecent(String path) {
                  for (final it in ctrl.items) {
                    final itPath = it['path']?.toString() ?? '';
                    if (itPath != path) continue;
                    return it['type']?.toString() == 'dir';
                  }
                  return true;
                }

                for (final path in selected) {
                  if (!shouldSaveToRecent(path)) continue;
                  await onSaveRecentFolder(path);
                }
                if (!context.mounted) return;
                Navigator.pop(context, selected);
              }
            },
            child: Text('ok'.tr),
          ),
        ),
      ),
    );
  }
}
