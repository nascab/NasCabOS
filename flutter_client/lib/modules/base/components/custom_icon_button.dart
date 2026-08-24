import 'package:flutter/material.dart';

/// 自定义图标按钮组件
/// 基于Flutter内置IconButton实现，提供统一的图标按钮样式
/// 支持自定义图标、颜色、大小、点击事件和悬浮提示
class CustomIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final Color? backgroundColor;
  final double iconSize;
  final double buttonSize;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final String? tooltip;
  final Color? hoverColor;
  final Color? focusColor;
  final Color? highlightColor;
  final Color? splashColor;
  final bool enableFeedback;
  final BorderSide? borderSide;

  const CustomIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconColor,
    this.backgroundColor,
    this.iconSize = 20,
    this.buttonSize = 40,
    this.padding,
    this.margin,
    this.borderRadius = 8,
    this.tooltip,
    this.hoverColor,
    this.focusColor,
    this.highlightColor,
    this.splashColor,
    this.enableFeedback = true,
    this.borderSide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: buttonSize,
      height: buttonSize,
      padding: padding,
      margin: margin,
      child: IconButton(
        icon: Icon(
          icon,
          color: iconColor ?? theme.colorScheme.onSurface,
          size: iconSize,
        ),
        onPressed: onPressed,
        iconSize: iconSize,
        tooltip: tooltip,
        color: iconColor ?? theme.colorScheme.onSurface,
        // 外层 Container 已限定按钮尺寸，这里去掉 IconButton 默认的 8px 内边距，
        // 否则图标会被挤向右下角而无法在按钮（及 hover 背景）中居中
        padding: EdgeInsets.zero,
        hoverColor:
            hoverColor ?? theme.colorScheme.primary.withValues(alpha: 0.1),
        focusColor:
            focusColor ?? theme.colorScheme.primary.withValues(alpha: 0.2),
        highlightColor:
            highlightColor ?? theme.colorScheme.primary.withValues(alpha: 0.3),
        splashColor:
            splashColor ?? theme.colorScheme.primary.withValues(alpha: 0.4),
        enableFeedback: enableFeedback,
        constraints: BoxConstraints(
          minWidth: buttonSize,
          minHeight: buttonSize,
        ),
        style: IconButton.styleFrom(
          side: borderSide,
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}
