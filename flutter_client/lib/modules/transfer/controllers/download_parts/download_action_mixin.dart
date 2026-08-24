part of '../download_controller.dart';

/// 下载操作 Mixin
/// 包含任务的暂停、恢复、删除、重试以及清空等操作逻辑
mixin DownloadActionMixin on DownloadWorkerMixin, DownloadWebMixin {
  Future<void> shareCompletedTask(
    BuildContext context,
    TransferTask task,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    if (task.status != TransferStatus.completed) return;

    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? Rect.zero
          : box.localToGlobal(Offset.zero) & box.size;

      final dir = Directory(task.localPath);
      if (await dir.exists()) {
        ToastUtil.show('not_implemented_yet'.tr);
        return;
      }

      final file = File(task.localPath);
      if (!await file.exists()) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }

      await Share.shareXFiles(
        [XFile(task.localPath)],
        subject: task.name,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  /// 暂停单个任务
  /// 会同时暂停正在运行的子任务（如果是文件夹下载）
  void pauseTask(TransferTask task) async {
    task.status = TransferStatus.paused;
    tasks.refresh();

    final cancel = webP2pCancels.remove(task.id);
    if (cancel != null) {
      try {
        cancel();
      } catch (_) {}
      return;
    }

    // 暂停正在运行的子任务
    final runningChildId = folderRunningChild[task.id];
    if (runningChildId != null) {
      if (desktopCancelTokens.containsKey(runningChildId)) {
        // 桌面端 Dio 下载取消（不支持暂停，需取消后断点续传）
        desktopCancelTokens[runningChildId]?.cancel();
      } else {
        final p2pCancel = webP2pCancels.remove(runningChildId);
        if (p2pCancel != null) {
          webP2pUserCanceled[runningChildId] = true;
          try {
            p2pCancel();
          } catch (_) {}
          return;
        }
        desktopCancelTokens[runningChildId]?.cancel();
      }
    }

    // 此时不再处理队列中的下一个任务
  }

  /// 恢复单个任务
  void resumeTask(TransferTask task) async {
    task.status = TransferStatus.uploading;
    tasks.refresh();

    if (kIsWeb) {
      final uri = Uri.tryParse(task.remotePath);
      if (uri != null && uri.origin.trim() == ApiController.p2pBaseUrl) {
        await restartWebTask(task);
        return;
      }
    }

    // 恢复正在运行的子任务
    final runningChildId = folderRunningChild[task.id];
    if (runningChildId != null) {
      // Dio 下载暂停即取消，无原生 resume；由 processNextFolderTask 在恢复时重试
    } else {
      // 如果没有运行中的子任务，则触发队列处理
      processNextFolderTask(task.id);
    }
  }

  /// 移除任务
  /// [deleteFile] 是否同时删除本地文件
  Future<void> removeTask(TransferTask task, {bool deleteFile = false}) async {
    tasks.remove(task);
    tasks.refresh();

    final cancel = webP2pCancels.remove(task.id);
    if (cancel != null) {
      try {
        cancel();
      } catch (_) {}
    }

    // 取消运行中的子任务
    final runningChildId = folderRunningChild[task.id];
    if (runningChildId != null) {
      if (desktopCancelTokens.containsKey(runningChildId)) {
        desktopCancelTokens[runningChildId]?.cancel();
        desktopCancelTokens.remove(runningChildId);
      } else {
        final p2pCancel = webP2pCancels.remove(runningChildId);
        if (p2pCancel != null) {
          webP2pUserCanceled[runningChildId] = true;
          try {
            p2pCancel();
          } catch (_) {}
        }
        desktopCancelTokens[runningChildId]?.cancel();
        desktopCancelTokens.remove(runningChildId);
      }
      activeDownloadTasks.remove(runningChildId);
    }

    // 清理队列和状态
    folderDownloadQueueLists.remove(task.id);
    folderRunningChild.remove(task.id);
    folderRunningTaskInfo.remove(task.id);

    // 清理子任务记录
    final childrenIds = parentToChildrenTasks[task.id];
    if (childrenIds != null) {
      // 同时清理进度记录，防止内存泄漏
      for (final childId in childrenIds) {
        fileProcessedBytes.remove(childId);
        fileSizes.remove(childId);
      }
      parentToChildrenTasks.remove(task.id);
    }

    if (deleteFile) {
      // 尝试删除本地文件/文件夹
      try {
        final file = File(task.localPath);
        if (await file.exists()) {
          await file.delete(recursive: true);
        } else {
          // 尝试删除临时文件
          final tempFile = File('${task.localPath}.nascab_tmp');
          if (await tempFile.exists()) {
            await tempFile.delete();
          }

          final dir = Directory(task.localPath);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
          }
        }
      } catch (e) {
        print('Error deleting file: $e');
      }
    }
  }

  /// 重试任务
  /// 采用“删除旧任务 + 添加新任务”的策略，确保状态彻底重置
  void retryTask(TransferTask task) async {
    final remotePath = task.remotePath;
    final localPath = task.localPath;
    final saveDir = p.dirname(localPath);
    // 移除任务但不删除文件，以便利用断点续传
    await removeTask(task, deleteFile: false);
    // 延迟一小段时间确保文件锁释放
    await Future.delayed(const Duration(milliseconds: 500));
    addTasks(
      [remotePath],
      saveDir,
      remoteIsDirectoryHint: task.remoteIsDirectory != null
          ? <bool?>[task.remoteIsDirectory]
          : null,
    );
  }

  /// 显示删除确认对话框
  void confirmRemoveTask(TransferTask task) {
    if (task.status == TransferStatus.completed) {
      removeTask(task, deleteFile: false);
      return;
    }

    if (kIsWeb && task.localPath == 'Browser') {
      removeTask(task, deleteFile: false);
      return;
    }

    final deleteFile = true.obs;
    Get.dialog(
      AlertDialog(
        title: Text('confirm_delete'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('confirm_delete_task'.tr),
            const SizedBox(height: 10),
            Row(
              children: [
                Obx(
                  () => CustomCheckbox(
                    value: deleteFile.value,
                    onChanged: (v) => deleteFile.value = v ?? false,
                  ),
                ),
                Text('delete_downloaded_local_file'.tr),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('cancel'.tr)),
          TextButton(
            onPressed: () {
              Get.back();
              removeTask(task, deleteFile: deleteFile.value);
            },
            child: Text('confirm'.tr),
          ),
        ],
      ),
    );
  }

  /// 暂停所有任务
  void pauseAll() async {
    for (var task in tasks) {
      if (task.status == TransferStatus.uploading) {
        task.status = TransferStatus.paused;
      }
    }
    tasks.refresh();

    for (final cancel in webP2pCancels.values) {
      try {
        cancel();
      } catch (_) {}
    }
    webP2pCancels.clear();

    for (final id in activeDownloadTasks.keys.toList()) {
      desktopCancelTokens[id]?.cancel();
    }
  }

  /// 开始/恢复所有任务
  void startAll() async {
    for (var task in tasks) {
      if (task.status == TransferStatus.paused) {
        task.status = TransferStatus.uploading;
      }
    }
    tasks.refresh();

    // 触发队列
    for (var task in tasks) {
      if (task.status == TransferStatus.uploading) {
        processNextFolderTask(task.id);
      }
    }
  }

  /// 清除已完成任务
  void clearCompleted() {
    tasks.removeWhere((t) => t.status == TransferStatus.completed);
    tasks.refresh();
  }

  /// 清除错误任务
  void clearError() {
    tasks.removeWhere((t) => t.status == TransferStatus.error);
    tasks.refresh();
  }

  /// 清空所有任务
  void clearAll({bool deleteFile = false}) async {
    for (final cancel in webP2pCancels.values) {
      try {
        cancel();
      } catch (_) {}
    }
    webP2pCancels.clear();

    // 取消所有桌面端 Token
    for (var token in desktopCancelTokens.values) {
      token.cancel();
    }
    desktopCancelTokens.clear();

    activeDownloadTasks.clear();

    // 清理所有进度记录
    fileProcessedBytes.clear();
    fileSizes.clear();
    parentToChildrenTasks.clear();

    if (deleteFile) {
      for (final task in tasks) {
        try {
          final file = File(task.localPath);
          if (await file.exists()) {
            await file.delete(recursive: true);
          } else {
            // 尝试删除临时文件
            final tempFile = File('${task.localPath}.nascab_tmp');
            if (await tempFile.exists()) {
              await tempFile.delete();
            }

            final dir = Directory(task.localPath);
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          }
        } catch (e) {
          print('Error deleting file: $e');
        }
      }
    }

    tasks.clear();
    tasks.refresh();
  }

  /// 确认清空所有任务
  void confirmClearAll() {
    clearAll(deleteFile: false);
  }
}
