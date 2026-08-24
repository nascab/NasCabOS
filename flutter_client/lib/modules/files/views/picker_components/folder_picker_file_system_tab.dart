import 'package:NasCabOS/modules/base/components/custom_divider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../base/components/custom_icon_button.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../controllers/file_controller.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../../utils/file_util.dart';
import '../../../../utils/dialog_util.dart';

class FolderPickerFileSystemTab extends StatelessWidget {
  const FolderPickerFileSystemTab({
    super.key,
    required this.ctrl,
    required this.crumbController,
    required this.multiSelect,
    required this.crumbBarHeight,
    this.onFolderCreated,
  });

  final FileController ctrl;
  final ScrollController crumbController;
  final bool multiSelect;
  final double crumbBarHeight;

  /// 新建文件夹成功后回调，参数为新文件夹完整路径
  final void Function(String newFolderPath)? onFolderCreated;

  @override
  Widget build(BuildContext context) {
    void toggle(String path) {
      if (multiSelect) {
        ctrl.toggleSelect(path);
      } else {
        ctrl.selected.clear();
        ctrl.toggleSelect(path);
      }
    }

    return Column(
      children: [
        SizedBox(
          height: crumbBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                CustomIconButton(
                  icon: Icons.create_new_folder_outlined,
                  onPressed: () async {
                    final supported = await ctrl.ensureCreateFolderSupported();
                    if (!supported) return;
                    final name = await DialogUtil.showInputDialog(
                      title: 'folder_new_dir'.tr,
                      content: 'enter_new_name'.tr,
                      confirmText: 'ok'.tr,
                      cancelText: 'cancel'.tr,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'name_cannot_be_empty'.tr;
                        }
                        return null;
                      },
                    );
                    if (name != null && name.isNotEmpty) {
                      final created = await ctrl.createFolder(name);
                      if (created) {
                        final base = ctrl.currentPath.value ?? '';
                        final separator = ctrl.sep.value;
                        final newPath = base.isEmpty
                            ? name.trim()
                            : '$base$separator${name.trim()}';
                        onFolderCreated?.call(newPath);
                      }
                    }
                  },
                  tooltip: 'folder_action_new'.tr,
                ),
                Obx(
                  () => CustomIconButton(
                    icon: Icons.arrow_upward_outlined,
                    onPressed: ctrl.isRoot ? null : () => ctrl.goUp(),
                    tooltip: 'back'.tr,
                  ),
                ),
                Expanded(
                  child: Obx(() {
                    final segs = ctrl.segments;
                    final separator = ctrl.sep.value;
                    final List<Widget> children = [];
                    children.add(
                      TextButton(
                        onPressed: () => ctrl.listDirectory('', null),
                        child: Text('folder_picker_root'.tr),
                      ),
                    );
                    if (segs.isNotEmpty) {
                      children.add(Text(separator));
                      final startIndex =
                          (segs.isNotEmpty &&
                              (segs.first['name']?.toString() ?? '') ==
                                  separator)
                          ? 1
                          : 0;
                      for (var i = startIndex; i < segs.length; i++) {
                        final s = segs[i];
                        children.add(
                          TextButton(
                            onPressed: () =>
                                ctrl.navigateTo(s['path']?.toString() ?? ''),
                            child: Text(s['name']?.toString() ?? ''),
                          ),
                        );
                        if (i < segs.length - 1) {
                          children.add(Text(separator));
                        }
                      }
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (crumbController.hasClients) {
                        final max = crumbController.position.maxScrollExtent;
                        crumbController.jumpTo(max);
                      }
                    });
                    return SingleChildScrollView(
                      controller: crumbController,
                      scrollDirection: Axis.horizontal,
                      child: Row(children: children),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
        const CustomDivider(height: 1),
        Expanded(
          child: Obx(
            () => ListView.builder(
              itemCount: ctrl.items.length,
              itemBuilder: (_, i) {
                final it = ctrl.items[i];
                final path = it['path']?.toString() ?? '';
                final name = it['name']?.toString() ?? '';
                final type = it['type']?.toString() ?? '';
                final filePath = it['path']?.toString() ?? '';
                final iconPath = ctrl.iconFor(name, filePath, type);
                return ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Obx(
                        () => CustomCheckbox(
                          value: ctrl.selected.contains(path),
                          onChanged: (_) => toggle(path),
                        ),
                      ),
                      const SizedBox(width: 6),
                      iconPath.startsWith('assets')
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                iconPath,
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CustomExtendedImage(
                                imageUrl: iconPath,
                                fit: BoxFit.cover,
                                width: 24,
                                height: 24,
                              ),
                            ),
                    ],
                  ),
                  title: Text(name),
                  subtitle: Text(
                    type == 'dir'
                        ? ctrl.formatMtime(it['mtimeMs'] as num?)
                        : FileUtil.formatSize(it['size'] as int?),
                  ),
                  onTap: () {
                    if (type == 'dir') {
                      ctrl.navigateTo(path);
                      return;
                    }
                    toggle(path);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
