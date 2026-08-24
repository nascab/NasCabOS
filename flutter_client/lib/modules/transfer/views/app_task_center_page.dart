import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/user/current_user_controller.dart';
import '../../base/components/custom_no_data.dart';
import '../../base/views/app_base_page.dart';
import 'file_log/file_log_page.dart';

/// App端任务中心页面
/// App Task Center Page
class AppTaskCenterPage extends StatelessWidget {
  const AppTaskCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final showFileLog = CurrentUserController.instance.isAdmin;
    return AppBasePage(
      title: showFileLog ? 'file_operation'.tr : 'app_task_center'.tr,
      body: showFileLog
          ? const FileLogPage()
          : CustomNoData(text: 'task_empty'.tr),
    );
  }
}
