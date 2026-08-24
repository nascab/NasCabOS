import 'package:flutter/material.dart';
import '../../../core/languages/language_service.dart';

/// 自定义语言选择器组件
/// 提供统一的语言选择器样式，支持自定义图标、颜色和语言选项
class CustomLanguageSelector extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final double iconSize;
  final String tooltip;
  final List<LanguageOption> languageOptions;
  final double buttonSize;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final BoxBorder? border;

  const CustomLanguageSelector({
    super.key,
    this.icon = Icons.language,
    this.iconColor,
    this.iconSize = 20,
    this.tooltip = '切换语言',
    this.languageOptions = const [],
    this.buttonSize = 30,
    this.padding,
    this.margin,
    this.borderRadius = 8,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double paddingAuto = (buttonSize - iconSize) / 2;
    return PopupMenuButton<String>(
      icon: Container(
        width: buttonSize,
        height: buttonSize,
        padding: padding ?? EdgeInsets.all(paddingAuto),
        margin: margin,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.transparent,
          border: border,
        ),
        child: Icon(
          icon,
          color: iconColor ?? theme.iconTheme.color,
          size: iconSize,
        ),
      ),
      tooltip: tooltip,
      onSelected: (String value) {
        _handleLanguageSelection(context, value);
      },
      itemBuilder: (BuildContext context) => _buildLanguageMenuItems(),
    );
  }

  List<PopupMenuEntry<String>> _buildLanguageMenuItems() {
    final options = languageOptions.isEmpty
        ? LanguageService.getFullLanguageOptions()
        : languageOptions;

    return options
        .map(
          (option) => PopupMenuItem<String>(
            value: option.value,
            child: Text(option.label),
          ),
        )
        .toList();
  }

  void _handleLanguageSelection(BuildContext context, String value) {
    final languageService = LanguageService.to;
    languageService.changeLanguage(value);
  }
}
