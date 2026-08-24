part of '../app_download_center_view.dart';

class _DownloadCenterTaskTab extends StatelessWidget {
  const _DownloadCenterTaskTab();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AppDownloadCenterController>();
    final downloadCtrl = controller.downloadController;

    return Obx(() {
      final tasks =
          downloadCtrl.tasks
              .where(
                (t) =>
                    t.status == TransferStatus.uploading ||
                    t.status == TransferStatus.pending ||
                    t.status == TransferStatus.paused,
              )
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
        separatorBuilder: (_, _) => const CustomDivider(height: 8),
        itemCount: tasks.length,
      );
    });
  }
}
