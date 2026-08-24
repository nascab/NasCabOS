import 'package:flutter/material.dart';

class CustomCheckbox extends StatelessWidget {
  const CustomCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.checkColor,
    this.activeColor,
    this.fillColor,
    this.side,
    this.shape,
    this.visualDensity,
    this.materialTapTargetSize,
    this.splashRadius,
    this.focusNode,
    this.autofocus = false,
    this.mouseCursor,
    this.isCircle = true,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  final Color? checkColor;
  final Color? activeColor;
  final MaterialStateProperty<Color?>? fillColor;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final VisualDensity? visualDensity;
  final MaterialTapTargetSize? materialTapTargetSize;
  final double? splashRadius;
  final FocusNode? focusNode;
  final bool autofocus;
  final MouseCursor? mouseCursor;
  final bool isCircle;

  @override
  Widget build(BuildContext context) {
    final effectiveSide =
        side ?? BorderSide(color: Colors.grey.shade500, width: 2);
    final effectiveShape =
        shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
    final effectiveCheckColor = checkColor ?? Colors.white;
    return Checkbox(
      shape: isCircle ? const CircleBorder() : effectiveShape,
      value: value,
      onChanged: onChanged,
      tristate: tristate,
      checkColor: effectiveCheckColor,
      activeColor: activeColor,
      fillColor: fillColor,
      side: effectiveSide,
      visualDensity: visualDensity,
      materialTapTargetSize: materialTapTargetSize,
      splashRadius: splashRadius,
      focusNode: focusNode,
      autofocus: autofocus,
      mouseCursor: mouseCursor,
    );
  }
}
