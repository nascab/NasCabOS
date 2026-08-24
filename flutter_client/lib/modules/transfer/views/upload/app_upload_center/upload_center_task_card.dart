import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'package:NasCabOS/modules/base/components/custom_icon_button.dart';
import '../../../controllers/upload_controller.dart';
import '../../../controllers/upload_parts/upload_transfer_helper.dart';
import '../../../models/transfer_task.dart';

class UploadCenterTaskCard extends StatelessWidget {
  const UploadCenterTaskCard({
    super.key,
    required this.task,
    required this.uploadCtrl,
  });

  final TransferTask task;
  final UploadController uploadCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final processed = uploadCtrl.formatBytes(task.processedSize);
    final total = uploadCtrl.formatBytes(task.totalSize);
    final progress = task.totalSize == 0
        ? 0.0
        : task.processedSize / task.totalSize;
    final message = UploadTransferHelper.getDisplayMessage(task.error ?? '');
    final isError = task.status == TransferStatus.error;
    final isFileExistsSkip = UploadTransferHelper.isFileExistsError(message);
    final statusColor = isError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _TaskThumb(task: task),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    task.remotePath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: (isError || isFileExistsSkip)
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        _statusText(task.status),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$processed / $total',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _TaskActions(task: task, uploadCtrl: uploadCtrl),
          ],
        ),
      ),
    );
  }

  String _statusText(TransferStatus status) {
    switch (status) {
      case TransferStatus.pending:
        return 'task_waitting'.tr;
      case TransferStatus.uploading:
        return 'task_uploading'.tr;
      case TransferStatus.paused:
        return 'pause'.tr;
      case TransferStatus.error:
        return 'error'.tr;
      case TransferStatus.completed:
        return 'task_completed'.tr;
    }
  }
}

class _TaskActions extends StatelessWidget {
  const _TaskActions({required this.task, required this.uploadCtrl});

  final TransferTask task;
  final UploadController uploadCtrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy =
        task.status == TransferStatus.uploading ||
        task.status == TransferStatus.pending;
    final isPaused = task.status == TransferStatus.paused;
    final isError = task.status == TransferStatus.error;

    Widget? primary;
    if (isBusy) {
      primary = CustomIconButton(
        tooltip: 'pause'.tr,
        onPressed: () => uploadCtrl.pauseTask(task),
        icon: Icons.pause_circle_outline,
      );
    } else if (isPaused) {
      primary = CustomIconButton(
        tooltip: 'continue'.tr,
        onPressed: () => uploadCtrl.startTask(task),
        icon: Icons.play_circle_outline,
        iconColor: theme.colorScheme.primary,
      );
    } else if (isError) {
      primary = CustomIconButton(
        tooltip: 'retry'.tr,
        onPressed: () => uploadCtrl.startTask(task),
        icon: Icons.refresh,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null) primary,
        CustomIconButton(
          tooltip: 'delete'.tr,
          onPressed: () => uploadCtrl.deleteTask(task),
          icon: Icons.delete_outline,
          iconColor: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _TaskThumb extends StatelessWidget {
  const _TaskThumb({required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFolder = task.folderRefs != null && task.folderRefs!.isNotEmpty;
    if (isFolder) {
      return _iconThumb(theme, Icons.folder_outlined);
    }
    final path = task.localPath.trim();
    if (path.isEmpty) {
      return _iconThumb(theme, Icons.insert_drive_file_outlined);
    }

    final ext = _extLower(path);
    if (_isImageExt(ext)) {
      final file = File(path);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          file,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          cacheWidth: 160,
          errorBuilder: (context, error, stackTrace) =>
              _iconThumb(theme, Icons.image_outlined),
        ),
      );
    }

    if (_isVideoExt(ext)) {
      return _VideoThumb(path: path);
    }

    return _iconThumb(theme, Icons.insert_drive_file_outlined);
  }

  Widget _iconThumb(ThemeData theme, IconData icon) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
    );
  }

  String _extLower(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0 || dot >= path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  bool _isImageExt(String ext) {
    const set = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
    return set.contains(ext);
  }

  bool _isVideoExt(String ext) {
    const set = {'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', '3gp'};
    return set.contains(ext);
  }
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.path});

  final String path;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = VideoThumbnail.thumbnailData(
      video: widget.path,
      imageFormat: ImageFormat.JPEG,
      maxHeight: 160,
      quality: 55,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null || data.isEmpty) {
            return Container(
              width: 56,
              height: 56,
              color: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.videocam_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          return Stack(
            children: [
              Image.memory(
                data,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
