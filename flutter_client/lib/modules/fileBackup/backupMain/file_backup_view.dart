import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:NasCabOS/modules/base/components/custom_glass_card.dart';
import 'package:NasCabOS/modules/base/components/custom_no_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import '../../base/components.dart';
import '../../files/views/folder_picker_dialog.dart';
import '../../../core/routes/app_routes.dart';
import '../../home/views/pc_home_controller.dart';
import '../serverBackup/file_backup_controller.dart';
import '../localBackup/local_backup_controller.dart';
import '../localBackup/local_backup_storage.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';
import '../../transfer/controllers/upload_parts/upload_transfer_helper.dart';
import '../../../core/api/api_controller.dart';

part 'left_menu.dart';
part 'backup_common_widgets.dart';
part '../serverBackup/server_backup_list_panel.dart';
part '../localBackup/local_backup_list_panel.dart';
part '../serverBackup/server_backup_dialog.dart';
part '../localBackup/local_backup_dialog.dart';

class FileBackupView extends GetView<FileBackupController> {
  const FileBackupView({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<FileBackupController>(
      init: FileBackupController(),
      builder: (ctrl) {
        if (DeviceUtils.isMobile) {
          return Scaffold(
            appBar: AppBar(
              leading: const BackButton(),
              title: Text('file_backup_menu_disk'.tr),
              actions: [
                IconButton(
                  onPressed: () {
                    DialogUtil.showInfoDialog(
                      title: 'file_backup_menu_disk'.tr,
                      content: 'file_backup_help_tooltip'.tr,
                    );
                  },
                  icon: const Icon(Icons.help_outline),
                  tooltip: 'file_backup_help_tooltip'.tr,
                ),
                IconButton(
                  onPressed: () => ctrl.refreshList(showLoading: true),
                  icon: const Icon(Icons.refresh_outlined),
                ),
                IconButton(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (_) => _ServerBackupDialog(ctrl: ctrl),
                    );
                  },
                  icon: const Icon(Icons.add_outlined),
                ),
              ],
            ),
            body: _ServerBackupListPanel(ctrl: ctrl, showHeader: false),
          );
        }
        return Obx(() {
          final collapsed = ctrl.sidebarCollapsed.value;
          final leftWidth = collapsed ? 64.0 : ctrl.leftWidth.value;
          return Scaffold(
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: leftWidth,
                  child: _LeftMenu(
                    controller: ctrl,
                    collapsed: collapsed,
                    onToggleCollapse: () =>
                        ctrl.sidebarCollapsed.value = !collapsed,
                  ),
                ),
                Expanded(child: _buildRight(context, ctrl)),
              ],
            ),
          );
        });
      },
    );
  }
}

Widget _buildRight(BuildContext context, FileBackupController ctrl) {
  return Obx(() {
    final key = ctrl.currentPageKey.value;
    if (key == 'backup.disk') {
      return _ServerBackupListPanel(ctrl: ctrl);
    }
    if (key == 'backup.local') {
      return const _LocalBackupPanel();
    }
    return Center(child: Text('not_implemented_yet'.tr));
  });
}
