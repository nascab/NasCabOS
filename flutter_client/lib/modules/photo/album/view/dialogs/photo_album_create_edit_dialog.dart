import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:NasCabOS/modules/base/components/custom_icon_button.dart';
import '../../controller/photo_album_controller.dart';
import '../../models/photo_album_model.dart';
import '../../service/photo_album_api_service.dart';

Widget buildPhotoAlbumCreateEditDialogContent({
  required BuildContext context,
  required TextEditingController nameCtrl,
  required VoidCallback onNameChanged,
  required bool isPublic,
  required void Function(bool next) onPublicChanged,
  required bool autofocus,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
  return ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: 300,
      maxWidth: 520,
      maxHeight: maxHeight,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            autofocus: autofocus,
            onChanged: (_) => onNameChanged(),
            decoration: InputDecoration(
              labelText: 'photo_album_name'.tr,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CustomIconButton(
                icon: Icons.help_outline,
                onPressed: () => DialogUtil.showInfoDialog(
                  title: 'tip'.tr,
                  content: 'photo_album_public_help'.tr,
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  activeColor: Theme.of(context).colorScheme.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text('photo_album_public'.tr),
                  value: isPublic,
                  onChanged: onPublicChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<void> showPhotoAlbumCreateDialogWithSubmit(
  BuildContext context, {
  required Future<bool> Function({required String name, required bool isPublic})
  onSubmit,
}) async {
  final nameCtrl = TextEditingController();
  var isPublic = false;
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
            return DialogUtil.createAlertDialog(
              title: Text('photo_album_create'.tr),
              content: buildPhotoAlbumCreateEditDialogContent(
                context: context,
                nameCtrl: nameCtrl,
                onNameChanged: () => setState(() {}),
                isPublic: isPublic,
                onPublicChanged: (v) => setState(() => isPublic = v),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          final suc = await onSubmit(
                            name: nameCtrl.text.trim(),
                            isPublic: isPublic,
                          );
                          if (suc) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          }
                        },
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

Future<void> showPhotoAlbumEditDialogWithSubmit(
  BuildContext context,
  PhotoAlbumItem album, {
  required Future<bool> Function({
    required int id,
    required String name,
    required bool isPublic,
  })
  onSubmit,
}) async {
  final nameCtrl = TextEditingController(text: album.name);
  var isPublic = album.isPublic;
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
            return DialogUtil.createAlertDialog(
              title: Text('photo_album_edit'.tr),
              content: buildPhotoAlbumCreateEditDialogContent(
                context: context,
                nameCtrl: nameCtrl,
                onNameChanged: () => setState(() {}),
                isPublic: isPublic,
                onPublicChanged: (v) => setState(() => isPublic = v),
                autofocus: false,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('cancel'.tr),
                ),
                ElevatedButton(
                  onPressed: nameCtrl.text.trim().isEmpty
                      ? null
                      : () async {
                          final suc = await onSubmit(
                            id: album.id,
                            name: nameCtrl.text.trim(),
                            isPublic: isPublic,
                          );
                          if (suc) {
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          }
                        },
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

Future<void> showPhotoAlbumCreateDialog(
  BuildContext context,
  PhotoAlbumController controller,
) async {
  await showPhotoAlbumCreateDialogWithSubmit(
    context,
    onSubmit: ({required name, required isPublic}) async {
      return controller.createAlbum(name: name, isPublic: isPublic);
    },
  );
}

Future<void> showPhotoAlbumEditDialog(
  BuildContext context,
  PhotoAlbumController controller,
  PhotoAlbumItem album,
) async {
  await showPhotoAlbumEditDialogWithSubmit(
    context,
    album,
    onSubmit: ({required id, required name, required isPublic}) async {
      return controller.updateAlbum(id: id, name: name, isPublic: isPublic);
    },
  );
}

Future<void> showPhotoAlbumCreateDialogWithApi(
  BuildContext context,
  PhotoAlbumApiService api,
) async {
  await showPhotoAlbumCreateDialogWithSubmit(
    context,
    onSubmit: ({required name, required isPublic}) async {
      final res = await api.createAlbum(name: name, isPublic: isPublic);
      if (!res.success && res.message != null) {
        DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
      }
      return res.success;
    },
  );
}

Future<void> showPhotoAlbumEditDialogWithApi(
  BuildContext context,
  PhotoAlbumItem album,
  PhotoAlbumApiService api,
) async {
  await showPhotoAlbumEditDialogWithSubmit(
    context,
    album,
    onSubmit: ({required id, required name, required isPublic}) async {
      final res = await api.updateAlbum(id: id, name: name, isPublic: isPublic);
      if (!res.success && res.message != null) {
        DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
      }
      return res.success;
    },
  );
}
