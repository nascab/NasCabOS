import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../controllers/app_file_controller.dart';
import '../../../transfer/controllers/download_controller.dart';

class AppFileMultiSelectBar extends StatelessWidget {
  const AppFileMultiSelectBar({super.key, required this.ctrl});

  final AppFileController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final hasSelection = ctrl.selected.isNotEmpty;
      final inFavoritesModule = ctrl.currentModule.value == 'favorites';
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Material(
            elevation: 8,
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _actionItem(
                      context,
                      icon: inFavoritesModule ? Icons.star_outline : Icons.star,
                      label: inFavoritesModule
                          ? 'unfavorite'.tr
                          : 'folder_add_favorite'.tr,
                      enabled: hasSelection,
                      onTap: () => _toggleFavoritesSelected(inFavoritesModule),
                    ),
                  ),
                  Expanded(
                    child: _actionItem(
                      context,
                      icon: Icons.download_outlined,
                      label: 'download'.tr,
                      enabled: hasSelection,
                      onTap: () => _downloadSelected(),
                    ),
                  ),
                  Expanded(
                    child: _actionItem(
                      context,
                      icon: Icons.delete_outline_outlined,
                      label: 'delete'.tr,
                      enabled: hasSelection,
                      danger: true,
                      onTap: () async => _confirmAndDeleteSelected(),
                    ),
                  ),
                  Expanded(
                    child: _actionItem(
                      context,
                      icon: Icons.more_horiz_outlined,
                      label: 'more'.tr,
                      enabled: hasSelection,
                      onTap: () => _showMoreSheet(context),
                    ),
                  ),
                  Container(width: 1, height: 36, color: theme.dividerColor),
                  SizedBox(
                    width: 64,
                    child: _actionItem(
                      context,
                      icon: Icons.close_outlined,
                      label: 'cancel'.tr,
                      enabled: true,
                      onTap: ctrl.exitMultiSelectMode,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _actionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = enabled
        ? (danger ? Colors.red : theme.colorScheme.onSurface)
        : theme.disabledColor;
    final textStyle = theme.textTheme.labelSmall?.copyWith(color: color);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteSelected() async {
    final isShellSupported = ApiController.instance.state.shellSupported;
    if (isShellSupported) {
      await DialogUtil.showConfirmThreeButtonsDialog(
        title: 'need_confirm'.tr,
        content: 'folder_delete_confirm'.trParams({
          'fileCount': ctrl.selected.length.toString(),
        }),
        cancelText: 'cancel'.tr,
        option1Text: 'delete'.tr,
        option2Text: 'put_in_recycle_bin'.tr,
        option2IsPrimary: true,
        onOption1: () => ctrl.deleteSelectedEntries(recycle: false),
        onOption2: () => ctrl.deleteSelectedEntries(recycle: true),
      );
    } else {
      final confirmed = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'folder_delete_confirm'.trParams({
          'fileCount': ctrl.selected.length.toString(),
        }),
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (confirmed == true) {
        await ctrl.deleteSelectedEntries();
      }
    }
  }

  void _toggleFavoritesSelected(bool inFavoritesModule) {
    if (ctrl.selected.isEmpty) return;
    final paths = ctrl.selected.toList(growable: false);
    final fut = inFavoritesModule
        ? ctrl.removeFavorites(paths)
        : ctrl.addFavorites(paths);
    fut.then((ok) {
      ToastUtil.show(ok ? 'operation_success'.tr : 'operation_failed'.tr);
      ctrl.clearSelect();
    });
  }

  Future<void> _downloadSelected() async {
    final paths = ctrl.selected.toList();
    if (paths.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    final hints = ctrl.remoteIsDirectoryHintsForPaths(paths);
    final hasAnyHint = hints.any((e) => e != null);
    await Get.find<DownloadController>().handleDownload(
      paths,
      remoteIsDirectoryHint: hasAnyHint ? hints : null,
    );
  }

  void _showMoreSheet(BuildContext context) {
    final theme = Theme.of(context);
    Get.bottomSheet(
      Container(
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text('folder_action_move_to'.tr),
                onTap: () {
                  Get.back();
                  ctrl.handleCopyOrMove(isCopy: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text('folder_action_copy_to'.tr),
                onTap: () {
                  Get.back();
                  ctrl.handleCopyOrMove(isCopy: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
