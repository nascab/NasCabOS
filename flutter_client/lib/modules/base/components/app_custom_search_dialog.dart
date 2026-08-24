import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app_custom_search.dart';

class AppCustomSearchDialog {
  /// 显示搜索对话框
  /// [context] BuildContext
  /// [hintText] 搜索提示文本
  /// [controller] 搜索输入控制器
  /// [onChanged] 文本变化回调
  /// [onClear] 清空时回调
  static Future<void> show({
    required BuildContext context,
    required String hintText,
    required TextEditingController controller,
    ValueChanged<String>? onChanged,
    VoidCallback? onClear,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('search'.tr),
          content: AppCustomSearch(
            hintText: hintText,
            controller: controller,
            onChanged: onChanged,
            onClear: onClear,
            showBorder: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                onClear?.call();
              },
              child: Text('clear'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('confirm'.tr),
            ),
          ],
        );
      },
    );
  }
}
