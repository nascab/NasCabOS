import 'package:flutter/material.dart';

/// 自定义下拉选择器组件
/// 提供统一的下拉选择器样式，支持PC和App的通用性
class CustomDropdownField<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final FormFieldValidator<T>? validator;
  final bool enabled;
  final Widget? icon;
  final Color? dropdownColor;
  final EdgeInsetsGeometry? contentPadding;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final Color? fillColor;
  final bool filled;

  const CustomDropdownField({
    super.key,
    this.value,
    this.items,
    this.onChanged,
    this.labelText,
    this.hintText,
    this.errorText,
    this.validator,
    this.enabled = true,
    this.icon,
    this.dropdownColor,
    this.contentPadding,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.fillColor,
    this.filled = false,
  });

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

    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: enabled ? onChanged : null,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        contentPadding: contentPadding ?? const EdgeInsets.all(16),
        border: border ?? defaultBorder,
        enabledBorder: enabledBorder ?? defaultBorder,
        focusedBorder: focusedBorder ?? defaultFocusedBorder,
        errorBorder: errorBorder ?? defaultErrorBorder,
        fillColor: fillColor ?? Colors.transparent,
        filled: filled,
      ),
      dropdownColor: dropdownColor ?? theme.cardColor,
      style: TextStyle(color: theme.colorScheme.onSurface),
      icon:
          icon ??
          Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
      validator: validator,
    );
  }
}
