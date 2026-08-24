import 'package:flutter/material.dart';

/// App端通用页面基类
/// App Base Page for Mobile
class AppBasePage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool showBackButton;

  const AppBasePage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTitle = title.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: backgroundColor ?? theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: showBackButton ? const BackButton() : null,
        automaticallyImplyLeading: showBackButton,
        title: hasTitle
            ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        actions: actions ?? [],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
