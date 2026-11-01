part of '../app_download_center_view.dart';

/// 全部 tab：展示所有状态的下载任务（内存，不持久化）
class _DownloadCenterAllTab extends StatelessWidget {
  const _DownloadCenterAllTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppDownloadCenterController>();
    final downloadCtrl = controller.downloadController;

    return Obx(() {
      final tasks = downloadCtrl.tasks
          .where((t) => t.type == TransferType.download)
          .toList()
        ..sort((a, b) => b.createdTime.compareTo(a.createdTime));

      if (tasks.isEmpty) {
        return CustomNoData(text: 'task_empty'.tr);
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemBuilder: (context, index) {
          final task = tasks[index];
          return TaskDownloadItem(task: task, controller: downloadCtrl);
        },
        separatorBuilder: (_, __) => const CustomDivider(height: 8),
        itemCount: tasks.length,
      );
    });
  }
}
