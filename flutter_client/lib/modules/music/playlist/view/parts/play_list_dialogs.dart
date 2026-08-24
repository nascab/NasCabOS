import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/toast_util.dart';
import '../../controller/play_list_controller.dart';
import '../../service/play_list_api_service.dart';

class PlayListDialogs {
  static Future<void> showCreateDialog(
    BuildContext context, {
    required PlayListController controller,
  }) async {
    var name = '';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return DialogUtil.createAlertDialog(
          title: Text('create'.tr),
          content: SizedBox(
            width: 420,
            child: TextFormField(
              autofocus: true,
              decoration: InputDecoration(hintText: 'name'.tr),
              initialValue: '',
              onChanged: (v) => name = v,
              onFieldSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final created = await controller.createList(name);
    if (!created) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  /// 选择模式下空列表：输入名称创建歌单并返回新建项。
  static Future<PlayListItem?> showCreateForSelection(
    BuildContext context, {
    required PlayListController controller,
  }) async {
    var name = '';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return DialogUtil.createAlertDialog(
          title: Text('create'.tr),
          content: SizedBox(
            width: 420,
            child: TextFormField(
              autofocus: true,
              decoration: InputDecoration(hintText: 'name'.tr),
              initialValue: '',
              onChanged: (v) => name = v,
              onFieldSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
    if (ok != true) return null;
    final createdItem = await controller.createListReturnItem(name);
    if (createdItem == null) {
      ToastUtil.show('operation_failed'.tr);
    }
    return createdItem;
  }

  static Future<void> showRenameDialog(
    BuildContext context, {
    required PlayListController controller,
    required PlayListItem item,
  }) async {
    var name = item.name;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return DialogUtil.createAlertDialog(
          title: Text('rename'.tr),
          content: SizedBox(
            width: 420,
            child: TextFormField(
              initialValue: name,
              autofocus: true,
              decoration: InputDecoration(hintText: 'name'.tr),
              onChanged: (v) => name = v,
              onFieldSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final renamed = await controller.updateList(id: item.id, name: name);
    if (!renamed) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  static Future<void> confirmDelete(
    BuildContext context, {
    required PlayListController controller,
    required PlayListItem item,
  }) async {
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: '${'delete'.tr} "${item.name}" ?',
    );
    if (ok != true) return;
    final deleted = await controller.deleteList(item.id);
    if (!deleted) {
      ToastUtil.show('delete_failed'.tr);
    } else {
      ToastUtil.show('delete_success'.tr);
    }
  }
}
