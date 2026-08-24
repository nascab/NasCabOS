import 'dart:ui';
import 'package:flutter/material.dart';

/// macOS 风格阴影：浅色模式极轻柔和，深色模式适度。
List<BoxShadow> _glassCardShadows(ThemeData theme) {
  final shadow = theme.colorScheme.shadow;
  if (theme.brightness == Brightness.light) {
    return [
      BoxShadow(
        color: shadow.withValues(alpha: 0.06),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 0.5),
      ),
    ];
  }
  return [
    BoxShadow(
      color: shadow.withValues(alpha: 0.18),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];
}

/// 根据主题亮度返回合适的默认边框：浅色用 outlineVariant，深色用半透白。
Border _defaultBorder(ThemeData theme) {
  final isLight = theme.brightness == Brightness.light;
  return Border.all(
    color: isLight
        ? theme.colorScheme.outlineVariant.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.12),
    width: isLight ? 0.5 : 0.5,
  );
}

class CustomGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final double borderRadius;
  final double blur;
  final double opacity;
  final VoidCallback? onTap;

  const CustomGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.border,
    this.borderRadius = 16.0,
    this.blur = 10.0,
    this.opacity = 0.55,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(borderRadius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: opacity),
        borderRadius: radius,
        border: border ?? _defaultBorder(theme),
      ),
      child: child,
    );

    Widget glass = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _glassCardShadows(theme),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        ),
      ),
    );

    if (onTap != null) {
      return Padding(
        padding: margin ?? EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: glass,
          ),
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: glass);
    }

    return glass;
  }
}
