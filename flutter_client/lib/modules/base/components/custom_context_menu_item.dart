import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

class CustomContextMenuItem {
  static MenuItem create({
    required Widget label,
    Widget? icon,
    Color? color,
    required String value,
    required void Function(dynamic)? onSelected,
  }) {
    // 包装文字，确保垂直居中
    final wrappedLabel = Padding(
      padding: EdgeInsets.fromLTRB(0, 3, 0, 0),
      child: label,
    );

    return MenuItem(
      label: wrappedLabel,
      icon: icon,
      textColor: color,
      value: value,
      onSelected: onSelected,
    );
  }
}
