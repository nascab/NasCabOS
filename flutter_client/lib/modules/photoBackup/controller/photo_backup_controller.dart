import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/api/api_controller.dart';
import '../../../core/notification/transfer_work_notification_hub.dart';
import '../../../core/api/dio_bad_certificate_compat.dart';
import '../../../core/user/current_user_controller.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/toast_util.dart';
import '../../transfer/controllers/upload_parts/upload_core.dart';
import '../../transfer/controllers/upload_parts/upload_transfer_helper.dart';
import '../../transfer/utils/upload_temp_file_cleaner.dart';
import '../models/photo_backup_models.dart';
import '../storage/photo_backup_storage.dart';

void _photoBackupLog(String label, [Object? value]) {
  // ignore: avoid_print
  print('[PhotoBackup] $label${value != null ? ': $value' : ''}');
}

class PhotoBackupRuntime {
  final RxBool running = false.obs;
  final RxString status = 'idle'.obs;
  final RxString currentFile = ''.obs;
  final RxInt totalFiles = 0.obs;
  final RxInt doneFiles = 0.obs;
  final RxInt totalBytes = 0.obs;
  final RxInt doneBytes = 0.obs;
  final RxString error = ''.obs;

  /// 有总大小时按字节，否则按文件数；都未知时返回 null（显示为 indeterminate）。
  double? get progress {
    final totalB = totalBytes.value;
    if (totalB > 0) {
      final done = doneBytes.value;
      if (done <= 0) return 0;
      if (done >= totalB) return 1;
      return done / totalB;
    }
    final totalF = totalFiles.value;
    if (totalF > 0) {
      final done = doneFiles.value;
      if (done <= 0) return 0;
      if (done >= totalF) return 1;
      return done / totalF;
    }
    return null;
  }
}

class PhotoBackupSourceValue {
  final PhotoBackupSourceType type;
  final String sourceId;
  final String sourceName;

  const PhotoBackupSourceValue({
    required this.type,
    required this.sourceId,
    required this.sourceName,
  });
}

class PhotoBackupController extends GetxController {
  final _storage = PhotoBackupStorage.instance;
  final RxList<PhotoBackupTask> tasks = <PhotoBackupTask>[].obs;
  final RxBool loading = false.obs;
  final Map<int, PhotoBackupRuntime> _runtime = {};
  final Map<int, dio.CancelToken> _cancelTokens = {};
  int _wakelockRefCount = 0;
  String _lastIdentityKey = '';
  String _lastAutoTriggerIdentityKey = '';
  late final dio.Dio _dio;

  /// 从异常中取错误文案，取消类统一返回国际化后的“用户已取消”
  String _errorMessage(dynamic e) {
    if (e is dio.DioException && e.type == dio.DioExceptionType.cancel) {
      return 'photo_backup_manual_cancel'.tr;
    }
    return UploadTransferHelper.getServerMessage(e);
  }

  void _syncBackupWorkNotification(PhotoBackupRuntime runtime) {
    TransferWorkNotificationHub.instance.photoBackupProgressThrottled(
      currentFile: runtime.currentFile.value,
      progress: runtime.progress,
      doneFiles: runtime.doneFiles.value,
      totalFiles: runtime.totalFiles.value,
    );
  }

  @override
  void onInit() {
    super.onInit();
    _dio = createDioWithBadCertificateCompat(
      dio.BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    unawaited(onSessionMaybeChanged());
  }

  @override
  void onClose() {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) token.cancel();
    }
    _cancelTokens.clear();
    super.onClose();
  }

  PhotoBackupRuntime runtimeOf(int taskId) {
    return _runtime.putIfAbsent(taskId, () => PhotoBackupRuntime());
  }

  Future<void> refreshTasks() async {
    loading.value = true;
    try {
      final identity = _identity();
      final list = await _storage.listTasks(
        serverId: identity.serverId,
        userId: identity.userId,
      );
      tasks.assignAll(list);
    } finally {
      loading.value = false;
    }
  }

  Future<void> _autoStartTasksOnLaunch() async {
    final list = tasks
        .where((e) => e.autoStartOnLaunch)
        .map((e) => e.id)
        .toList(growable: false);
    for (final taskId in list) {
      await runUploadNew(taskId, trigger: PhotoBackupRunTrigger.autoStart);
    }
  }

  _Identity _identity() {
    final serverId = ApiController.instance.state.serverId.trim();
    final userId = CurrentUserController.instance.current?.id ?? 0;
    return _Identity(serverId: serverId, userId: userId);
  }

  /// 会话（服务器/用户）可能变化时：只刷新任务列表，不触发自动开始备份。
  /// 自动开始备份仅在 [onConnectionConfirmed] 中触发，确保在登录/连接成功后再执行。
  Future<void> onSessionMaybeChanged() async {
    final id = _identity();
    final key = '${id.serverId}#${id.userId}';
    final changed = key != _lastIdentityKey;
    if (changed) {
      _lastIdentityKey = key;
      await refreshTasks();
    } else if (tasks.isEmpty) {
      await refreshTasks();
    }
  }

  /// 在确认当前服务器连接可用后调用，用于在「APP 打开时自动开启备份」开启时触发备份。
  /// 应在登录成功（setAuthInfo）或冷启动后首次 API 成功（如首页加载成功）后调用，
  /// 避免在连接未就绪时触发导致 connection refused。
  /// 移动端仅在 WiFi 网络下才会自动开始备份，避免消耗蜂窝流量。
  Future<void> onConnectionConfirmed() async {
    if (!ApiController.instance.isAuthenticated) return;
    final id = _identity();
    final key = '${id.serverId}#${id.userId}';
    if (id.serverId.isEmpty || id.userId <= 0) return;
    if (_lastAutoTriggerIdentityKey == key) return;
    if (DeviceUtils.isMobile && !await _isOnWifi()) {
      _photoBackupLog('onConnectionConfirmed', 'skip auto-start: not on WiFi');
      return;
    }
    _lastAutoTriggerIdentityKey = key;
    await refreshTasks();
    await _autoStartTasksOnLaunch();
  }

  /// 当前是否在 WiFi 下（移动端用于控制自动备份是否执行）
  Future<bool> _isOnWifi() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveTask({
    int? id,
    required PhotoBackupSourceType sourceType,
    required String sourceId,
    required String sourceName,
    required String targetDir,
    required String nameStrategy,
    required String saveType,
    required bool uploadLivePhotoVideo,
    required bool autoStartOnLaunch,
  }) async {
    if (sourceId.trim().isEmpty ||
        sourceName.trim().isEmpty ||
        targetDir.trim().isEmpty) {
      ToastUtil.show('photo_backup_required'.tr);
      return false;
    }
    final identity = _identity();
    if (identity.serverId.isEmpty || identity.userId <= 0) {
      ToastUtil.show('operation_failed'.tr);
      return false;
    }
    final taskName = sourceName.trim();
    final sourceTypeValue = sourceType == PhotoBackupSourceType.album
        ? 'album'
        : 'folder';
    await _storage.upsertTask(
      id: id,
      serverId: identity.serverId,
      userId: identity.userId,
      name: taskName,
      sourceType: sourceTypeValue,
      sourceId: sourceId.trim(),
      sourceName: sourceName.trim(),
      targetDir: targetDir.trim(),
      nameStrategy: nameStrategy.trim().isEmpty ? 'skip' : nameStrategy.trim(),
      saveType: saveType.trim(),
      uploadLivePhotoVideo: uploadLivePhotoVideo,
      autoStartOnLaunch: autoStartOnLaunch,
    );
    await refreshTasks();
    return true;
  }

  Future<void> deleteTask(int taskId) async {
    cancelTask(taskId);
    await _storage.deleteTask(taskId);
    tasks.removeWhere((e) => e.id == taskId);
  }

  void cancelTask(int taskId) {
    final token = _cancelTokens[taskId];
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
  }

  /// 登出或切换服务器前调用：取消所有进行中的相册备份上传，避免 token/地址变更后仍向旧服务器传数据。
  void cancelAllRunning() {
    for (final t in tasks) {
      if (runtimeOf(t.id).running.value) {
        cancelTask(t.id);
      }
    }
  }

  Future<List<PhotoBackupRunRecord>> listRuns(int taskId) async {
    return await _storage.listRuns(taskId);
  }

  Future<List<PhotoBackupFileRecord>> listRunFiles(int runId) async {
    return await _storage.listRunFiles(runId);
  }

  Future<void> deleteRun(int runId) async {
    await _storage.deleteRun(runId);
  }

  Future<void> runUploadNew(
    int taskId, {
    PhotoBackupRunTrigger trigger = PhotoBackupRunTrigger.uploadNew,
  }) async {
    await _run(taskId: taskId, modeAll: false, trigger: trigger);
  }

  Future<void> runUploadAll(int taskId) async {
    await _run(
      taskId: taskId,
      modeAll: true,
      trigger: PhotoBackupRunTrigger.uploadAll,
    );
  }

  Future<void> _run({
    required int taskId,
    required bool modeAll,
    required PhotoBackupRunTrigger trigger,
  }) async {
    final task = tasks.firstWhereOrNull((e) => e.id == taskId);
    if (task == null) return;
    final runtime = runtimeOf(task.id);
    if (runtime.running.value) return;

    final token = ApiController.instance.accessToken?.trim() ?? '';
    if (token.isEmpty) {
      runtime.error.value = 'network_failure'.tr;
      runtime.status.value = 'error';
      return;
    }

    runtime.running.value = true;
    runtime.status.value = 'running';
    runtime.error.value = '';
    runtime.currentFile.value = '';
    runtime.totalBytes.value = 0;
    runtime.doneBytes.value = 0;
    runtime.totalFiles.value = 0;
    runtime.doneFiles.value = 0;

    _wakelockRefCount += 1;
    if (_wakelockRefCount == 1) WakelockPlus.enable();
    unawaited(TransferWorkNotificationHub.instance.backupWorkBegan());

    final cancelToken = dio.CancelToken();
    _cancelTokens[task.id]?.cancel();
    _cancelTokens[task.id] = cancelToken;

    final runTotal = Stopwatch()..start();
    _photoBackupLog(
      '_run start',
      'taskId=${task.id} modeAll=$modeAll source=${task.sourceType == PhotoBackupSourceType.album ? "album" : "folder"}',
    );
    int? runId;
    int successCount = 0;
    int failedCount = 0;
    int consumedBytes = 0;
    try {
      if (modeAll) {
        final sw = Stopwatch()..start();
        await _storage.clearTaskRecords(task.id);
        _photoBackupLog('clearTaskRecords', '${sw.elapsedMilliseconds}ms');
      }
      final swCreate = Stopwatch()..start();
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      runId = await _storage.createRun(
        taskId: task.id,
        triggerType: _triggerValue(trigger),
        startedAtMs: startedAt,
      );
      _photoBackupLog('createRun', '${swCreate.elapsedMilliseconds}ms');

      final swCursor = Stopwatch()..start();
      final cursor = modeAll ? null : await _storage.loadCursor(task.id);
      _photoBackupLog('loadCursor', '${swCursor.elapsedMilliseconds}ms');
      final baseUrl = ApiController.instance.baseUrl;

      // 仅「上传全部」时按页流式上传，可随时开始、随时结束；顺序依赖系统 API 分页。
      // 「上传新增」必须全量扫描后按 orderMs+id 排序再过滤 cursor，保证顺序稳定、不重复传已成功的。
      if (task.sourceType == PhotoBackupSourceType.album && modeAll) {
        runtime.totalFiles.value = 0;
        runtime.totalBytes.value = 0;
        _photoBackupLog('branch', 'album+uploadAll(streaming)');
        await for (final batch in _scanAlbumBatched(task, null)) {
          for (final item in batch) {
            if (cancelToken.isCancelled) {
              throw dio.DioException(
                requestOptions: dio.RequestOptions(path: ''),
                type: dio.DioExceptionType.cancel,
              );
            }
            runtime.currentFile.value = item.displayName;
            _syncBackupWorkNotification(runtime);
            final uploadedAt = DateTime.now().millisecondsSinceEpoch;
            String status = 'success';
            String error = '';
            try {
              final fileHash = sha256
                  .convert(
                    utf8.encode(
                      '${item.sourceUniqueId}|${item.size}|${item.fileMtimeMs}',
                    ),
                  )
                  .toString();
              final relPath = p.posix.join(task.sourceName, item.relativePath);
              await UploadCore.processFile(
                dioClient: _dio,
                baseUrl: baseUrl,
                token: token,
                fileRef: XFile(item.localPath, name: item.displayName),
                fileName: item.displayName,
                fileSize: item.size,
                remotePath: task.targetDir,
                nameStrategy: task.nameStrategy,
                saveType: task.saveType.isEmpty ? null : task.saveType,
                fileHash: fileHash,
                cancelToken: cancelToken,
                relativePath: relPath,
                fileMtimeMs: item.fileMtimeMs,
                fileBirthtimeMs: item.orderMs > 0 ? item.orderMs : null,
                onProgress: (increment) {
                  runtime.doneBytes.value += increment;
                  _syncBackupWorkNotification(runtime);
                },
                onCompleted: (_) {},
              );
              successCount += 1;
              consumedBytes += item.size;
              await _storage.upsertCursor(
                taskId: task.id,
                lastCreatedAtMs: item.orderMs,
                lastUniqueId: item.sourceUniqueId,
              );
            } catch (e) {
              status = 'error';
              error = _errorMessage(e);
              runtime.error.value = error;
              failedCount += 1;
            } finally {
              await _storage.insertFileRecord(
                taskId: task.id,
                runId: runId,
                sourceUniqueId: item.sourceUniqueId,
                displayName: item.displayName,
                localPath: item.localPath,
                size: item.size,
                sourceCreateAtMs: item.orderMs,
                uploadedAtMs: uploadedAt,
                status: status,
                error: error,
              );
              // iOS 上 originFile 可能导出到沙盒 tmp/cache，上传完成后可清理避免残留。
              await UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(
                item.localPath,
              );
              runtime.doneFiles.value += 1;
              if (runtime.totalBytes.value > 0 &&
                  runtime.doneBytes.value > runtime.totalBytes.value) {
                runtime.doneBytes.value = runtime.totalBytes.value;
              }
            }
            if (status == 'error') break;
          }
          if (failedCount > 0) break;
        }
        await _storage.finishRun(
          runId: runId,
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          successCount: successCount,
          failedCount: failedCount,
          totalBytes: consumedBytes,
        );
        runtime.status.value = failedCount > 0 ? 'error' : 'idle';
        return;
      }

      // 相册 + 上传新增 + 有 cursor：只拉待上传的 Meta 列表，上传时再按需解析 originFile，避免一次性解析几百条卡住
      if (task.sourceType == PhotoBackupSourceType.album &&
          !modeAll &&
          cursor != null) {
        final swScan = Stopwatch()..start();
        _photoBackupLog('scanBranch', 'scanAlbumPendingMeta');
        final pendingMetaList = await _scanAlbumPendingMeta(task, cursor);
        _photoBackupLog(
          'scanSource done',
          '${swScan.elapsedMilliseconds}ms, metaCount=${pendingMetaList.length}',
        );
        if (pendingMetaList.isEmpty) {
          await _storage.finishRun(
            runId: runId,
            finishedAtMs: DateTime.now().millisecondsSinceEpoch,
            successCount: 0,
            failedCount: 0,
            totalBytes: 0,
          );
          runtime.error.value = '';
          runtime.status.value = 'idle';
          runtime.running.value = false;
          if (trigger == PhotoBackupRunTrigger.uploadNew) {
            ToastUtil.show('photo_backup_no_new_files'.tr);
          }
          return;
        }
        runtime.totalFiles.value = pendingMetaList.length;
        runtime.totalBytes.value = 0;
        _photoBackupLog(
          'upload loop start (resolve on demand)',
          '${runTotal.elapsedMilliseconds}ms',
        );

        for (final m in pendingMetaList) {
          if (cancelToken.isCancelled) {
            throw dio.DioException(
              requestOptions: dio.RequestOptions(path: ''),
              type: dio.DioExceptionType.cancel,
            );
          }
          final entries = await _resolveAlbumMetaToEntries(m, task);
          for (final item in entries) {
            if (cancelToken.isCancelled) {
              throw dio.DioException(
                requestOptions: dio.RequestOptions(path: ''),
                type: dio.DioExceptionType.cancel,
              );
            }
            runtime.currentFile.value = item.displayName;
            _syncBackupWorkNotification(runtime);
            final uploadedAt = DateTime.now().millisecondsSinceEpoch;
            String status = 'success';
            String error = '';
            try {
              final fileHash = sha256
                  .convert(
                    utf8.encode(
                      '${item.sourceUniqueId}|${item.size}|${item.fileMtimeMs}',
                    ),
                  )
                  .toString();
              final relPath = p.posix.join(task.sourceName, item.relativePath);
              await UploadCore.processFile(
                dioClient: _dio,
                baseUrl: baseUrl,
                token: token,
                fileRef: XFile(item.localPath, name: item.displayName),
                fileName: item.displayName,
                fileSize: item.size,
                remotePath: task.targetDir,
                nameStrategy: task.nameStrategy,
                saveType: task.saveType.isEmpty ? null : task.saveType,
                fileHash: fileHash,
                cancelToken: cancelToken,
                relativePath: relPath,
                fileMtimeMs: item.fileMtimeMs,
                fileBirthtimeMs: item.orderMs > 0 ? item.orderMs : null,
                onProgress: (increment) {
                  runtime.doneBytes.value += increment;
                  _syncBackupWorkNotification(runtime);
                },
                onCompleted: (_) {},
              );
              successCount += 1;
              consumedBytes += item.size;
              await _storage.upsertCursor(
                taskId: task.id,
                lastCreatedAtMs: item.orderMs,
                lastUniqueId: item.sourceUniqueId,
              );
            } catch (e) {
              status = 'error';
              error = _errorMessage(e);
              runtime.error.value = error;
              failedCount += 1;
            } finally {
              await _storage.insertFileRecord(
                taskId: task.id,
                runId: runId,
                sourceUniqueId: item.sourceUniqueId,
                displayName: item.displayName,
                localPath: item.localPath,
                size: item.size,
                sourceCreateAtMs: item.orderMs,
                uploadedAtMs: uploadedAt,
                status: status,
                error: error,
              );
              // iOS 上 originFile 可能导出到沙盒 tmp/cache，上传完成后可清理避免残留。
              await UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(
                item.localPath,
              );
              runtime.doneFiles.value += 1;
              if (runtime.totalBytes.value > 0 &&
                  runtime.doneBytes.value > runtime.totalBytes.value) {
                runtime.doneBytes.value = runtime.totalBytes.value;
              }
            }
            if (status == 'error') break;
          }
          if (failedCount > 0) break;
        }
        await _storage.finishRun(
          runId: runId,
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          successCount: successCount,
          failedCount: failedCount,
          totalBytes: consumedBytes,
        );
        runtime.status.value = failedCount > 0 ? 'error' : 'idle';
        return;
      }

      // 相册全量 / 文件夹：先拿到完整 _SourceEntry 列表再上传
      final swScan = Stopwatch()..start();
      final String scanBranch =
          task.sourceType == PhotoBackupSourceType.album && !modeAll
          ? 'scanAlbum(full)'
          : 'scanFolder';
      _photoBackupLog('scanBranch', scanBranch);
      final sourceEntries =
          task.sourceType == PhotoBackupSourceType.album && !modeAll
          ? await _scanAlbum(task)
          : await _scanSource(task);
      _photoBackupLog(
        'scanSource done',
        '${swScan.elapsedMilliseconds}ms, entries=${sourceEntries.length}',
      );
      if (sourceEntries.isEmpty) {
        await _storage.finishRun(
          runId: runId,
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          successCount: 0,
          failedCount: 0,
          totalBytes: 0,
        );
        runtime.error.value = task.sourceType == PhotoBackupSourceType.album
            ? 'photo_backup_no_files_album'.tr
            : 'photo_backup_no_files_folder'.tr;
        runtime.status.value = 'idle';
        runtime.running.value = false;
        return;
      }

      final pending = sourceEntries
          .where((entry) {
            if (cursor == null) return true;
            if (entry.orderMs > cursor.lastCreatedAtMs) return true;
            if (entry.orderMs < cursor.lastCreatedAtMs) return false;
            return entry.sourceUniqueId.compareTo(cursor.lastUniqueId) > 0;
          })
          .toList(growable: false);

      if (pending.isEmpty) {
        await _storage.finishRun(
          runId: runId,
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          successCount: 0,
          failedCount: 0,
          totalBytes: 0,
        );
        runtime.status.value = 'idle';
        runtime.running.value = false;
        return;
      }

      runtime.totalFiles.value = pending.length;
      runtime.totalBytes.value = 0;
      _photoBackupLog('pending count', pending.length);
      _photoBackupLog(
        'upload loop start (total so far)',
        '${runTotal.elapsedMilliseconds}ms',
      );

      for (final item in pending) {
        if (cancelToken.isCancelled) {
          throw dio.DioException(
            requestOptions: dio.RequestOptions(path: ''),
            type: dio.DioExceptionType.cancel,
          );
        }
        runtime.currentFile.value = item.displayName;
        _syncBackupWorkNotification(runtime);
        final uploadedAt = DateTime.now().millisecondsSinceEpoch;
        String status = 'success';
        String error = '';
        try {
          final fileHash = sha256
              .convert(
                utf8.encode(
                  '${item.sourceUniqueId}|${item.size}|${item.fileMtimeMs}',
                ),
              )
              .toString();
          final relPath = p.posix.join(task.sourceName, item.relativePath);
          await UploadCore.processFile(
            dioClient: _dio,
            baseUrl: baseUrl,
            token: token,
            fileRef: XFile(item.localPath, name: item.displayName),
            fileName: item.displayName,
            fileSize: item.size,
            remotePath: task.targetDir,
            nameStrategy: task.nameStrategy,
            saveType: task.saveType.isEmpty ? null : task.saveType,
            fileHash: fileHash,
            cancelToken: cancelToken,
            relativePath: relPath,
            fileMtimeMs: item.fileMtimeMs,
            fileBirthtimeMs: item.orderMs > 0 ? item.orderMs : null,
            onProgress: (increment) {
              runtime.doneBytes.value += increment;
              _syncBackupWorkNotification(runtime);
            },
            onCompleted: (_) {},
          );
          successCount += 1;
          consumedBytes += item.size;
          await _storage.upsertCursor(
            taskId: task.id,
            lastCreatedAtMs: item.orderMs,
            lastUniqueId: item.sourceUniqueId,
          );
        } catch (e) {
          status = 'error';
          error = _errorMessage(e);
          runtime.error.value = error;
          failedCount += 1;
        } finally {
          await _storage.insertFileRecord(
            taskId: task.id,
            runId: runId,
            sourceUniqueId: item.sourceUniqueId,
            displayName: item.displayName,
            localPath: item.localPath,
            size: item.size,
            sourceCreateAtMs: item.orderMs,
            uploadedAtMs: uploadedAt,
            status: status,
            error: error,
          );
          // iOS 上 originFile 可能导出到沙盒 tmp/cache，上传完成后可清理避免残留。
          await UploadTempFileCleaner.instance.maybeDeleteSandboxTempFile(
            item.localPath,
          );
          runtime.doneFiles.value += 1;
          if (runtime.totalBytes.value > 0 &&
              runtime.doneBytes.value > runtime.totalBytes.value) {
            runtime.doneBytes.value = runtime.totalBytes.value;
          }
        }

        if (status == 'error') {
          break;
        }
      }

      await _storage.finishRun(
        runId: runId,
        finishedAtMs: DateTime.now().millisecondsSinceEpoch,
        successCount: successCount,
        failedCount: failedCount,
        totalBytes: consumedBytes,
      );

      runtime.status.value = failedCount > 0 ? 'error' : 'idle';
    } catch (e) {
      if (runId != null) {
        await _storage.finishRun(
          runId: runId,
          finishedAtMs: DateTime.now().millisecondsSinceEpoch,
          successCount: successCount,
          failedCount: failedCount > 0 ? failedCount : 1,
          totalBytes: consumedBytes,
        );
      }
      if (e is _PhotoBackupPermissionDeniedException) {
        runtime.status.value = 'idle';
        runtime.error.value = '';
      } else if (e is dio.DioException &&
          e.type == dio.DioExceptionType.cancel) {
        runtime.status.value = 'idle';
        runtime.error.value = 'photo_backup_manual_cancel'.tr;
      } else {
        runtime.status.value = 'error';
        runtime.error.value = _errorMessage(e);
      }
    } finally {
      unawaited(TransferWorkNotificationHub.instance.backupWorkEnded());
      runtime.running.value = false;
      runtime.currentFile.value = '';
      _cancelTokens.remove(task.id);
      _wakelockRefCount -= 1;
      if (_wakelockRefCount <= 0) {
        _wakelockRefCount = 0;
        WakelockPlus.disable();
      }
      _photoBackupLog('_run total', '${runTotal.elapsedMilliseconds}ms');
    }
  }

  String _triggerValue(PhotoBackupRunTrigger trigger) {
    switch (trigger) {
      case PhotoBackupRunTrigger.uploadAll:
        return 'upload_all';
      case PhotoBackupRunTrigger.autoStart:
        return 'auto_start';
      case PhotoBackupRunTrigger.uploadNew:
        return 'upload_new';
    }
  }

  Future<List<_SourceEntry>> _scanSource(PhotoBackupTask task) async {
    if (task.sourceType == PhotoBackupSourceType.folder) {
      return await _scanFolder(task);
    }
    return await _scanAlbum(task);
  }

  Future<List<_SourceEntry>> _scanFolder(PhotoBackupTask task) async {
    final root = task.sourceId.trim();
    if (root.isEmpty) return const <_SourceEntry>[];
    final rootDir = Directory(root);
    if (!await rootDir.exists()) return const <_SourceEntry>[];
    final sw = Stopwatch()..start();
    final out = <_SourceEntry>[];
    await for (final entity in rootDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.size <= 0) continue;
      final rel = p.relative(entity.path, from: root);
      final relPosix = p.posix.joinAll(p.split(rel));
      final fileName = p.basename(relPosix);
      if (UploadTransferHelper.shouldIgnore(fileName)) continue;
      final orderMs = stat.modified.millisecondsSinceEpoch;
      out.add(
        _SourceEntry(
          sourceUniqueId: relPosix,
          displayName: fileName,
          localPath: entity.path,
          relativePath: relPosix,
          orderMs: orderMs,
          size: stat.size,
          fileMtimeMs: orderMs,
        ),
      );
    }
    _photoBackupLog(
      '_scanFolder list+stat',
      '${sw.elapsedMilliseconds}ms count=${out.length}',
    );
    out.sort((a, b) {
      final c = a.orderMs.compareTo(b.orderMs);
      if (c != 0) return c;
      return a.sourceUniqueId.compareTo(b.sourceUniqueId);
    });
    return out;
  }

  /// 与创建任务时表单逻辑一致：使用 photo_manager 请求/判断权限（与枚举相册同源），
  /// 已授权或限权均视为可访问；避免 iOS 上 permission_handler 与 Photos 框架状态不一致。
  /// 未授权时弹窗引导用户前往设置，不只在卡片上显示错误文案。
  Future<bool> _ensurePhotoPermission() async {
    final sw = Stopwatch()..start();
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return true;
    }
    final pm.PermissionState state =
        await pm.PhotoManager.requestPermissionExtend();
    if (state.hasAccess) {
      _photoBackupLog(
        '_ensurePhotoPermission',
        '${sw.elapsedMilliseconds}ms (hasAccess)',
      );
      return true;
    }

    _photoBackupLog(
      '_ensurePhotoPermission',
      '${sw.elapsedMilliseconds}ms (no access)',
    );
    ToastUtil.show('photo_library_permission_missing'.tr);
    return false;
  }

  /// 打开应用设置。iOS 上先提示并延迟再打开，减少从设置返回时的崩溃（见 permission_handler/photo_manager 已知问题）。
  /// 供本控制器及相册备份页面等调用。
  void openAppSettingsForPhotoPermission() {
    if (Platform.isIOS) {
      ToastUtil.show('permission_open_settings_ios_hint'.tr);
      Future.delayed(const Duration(milliseconds: 500), () {
        openAppSettings();
      });
    } else {
      openAppSettings();
    }
  }

  Future<List<_SourceEntry>> _scanAlbum(PhotoBackupTask task) async {
    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      throw _PhotoBackupPermissionDeniedException();
    }

    final swPath = Stopwatch()..start();
    final all = await pm.PhotoManager.getAssetPathList(
      type: pm.RequestType.common,
      hasAll: true,
    );
    final pathEntity = all.firstWhereOrNull((e) => e.id == task.sourceId);
    _photoBackupLog(
      '_scanAlbum getAssetPathList',
      '${swPath.elapsedMilliseconds}ms',
    );
    if (pathEntity == null) {
      throw Exception('photo_backup_album_not_found'.tr);
    }

    final out = <_SourceEntry>[];
    int page = 0;
    const pageSize = 200;
    while (true) {
      final swPage = Stopwatch()..start();
      final list = await pathEntity.getAssetListPaged(
        page: page,
        size: pageSize,
      );
      if (list.isEmpty) break;
      _photoBackupLog(
        '_scanAlbum getAssetListPaged page=$page',
        '${swPage.elapsedMilliseconds}ms count=${list.length}',
      );
      final swOrigin = Stopwatch()..start();
      for (final item in list) {
        final file = await item.originFile;
        if (file == null) continue;
        final size = await file.length();
        if (size <= 0) continue;
        final name = (await item.titleAsync).trim();
        final displayName = name.isEmpty ? p.basename(file.path) : name;
        final orderMs = item.createDateTime.millisecondsSinceEpoch;
        out.add(
          _SourceEntry(
            sourceUniqueId: item.id,
            displayName: displayName,
            localPath: file.path,
            relativePath: displayName,
            orderMs: orderMs,
            size: size,
            fileMtimeMs: file.statSync().modified.millisecondsSinceEpoch,
          ),
        );

        if (!task.uploadLivePhotoVideo) continue;
        try {
          final liveVideo = await item.originFileWithSubtype;
          if (liveVideo == null) continue;
          if (liveVideo.path == file.path) continue;
          final lvSize = await liveVideo.length();
          if (lvSize <= 0) continue;
          final lvName = '${p.basenameWithoutExtension(displayName)}.MOV';
          out.add(
            _SourceEntry(
              sourceUniqueId: '${item.id}#live',
              displayName: lvName,
              localPath: liveVideo.path,
              relativePath: lvName,
              orderMs: orderMs,
              size: lvSize,
              fileMtimeMs: liveVideo.statSync().modified.millisecondsSinceEpoch,
            ),
          );
        } catch (_) {}
      }
      _photoBackupLog(
        '_scanAlbum page=$page originFile+build',
        '${swOrigin.elapsedMilliseconds}ms',
      );
      if (list.length < pageSize) break;
      page += 1;
    }

    final swSort = Stopwatch()..start();
    out.sort((a, b) {
      final c = a.orderMs.compareTo(b.orderMs);
      if (c != 0) return c;
      return a.sourceUniqueId.compareTo(b.sourceUniqueId);
    });
    _photoBackupLog(
      '_scanAlbum sort',
      '${swSort.elapsedMilliseconds}ms total=${out.length}',
    );
    return out;
  }

  /// 上传新增专用：只拉「创建时间 ≥ cursor」的 AssetEntity 列表（不读 originFile），上传时再按需解析。
  Future<List<_AlbumAssetMeta>> _scanAlbumPendingMeta(
    PhotoBackupTask task,
    PhotoBackupCursor cursor,
  ) async {
    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      throw _PhotoBackupPermissionDeniedException();
    }

    final minTime = DateTime.fromMillisecondsSinceEpoch(cursor.lastCreatedAtMs);
    final maxTime = DateTime.now().add(const Duration(days: 1));
    final filter = pm.FilterOptionGroup(
      createTimeCond: pm.DateTimeCond(min: minTime, max: maxTime),
    );
    pm.AssetPathEntity? pathEntity;
    final swFromId = Stopwatch()..start();
    try {
      pathEntity = await pm.AssetPathEntity.fromId(
        task.sourceId,
        filterOption: filter,
        type: pm.RequestType.common,
      );
    } catch (_) {
      throw Exception('photo_backup_album_not_found'.tr);
    }
    _photoBackupLog(
      '_scanAlbumPendingMeta fromId(createTimeCond)',
      '${swFromId.elapsedMilliseconds}ms',
    );

    final pendingMeta = <_AlbumAssetMeta>[];
    int page = 0;
    const pageSize = 500;
    while (true) {
      final swPage = Stopwatch()..start();
      final list = await pathEntity.getAssetListPaged(
        page: page,
        size: pageSize,
      );
      if (list.isEmpty) break;
      _photoBackupLog(
        '_scanAlbumPendingMeta getAssetListPaged page=$page',
        '${swPage.elapsedMilliseconds}ms count=${list.length}',
      );
      for (final item in list) {
        final orderMs = item.createDateTime.millisecondsSinceEpoch;
        if (orderMs < cursor.lastCreatedAtMs) continue;
        if (orderMs == cursor.lastCreatedAtMs &&
            item.id.compareTo(cursor.lastUniqueId) <= 0) {
          continue;
        }
        pendingMeta.add(_AlbumAssetMeta(entity: item, orderMs: orderMs));
      }
      if (list.length < pageSize) break;
      page += 1;
    }
    pendingMeta.sort((a, b) {
      final c = a.orderMs.compareTo(b.orderMs);
      if (c != 0) return c;
      return a.entity.id.compareTo(b.entity.id);
    });
    _photoBackupLog(
      '_scanAlbumPendingMeta done',
      'count=${pendingMeta.length}',
    );
    return pendingMeta;
  }

  /// 上传该条相册资源时再解析：取 originFile、size、displayName 等，含主图 + 可选 Live 视频。
  Future<List<_SourceEntry>> _resolveAlbumMetaToEntries(
    _AlbumAssetMeta m,
    PhotoBackupTask task,
  ) async {
    final item = m.entity;
    final file = await item.originFile;
    if (file == null) return const [];
    final size = await file.length();
    if (size <= 0) return const [];
    final name = (await item.titleAsync).trim();
    final displayName = name.isEmpty ? p.basename(file.path) : name;
    final entries = <_SourceEntry>[
      _SourceEntry(
        sourceUniqueId: item.id,
        displayName: displayName,
        localPath: file.path,
        relativePath: displayName,
        orderMs: m.orderMs,
        size: size,
        fileMtimeMs: file.statSync().modified.millisecondsSinceEpoch,
      ),
    ];
    if (!task.uploadLivePhotoVideo) return entries;
    try {
      final liveVideo = await item.originFileWithSubtype;
      if (liveVideo == null || liveVideo.path == file.path) return entries;
      final lvSize = await liveVideo.length();
      if (lvSize <= 0) return entries;
      final lvName = '${p.basenameWithoutExtension(displayName)}.MOV';
      entries.add(
        _SourceEntry(
          sourceUniqueId: '${item.id}#live',
          displayName: lvName,
          localPath: liveVideo.path,
          relativePath: lvName,
          orderMs: m.orderMs,
          size: lvSize,
          fileMtimeMs: liveVideo.statSync().modified.millisecondsSinceEpoch,
        ),
      );
    } catch (_) {}
    return entries;
  }

  /// 按页拉取相册资源并逐批 yield，不先全量扫描，便于立即开始上传。
  /// 每批内按 orderMs（创建时间）再按 sourceUniqueId 排序；批与批之间依赖系统 API 的页顺序（一般为时间序）。
  Stream<List<_SourceEntry>> _scanAlbumBatched(
    PhotoBackupTask task,
    PhotoBackupCursor? cursor,
  ) async* {
    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      throw _PhotoBackupPermissionDeniedException();
    }
    final swPath = Stopwatch()..start();
    final all = await pm.PhotoManager.getAssetPathList(
      type: pm.RequestType.common,
      hasAll: true,
    );
    final pathEntity = all.firstWhereOrNull((e) => e.id == task.sourceId);
    _photoBackupLog(
      '_scanAlbumBatched getAssetPathList',
      '${swPath.elapsedMilliseconds}ms',
    );
    if (pathEntity == null) {
      throw Exception('photo_backup_album_not_found'.tr);
    }
    const pageSize = 80;
    int page = 0;
    while (true) {
      final swPage = Stopwatch()..start();
      final list = await pathEntity.getAssetListPaged(
        page: page,
        size: pageSize,
      );
      if (list.isEmpty) break;
      _photoBackupLog(
        '_scanAlbumBatched getAssetListPaged page=$page',
        '${swPage.elapsedMilliseconds}ms count=${list.length}',
      );
      final swOrigin = Stopwatch()..start();
      final out = <_SourceEntry>[];
      for (final item in list) {
        final file = await item.originFile;
        if (file == null) continue;
        final size = await file.length();
        if (size <= 0) continue;
        final name = (await item.titleAsync).trim();
        final displayName = name.isEmpty ? p.basename(file.path) : name;
        final orderMs = item.createDateTime.millisecondsSinceEpoch;
        final entry = _SourceEntry(
          sourceUniqueId: item.id,
          displayName: displayName,
          localPath: file.path,
          relativePath: displayName,
          orderMs: orderMs,
          size: size,
          fileMtimeMs: file.statSync().modified.millisecondsSinceEpoch,
        );
        if (cursor != null) {
          if (orderMs < cursor.lastCreatedAtMs) continue;
          if (orderMs == cursor.lastCreatedAtMs &&
              entry.sourceUniqueId.compareTo(cursor.lastUniqueId) <= 0) {
            continue;
          }
        }
        out.add(entry);
        if (!task.uploadLivePhotoVideo) continue;
        try {
          final liveVideo = await item.originFileWithSubtype;
          if (liveVideo == null) continue;
          if (liveVideo.path == file.path) continue;
          final lvSize = await liveVideo.length();
          if (lvSize <= 0) continue;
          final lvName = '${p.basenameWithoutExtension(displayName)}.MOV';
          final lvEntry = _SourceEntry(
            sourceUniqueId: '${item.id}#live',
            displayName: lvName,
            localPath: liveVideo.path,
            relativePath: lvName,
            orderMs: orderMs,
            size: lvSize,
            fileMtimeMs: liveVideo.statSync().modified.millisecondsSinceEpoch,
          );
          if (cursor != null) {
            if (lvEntry.orderMs < cursor.lastCreatedAtMs) continue;
            if (lvEntry.orderMs == cursor.lastCreatedAtMs &&
                lvEntry.sourceUniqueId.compareTo(cursor.lastUniqueId) <= 0) {
              continue;
            }
          }
          out.add(lvEntry);
        } catch (_) {}
      }
      if (out.isNotEmpty) {
        _photoBackupLog(
          '_scanAlbumBatched page=$page originFile+build',
          '${swOrigin.elapsedMilliseconds}ms yield=${out.length}',
        );
        out.sort((a, b) {
          final c = a.orderMs.compareTo(b.orderMs);
          if (c != 0) return c;
          return a.sourceUniqueId.compareTo(b.sourceUniqueId);
        });
        yield out;
      }
      if (list.length < pageSize) break;
      page += 1;
    }
  }
}

/// 相册权限未授予且已弹窗引导用户去设置，不再在卡片上显示错误文案。
class _PhotoBackupPermissionDeniedException implements Exception {}

class _Identity {
  final String serverId;
  final int userId;
  const _Identity({required this.serverId, required this.userId});
}

class _SourceEntry {
  final String sourceUniqueId;
  final String displayName;
  final String localPath;
  final String relativePath;
  final int orderMs;
  final int size;
  final int fileMtimeMs;

  const _SourceEntry({
    required this.sourceUniqueId,
    required this.displayName,
    required this.localPath,
    required this.relativePath,
    required this.orderMs,
    required this.size,
    required this.fileMtimeMs,
  });
}

class _AlbumAssetMeta {
  final pm.AssetEntity entity;
  final int orderMs;

  const _AlbumAssetMeta({required this.entity, required this.orderMs});
}
