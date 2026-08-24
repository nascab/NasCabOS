import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 自定义标题栏组件
/// 提供统一的标题栏样式，支持PC和App的通用性
class CustomTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final Color? backgroundColor;
  final double elevation;
  final TextStyle? titleStyle;
  final double toolbarHeight;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

  const CustomTitleBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.backgroundColor,
    this.elevation = 0,
    this.titleStyle,
    this.toolbarHeight = kToolbarHeight,
    this.showBackButton = false,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 处理后退按钮
    Widget? effectiveLeading = leading;
    if (showBackButton && effectiveLeading == null) {
      effectiveLeading = IconButton(
        icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
        onPressed: onBackPressed ?? () => Get.back(),
      );
    }

    return AppBar(
      title: Text(
        title,
        style:
            titleStyle ??
            TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
      ),
      leading: effectiveLeading,
      actions: actions,
      centerTitle: centerTitle,
      backgroundColor: backgroundColor ?? theme.scaffoldBackgroundColor,
      elevation: elevation,
      toolbarHeight: toolbarHeight,
      automaticallyImplyLeading: effectiveLeading != null,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);
}
