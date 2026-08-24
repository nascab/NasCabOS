part of '../encrypted_space_view.dart';

class AppEncryptedSpaceListTopBar extends StatelessWidget {
  const AppEncryptedSpaceListTopBar({super.key, required this.ctrl});

  final EncryptedSpaceController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'home'.tr,
              onPressed: () => AppRoutes.toHome(),
              icon: Icon(
                Icons.home_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: () => ctrl.importSpaceFlow(context),
              child: Text('import'.tr),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => ctrl.showExportTasksDialog(context),
              child: Text('encrypted_space_export'.tr),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'create'.tr,
              onPressed: () => ctrl.createSpaceFlow(context),
              icon: Icon(Icons.add, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
