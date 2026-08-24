part of '../video_collection_list_view.dart';

Widget _buildCollectionCreateEditDialogContent({
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
            labelText: 'photo_collection_name'.tr,
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
                    sourceType: 'video',
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
                    if (index != pathList.length - 1) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

Future<void> _showCreateDialog(
  BuildContext context,
  VideoCollectionController controller,
) async {
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
                Text('photo_create_collection'.tr),
                const SizedBox(width: 8),
                CustomIconButton(
                  icon: Icons.info_outlined,
                  onPressed: () => DialogUtil.showInfoDialog(
                    title: 'photo_create_collection'.tr,
                    content: 'photo_create_collection_alert'.tr,
                  ),
                ),
              ],
            ),
            content: _buildCollectionCreateEditDialogContent(
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

Future<void> _showEditDialog(
  BuildContext context,
  VideoCollectionController controller,
  VideoCollectionItem collection,
) async {
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
            content: _buildCollectionCreateEditDialogContent(
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

Future<void> _confirmDelete(
  BuildContext context,
  VideoCollectionController controller,
  VideoCollectionItem collection,
) async {
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
