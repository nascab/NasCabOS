part of '../photo_trash_controller.dart';

// 恢复操作管理
extension PhotoTrashRestore on PhotoTrashController {
  /// 恢复选中的照片
  Future<void> restoreSelected() async {
    if (selectedItems.isEmpty) return;

    try {
      final ids = selectedItems.toList();

      final ok = await _apiService.restoreFromTrash(ids);
      if (ok) {
        ToastUtil.show('operation_success'.tr);
        fetchTrashPhotos();
        selectedItems.clear();
        isMultiSelectMode.value = false;
      } else {
        ToastUtil.show('operation_failed'.tr);
      }
    } catch (e) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  /// 恢复所有照片
  Future<void> restoreAll() async {
    DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'restore_all_confirm'.tr,
      onConfirm: () async {
        try {
          final ok = await _apiService.restoreAllFromTrash();
          if (ok) {
            ToastUtil.show('operation_success'.tr);
            fetchTrashPhotos();
          } else {
            ToastUtil.show('operation_failed'.tr);
          }
        } catch (e) {
          ToastUtil.show('operation_failed'.tr);
        }
      },
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
  }
}
