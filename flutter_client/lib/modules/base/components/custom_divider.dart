import 'package:flutter/material.dart';

/// 自定义分割线组件
/// 提供统一的分割线样式，支持PC和App的通用性
class CustomDivider extends StatelessWidget {
  final double? height;
  final Color? color;
  final double? thickness;
  final double? indent;
  final double? endIndent;

  const CustomDivider({
    super.key,
    this.height = 1,
    this.color,
    this.thickness,
    this.indent,
    this.endIndent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color dividerColor = color ?? theme.dividerColor;

    return Divider(
      height: height,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      color: dividerColor,
    );
  }
}
