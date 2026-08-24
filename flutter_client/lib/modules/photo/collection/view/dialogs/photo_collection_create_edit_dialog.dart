import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/modules/base/components/custom_icon_button.dart';
import 'package:NasCabOS/modules/files/views/folder_picker_dialog.dart';
import '../../controller/photo_collection_controller.dart';
import '../../models/photo_collection_model.dart';
import '../../service/photo_collection_api_service.dart';

Widget buildPhotoCollectionCreateEditDialogContent({
  required BuildContext context,
  required TextEditingController nameCtrl,
  required VoidCallback onChanged,
  required List<String> pathList,
}) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 360, maxWidth: 520),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameCtrl,
          autofocus: true,
          onChanged: (_) => onChanged(),
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
                    sourceType: 'photo',
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

Future<void> showPhotoCollectionCreateDialogWithSubmit(
  BuildContext context, {
  required Future<bool> Function({
    required String name,
    required List<String> pathList,
  })
  onSubmit,
}) async {
  final nameCtrl = TextEditingController();
  final pathList = <String>[];
  var disposed = false;
  void safeDispose() {
    if (disposed) return;
    disposed = true;
    nameCtrl.dispose();
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit =
                nameCtrl.text.trim().isNotEmpty && pathList.isNotEmpty;
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
              content: buildPhotoCollectionCreateEditDialogContent(
                context: context,
                nameCtrl: nameCtrl,
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
                          final suc = await onSubmit(
                            name: nameCtrl.text.trim(),
                            pathList: pathList,
                          );
                          if (suc) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
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
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      safeDispose();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => safeDispose());
    }
  }
}

Future<void> showPhotoCollectionEditDialogWithSubmit(
  BuildContext context,
  PhotoCollectionItem collection, {
  required Future<bool> Function({
    required int id,
    required String name,
    required List<String> pathList,
  })
  onSubmit,
}) async {
  final nameCtrl = TextEditingController(text: collection.name);
  final pathList = collection.pathList.toList();
  var disposed = false;
  void safeDispose() {
    if (disposed) return;
    disposed = true;
    nameCtrl.dispose();
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSubmit =
                nameCtrl.text.trim().isNotEmpty && pathList.isNotEmpty;
            return DialogUtil.createAlertDialog(
              title: Text('edit'.tr),
              content: buildPhotoCollectionCreateEditDialogContent(
                context: context,
                nameCtrl: nameCtrl,
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
                          final suc = await onSubmit(
                            id: collection.id,
                            name: nameCtrl.text.trim(),
                            pathList: pathList,
                          );
                          if (suc) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
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
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      safeDispose();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => safeDispose());
    }
  }
}

Future<void> showPhotoCollectionCreateDialog(
  BuildContext context,
  PhotoCollectionController controller,
) async {
  await showPhotoCollectionCreateDialogWithSubmit(
    context,
    onSubmit: ({required name, required pathList}) async {
      return controller.createCollection(name: name, pathList: pathList);
    },
  );
}

Future<void> showPhotoCollectionEditDialog(
  BuildContext context,
  PhotoCollectionController controller,
  PhotoCollectionItem collection,
) async {
  await showPhotoCollectionEditDialogWithSubmit(
    context,
    collection,
    onSubmit: ({required id, required name, required pathList}) async {
      return controller.updateCollection(
        id: id,
        name: name,
        pathList: pathList,
      );
    },
  );
}

Future<void> showPhotoCollectionCreateDialogWithApi(
  BuildContext context,
  PhotoCollectionApiService api,
) async {
  await showPhotoCollectionCreateDialogWithSubmit(
    context,
    onSubmit: ({required name, required pathList}) async {
      final res = await api.createCollection(name: name, pathList: pathList);
      if (!res.success && res.message != null) {
        DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
      }
      return res.success;
    },
  );
}

Future<void> showPhotoCollectionEditDialogWithApi(
  BuildContext context,
  PhotoCollectionItem collection,
  PhotoCollectionApiService api,
) async {
  await showPhotoCollectionEditDialogWithSubmit(
    context,
    collection,
    onSubmit: ({required id, required name, required pathList}) async {
      final res = await api.updateCollection(
        id: id,
        name: name,
        pathList: pathList,
      );
      if (!res.success && res.message != null) {
        DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
      }
      return res.success;
    },
  );
}

Future<void> confirmDeletePhotoCollection(
  BuildContext context,
  PhotoCollectionController controller,
  PhotoCollectionItem collection,
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
