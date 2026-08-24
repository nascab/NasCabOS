import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/user/current_user_controller.dart';
import '../../base/components.dart';
import '../controllers/task_center_controller.dart';
import '../controllers/upload_controller.dart';
import '../controllers/download_controller.dart';
import 'upload/task_upload_page.dart';
import 'download/task_download_page.dart';
import 'file_log/file_log_page.dart';

class TaskCenterView extends StatelessWidget {
  const TaskCenterView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(TaskCenterController());
    Get.put(UploadController(), permanent: true);
    Get.put(DownloadController(), permanent: true);
    final showFileLog = CurrentUserController.instance.isAdmin;
    if (!showFileLog && controller.currentKey.value == 'task.file_log') {
      controller.currentKey.value = 'task.upload';
    }
    final customColors = Theme.of(context).extension<CustomColors>();

    return Scaffold(
      backgroundColor: customColors?.mainContentBgColor,
      body: Row(
        children: [
          // 左边栏
          SizedBox(
            width: 150,
            child: OneLevelSideMenu(
              currentKey: controller.currentKey,
              onSelect: controller.selectKey,
              items: [
                OneLevelSideMenuItem(
                  title: 'task_upload'.tr,
                  key: 'task.upload',
                  icon: Icons.file_upload_outlined,
                ),
                OneLevelSideMenuItem(
                  title: 'task_download'.tr,
                  key: 'task.download',
                  icon: Icons.file_download_outlined,
                ),
                if (showFileLog)
                  OneLevelSideMenuItem(
                    title: 'file_operation'.tr,
                    key: 'task.file_log',
                    icon: Icons.file_present,
                  ),
              ],
              showCollapseToggle: false,
              topPlaceholderHeight: 40,
            ),
          ),
          // 任务中心
          Expanded(
            child: Obx(() {
              if (!showFileLog &&
                  controller.currentKey.value == 'task.file_log') {
                controller.currentKey.value = 'task.upload';
              }
              if (controller.currentKey.value == 'task.upload') {
                return const TaskUploadPage();
              } else if (controller.currentKey.value == 'task.download') {
                return const TaskDownloadPage();
              } else if (controller.currentKey.value == 'task.file_log') {
                return const FileLogPage();
              }
              return const SizedBox();
            }),
          ),
        ],
      ),
    );
  }
}
