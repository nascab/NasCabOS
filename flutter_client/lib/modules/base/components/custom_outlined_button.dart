import 'package:flutter/material.dart';

class CustomOutlinedButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Color? foregroundColor;
  final Color? borderColor;
  final bool compact;

  const CustomOutlinedButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.foregroundColor,
    this.borderColor,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fc = foregroundColor ?? theme.colorScheme.primary;
    final bc = borderColor ?? theme.colorScheme.primary;
    final style = OutlinedButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      foregroundColor: fc,
      side: BorderSide(color: bc),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
    );
    return icon != null
        ? OutlinedButton.icon(
            icon: icon!,
            label: Text(text),
            onPressed: onPressed,
            style: style,
          )
        : OutlinedButton(onPressed: onPressed, style: style, child: Text(text));
  }
}
