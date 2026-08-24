part of '../download_controller.dart';

/// 桌面端下载 Worker Mixin
/// 专门负责处理桌面端（Windows/Linux/MacOS）的直接下载逻辑
/// 使用 Dio 实现断点续传和流式下载
mixin DesktopDownloadWorkerMixin on DownloadStateMixin {
  // Expected to be implemented by the class mixing this in (DownloadWorkerMixin/DownloadController)
  void handleDownloadUpdate(NascabTaskUpdate update);

  /// 启动桌面端直接下载
  /// [taskId] 任务ID
  /// [url] 下载链接
  /// [savePath] 保存路径（包含文件名）
  /// [originalPath] 原始路径（用于下载完成后重命名）
  /// [parentId] 父任务ID
  /// [name] 显示名称
  /// [remotePathForRefresh] 非空时每次请求用当前 [ApiController.getDownloadUrl] 重建 URL（直连/P2P 切换后续传）
  Future<void> startDesktopDirectDownload(
    String taskId,
    String url,
    String savePath,
    String originalPath,
    String parentId,
    String name, {
    String? remotePathForRefresh,
  }) async {
    final task = NascabDownloadWorkerTask(
      taskId: taskId,
      url: url,
      filename: p.basename(savePath),
      directory: p.dirname(savePath),
      metaData: parentId,
      displayName: name,
    );

    activeDownloadTasks[taskId] = task;

    // Initial progress / Resume check
    print("Desktop Download: $savePath");
    final file = File(savePath);
    int receivedBytes = 0;
    if (file.existsSync()) {
      receivedBytes = file.lengthSync();
    }
    // fileProcessedBytes updated in handleDownloadUpdate

    final cancelToken = dio.CancelToken();
    desktopCancelTokens[taskId] = cancelToken;

    // Auto-retry configuration
    const int maxRetries = 3;
    const Duration timeout = Duration(seconds: 10); // Configurable timeout
    int retryCount = 0;

    Future<void> performDownload() async {
      try {
        // Send initial status
        handleDownloadUpdate(NascabTaskStatusUpdate(task, NascabTaskStatus.running));

        final dioClient = createDioWithBadCertificateCompat();

        // Range header for resume
        // Re-check receivedBytes as it might change on retry
        int initialBytes = 0;
        if (file.existsSync()) {
          initialBytes = file.lengthSync();
        }
        receivedBytes = initialBytes;

        final requestUrl =
            (remotePathForRefresh != null && remotePathForRefresh.isNotEmpty)
            ? ApiController.instance.getDownloadUrl([remotePathForRefresh])
            : url;
        final requestHeaders = _buildAuthHeadersForUrl(
          requestUrl,
          extraHeaders: initialBytes > 0 ? {'Range': 'bytes=$initialBytes-'} : null,
        );

        final options = dio.Options(
          responseType: dio.ResponseType.stream,
          headers: requestHeaders,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: timeout,
          sendTimeout: timeout,
        );

        final response = await dioClient.get<dio.ResponseBody>(
          requestUrl,
          options: options,
          cancelToken: cancelToken,
        );

        final inferred = _inferFileTotalFromDioResponse(response);
        if (inferred != null) {
          mergeInferredFileTotalForChild(parentId, taskId, inferred);
        }

        // Check status code for resume validity
        if (initialBytes > 0 && response.statusCode != 206) {
          print(
            "Desktop Download: Server returned ${response.statusCode} for range request. Resetting download.",
          );
          initialBytes = 0;
          receivedBytes = 0;
          if (file.existsSync()) {
            file.deleteSync();
            file.createSync();
          }
        }

        if (response.statusCode != 200 && response.statusCode != 206) {
          final code = response.statusCode ?? 0;
          throw NascabTaskHttpException(
            code == 403 ? 'permission_denied' : 'HTTP $code',
            code,
          );
        }

        final stream = response.data!.stream;
        final sink = file.openWrite(mode: FileMode.append);

        int streamBytes = 0;

        // Listen to stream
        final subscription = stream.listen((data) {
          try {
            sink.add(data);
            streamBytes += data.length;
            receivedBytes = initialBytes + streamBytes;

            final total = fileSizes[taskId] ?? 0;
            double progress = 0.0;
            if (total > 0) {
              progress = receivedBytes / total;
            }
            // 触发进度更新，这里会更新 fileProcessedBytes 和父任务进度
            handleDownloadUpdate(NascabTaskProgressUpdate(task, progress));
          } catch (e) {
            print("Sink write error: $e");
            // If write fails, it might be disk full or permission.
            // Throwing here to trigger onError
            rethrow;
          }
        }, cancelOnError: true);

        final completer = Completer<void>();

        subscription.onDone(() async {
          print("Desktop Download: Stream done.");
          try {
            await sink.flush();
            await sink.close();
          } catch (e) {
            print("Error closing sink: $e");
          }

          // 连接被对端关闭（例如切换直连/P2P、代理断开）时，流仍会正常结束，
          // 必须按实际文件大小与已知总大小比对，避免半文件被误判为已完成。
          final expected = fileSizes[taskId] ?? 0;
          final actual = file.existsSync() ? file.lengthSync() : 0;
          if (expected > 0 && actual < expected) {
            print(
              "Desktop Download: Incomplete ($actual/$expected bytes), "
              "treating as connection drop.",
            );
            if (retryCount < maxRetries) {
              retryCount++;
              print(
                "Desktop Download: Retrying ($retryCount/$maxRetries) after incomplete stream.",
              );
              await Future.delayed(const Duration(seconds: 2));
              await performDownload();
              completer.complete();
              return;
            }
            desktopCancelTokens.remove(taskId);
            handleDownloadUpdate(
              NascabTaskStatusUpdate(
                task,
                NascabTaskStatus.failed,
                NascabTaskException('download_incomplete'),
              ),
            );
            completer.complete();
            return;
          }

          desktopCancelTokens.remove(taskId);
          handleDownloadUpdate(NascabTaskStatusUpdate(task, NascabTaskStatus.complete));
          completer.complete();
        });

        subscription.onError((e) async {
          print("Desktop Download: Error: $e");
          try {
            await sink.close();
          } catch (_) {}

          // 403 权限错误不重试，立即结束并设置错误信息
          final is403 = e is NascabTaskHttpException && e.httpResponseCode == 403;
          if (!is403 &&
              e is dio.DioException &&
              !dio.CancelToken.isCancel(e) &&
              retryCount < maxRetries) {
            retryCount++;
            print(
              "Desktop Download: Retrying ($retryCount/$maxRetries) after error: $e",
            );
            await Future.delayed(const Duration(seconds: 2));
            await performDownload(); // Recursive retry
            completer.complete();
            return;
          }

          desktopCancelTokens.remove(taskId);
          if (e is dio.DioException && dio.CancelToken.isCancel(e)) {
            handleDownloadUpdate(NascabTaskStatusUpdate(task, NascabTaskStatus.canceled));
          } else {
            handleDownloadUpdate(
              NascabTaskStatusUpdate(
                task,
                NascabTaskStatus.failed,
                e is NascabTaskHttpException
                    ? e
                    : NascabTaskException(e.toString()),
              ),
            );
          }
          completer.complete();
        });

        await completer.future;
      } catch (e) {
        // Top level catch；403 权限错误不重试
        final is403 = e is NascabTaskHttpException && e.httpResponseCode == 403;
        if (!is403 &&
            e is dio.DioException &&
            !dio.CancelToken.isCancel(e) &&
            retryCount < maxRetries) {
          retryCount++;
          print(
            "Desktop Download: Retrying ($retryCount/$maxRetries) after catch: $e",
          );
          await Future.delayed(const Duration(seconds: 2));
          await performDownload();
          return;
        }

        desktopCancelTokens.remove(taskId);
        if (e is dio.DioException && dio.CancelToken.isCancel(e)) {
          handleDownloadUpdate(NascabTaskStatusUpdate(task, NascabTaskStatus.canceled));
        } else {
          handleDownloadUpdate(
            NascabTaskStatusUpdate(
              task,
              NascabTaskStatus.failed,
              e is NascabTaskHttpException
                  ? e
                  : NascabTaskException(e.toString()),
            ),
          );
        }
      }
    }

    unawaited(TransferWorkNotificationHub.instance.downloadWorkBegan());
    try {
      await performDownload();
    } finally {
      unawaited(TransferWorkNotificationHub.instance.downloadWorkEnded());
    }
  }
}
