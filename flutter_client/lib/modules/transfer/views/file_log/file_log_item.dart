import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:NasCabOS/modules/base/components/custom_icon_button.dart';
import '../../controllers/file_log_controller.dart';
import '../../models/file_operation_log.dart';
import '../../../base/components/custom_tag.dart';

class FileLogItem extends StatelessWidget {
  final FileOperationLog log;
  final FileLogController? controller;

  /// Optional cancel callback; when set, used for cancel button instead of controller.
  final Future<void> Function(FileOperationLog)? onCancel;

  /// When true, use vertical/compact layout for narrow screens (e.g. mobile).
  final bool compact;

  /// When true, remove left padding from the default (non-compact) layout.
  final bool noLeftPadding;

  const FileLogItem({
    super.key,
    required this.log,
    this.controller,
    this.onCancel,
    this.compact = false,
    this.noLeftPadding = false,
  });

  IconData _getIcon() {
    switch (log.type) {
      case 'copy':
        return Icons.copy;
      case 'move':
        return Icons.drive_file_move;
      case 'delete':
        return Icons.delete;
      case 'rename':
        return Icons.drive_file_rename_outline;
      default:
        return Icons.file_present;
    }
  }

  Color _getStatusColor() {
    var theme = Get.theme;
    switch (log.state) {
      case 'SUCCESS':
        return theme.colorScheme.primary;
      case 'ERROR':
      case 'CANCELLED':
      case 'INTERRUPTED':
        return Colors.red;
      case 'PROCESSING':
      case 'WAIT':
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.primary;
    }
  }

  // 显示操作文件列表
  void _showSourcePaths() {
    DialogUtil.showInfoDialog(
      title: 'operation_file_list'.tr,
      content: log.sourcePath.join('\n\n'),
      scrollableContent: true,
    );
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '-';
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
    } catch (e) {
      return '-';
    }
  }

  Widget _buildCancelButton() {
    if ((controller == null && onCancel == null) ||
        log.state != 'WAIT' && log.state != 'PROCESSING') {
      return const SizedBox.shrink();
    }
    return CustomIconButton(
      icon: Icons.cancel,
      iconColor: Colors.red,
      tooltip: 'cancel'.tr,
      onPressed: () {
        if (onCancel != null) {
          onCancel!(log);
        } else if (controller != null) {
          controller!.cancelTask(log);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProcessing = log.state == 'PROCESSING';
    final progress = log.progress;
    final progressPercent = '${(progress * 100).toInt()}%';
    final theme = Get.theme;
    final statusColor = _getStatusColor();

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_getIcon(), color: statusColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          log.type.toLowerCase().tr,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      CustomTag(
                        text: log.state.toLowerCase().tr,
                        fontSize: 10,
                        backgroundColor: statusColor.withValues(alpha: 0.2),
                        textColor: statusColor,
                      ),
                    ],
                  ),
                ),
                if (isProcessing) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            statusColor,
                          ),
                          strokeWidth: 2.5,
                        ),
                        Text(
                          progressPercent,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                _buildCancelButton(),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _showSourcePaths,
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  log.sourcePath.isNotEmpty
                      ? log.sourcePath.first +
                            (log.sourcePath.length > 1
                                ? ' (+${log.sourcePath.length - 1})'
                                : '')
                      : '-',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (log.targetPath != null) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  log.targetPath!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (log.message != null && log.state == 'ERROR')
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: Text(
                  log.message!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8,
        left: noLeftPadding ? 0 : 16,
        right: 16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_getIcon(), color: statusColor),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      log.type.toLowerCase().tr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (log.createTime != null)
                      Text(
                        _formatTime(log.createTime),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(width: 8),
                    CustomTag(
                      text: log.state.toLowerCase().tr,
                      fontSize: 10,
                      backgroundColor: statusColor.withValues(alpha: 0.2),
                      textColor: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                InkWell(
                  onTap: _showSourcePaths,
                  child: Row(
                    children: [
                      const Icon(Icons.output, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          log.sourcePath.isNotEmpty
                              ? log.sourcePath.first +
                                    (log.sourcePath.length > 1
                                        ? ' (+${log.sourcePath.length - 1})'
                                        : '')
                              : '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (log.targetPath != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.save, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          log.targetPath!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (log.message != null && log.state == 'ERROR')
                  Text(
                    log.message!,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isProcessing)
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        strokeWidth: 3,
                      ),
                      Text(
                        progressPercent,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          _buildCancelButton(),
        ],
      ),
    );
  }
}
