import 'package:flutter/material.dart';

class CustomInsetBorderShell extends StatelessWidget {
  final Widget child;
  final double radius;
  final double borderWidth;
  final Color borderColor;
  final Color backgroundColor;
  final Clip clipBehavior;
  final bool clipChild;

  const CustomInsetBorderShell({
    super.key,
    required this.child,
    required this.radius,
    required this.borderColor,
    required this.backgroundColor,
    this.borderWidth = 1,
    this.clipBehavior = Clip.antiAlias,
    this.clipChild = true,
  });

  @override
  Widget build(BuildContext context) {
    final innerRadius = radius > borderWidth ? radius - borderWidth : 0.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: borderColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(
        padding: EdgeInsets.all(borderWidth),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(innerRadius),
                clipBehavior: clipBehavior,
                child: ColoredBox(color: backgroundColor),
              ),
            ),
            if (clipChild)
              ClipRRect(
                borderRadius: BorderRadius.circular(innerRadius),
                clipBehavior: clipBehavior,
                child: child,
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}
