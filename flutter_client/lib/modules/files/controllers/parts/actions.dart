part of '../file_controller.dart';

extension FileControllerActions on FileController {
  Future<bool> _ensureWriteSupported() async {
    final base = currentPath.value ?? '';
    try {
      final res = await _api.checkMkdirSupport(base);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      final supported = res.data?['supported'] == true;
      if (!supported) {
        ToastUtil.show('folder_action_not_supported'.tr);
      }
      return supported;
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  Future<bool> ensureCreateFolderSupported() async {
    return _ensureWriteSupported();
  }

  Future<bool> ensureCreateFileSupported() async {
    return _ensureWriteSupported();
  }

  Future<bool> ensureUploadSupported() async {
    return _ensureWriteSupported();
  }

  /// 创建文件夹
  Future<bool> createFolder(String name) async {
    final base = currentPath.value ?? '';
    if (base.isEmpty || name.trim().isEmpty) return false;
    try {
      final res = await _api.mkdir(base, name.trim());
      if (res.success) {
        // 重新获取列表以确保数据最新，因为需要获取新创建文件夹的完整信息
        await listDirectory(base, null);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
      return res.success;
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  Future<bool> createTextFileAndOpen({
    required String name,
    required String type,
  }) async {
    final base = currentPath.value ?? '';
    final trimmed = name.trim();
    if (base.isEmpty || trimmed.isEmpty) return false;
    try {
      final res = await _api.createFile(base, trimmed, type: type);
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return false;
      }
      final created = (res.data ?? <String, dynamic>{});
      if (created.isNotEmpty) {
        await listDirectory(base, null);
        if (type.trim().toLowerCase() == 'txt') {
          await openTextEditorForItem(created);
        } else {
          await handleItemTap(created, [created], forceEnter: true);
        }
      } else {
        await listDirectory(base, null);
      }
      return true;
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
  }

  /// 复制到/移动到：弹出目录选择器选择目标目录，然后调用后端创建任务
  Future<void> handleCopyOrMove({required bool isCopy}) async {
    final paths = selected.toList();
    if (paths.isEmpty) return;

    final targetDir = await showFolderPickerBottomSheet(
      Get.context!,
      multiSelect: false,
    );
    if (targetDir == null || targetDir.isEmpty) return;

    final targetPath = targetDir.first;
    final confirm = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: isCopy
          ? 'folder_action_confirm_copy'.trParams({
              'count': paths.length.toString(),
              'target': targetPath,
            })
          : 'folder_action_confirm_move'.trParams({
              'count': paths.length.toString(),
              'target': targetPath,
            }),
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (confirm != true) return;

    final result = isCopy
        ? await _api.copyFiles(paths, targetPath)
        : await _api.moveFiles(paths, targetPath);

    if (result.success) {
      print("showRunningTaskListDialog");
      showRunningTaskListDialog(Get.context!);
    } else {
      ToastUtil.show(result.message ?? 'operation_failed'.tr);
    }
  }

  /// 删除已选中的文件或文件夹
  Future<bool> deleteSelectedEntries({bool recycle = false}) async {
    final targets = getSelected();
    if (targets.isEmpty) return false;
    try {
      final res = await _api.deleteEntries(targets, recycle: recycle);
      if (res.success) {
        clearSelect();
        // 从当前列表中移除被删除的项，而不是重新获取整个列表，以保持滚动位置
        items.removeWhere(
          (item) => targets.contains(item['path']?.toString() ?? ''),
        );
        ToastUtil.show('delete_success'.tr);
      } else {
        DialogUtil.showErrorDialog(
          message: res.message ?? 'operation_failed'.tr,
        );
      }
      return res.success;
    } catch (_) {
      return false;
    }
  }

  /// 重命名文件或文件夹
  Future<bool> renameEntry(String path, String newName) async {
    try {
      final res = await _api.rename(path, newName);
      if (res.success) {
        final result = res.data ?? {};
        if (result.isNotEmpty) {
          // 更新本地列表中的数据，而不是重新获取整个列表，以保持滚动位置
          final index = items.indexWhere(
            (item) => item['path']?.toString() == path,
          );
          if (index >= 0) {
            items[index] = result;
          }
          ToastUtil.show('operation_success'.tr);
        }
        return true;
      } else {
        DialogUtil.showErrorDialog(
          message: res.message ?? 'operation_failed'.tr,
        );
        return false;
      }
    } catch (_) {
      DialogUtil.showErrorDialog(message: 'operation_failed'.tr);
      return false;
    }
  }

  /// PC 端拖放移动：目标是否为合法文件夹落点（不含写权限校验）
  bool canAcceptInternalFileDrop(
    List<String> sourcePaths,
    String targetFolder,
  ) {
    final tgt = targetFolder.trim().replaceAll('\\', '/');
    if (tgt.isEmpty || sourcePaths.isEmpty) return false;
    final sources = sourcePaths
        .map((e) => e.replaceAll('\\', '/'))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (sources.isEmpty) return false;
    if (_targetInsideAnySourceForMove(sources, tgt)) return false;
    final toMove = sources.where((s) => p.posix.dirname(s) != tgt).toList();
    return toMove.isNotEmpty;
  }

  /// PC 端拖放：立即移动（无确认框），失败时 Toast
  Future<void> moveEntriesToFolderImmediate(
    List<String> sourcePaths,
    String targetFolder,
  ) async {
    final tgt = targetFolder.trim().replaceAll('\\', '/');
    if (tgt.isEmpty || sourcePaths.isEmpty) return;
    final sources = sourcePaths
        .map((e) => e.replaceAll('\\', '/'))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (sources.isEmpty) return;
    if (_targetInsideAnySourceForMove(sources, tgt)) return;
    final toMove = sources.where((s) => p.posix.dirname(s) != tgt).toList();
    if (toMove.isEmpty) return;

    final confirmed = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'folder_action_confirm_move'.trParams({
        'count': toMove.length.toString(),
        'target': tgt,
      }),
      confirmOnEnter: true,
    );
    if (confirmed != true) return;

    final ok = await _ensureWriteSupported();
    if (!ok) return;

    final result = await _api.moveFiles(toMove, tgt);
    if (result.success) {
      final ctx = Get.overlayContext ?? Get.context;
      if (ctx != null && ctx.mounted) {
        showRunningTaskListDialog(ctx);
      }
      final base = currentPath.value ?? '';
      String? listSrc;
      if (currentModule.value == 'favorites') {
        listSrc = 'favorites';
      } else if (currentModule.value == 'recent') {
        listSrc = 'recent';
      }
      await listDirectory(base, listSrc, sourceType: currentSourceType.value);
    } else {
      ToastUtil.show(result.message ?? 'operation_failed'.tr);
    }
  }
}

bool _targetInsideAnySourceForMove(List<String> sources, String target) {
  final t = target.replaceAll('\\', '/');
  for (final raw in sources) {
    final s = raw.replaceAll('\\', '/');
    if (s.isEmpty) continue;
    if (t == s) return true;
    final pref = s.endsWith('/') ? s : '$s/';
    if (t.startsWith(pref)) return true;
  }
  return false;
}
