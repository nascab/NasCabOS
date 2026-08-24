import 'package:flutter/material.dart';
import 'dart:async';

/// 自定义输入框组件
/// 提供统一的输入框样式，支持PC和App的通用性
class CustomTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final bool obscureText;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final GestureTapCallback? onTap;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? prefixText;
  final String? suffixText;
  final int? maxLines;
  final int? maxLength;
  final bool expands;
  final TextAlign textAlign;
  final EdgeInsetsGeometry? contentPadding;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final InputBorder? disabledBorder;
  final Color? fillColor;
  final bool filled;
  final TextStyle? hintStyle;
  final bool autoSearchOnChange;
  final Duration? debounceDuration;
  final ValueChanged<String>? onDebouncedChanged;
  final Iterable<String>? autofillHints;

  const CustomTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onTap,
    this.validator,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.suffixText,
    this.maxLines = 1,
    this.maxLength,
    this.expands = false,
    this.textAlign = TextAlign.start,
    this.contentPadding,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.disabledBorder,
    this.fillColor,
    this.filled = false,
    this.hintStyle,
    this.autoSearchOnChange = false,
    this.debounceDuration,
    this.onDebouncedChanged,
    this.autofillHints,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    if (!widget.autoSearchOnChange) return;
    _debounceTimer?.cancel();
    final dur = widget.debounceDuration ?? const Duration(milliseconds: 400);
    _debounceTimer = Timer(dur, () {
      final v = widget.controller?.text ?? value;
      widget.onDebouncedChanged?.call(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    InputBorder defaultBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: theme.dividerColor, width: 1),
    );

    InputBorder defaultFocusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: theme.dividerColor, width: 2),
    );

    InputBorder defaultErrorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
    );

    return Material(
      type: MaterialType.transparency,
      child: TextFormField(
        controller: widget.controller,
        obscureText: widget.obscureText,
        readOnly: widget.readOnly,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onChanged: _handleChanged,
        onTap: widget.onTap,
        validator: widget.validator,
        enabled: widget.enabled,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        expands: widget.expands,
        textAlign: widget.textAlign,
        autofillHints: widget.autofillHints,
        decoration: InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
          hintStyle:
              widget.hintStyle ??
              TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
          errorText: widget.errorText,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          prefixText: widget.prefixText,
          suffixText: widget.suffixText,
          contentPadding: widget.contentPadding ?? const EdgeInsets.all(16),
          border: widget.border ?? defaultBorder,
          enabledBorder: widget.enabledBorder ?? defaultBorder,
          focusedBorder: widget.focusedBorder ?? defaultFocusedBorder,
          errorBorder: widget.errorBorder ?? defaultErrorBorder,
          disabledBorder: widget.disabledBorder ?? defaultBorder,
          fillColor:
              widget.fillColor ?? (widget.filled ? theme.cardColor : null),
          filled: widget.filled,
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}
