part of '../user_management_view.dart';

class _UserManagementScaffold extends StatelessWidget {
  final UserManagementController ctrl;
  const _UserManagementScaffold({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isMobileApp =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobileApp) {
      return _AppUserManagementScaffold(ctrl: ctrl);
    }
    return _UserManagementDesktopScaffold(ctrl: ctrl);
  }
}

class _UserManagementDesktopScaffold extends StatelessWidget {
  final UserManagementController ctrl;
  const _UserManagementDesktopScaffold({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = 980.0;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: _UserManagementSidebar(ctrl: ctrl),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _UserManagementDetailPanel(ctrl: ctrl)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: null,
    );
  }
}
