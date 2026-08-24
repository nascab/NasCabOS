import 'package:NasCabOS/modules/base/components/custom_bordered_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/upload_controller.dart';
import '../../controllers/upload_parts/upload_transfer_helper.dart';
import '../../models/transfer_task.dart';

class TaskUploadItem extends StatelessWidget {
  final TransferTask task;
  final UploadController controller;

  const TaskUploadItem({
    super.key,
    required this.task,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 预计算格式化的大小，避免重复计算
    final formattedProcessed = controller.formatBytes(task.processedSize);
    final formattedTotal = controller.formatBytes(task.totalSize);
    final progressPercent = '${(task.progress * 100).toInt()}%';
    final message = UploadTransferHelper.getDisplayMessage(task.error ?? '');
    final showErrorMessage =
        message.isNotEmpty &&
        (task.status == TransferStatus.error ||
            UploadTransferHelper.isFileExistsError(message));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              task.folderRefs != null && task.folderRefs!.isNotEmpty
                  ? Icons.folder
                  : Icons.insert_drive_file,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 15),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Text(
                  '${'task_upload_to'.tr} ${task.remotePath}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (showErrorMessage) ...[
                  const SizedBox(height: 5),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      "$formattedProcessed / $formattedTotal",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 进度条
          if (task.status == TransferStatus.uploading ||
              task.status == TransferStatus.pending)
            SizedBox(
              width: 45,
              height: 45,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: task.progress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blue,
                    ),
                    strokeWidth: 3,
                  ),
                  Text(
                    progressPercent,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          // Status / Action
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (task.status == TransferStatus.completed)
                const Icon(Icons.check_circle, color: Colors.green)
              else if (task.status == TransferStatus.error)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: message.isNotEmpty ? message : 'Unknown Error',
                      child: const Icon(Icons.error, color: Colors.red),
                    ),
                    CustomBorderedIconButton(
                      onTap: () => controller.startTask(task),
                      icon: Icons.refresh,
                      iconColor: Colors.blue,
                      tooltip: 'retry'.tr,
                    ),
                    SizedBox(width: 4),
                  ],
                )
              else if (task.status == TransferStatus.paused)
                CustomBorderedIconButton(
                  onTap: () => controller.startTask(task),
                  icon: Icons.play_circle_fill,
                  tooltip: 'continue'.tr,
                )
              else if (task.status == TransferStatus.uploading)
                CustomBorderedIconButton(
                  onTap: () => controller.pauseTask(task),
                  icon: Icons.pause,
                  tooltip: 'pause'.tr,
                ),
              SizedBox(width: 4),
              CustomBorderedIconButton(
                icon: Icons.delete,
                onTap: () => controller.deleteTask(task),
                tooltip: 'delete'.tr,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
