part of '../file_controller.dart';

extension FileControllerClipboard on FileController {
  void copyToClipboard() {
    if (selected.isEmpty) return;
    clipboardItems.assignAll(selected.toList());
    clipboardAction.value = 'copy';
    ToastUtil.show(
      'file_clipboard_copy'.trParams({'count': selected.length.toString()}),
    );
  }

  void cutToClipboard() {
    if (selected.isEmpty) return;
    clipboardItems.assignAll(selected.toList());
    clipboardAction.value = 'cut';
    ToastUtil.show(
      'file_clipboard_cut'.trParams({'count': selected.length.toString()}),
    );
  }

  /// 清空剪贴板
  void clearClipboard() {
    clipboardItems.clear();
    clipboardAction.value = '';
    ToastUtil.show('folder_clean_clipboard'.tr);
  }

  Future<void> pasteFromClipboard() async {
    if (clipboardItems.isEmpty) return;
    // “最近”“收藏”列表不能作为黏贴目的地，不响应黏贴
    if (currentModule.value == 'recent' || currentModule.value == 'favorites') {
      return;
    }
    final targetPath = currentPath.value ?? '';

    final isCopy = clipboardAction.value == 'copy';

    final confirm = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'file_clipboard_paste'.trParams({
        'count': clipboardItems.length.toString(),
        'target': targetPath,
      }),
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );

    if (confirm == true) {
      final res = isCopy
          ? await _api.copyFiles(clipboardItems, targetPath)
          : await _api.moveFiles(clipboardItems, targetPath);

      if (res.success) {
        showRunningTaskListDialog(Get.context!);
        if (!isCopy) {
          clipboardItems.clear();
          clipboardAction.value = '';
        }
        await refreshPage();
        clipboardItems.value = [];
      } else {
        DialogUtil.showErrorDialog(
          message: res.message ?? 'operation_failed'.tr,
        );
      }
    }
  }
}
