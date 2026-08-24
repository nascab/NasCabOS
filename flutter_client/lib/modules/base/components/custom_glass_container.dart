import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 苹果风格液态玻璃效果容器。
///
/// 使用 [BackdropFilter] 实现背景模糊 + 白色渐变 + 细微白色边框，
/// 适用于需要液态玻璃效果的容器（如 Dock 栏、右键菜单等）。
class CustomGlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final double borderOpacity;
  final double gradientStartOpacity;
  final double gradientEndOpacity;

  const CustomGlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.blur = 20,
    this.borderOpacity = 0.18,
    this.gradientStartOpacity = 0.20,
    this.gradientEndOpacity = 0.06,
  });

  /// 返回液态玻璃风格的 [BoxDecoration]，供 [ContextMenu] 等不支持
  /// [BackdropFilter] 的场景使用（仅渐变 + 边框，无模糊）。
  static BoxDecoration glassBoxDecoration({
    double borderRadius = 12,
    double borderOpacity = 0.18,
    double gradientStartOpacity = 0.22,
    double gradientEndOpacity = 0.08,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: gradientStartOpacity),
          Colors.white.withValues(alpha: gradientEndOpacity),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: borderOpacity),
        width: 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget glass = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: glassBoxDecoration(
            borderRadius: borderRadius,
            borderOpacity: borderOpacity,
            gradientStartOpacity: gradientStartOpacity,
            gradientEndOpacity: gradientEndOpacity,
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      return Padding(padding: margin!, child: glass);
    }
    return glass;
  }
}
