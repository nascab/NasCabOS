part of '../encrypted_space_view.dart';

class _EncryptedSpaceListTopBar extends StatelessWidget {
  final EncryptedSpaceController ctrl;

  const _EncryptedSpaceListTopBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Spacer(),
            CustomBorderedIconButton(
              icon: Icons.refresh,
              tooltip: 'refresh'.tr,
              onTap: () => ctrl.refreshList(showLoading: true),
            ),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: Icons.add,
              tooltip: 'create'.tr,
              onTap: () => ctrl.createSpaceFlow(context),
            ),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: Icons.drive_folder_upload_outlined,
              tooltip: 'import'.tr,
              onTap: () => ctrl.importSpaceFlow(context),
            ),
            const SizedBox(width: 8),
            CustomBorderedIconButton(
              icon: Icons.list_alt_outlined,
              tooltip: 'encrypted_space_export_tasks'.tr,
              onTap: () => ctrl.showExportTasksDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}
