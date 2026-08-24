part of '../photo_trash_controller.dart';

// 删除操作管理
extension PhotoTrashDelete on PhotoTrashController {
  /// 删除选中的照片（物理删除）
  Future<void> deleteSelected() async {
    if (selectedItems.isEmpty) return;

    final isShellSupported = ApiController.instance.state.shellSupported;

    // 检测要删除的照片中是否有live_filename或raw_filename非空的
    final selectedPhotos = photoItems
        .where((item) => selectedItems.contains(item.id))
        .toList();
    final hasLivePhoto = selectedPhotos.any(
      (item) => item.liveFilename.isNotEmpty,
    );
    final hasRawFile = selectedPhotos.any(
      (item) => item.rawFilename.isNotEmpty,
    );

    // 创建带有删除方式选择和关联文件选择的自定义对话框
    showDialog(
      context: Get.overlayContext!,
      builder: (BuildContext context) {
        bool recycle = isShellSupported;
        bool deleteLivePhotoFile = true;
        bool deleteRawFile = true;

        return StatefulBuilder(
          builder: (context, setState) {
            return DialogUtil.createAlertDialog(
              title: Text('need_confirm'.tr),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'folder_delete_confirm'.trParams({
                      'fileCount': selectedItems.length.toString(),
                    }),
                  ),
                  const SizedBox(height: 16),

                  // 删除方式选择（仅在支持系统回收站时显示）
                  if (isShellSupported)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Radio<bool>(
                              value: false,
                              groupValue: recycle,
                              onChanged: (value) {
                                setState(() {
                                  recycle = value ?? false;
                                });
                              },
                            ),
                            Text('delete_direct'.tr),
                            const SizedBox(width: 24),
                            Radio<bool>(
                              value: true,
                              groupValue: recycle,
                              onChanged: (value) {
                                setState(() {
                                  recycle = value ?? true;
                                });
                              },
                            ),
                            Text('put_in_recycle_bin'.tr),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // 关联文件删除选择
                  if (hasLivePhoto)
                    CheckboxListTile(
                      title: Text('delete_related_livephoto'.tr),
                      value: deleteLivePhotoFile,
                      onChanged: (value) {
                        setState(() {
                          deleteLivePhotoFile = value ?? true;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),

                  if (hasRawFile)
                    CheckboxListTile(
                      title: Text('delete_related_raw'.tr),
                      value: deleteRawFile,
                      onChanged: (value) {
                        setState(() {
                          deleteRawFile = value ?? true;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: () {
                    Get.back();
                    _deleteSelectedPhotos(
                      recycle,
                      deleteLivePhotoFile: deleteLivePhotoFile,
                      deleteRawFile: deleteRawFile,
                    );
                  },
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 实际执行删除选中的照片
  Future<void> _deleteSelectedPhotos(
    bool recycle, {
    required bool deleteLivePhotoFile,
    required bool deleteRawFile,
  }) async {
    try {
      final ids = selectedItems.toList();

      final res = await _apiService.deleteFromTrash(
        ids,
        recycle: recycle,
        deleteLivePhotoFile: deleteLivePhotoFile,
        deleteRawFile: deleteRawFile,
      );
      if (res.success) {
        ToastUtil.show('delete_success'.tr);
        fetchTrashPhotos();
        selectedItems.clear();
        isMultiSelectMode.value = false;
      } else {
        ToastUtil.show((res.code == 403 ? 'permission_denied' : 'delete_failed').tr);
      }
    } catch (e) {
      ToastUtil.show('delete_failed'.tr);
    }
  }

  /// 清空回收站
  Future<void> emptyTrash() async {
    final isShellSupported = ApiController.instance.state.shellSupported;

    // 创建带有checkbox的自定义对话框
    showDialog(
      context: Get.overlayContext!,
      builder: (BuildContext context) {
        bool recycle = isShellSupported;
        bool deleteLivePhotoFile = true;
        bool deleteRawFile = true;

        return StatefulBuilder(
          builder: (context, setState) {
            return DialogUtil.createAlertDialog(
              title: Text('need_confirm'.tr),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('delete_all_files'.tr),
                  const SizedBox(height: 16),
                  if (isShellSupported)
                    Row(
                      children: [
                        Radio<bool>(
                          value: false,
                          groupValue: recycle,
                          onChanged: (value) {
                            setState(() {
                              recycle = value ?? false;
                            });
                          },
                        ),
                        Text('delete_direct'.tr),
                        const SizedBox(width: 24),
                        Radio<bool>(
                          value: true,
                          groupValue: recycle,
                          onChanged: (value) {
                            setState(() {
                              recycle = value ?? true;
                            });
                          },
                        ),
                        Text('put_in_recycle_bin'.tr),
                      ],
                    ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: Text('delete_related_livephoto'.tr),
                    value: deleteLivePhotoFile,
                    onChanged: (value) {
                      setState(() {
                        deleteLivePhotoFile = value ?? true;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    title: Text('delete_related_raw_file'.tr),
                    value: deleteRawFile,
                    onChanged: (value) {
                      setState(() {
                        deleteRawFile = value ?? true;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: () {
                    Get.back();
                    _performEmptyTrash(
                      recycle,
                      deleteLivePhotoFile: deleteLivePhotoFile,
                      deleteRawFile: deleteRawFile,
                    );
                  },
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 执行清空回收站
  Future<void> _performEmptyTrash(
    bool recycle, {
    required bool deleteLivePhotoFile,
    required bool deleteRawFile,
  }) async {
    try {
      final res = await _apiService.emptyTrash(
        recycle: recycle,
        deleteLivePhotoFile: deleteLivePhotoFile,
        deleteRawFile: deleteRawFile,
      );
      if (res.success) {
        ToastUtil.show('delete_success'.tr);
        fetchTrashPhotos();
      } else {
        ToastUtil.show((res.code == 403 ? 'permission_denied' : 'delete_failed').tr);
      }
    } catch (e) {
      ToastUtil.show('delete_failed'.tr);
    }
  }
}
