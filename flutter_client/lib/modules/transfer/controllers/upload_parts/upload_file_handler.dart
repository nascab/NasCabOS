import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import '../../utils/upload_temp_file_cleaner.dart';

/// 单个文件上传处理器
/// 负责处理单个文件的上传逻辑
class UploadFileHandler {
  final Map<String, dynamic> _activeFiles;
  final List<String> _processingIds;
  final Map<String, dio.CancelToken> _cancelTokens;
  final dio.Dio _dio;
  final RxList<TransferTask> _tasks;
  final RxString _nameStrategy;
  final RxString _saveType;
  final Function refreshThrottled;

  UploadFileHandler(
    this._activeFiles,
    this._processingIds,
    this._cancelTokens,
    this._dio,
    this._tasks,
    this._nameStrategy,
    this._saveType,
    this.refreshThrottled,
  );

  /// 上传单个文件
  Future<void> uploadFile(TransferTask task) async {
    if (!_tasks.any((t) => t.id == task.id)) {
      _cancelTokens[task.id]?.cancel();
      _cancelTokens.remove(task.id);
      _processingIds.remove(task.id);
      final removed = _activeFiles.remove(task.id);
      if (!kIsWeb && removed is XFile) {
        unawaited(
          UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(removed.path),
        );
      }
      return;
    }
    _processingIds.add(task.id);
    task.status = TransferStatus.uploading;
    task.error = null;
    _tasks.refresh();

    final cancelToken = _cancelTokens[task.id] ?? dio.CancelToken();
    _cancelTokens[task.id] = cancelToken;

    dynamic fileRef = _activeFiles[task.id];

    if (fileRef == null && !kIsWeb && task.localPath.isNotEmpty) {
      fileRef = XFile(task.localPath);
    }

    if (fileRef == null) {
      task.status = TransferStatus.error;
      task.error = kIsWeb ? "Web文件丢失（刷新页面？）" : "文件未找到";
      _processingIds.remove(task.id);
      _cancelTokens.remove(task.id);
      _tasks.refresh();
      return;
    }

    if (!kIsWeb && fileRef is XFile) {
      final file = File(fileRef.path);
      if (!await file.exists()) {
        task.status = TransferStatus.error;
        task.error = "磁盘上未找到文件";
        _processingIds.remove(task.id);
        _cancelTokens.remove(task.id);
        _tasks.refresh();
        return;
      }
    }

    unawaited(TransferWorkNotificationHub.instance.uploadWorkBegan());
    try {
      if (cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }

      if (_nameStrategy.value.toLowerCase() == 'skip') {
        final exists = await FileApiService.instance.existsResolved(
          targetDir: task.remotePath,
          relativePath: task.name,
        );
        if (exists) {
          task.status = TransferStatus.error;
          task.error = 'upload_file_exists_skipped'.tr;
          _tasks.refresh();
          return;
        }
      }

      int? fileMtimeMs;
      int? fileBirthtimeMs;
      if (kIsWeb) {
        if (fileRef is! XFile) {
          try {
            fileMtimeMs = UploadWebFileHelper.getLastModified(fileRef);
          } catch (_) {}
        }
      } else if (fileRef is XFile) {
        try {
          final stat = await File(fileRef.path).stat();
          fileMtimeMs = stat.modified.millisecondsSinceEpoch;
          fileBirthtimeMs = stat.changed.millisecondsSinceEpoch;
        } catch (_) {}
      }

      // 1. 计算哈希
      if (task.fileHash == null) {
        task.isCalculatingHash = true;
        refreshThrottled();

        final fileName = task.name;
        final size = task.totalSize;
        String? createTimeStr;
        if (!kIsWeb && fileRef is XFile) {
          try {
            final file = File(fileRef.path);
            final stat = await file.stat();
            createTimeStr = stat.modified.millisecondsSinceEpoch.toString();
          } catch (e) {
            // ignore
          }
        }

        final meta = createTimeStr != null
            ? '$fileName|$size|$createTimeStr'
            : '$fileName|$size';

        task.fileHash = sha256.convert(utf8.encode(meta)).toString();
        task.isCalculatingHash = false;
        refreshThrottled();
      }

      if (cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }

      final baseUrl = ApiController.instance.baseUrl;
      final token = ApiController.instance.accessToken;

      // 2. 调用核心上传逻辑
      var skipped = false;
      final processed = await UploadCore.processFile(
        dioClient: _dio,
        baseUrl: baseUrl,
        token: token ?? '',
        fileRef: fileRef,
        fileName: task.name,
        fileSize: task.totalSize,
        remotePath: task.remotePath,
        nameStrategy: _nameStrategy.value,
        saveType: _saveType.value.isNotEmpty ? _saveType.value : null,
        fileHash: task.fileHash!,
        cancelToken: cancelToken,
        chunkSizeOverride: task.chunkSize,
        fileMtimeMs: fileMtimeMs,
        fileBirthtimeMs: fileBirthtimeMs,
        onProgress: (increment) {
          task.processedSize += increment;
          if (task.processedSize > task.totalSize) {
            task.processedSize = task.totalSize;
          }
          TransferWorkNotificationHub.instance.uploadProgressThrottled(
            displayName: task.name,
            processed: task.processedSize,
            total: task.totalSize,
          );
        },
        onSkipped: (_) {
          skipped = true;
          task.error = 'upload_file_exists_skipped'.tr;
          _tasks.refresh();
        },
        onUiRefresh: () => _tasks.refresh(),
      );

      task.processedSize = processed;
      task.status = skipped ? TransferStatus.error : TransferStatus.completed;
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
      if (task.status == TransferStatus.completed) {
        if (!kIsWeb && fileRef is XFile) {
          await UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(
            fileRef.path,
          );
        }
        _activeFiles.remove(task.id);
      }
      _tasks.refresh();
    }
  }
}
