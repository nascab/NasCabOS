import 'package:flutter/material.dart';

/// 自定义按钮组件
/// 提供统一的按钮样式，支持PC和App的通用性
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final bool isPrimary;
  final bool isDisabled;
  final double? width;
  final double? height;
  final Widget? icon;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style,
    this.isPrimary = true,
    this.isDisabled = false,
    this.width,
    this.height,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    ButtonStyle defaultStyle = ElevatedButton.styleFrom(
      disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
      disabledBackgroundColor: Colors.grey.withValues(alpha: 0.12),
      // padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: Size(width ?? 80, height ?? 40),
    );

    return SizedBox(
      width: width,
      height: height,
      child: icon != null
          ? ElevatedButton.icon(
              onPressed: isDisabled ? null : onPressed,
              icon: icon!,
              label: Text(text),
              style: style ?? defaultStyle,
            )
          : ElevatedButton(
              onPressed: isDisabled ? null : onPressed,
              style: style ?? defaultStyle,
              child: Text(text),
            ),
    );
  }
}
