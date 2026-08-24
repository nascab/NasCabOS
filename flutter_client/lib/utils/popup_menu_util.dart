import 'package:flutter/material.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';

/// 在指定按钮下方弹出 PopupMenu 的工具类
class PopupMenuUtil {
  /// 在 [buttonKey] 对应按钮的正下方弹出菜单
  /// 返回用户选中的值，若未选择则返回 null
  static Future<T?> showBelowButton<T>({
    required BuildContext context,
    required GlobalKey buttonKey,
    required List<PopupMenuEntry<T>> items,
    double borderRadius = 10.0,
  }) {
    final renderBox =
        buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return Future.value(null);
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final customColors = Theme.of(context).extension<CustomColors>();

    return showBelowContent<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        offset.dy + size.height + 4,
      ),
      items: items,
      borderRadius: borderRadius,
    );
  }

  /// 弹出内容面板，统一样式（背景色、边框、圆角）
  /// 调用方自行计算 [position]
  static Future<T?> showBelowContent<T>({
    required BuildContext context,
    required RelativeRect position,
    required List<PopupMenuEntry<T>> items,
    double borderRadius = 10.0,
  }) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return showMenu<T>(
      context: context,
      position: position,
      color: customColors?.oprationBarBgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
      ),
      items: items,
    );
  }
}
