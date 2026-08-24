import 'package:flutter/material.dart';

/// 自定义加载指示器组件
/// 提供统一的加载指示器样式，支持PC和App的通用性
class CustomLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  final String? message;
  final bool isCircular;
  final EdgeInsetsGeometry? padding;

  const CustomLoadingIndicator({
    super.key,
    this.size = 32,
    this.color,
    this.message,
    this.isCircular = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget indicator = isCircular
        ? SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? theme.primaryColor,
              ),
            ),
          )
        : SizedBox(
            width: size,
            height: size,
            child: LinearProgressIndicator(
              backgroundColor: theme.dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? theme.primaryColor,
              ),
            ),
          );

    if (message != null) {
      return Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator,
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: indicator,
    );
  }
}
