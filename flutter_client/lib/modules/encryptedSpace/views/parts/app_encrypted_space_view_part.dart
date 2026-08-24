part of '../encrypted_space_view.dart';

class AppEncryptedSpaceView extends StatelessWidget {
  const AppEncryptedSpaceView({
    super.key,
    required this.ctrl,
    required this.onOpen,
  });

  final EncryptedSpaceController ctrl;
  final void Function(Map<String, dynamic> space) onOpen;

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('app_encrypted'.tr),
        actions: [
          IconButton(
            tooltip: 'refresh'.tr,
            onPressed: () => ctrl.refreshList(showLoading: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'create'.tr,
            onPressed: () => ctrl.createSpaceFlow(context),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'import'.tr,
            onPressed: () => ctrl.importSpaceFlow(context),
            icon: const Icon(Icons.drive_folder_upload_outlined),
          ),
          IconButton(
            tooltip: 'encrypted_space_export_tasks'.tr,
            onPressed: () => ctrl.showExportTasksDialog(context),
            icon: const Icon(Icons.list_alt_outlined),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(color: customColors?.mainContentBgColor),
        child: SafeArea(
          top: false,
          child: AppEncryptedSpaceSpaceGrid(ctrl: ctrl, onOpen: onOpen),
        ),
      ),
    );
  }
}
