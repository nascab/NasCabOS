import 'package:flutter/material.dart';

class CustomSwitch extends StatelessWidget {
  const CustomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.materialTapTargetSize,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Transform.scale(
      scale: 0.9,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: activeColor ?? theme.colorScheme.primary,
        activeTrackColor:
            activeTrackColor ??
            theme.colorScheme.primary.withValues(alpha: 0.35),
        inactiveThumbColor:
            inactiveThumbColor ??
            theme.colorScheme.outline.withValues(alpha: 0.9),
        inactiveTrackColor:
            inactiveTrackColor ??
            theme.colorScheme.outline.withValues(alpha: 0.25),
        materialTapTargetSize:
            materialTapTargetSize ?? MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
