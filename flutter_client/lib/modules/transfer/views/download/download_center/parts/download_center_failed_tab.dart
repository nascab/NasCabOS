part of '../app_download_center_view.dart';

/// 已失败 tab：仅展示失败任务（内存，不持久化）
class _DownloadCenterFailedTab extends StatelessWidget {
  const _DownloadCenterFailedTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppDownloadCenterController>();
    final downloadCtrl = controller.downloadController;

    return Obx(() {
      final failedTasks = downloadCtrl.tasks
          .where(
            (t) =>
                t.type == TransferType.download &&
                t.status == TransferStatus.error,
          )
          .toList()
        ..sort((a, b) => b.createdTime.compareTo(a.createdTime));

      if (failedTasks.isEmpty) {
        return CustomNoData(text: 'task_empty'.tr);
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemBuilder: (context, index) {
          final task = failedTasks[index];
          return TaskDownloadItem(task: task, controller: downloadCtrl);
        },
        separatorBuilder: (_, __) => const CustomDivider(height: 8),
        itemCount: failedTasks.length,
      );
    });
  }
}
