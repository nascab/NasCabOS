import 'package:flutter/material.dart';
import '../../../../utils/dimens_util.dart';

/// 自定义容器组件
/// 提供统一的容器样式，支持PC和App的通用性
class CustomContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double? width;
  final double? height;
  final BoxDecoration? decoration;
  final BorderRadius? borderRadius;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;
  final Clip clipBehavior;

  const CustomContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.width,
    this.height,
    this.decoration,
    this.borderRadius,
    this.constraints,
    this.alignment,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    BoxDecoration defaultDecoration = BoxDecoration(
      color: backgroundColor ?? theme.cardColor,
      borderRadius:
          borderRadius ?? BorderRadius.circular(DimensUtil.containerCardRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16),
      margin: margin,
      decoration: decoration ?? defaultDecoration,
      constraints: constraints,
      alignment: alignment,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}
