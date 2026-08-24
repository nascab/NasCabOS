import 'package:flutter/material.dart';

/// 自定义标签组件
/// 提供统一的标签样式，支持自定义背景色、文字样式和边框
class CustomTag extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Border? border;
  final double? width;
  final double? height;
  final double? fontSize;

  const CustomTag({
    super.key,
    required this.text,
    required this.backgroundColor,
    this.textColor = Colors.white,
    this.textStyle,
    this.padding,
    this.margin,
    this.borderRadius = 4,
    this.border,
    this.width,
    this.height,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: margin ?? const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style:
            textStyle ?? TextStyle(fontSize: fontSize ?? 12, color: textColor),
      ),
    );
  }
}
