import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:cross_file/cross_file.dart';

import '../../models/transfer_task.dart';
import '../../../../core/api/api_controller.dart';
import '../../../files/service/file_api_service.dart';
import 'upload_transfer_helper.dart';
import 'upload_core.dart';
import 'upload_web_file_helper.dart';
import '../../../../core/notification/transfer_work_notification_hub.dart';

/// 文件夹上传处理器
/// 负责处理文件夹的上传逻辑
class UploadFolderHandler {
  final List<String> _processingIds;
  final Map<String, dio.CancelToken> _cancelTokens;
  final dio.Dio _dio;
  final RxList<TransferTask> _tasks;
  final RxString _nameStrategy;
  final RxString _saveType;
  final Function refreshThrottled;

  UploadFolderHandler(
    this._processingIds,
    this._cancelTokens,
    this._dio,
    this._tasks,
    this._nameStrategy,
    this._saveType,
    this.refreshThrottled,
  );

  /// 上传文件夹
  Future<void> uploadFolder(TransferTask task) async {
    if (!_tasks.any((t) => t.id == task.id)) {
      _cancelTokens[task.id]?.cancel();
      _cancelTokens.remove(task.id);
      _processingIds.remove(task.id);
      return;
    }
    _processingIds.add(task.id);
    task.status = TransferStatus.uploading;
    _tasks.refresh();

    final cancelToken = _cancelTokens[task.id] ?? dio.CancelToken();
    _cancelTokens[task.id] = cancelToken;

    unawaited(TransferWorkNotificationHub.instance.uploadWorkBegan());
    final entries = task.folderRefs ?? [];
    try {
      if (cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }
      final baseUrl = ApiController.instance.baseUrl;
      final token = ApiController.instance.accessToken;

      for (final entry in entries) {
        if (cancelToken.isCancelled) {
          throw dio.DioException(
            requestOptions: dio.RequestOptions(path: ''),
            type: dio.DioExceptionType.cancel,
          );
        }

        final rel = (entry['rel'] as String).replaceAll('\\', '/');
        final size = entry['size'] as int;
        final ref = entry['ref'];
        int? fileMtimeMs;
        if (kIsWeb) {
          if (ref is! XFile) {
            try {
              fileMtimeMs = UploadWebFileHelper.getLastModified(ref);
            } catch (_) {}
          } else {
            try {
              final dt = await ref.lastModified();
              fileMtimeMs = dt.millisecondsSinceEpoch;
            } catch (_) {}
          }
        } else if (ref is XFile) {
          try {
            final dt = await ref.lastModified();
            fileMtimeMs = dt.millisecondsSinceEpoch;
          } catch (_) {}
        }

        final completedList = task.folderCompleted ?? [];
        if (completedList.contains(rel)) {
          continue;
        }

        if (_nameStrategy.value.toLowerCase() == 'skip') {
          final exists = await FileApiService.instance.existsResolved(
            targetDir: task.remotePath,
            relativePath: rel,
          );
          if (exists) {
            task.folderCompleted ??= [];
            if (!task.folderCompleted!.contains(rel)) {
              task.folderCompleted!.add(rel);
            }
            task.processedSize += size;
            if (task.processedSize > task.totalSize) {
              task.processedSize = task.totalSize;
            }
            task.error = 'upload_file_exists_skipped'.tr;
            _tasks.refresh();
            continue;
          }
        }

        final chunkSize = UploadTransferHelper.calculateChunkSize(size);
        final meta = '$rel|$size';
        final fileHash = sha256.convert(utf8.encode(meta)).toString();

        await UploadCore.processFile(
          dioClient: _dio,
          baseUrl: baseUrl,
          token: token ?? '',
          fileRef: ref,
          fileName: rel.split('/').last,
          fileSize: size,
          remotePath: task.remotePath,
          nameStrategy: _nameStrategy.value,
          saveType: _saveType.value.isNotEmpty ? _saveType.value : null,
          fileHash: fileHash,
          cancelToken: cancelToken,
          chunkSizeOverride: chunkSize,
          relativePath: rel,
          fileMtimeMs: fileMtimeMs,
          onProgress: (increment) {
            task.processedSize += increment;
            TransferWorkNotificationHub.instance.uploadProgressThrottled(
              displayName: rel.split('/').last,
              processed: task.processedSize,
              total: task.totalSize,
            );
            refreshThrottled();
          },
          onCompleted: (relPath) {
            task.folderCompleted ??= [];
            if (!task.folderCompleted!.contains(relPath)) {
              task.folderCompleted!.add(relPath);
            }
          },
          onSkipped: (_) {
            task.error = 'upload_file_exists_skipped'.tr;
            _tasks.refresh();
          },
          onUiRefresh: () => _tasks.refresh(),
        );
      }

      task.status = TransferStatus.completed;
      task.processedSize = task.totalSize;
      _tasks.refresh();
    } catch (e) {
      if (e is dio.DioException && e.type == dio.DioExceptionType.cancel) {
        task.status = TransferStatus.paused;
      } else {
        task.status = TransferStatus.error;
        task.error = UploadTransferHelper.getServerMessage(e);
      }
    } finally {
      await TransferWorkNotificationHub.instance.uploadWorkEnded();
      _processingIds.remove(task.id);
      _cancelTokens.remove(task.id);
      _tasks.refresh();
    }
  }
}
