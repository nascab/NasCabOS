import 'package:NasCabOS/modules/base/components.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../files/views/folder_picker_dialog.dart';
import '../../controller/book_collection_controller.dart';
import '../../models/book_collection_model.dart';

class BookCollectionDialogs {
  static Widget buildCreateEditDialogContent({
    required BuildContext context,
    required String nameValue,
    required ValueChanged<String> onNameChanged,
    required VoidCallback onChanged,
    required List<String> pathList,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 360, maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            initialValue: nameValue,
            autofocus: true,
            onChanged: (v) {
              onNameChanged(v);
            },
            decoration: InputDecoration(
              labelText: 'name'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final selected = await showFolderPickerBottomSheet(
                      context,
                      multiSelect: true,
                      allowFileSelect: false,
                      sourceType: 'book',
                    );
                    if (selected == null || selected.isEmpty) return;
                    for (final p in selected) {
                      if (!pathList.contains(p)) {
                        pathList.add(p);
                      }
                    }
                    onChanged();
                  },
                  icon: const Icon(Icons.folder_open),
                  label: Text('choose_path'.tr),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (pathList.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int index = 0; index < pathList.length; index++) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pathList[index],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              tooltip: 'delete'.tr,
                              onPressed: () {
                                pathList.removeAt(index);
                                onChanged();
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                      if (index != pathList.length - 1)
                        const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Future<void> showCreateDialog(
    BuildContext context, {
    required BookCollectionController controller,
  }) async {
    var name = '';
    final pathList = <String>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = name.trim().isNotEmpty && pathList.isNotEmpty;
            return DialogUtil.createAlertDialog(
              title: Row(
                children: [
                  Text('book_create_collection'.tr),
                  const SizedBox(width: 8),
                  CustomIconButton(
                    icon: Icons.info_outlined,
                    onPressed: () => DialogUtil.showInfoDialog(
                      title: 'book_create_collection'.tr,
                      content: 'book_create_collection_alert'.tr,
                    ),
                  ),
                ],
              ),
              content: buildCreateEditDialogContent(
                context: context,
                nameValue: name,
                onNameChanged: (v) {
                  name = v;
                  setState(() {});
                },
                onChanged: () => setState(() {}),
                pathList: pathList,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final suc = await controller.createCollection(
                            name: name.trim(),
                            pathList: pathList,
                          );
                          if (suc) {
                            Navigator.of(Get.context!).pop();
                          }
                        }
                      : null,
                  child: Text('create'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> showEditDialog(
    BuildContext context, {
    required BookCollectionController controller,
    required BookCollectionItem collection,
  }) async {
    var name = collection.name;
    final pathList = collection.pathList.toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit = name.trim().isNotEmpty && pathList.isNotEmpty;
            return DialogUtil.createAlertDialog(
              title: Text('edit'.tr),
              content: buildCreateEditDialogContent(
                context: context,
                nameValue: name,
                onNameChanged: (v) {
                  name = v;
                  setState(() {});
                },
                onChanged: () => setState(() {}),
                pathList: pathList,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: canSubmit
                      ? () async {
                          final suc = await controller.updateCollection(
                            id: collection.id,
                            name: name.trim(),
                            pathList: pathList,
                          );
                          if (suc) {
                            Navigator.of(Get.context!).pop();
                          }
                        }
                      : null,
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> confirmDelete(
    BuildContext context, {
    required BookCollectionController controller,
    required BookCollectionItem collection,
  }) async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: "${'confirm_delete'.tr}[${collection.name}]",
      confirmText: 'confirm'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok == true) {
      await controller.deleteCollection(collection.id);
    }
  }
}
