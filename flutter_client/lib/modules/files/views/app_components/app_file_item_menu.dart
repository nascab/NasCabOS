import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../controllers/file_controller.dart';
import '../../service/file_stats_service.dart';
import '../../../../utils/file_util.dart';
import '../../../transfer/controllers/download_controller.dart';
import 'package:path/path.dart' as p;

Future<void> showAppFileItemMenuBottomSheet(
  BuildContext context, {
  required FileController ctrl,
  required Map<String, dynamic> item,
  required List<Map<String, dynamic>> allItems,
}) async {
  final theme = Theme.of(context);
  final path = item['path']?.toString() ?? '';
  final name = item['name']?.toString() ?? '';
  final isCustomPath = item['isCustomPath'] == true;

  if (path.isNotEmpty) {
    ctrl.selectOnly(path);
  }

  final inFavoritesModule = ctrl.currentModule.value == 'favorites';
  var actionTaken = false;
  final type = item['type']?.toString() ?? '';
  final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
  final isTxt = type.trim().toLowerCase() == 'txt' || ext == 'txt';

  if (isCustomPath) {
    await Get.bottomSheet(
      Container(
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  children: [
                    ListTile(
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.remove_circle_outline_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'file_custom_path_remove'.tr,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      onTap: () async {
                        actionTaken = true;
                        Get.back();
                        if (path.trim().isEmpty) {
                          ctrl.clearSelect();
                          return;
                        }
                        await ctrl.removeCustomPath(path);
                        ctrl.clearSelect();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
    if (!actionTaken) {
      ctrl.clearSelect();
    }
    return;
  }

  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                children: [
                  ListTile(
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.drive_file_rename_outline_outlined,
                    ),
                    title: Text('rename'.tr),
                    onTap: () async {
                      actionTaken = true;
                      Get.back();
                      final newName = await DialogUtil.showInputDialog(
                        title: 'rename'.tr,
                        content: 'enter_new_name'.tr,
                        initialValue: name,
                        confirmText: 'ok'.tr,
                        cancelText: 'cancel'.tr,
                        validator: (value) {
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) return 'name_cannot_be_empty'.tr;
                          return null;
                        },
                      );
                      if (newName != null &&
                          newName.isNotEmpty &&
                          newName != name) {
                        await ctrl.renameEntry(path, newName);
                      }
                      ctrl.clearSelect();
                    },
                  ),
                  if (isTxt && type != 'dir')
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text('edit'.tr),
                      onTap: () async {
                        actionTaken = true;
                        Get.back();
                        await ctrl.openTextEditorForItem(item);
                        ctrl.clearSelect();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: Text('download'.tr),
                    onTap: () async {
                      actionTaken = true;
                      Get.back();
                      if (path.isEmpty) {
                        ctrl.clearSelect();
                        return;
                      }
                      if (!Get.isRegistered<DownloadController>()) {
                        Get.put(DownloadController(), permanent: true);
                      }
                      bool? dirHint;
                      final t = item['type']?.toString() ?? '';
                      if (t == 'dir') {
                        dirHint = true;
                      } else if (t.isNotEmpty) {
                        dirHint = false;
                      }
                      await Get.find<DownloadController>().handleDownload(
                        [path],
                        remoteIsDirectoryHint: dirHint != null
                            ? <bool?>[dirHint]
                            : null,
                      );
                      ctrl.clearSelect();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.flash_on_outlined),
                    title: Text('quick_share_title'.tr),
                    onTap: () {
                      actionTaken = true;
                      Get.back();
                      final p = path.trim();
                      if (p.isEmpty) {
                        ctrl.clearSelect();
                        return;
                      }
                      ctrl.openQuickShareCreateAt(p);
                      ctrl.clearSelect();
                    },
                  ),
                  if (!inFavoritesModule) ...[
                    ListTile(
                      leading: const Icon(Icons.copy_outlined),
                      title: Text('folder_action_copy_to'.tr),
                      onTap: () async {
                        actionTaken = true;
                        Get.back();
                        await ctrl.handleCopyOrMove(isCopy: true);
                        ctrl.clearSelect();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.drive_file_move_outline),
                      title: Text('folder_action_move_to'.tr),
                      onTap: () async {
                        actionTaken = true;
                        Get.back();
                        await ctrl.handleCopyOrMove(isCopy: false);
                        ctrl.clearSelect();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: Text('folder_add_favorite'.tr),
                      onTap: () async {
                        actionTaken = true;
                        Get.back();
                        final ok = await ctrl.addFavorites(
                          ctrl.selected.toList(),
                        );
                        ToastUtil.show(
                          ok ? 'operation_success'.tr : 'operation_failed'.tr,
                        );
                        ctrl.clearSelect();
                      },
                    ),
                  ] else ...[
                    ListTile(
                      leading: const Icon(Icons.star_outline),
                      title: Text('unfavorite'.tr),
                      onTap: () async {
                        actionTaken = true;
                        Get.back();
                        final ok = await ctrl.removeFavorites(
                          ctrl.selected.toList(),
                        );
                        ToastUtil.show(
                          ok ? 'operation_success'.tr : 'operation_failed'.tr,
                        );
                        if (ok) {
                          await ctrl.refreshPage();
                        }
                        ctrl.clearSelect();
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'delete'.tr,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () async {
                      actionTaken = true;
                      Get.back();
                      final isShellSupported =
                          ApiController.instance.state.shellSupported;
                      if (isShellSupported) {
                        await DialogUtil.showConfirmThreeButtonsDialog(
                          title: 'need_confirm'.tr,
                          content: 'folder_delete_confirm'.trParams({
                            'fileCount': ctrl.selected.length.toString(),
                          }),
                          cancelText: 'cancel'.tr,
                          option1Text: 'delete'.tr,
                          option2Text: 'put_in_recycle_bin'.tr,
                          option2IsPrimary: true,
                          onOption1: () =>
                              ctrl.deleteSelectedEntries(recycle: false),
                          onOption2: () =>
                              ctrl.deleteSelectedEntries(recycle: true),
                        );
                      } else {
                        final confirmed = await DialogUtil.showConfirmDialog(
                          title: 'need_confirm'.tr,
                          content: 'folder_delete_confirm'.trParams({
                            'fileCount': ctrl.selected.length.toString(),
                          }),
                          confirmText: 'ok'.tr,
                          cancelText: 'cancel'.tr,
                        );
                        if (confirmed == true) {
                          await ctrl.deleteSelectedEntries();
                        }
                      }
                      ctrl.clearSelect();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text('property'.tr),
                    onTap: () async {
                      actionTaken = true;
                      Get.back();
                      await showAppFilePropertiesSheet(
                        context,
                        ctrl: ctrl,
                        item: item,
                      );
                      ctrl.clearSelect();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    ),
  );
  if (!actionTaken) {
    ctrl.clearSelect();
  }
}

Future<void> showAppFilePropertiesSheet(
  BuildContext context, {
  required FileController ctrl,
  required Map<String, dynamic> item,
}) async {
  final theme = Theme.of(context);
  final name = item['name']?.toString() ?? '';
  final path = item['path']?.toString() ?? '';
  final type = item['type']?.toString() ?? '';
  final size = (item['size'] as int?) ?? -1;
  final mtime = item['mtimeMs'] as num?;

  String typeLabel() {
    if (type == 'dir') return 'dir'.tr;
    if (type == 'image') return 'file_type_image'.tr;
    if (type == 'video') return 'file_type_video'.tr;
    if (type == 'archive') return 'file_type_archive'.tr;
    return 'file'.tr;
  }

  final isDir = type == 'dir';
  final statsService = FileStatsService();
  final statsSize = 0.obs;
  final statsFileCount = 0.obs;
  final statsFolderCount = 0.obs;
  final statsCtime = Rxn<DateTime>();
  final statsMtime = Rxn<DateTime>();
  final isCalculating = false.obs;

  void closeSheet() {
    if (isDir) statsService.close();
    Get.back();
  }

  if (isDir && path.isNotEmpty) {
    isCalculating.value = true;
    statsService.connect(
      paths: [path],
      onProgress: (stats) {
        statsSize.value = stats.size;
        statsFileCount.value = stats.count;
        statsFolderCount.value = stats.folderCount;
        if (stats.ctime != null) statsCtime.value = stats.ctime;
        if (stats.mtime != null) statsMtime.value = stats.mtime;
      },
      onComplete: (stats) {
        statsSize.value = stats.size;
        statsFileCount.value = stats.count;
        statsFolderCount.value = stats.folderCount;
        isCalculating.value = false;
      },
      onError: (_) {
        isCalculating.value = false;
      },
    );
  }

  await Get.bottomSheet(
    Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Obx(() {
            final df = DateFormat('yyyy-MM-dd HH:mm:ss');
            final sizeText = isDir
                ? FileUtil.formatSize(statsSize.value)
                : (size >= 0 ? FileUtil.formatSize(size) : '');
            final ctimeText = statsCtime.value != null
                ? df.format(statsCtime.value!)
                : '';
            final mtimeText = isDir
                ? (statsMtime.value != null ? df.format(statsMtime.value!) : '')
                : ctrl.formatMtime(mtime);
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'property'.tr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _kv(theme, 'name'.tr, name),
                  const SizedBox(height: 8),
                  _kv(theme, 'path'.tr, path),
                  const SizedBox(height: 8),
                  _kv(theme, 'type'.tr, typeLabel()),
                  const SizedBox(height: 8),
                  _kv(theme, 'size'.tr, sizeText),
                  if (isDir) ...[
                    const SizedBox(height: 8),
                    _kv(
                      theme,
                      'contains'.tr,
                      "${'file_count_format'.trParams({'count': statsFileCount.value.toString()})}, ${'folder_count_format'.trParams({'count': statsFolderCount.value.toString()})}",
                    ),
                  ],
                  if (ctimeText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _kv(theme, 'create_time'.tr, ctimeText),
                  ],
                  const SizedBox(height: 8),
                  _kv(theme, 'modified_at'.tr, mtimeText),
                  if (isDir && isCalculating.value) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: closeSheet,
                      child: Text('home_window_close'.tr),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          }),
        ),
      ),
    ),
    isScrollControlled: true,
  ).whenComplete(() {
    if (isDir) statsService.close();
  });
}

Widget _kv(ThemeData theme, String k, String v) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 76,
        child: Text(
          k,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
    ],
  );
}
