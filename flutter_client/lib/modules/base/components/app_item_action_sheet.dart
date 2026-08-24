import 'package:flutter/material.dart';

sealed class AppItemActionSheetEntry {
  const AppItemActionSheetEntry();
}

class AppItemActionSheetDivider extends AppItemActionSheetEntry {
  const AppItemActionSheetDivider();
}

class AppItemActionSheetAction extends AppItemActionSheetEntry {
  final Widget? icon;
  final String title;
  final Color? titleColor;
  final VoidCallback? onTap;

  const AppItemActionSheetAction({
    required this.title,
    this.icon,
    this.titleColor,
    this.onTap,
  });
}

class AppItemActionSheet extends StatelessWidget {
  final Widget headerLeading;
  final String headerTitle;
  final String? headerSubtitle;
  final List<AppItemActionSheetEntry> entries;

  const AppItemActionSheet({
    super.key,
    required this.headerLeading,
    required this.headerTitle,
    required this.entries,
    this.headerSubtitle,
  });

  static Future<void> show(
    BuildContext context, {
    required Widget headerLeading,
    required String headerTitle,
    String? headerSubtitle,
    required List<AppItemActionSheetEntry> entries,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return AppItemActionSheet(
          headerLeading: headerLeading,
          headerTitle: headerTitle,
          headerSubtitle: headerSubtitle,
          entries: entries,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: headerLeading,
            title: Text(headerTitle),
            subtitle: (headerSubtitle == null || headerSubtitle!.trim().isEmpty)
                ? null
                : Text(headerSubtitle!.trim()),
          ),
          SizedBox(height: 15),
          const Divider(height: 1),
          for (final e in entries) ...[
            if (e is AppItemActionSheetDivider) const Divider(height: 1),
            if (e is AppItemActionSheetAction)
              ListTile(
                dense: true,
                leading: e.icon,
                title: Text(
                  e.title,
                  style: e.titleColor == null
                      ? null
                      : TextStyle(color: e.titleColor),
                ),
                onTap: e.onTap == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        e.onTap?.call();
                      },
              ),
          ],
        ],
      ),
    );
  }
}
