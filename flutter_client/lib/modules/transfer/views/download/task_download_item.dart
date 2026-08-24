import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../controllers/download_controller.dart';
import '../../models/transfer_task.dart';
import '../../../../utils/file_util.dart';
import '../../../../utils/device_utils.dart';
import '../../../base/components/custom_bordered_icon_button.dart';
import '../../../base/components/custom_tag.dart';

class TaskDownloadItem extends StatelessWidget {
  final TransferTask task;
  final DownloadController controller;

  const TaskDownloadItem({
    super.key,
    required this.task,
    required this.controller,
  });

  /// 是否为 403 权限错误（不展示重试按钮）
  bool _is403Error(String? error) {
    if (error == null || error.isEmpty) return false;
    final lower = error.toLowerCase();
    return lower.contains('403') || lower.contains('permission_denied');
  }

  String _getFriendlyErrorMessage(String error) {
    if (error.toLowerCase().contains('connection timeout') ||
        error.toLowerCase().contains('timed out')) {
      return 'connection_timeout'.tr;
    }
    if (error.toLowerCase().contains('connection closed')) {
      return 'connection_closed'.tr;
    }
    if (error.toLowerCase().contains('socketexception')) {
      return 'network_error'.tr;
    }
    if (error.toLowerCase().contains('404')) {
      return 'file_not_found'.tr;
    }
    if (error.toLowerCase().contains('403')) {
      return 'permission_denied'.tr;
    }
    if (error.toLowerCase().contains('500')) {
      return 'server_error'.tr;
    }
    // Clean up Dio error prefix
    if (error.startsWith('DioException')) {
      // Try to extract message
      if (error.contains(':')) {
        return error.split(':').last.trim();
      }
    }
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final formattedProcessed = FileUtil.formatSize(task.processedSize);
    final hasTotalSize = task.totalSize > 0;
    final formattedTotal = hasTotalSize
        ? FileUtil.formatSize(task.totalSize)
        : '';
    final progressPercent = '${(task.progress * 100).toInt()}%';
    final isWebP2pTask = kIsWeb && task.localPath == 'Browser';

    final shareEnabled =
        task.status == TransferStatus.completed && DeviceUtils.isIOS;

    return InkWell(
      onTap: shareEnabled
          ? () => controller.shareCompletedTask(context, task)
          : null,
      child: Padding(
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
              child: const Icon(Icons.download, color: Colors.blue),
            ),
            const SizedBox(width: 15),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          task.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (task.status == TransferStatus.completed) ...[
                        const SizedBox(width: 8),
                        CustomTag(
                          text: 'success'.tr,
                          backgroundColor: Colors.green.withValues(alpha: 0.1),
                          textColor: Colors.green,
                          fontSize: 10,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                        ),
                      ],
                      if (task.status == TransferStatus.error) ...[
                        const SizedBox(width: 8),
                        CustomTag(
                          text: 'failed'.tr,
                          backgroundColor: Colors.red.withValues(alpha: 0.1),
                          textColor: Colors.red,
                          fontSize: 10,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isWebP2pTask
                              ? '${'download_to'.tr} ${'browser_download_location'.tr}'
                              : '${'download_to'.tr} ${task.localPath}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isWebP2pTask)
                        SizedBox(
                          height: 20,
                          width: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: 'info'.tr,
                            icon: const Icon(
                              Icons.info_outline,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              Get.dialog(
                                AlertDialog(
                                  title: Text('browser_download_help_title'.tr),
                                  content: Text(
                                    'browser_download_help_body'.tr,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Get.back(),
                                      child: Text('ok'.tr),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (task.status == TransferStatus.error)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _getFriendlyErrorMessage(
                              task.error ?? 'unknown_error'.tr,
                            ),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 403 权限错误不提供重试（参考 PC 端：无权限时重试无意义）
                        if (!_is403Error(task.error)) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 24,
                            child: TextButton.icon(
                              onPressed: () {
                                controller.retryTask(task);
                              },
                              icon: const Icon(Icons.refresh, size: 14),
                              label: Text(
                                'retry'.tr,
                                style: const TextStyle(fontSize: 12),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                foregroundColor: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          hasTotalSize
                              ? "$formattedProcessed / $formattedTotal"
                              : formattedProcessed,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Progress
            if (task.status == TransferStatus.uploading ||
                task.status == TransferStatus.pending)
              SizedBox(
                width: 45,
                height: 45,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: task.totalSize > 0 ? task.progress : null,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.blue,
                      ),
                      strokeWidth: 3,
                    ),
                    if (task.totalSize > 0)
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
            // Actions
            if (task.status == TransferStatus.uploading ||
                task.status == TransferStatus.pending)
              if (!isWebP2pTask)
                CustomBorderedIconButton(
                  icon: Icons.pause,
                  onTap: () {
                    controller.pauseTask(task);
                  },
                ),
            if (task.status == TransferStatus.paused)
              if (!isWebP2pTask)
                CustomBorderedIconButton(
                  icon: Icons.play_arrow,
                  onTap: () {
                    controller.resumeTask(task);
                  },
                ),
            SizedBox(width: 4),
            CustomBorderedIconButton(
              icon: Icons.delete_outline,
              onTap: () {
                controller.confirmRemoveTask(task);
              },
            ),
          ],
        ),
      ),
    );
  }
}
