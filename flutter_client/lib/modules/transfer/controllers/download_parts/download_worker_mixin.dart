part of '../download_controller.dart';

/// 从 Content-Range / Content-Length 推断完整文件字节数（用于列表未给 size 时的完整性校验）。
int? _inferFileTotalBytesFromHttp(
  int statusCode,
  String? contentRange,
  String? contentLength,
) {
  final cr = contentRange?.trim();
  if (cr != null && cr.contains('/')) {
    final totalStr = cr.split('/').last.trim();
    if (totalStr != '*') {
      final t = int.tryParse(totalStr);
      if (t != null && t > 0) return t;
    }
  }
  if (statusCode == 200) {
    final cl = contentLength?.trim();
    if (cl != null && cl.isNotEmpty) {
      final t = int.tryParse(cl);
      if (t != null && t > 0) return t;
    }
  }
  return null;
}

int? _inferFileTotalFromDioResponse(dio.Response<dio.ResponseBody> response) {
  return _inferFileTotalBytesFromHttp(
    response.statusCode ?? 0,
    response.headers.value('content-range'),
    response.headers.value('content-length'),
  );
}

int? _inferFileTotalFromP2pResponse(
  int statusCode,
  Map<String, String> headers,
) {
  String? ci(String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  return _inferFileTotalBytesFromHttp(
    statusCode,
    ci('content-range'),
    ci('content-length'),
  );
}

String? _safeJoinWithin(String baseDir, String unsafeRel) {
  final base = baseDir.trim();
  final rel = unsafeRel.trim();
  if (base.isEmpty || rel.isEmpty) return null;
  if (p.isAbsolute(rel)) return null;
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(rel)) return null;
  if (rel.contains('\u0000')) return null;
  final candidate = p.normalize(p.join(base, rel));
  final baseNorm = p.normalize(base);
  if (p.equals(candidate, baseNorm) || p.isWithin(baseNorm, candidate)) {
    return candidate;
  }
  return null;
}

bool _isSafePathSegment(String name) {
  final n = name.trim();
  if (n.isEmpty) return false;
  if (n == '.' || n == '..') return false;
  if (n.contains('/') || n.contains('\\')) return false;
  if (n.contains('\u0000')) return false;
  return true;
}

/// 通用下载 Worker Mixin
/// 处理任务添加、队列管理、文件/文件夹下载逻辑以及进度更新
mixin DownloadWorkerMixin on DesktopDownloadWorkerMixin {
  bool _isUrl(String path) {
    final uri = Uri.tryParse(path);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  bool _shouldUseP2pDownloadUrl(String url) {
    final api = ApiController.instance;
    if (!api.isP2pMode) return false;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    return uri.origin.trim() == ApiController.p2pBaseUrl;
  }

  /// 获取文件名（处理Windows路径分隔符）
  String _getBasename(String path) {
    if (_isUrl(path)) {
      final uri = Uri.parse(path);
      final qName = uri.queryParameters['fileName'];
      if (qName != null && qName.trim().isNotEmpty) {
        final name = qName.replaceAll('\\', '/');
        return p.basename(name);
      }
      final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      final name = seg.isNotEmpty ? seg : 'download';
      return name;
    }
    String name = path.replaceAll('\\', '/');
    return p.basename(name);
  }

  /// 获取不重复的文件路径
  /// 如果路径已存在，则添加 (1), (2) 等后缀
  String _getUniquePath(String path) {
    if (!File(path).existsSync()) return path;

    final dir = p.dirname(path);
    final name = p.basenameWithoutExtension(path);
    final ext = p.extension(path);

    int i = 1;
    while (true) {
      final newPath = p.join(dir, '$name($i)$ext');
      if (!File(newPath).existsSync()) return newPath;
      i++;
    }
  }

  bool _isImagePath(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.tiff') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  bool _isVideoPath(String filePath) {
    final lower = filePath.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp');
  }

  /// 将已下载文件复制到系统「下载」目录下可见子路径（替代 background_downloader 的 moveFileToSharedStorage）。
  Future<String?> _exposeAndroidDownloadInPublicStorage({
    required String sourcePath,
    required int childrenCount,
    required String parentName,
    required String parentLocalPath,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;
      final downloads = await getDownloadsDirectory();
      if (downloads == null) return null;

      String? relDir;
      if (childrenCount > 1) {
        try {
          relDir = p.relative(
            p.dirname(sourcePath),
            from: parentLocalPath,
          );
          if (relDir == '.' || relDir.isEmpty) relDir = null;
        } catch (_) {
          relDir = null;
        }
      }

      final baseSharedDir =
          childrenCount > 1 && parentName.trim().isNotEmpty
          ? p.join('NasCabDownload', parentName.trim())
          : 'NasCabDownload';
      final sub = relDir == null ? baseSharedDir : p.join(baseSharedDir, relDir);

      final destDir = Directory(p.join(downloads.path, sub));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      final baseName = p.basename(sourcePath);
      var destPath = p.join(destDir.path, baseName);
      var destFile = File(destPath);
      var i = 1;
      while (await destFile.exists()) {
        destPath = p.join(
          destDir.path,
          '${p.basenameWithoutExtension(baseName)}($i)${p.extension(baseName)}',
        );
        destFile = File(destPath);
        i++;
      }
      await src.copy(destPath);
      return destPath;
    } catch (e) {
      print('_exposeAndroidDownloadInPublicStorage: $e');
      return null;
    }
  }

  Future<bool> _ensureIosAddToPhotosPermission() async {
    if (!Platform.isIOS) return false;
    try {
      // 保存到相册主要对应「仅添加」权限；先走 permission_handler，与系统设置项一致。
      final addCurrent = await Permission.photosAddOnly.status;
      if (addCurrent.isGranted || addCurrent.isLimited) {
        return true;
      }
      final addReq = await Permission.photosAddOnly.request();
      if (addReq.isGranted || addReq.isLimited) {
        return true;
      }

      // 与相册备份一致：photo_manager 再请求一次（全库/限权等状态与系统对齐）
      final pmState = await pm.PhotoManager.requestPermissionExtend();
      if (pmState.hasAccess) {
        return true;
      }
      return false;
    } catch (e, st) {
      DownloadHistoryStorage.trace(
        '_ensureIosAddToPhotosPermission error',
        '$e\n$st',
      );
      return false;
    }
  }

  Future<bool> _ensureAndroidAddToPhotosPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      var photos = await Permission.photos.status;
      if (photos.isGranted || photos.isLimited) return true;
      photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;

      var videos = await Permission.videos.status;
      if (videos.isGranted || videos.isLimited) return true;
      videos = await Permission.videos.request();
      if (videos.isGranted || videos.isLimited) return true;

      final pmState = await pm.PhotoManager.requestPermissionExtend();
      return pmState.hasAccess;
    } catch (e, st) {
      DownloadHistoryStorage.trace(
        '_ensureAndroidAddToPhotosPermission error',
        '$e\n$st',
      );
      return false;
    }
  }

  /// 在已授权时把下载得到的图片/视频写入系统相册（iOS / Android）。
  Future<void> _saveDownloadedMediaToGalleryIfPermitted(
    String sourcePath, {
    required bool showToastOnFail,
  }) async {
    if (kIsWeb) return;
    if (!_isImagePath(sourcePath) && !_isVideoPath(sourcePath)) return;

    final ok = Platform.isIOS
        ? await _ensureIosAddToPhotosPermission()
        : Platform.isAndroid
        ? await _ensureAndroidAddToPhotosPermission()
        : false;
    if (!ok) return;

    try {
      if (_isImagePath(sourcePath)) {
        await pm.PhotoManager.editor.saveImageWithPath(
          sourcePath,
          title: p.basename(sourcePath),
          relativePath: Platform.isAndroid ? 'Pictures/NasCabDownload/' : null,
        );
      } else if (_isVideoPath(sourcePath)) {
        await pm.PhotoManager.editor.saveVideo(
          File(sourcePath),
          title: p.basename(sourcePath),
        );
      }
    } catch (_) {
      if (showToastOnFail) {
        ToastUtil.show('operation_failed'.tr);
      }
    }
  }

  /// 添加下载任务
  /// [paths] 远程文件路径列表
  /// [saveDir] 本地保存目录
  /// [remoteIsDirectoryHint] 与 [paths] 下标对齐：`true` 目录、`false` 文件、缺省或 `null` 表示该项未知。
  void addTasks(
    List<String> paths,
    String saveDir, {
    List<bool?>? remoteIsDirectoryHint,
  }) {
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final name = _getBasename(path);
      bool? dirHint;
      if (remoteIsDirectoryHint != null && i < remoteIsDirectoryHint.length) {
        dirHint = remoteIsDirectoryHint[i];
      }
      final task = TransferTask(
        id: '${DateTime.now().millisecondsSinceEpoch}_$name',
        name: name,
        localPath: p.join(saveDir, name),
        remotePath: path,
        type: TransferType.download,
        status: TransferStatus.pending,
        remoteIsDirectory: dirHint,
      );

      // 如果是单文件且已经计算过大小，直接使用
      if (paths.length == 1 && statsSize.value > 0) {
        task.totalSize = statsSize.value;
      }

      tasks.add(task);
      processTask(task);
    }
    ToastUtil.show('task_added'.tr);

    if (kIsWeb) return;

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop && Get.isRegistered<PcHomeController>()) {
      final home = PcHomeController.instance;
      final taskCenter = Get.isRegistered<TaskCenterController>()
          ? TaskCenterController.to
          : Get.put(TaskCenterController());
      taskCenter.jumpToPage(1);
      home.openApp(
        windowId: 'task_center',
        viewBuilder: home.builtinAppViewBuilder('task_center'),
        title: 'app_task_center'.tr,
        icon: home.buildAppIcon('task_center'),
      );
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      Get.to(() => const AppDownloadCenterView());
      return;
    }

    if (Get.isRegistered<AppHomeController>()) {
      AppHomeController.instance.openApp('task_center');
    }
  }

  /// 处理单个下载任务
  /// 区分文件和文件夹，递归处理
  Future<void> processTask(TransferTask task) async {
    task.status = TransferStatus.uploading;
    tasks.refresh();
    try {
      final refs = task.folderRefs;
      if (refs != null && refs.isNotEmpty) {
        final dir = Directory(task.localPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        if (task.totalSize <= 0) {
          int sum = 0;
          for (final r in refs) {
            final size = r['size'];
            if (size is num) sum += size.toInt();
          }
          task.totalSize = sum;
        }

        for (final r in refs) {
          if (task.status == TransferStatus.paused ||
              task.status == TransferStatus.error) {
            return;
          }

          final remote = (r['path'] ?? r['remotePath'] ?? '').toString();
          if (remote.isEmpty) continue;

          final relRaw = (r['rel'] ?? r['name'] ?? '').toString();
          final rel = relRaw.isNotEmpty ? relRaw : _getBasename(remote);

          final size = r['size'];
          final fileSize = size is num ? size.toInt() : 0;

          final local = _safeJoinWithin(task.localPath, rel);
          if (local == null) {
            DownloadHistoryStorage.trace(
              'processTask invalid local path (refs)',
              'base=${task.localPath} rel=$relRaw remote=$remote',
            );
            task.status = TransferStatus.error;
            task.error = 'api_code_file_invalid_params'.tr;
            tasks.refresh();
            return;
          }
          await downloadFile(task, remote, local, fileSize);
        }
        checkParentStatus(task);
        return;
      }

      if (task.totalSize == 0 && !_isUrl(task.remotePath)) {
        await fetchTaskSize(task);
      }
      if (_isUrl(task.remotePath)) {
        await downloadFile(
          task,
          task.remotePath,
          task.localPath,
          task.totalSize,
        );
        checkParentStatus(task);
        return;
      }
      bool isDir = false;
      final hint = task.remoteIsDirectory;
      if (hint != null) {
        isDir = hint;
        DownloadHistoryStorage.trace(
          'processTask use remoteIsDirectory hint (skip listDirectory)',
          'remote=${task.remotePath} isDir=$isDir',
        );
      } else {
        try {
          final attrs = await api.getPathAttributes(
            task.remotePath,
            showLoading: false,
          );
          if (attrs != null) {
            isDir = attrs['isDirectory'] == true;
            DownloadHistoryStorage.trace(
              'processTask getPathAttributes',
              'remote=${task.remotePath} isDir=$isDir isFile=${attrs['isFile']} size=${attrs['size']}',
            );
            if (!isDir && task.totalSize <= 0) {
              final sz = attrs['size'];
              if (sz is num) task.totalSize = sz.toInt();
            }
          } else {
            final res = await api.listDirectory(
              task.remotePath,
              onlyDir: false,
              showLoading: false,
            );
            final items = res['items'] as List?;
            if (res['targetIsFile'] == true) {
              isDir = false;
            } else if (items != null && items.isEmpty) {
              // 某些后端/权限场景下，对文件路径 listDirectory 可能返回空 items。
              // 若此处判定为目录会导致任务瞬间完成且不落下载历史。
              isDir = false;
            } else if (items != null) {
              final requested = p.normalize(task.remotePath.trim());
              final listedBase = p.normalize(
                (res['base'] ?? '').toString().trim(),
              );
              if (listedBase.isNotEmpty &&
                  requested.isNotEmpty &&
                  !p.equals(listedBase, requested)) {
                isDir = false;
              } else {
                isDir = true;
              }
            }
            DownloadHistoryStorage.trace(
              'processTask listDirectory fallback',
              'remote=${task.remotePath} targetIsFile=${res['targetIsFile']} '
                  'itemsLen=${items?.length} base=${res['base']} => isDir=$isDir',
            );
          }
        } catch (e, st) {
          DownloadHistoryStorage.trace(
            'processTask dir/file detect error',
            '$e\n$st',
          );
        }
      }
      if (isDir) {
        await downloadFolder(task, task.remotePath, task.localPath);
        checkParentStatus(task);
      } else {
        await downloadFile(
          task,
          task.remotePath,
          task.localPath,
          task.totalSize,
        );
      }
    } catch (e) {
      task.error = e.toString();
      task.status = TransferStatus.error;
      tasks.refresh();
    }
  }

  /// 获取任务大小（用于未预先计算大小的情况）
  Future<void> fetchTaskSize(TransferTask task) async {
    if (!_isUrl(task.remotePath)) {
      try {
        final attrs = await api.getPathAttributes(
          task.remotePath,
          showLoading: false,
        );
        if (attrs != null &&
            attrs['isFile'] == true &&
            task.totalSize <= 0) {
          final sz = attrs['size'];
          if (sz is num && sz.toInt() > 0) {
            task.totalSize = sz.toInt();
            return;
          }
        }
      } catch (_) {}
    }

    final completer = Completer<void>();
    final stats = FileStatsService();
    stats.connect(
      paths: [task.remotePath],
      onProgress: (s) {},
      onComplete: (s) {
        task.totalSize = s.size;
        completer.complete();
        stats.close();
      },
      onError: (err) {
        if (!completer.isCompleted) completer.complete();
        stats.close();
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }

  /// 递归下载文件夹
  Future<void> downloadFolder(
    TransferTask rootTask,
    String remotePath,
    String localPath,
  ) async {
    final dir = Directory(localPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final res = await api.listDirectory(remotePath, onlyDir: false);
    final items = res['items'] as List?;
    if (items == null) return;

    for (final item in items) {
      if (rootTask.status == TransferStatus.paused ||
          rootTask.status == TransferStatus.error) {
        return;
      }

      final name = (item['name'] ?? '').toString();
      if (!_isSafePathSegment(name)) {
        DownloadHistoryStorage.trace(
          'downloadFolder invalid name',
          'remote=$remotePath name=$name',
        );
        rootTask.status = TransferStatus.error;
        rootTask.error = 'api_code_file_invalid_params'.tr;
        tasks.refresh();
        return;
      }
      final type = item['type'];
      final size = item['size'] ?? 0;
      final itemRemotePath = p.join(remotePath, name);
      final itemLocalPath = _safeJoinWithin(localPath, name);
      if (itemLocalPath == null) {
        DownloadHistoryStorage.trace(
          'downloadFolder invalid local path',
          'base=$localPath name=$name',
        );
        rootTask.status = TransferStatus.error;
        rootTask.error = 'api_code_file_invalid_params'.tr;
        tasks.refresh();
        return;
      }

      if (type == 'dir') {
        await downloadFolder(rootTask, itemRemotePath, itemLocalPath);
      } else {
        await downloadFile(rootTask, itemRemotePath, itemLocalPath, size);
      }
    }
  }

  /// 下载单个文件
  /// 将文件添加到下载队列
  Future<void> downloadFile(
    TransferTask rootTask,
    String remotePath,
    String localPath,
    int size,
  ) async {
    final baseUrl = ApiController.instance.baseUrl;
    final token = ApiController.instance.accessToken;
    String url;
    if (_isUrl(remotePath)) {
      url = remotePath;
    } else {
      url =
          '$baseUrl/api/file/download?path=${Uri.encodeComponent(remotePath)}';
      if (token != null) {
        url += '&accessToken=$token';
      }
    }

    final taskId =
        '${DateTime.now().microsecondsSinceEpoch}_${_getBasename(remotePath)}';

    // 检查目标文件是否已存在且大小一致
    // 必须 size > 0：未知大小时 fetchTaskSize 常为 0，若此处仍判「与本地 0 字节文件相等」会误跳过下载，
    // 表现为不 Enqueue、无 handleDownloadUpdate、无历史记录（一闪而过）。
    final targetFile = File(localPath);
    if (size > 0 &&
        targetFile.existsSync() &&
        targetFile.lengthSync() == size) {
      DownloadHistoryStorage.trace(
        'downloadFile skip already on disk (size match)',
        'local=$localPath size=$size',
      );
      // 注册映射关系
      downloadTaskToParent[taskId] = rootTask;
      fileSizes[taskId] = size;

      if (!parentToChildrenTasks.containsKey(rootTask.id)) {
        parentToChildrenTasks[rootTask.id] = {};
      }
      parentToChildrenTasks[rootTask.id]!.add(taskId);
      completedChildTasks.putIfAbsent(rootTask.id, () => <String>{});
      completedChildTasks[rootTask.id]!.add(taskId);

      // 直接标记完成
      fileProcessedBytes[taskId] = size;
      updateParentProgress(rootTask);
      checkParentStatus(rootTask);

      if (!kIsWeb) {
        final localH = localPath.trim();
        if (localH.isNotEmpty) {
          unawaited(
            DownloadHistoryStorage.instance.recordCompletedFile(
              localPath: localH,
              remotePath: remotePath,
              displayName: p.basename(localH),
              size: size,
              taskId: rootTask.id,
            ),
          );
        }
      }

      return;
    }

    // 注册映射关系
    downloadTaskToParent[taskId] = rootTask;
    fileSizes[taskId] = size;
    fileProcessedBytes[taskId] = 0; // 初始化进度

    if (!parentToChildrenTasks.containsKey(rootTask.id)) {
      parentToChildrenTasks[rootTask.id] = {};
    }
    parentToChildrenTasks[rootTask.id]!.add(taskId);
    completedChildTasks.putIfAbsent(rootTask.id, () => <String>{});

    // 使用临时文件名
    // 直接下载到目标文件夹，但在下载过程中添加 .nascab_tmp 后缀
    // 下载完成后重命名为原始名称
    final savePath = '$localPath.nascab_tmp';

    // 确保目录存在
    final directory = Directory(p.dirname(savePath));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    // 准备任务信息存入队列
    final taskInfo = {
      'taskId': taskId,
      'url': url,
      'savePath': savePath,
      'rootId': rootTask.id,
      'originalPath': localPath, // 存储原始路径用于重命名
      if (!_isUrl(remotePath)) 'remotePath': remotePath,
    };

    // 添加到队列
    if (!folderDownloadQueueLists.containsKey(rootTask.id)) {
      folderDownloadQueueLists[rootTask.id] = Queue<Map<String, dynamic>>();
    }
    folderDownloadQueueLists[rootTask.id]!.add(taskInfo);

    // 触发处理
    processNextFolderTask(rootTask.id);
  }

  /// 处理下一个文件夹下载任务
  /// 从队列中取出一个任务并开始下载
  void processNextFolderTask(String parentId) async {
    // 如果该父任务已有正在运行的子任务，则不做处理（串行下载）
    if (folderRunningChild[parentId] != null) {
      // print('processNextFolderTask: $parentId is running');
      return;
    }

    // 获取父任务检查状态
    final parent = tasks.firstWhereOrNull((t) => t.id == parentId);
    if (parent == null) {
      // print('processNextFolderTask: $parentId not found');
      return;
    }
    if (parent.status == TransferStatus.paused ||
        parent.status == TransferStatus.error) {
      // print('processNextFolderTask: $parentId is paused or error');
      return;
    }

    final queue = folderDownloadQueueLists[parentId];
    if (queue == null || queue.isEmpty) {
      // 队列为空，说明所有子任务已添加并处理完毕（或正在处理最后一个）
      return;
    }

    final taskInfo = queue.removeFirst();
    final taskId = taskInfo['taskId'] as String;
    final url = taskInfo['url'] as String;
    final savePath = taskInfo['savePath'] as String;
    final originalPath = taskInfo['originalPath'] as String;
    final remotePathForRefresh = taskInfo['remotePath'] as String?;

    folderRunningChild[parentId] = taskId;
    folderRunningTaskInfo[parentId] = taskInfo;

    // 开始下载（根据平台选择下载方式）
    if (_shouldUseP2pDownloadUrl(url)) {
      await startP2pDirectDownload(
        taskId,
        url,
        savePath,
        originalPath,
        parentId,
        p.basename(originalPath),
        remotePathForRefresh: remotePathForRefresh,
      );
      return;
    }

    await startDesktopDirectDownload(
      taskId,
      url,
      savePath,
      originalPath,
      parentId,
      p.basename(originalPath),
      remotePathForRefresh: remotePathForRefresh,
    );
  }

  Future<void> startP2pDirectDownload(
    String taskId,
    String url,
    String savePath,
    String originalPath,
    String parentId,
    String name, {
    String? remotePathForRefresh,
  }) async {
    final parent = tasks.firstWhereOrNull((t) => t.id == parentId);
    if (parent == null) return;

    final file = File(savePath);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }

    bool canceled = false;
    P2pStreamedResponse? streamed;
    void cancel() {
      canceled = true;
      try {
        streamed?.cancel();
      } catch (_) {}
    }

    webP2pCancels[taskId] = cancel;

    unawaited(TransferWorkNotificationHub.instance.downloadWorkBegan());
    try {
    Future<P2pStreamedResponse> openStream({required int rangeStart}) async {
      final requestUrl =
          (remotePathForRefresh != null && remotePathForRefresh.isNotEmpty)
          ? ApiController.instance.getDownloadUrl([remotePathForRefresh])
          : url;
      final req = http.Request('GET', Uri.parse(requestUrl));
      final requestHeaders = _buildAuthHeadersForUrl(
        requestUrl,
        extraHeaders: rangeStart > 0 ? {'range': 'bytes=$rangeStart-'} : null,
      );
      if (requestHeaders != null) {
        req.headers.addAll(requestHeaders);
      }
      return ApiController.instance.sendP2pStreamRequest(
        req,
        timeout: const Duration(minutes: 30),
        channel: P2pRtcChannel.download,
      );
    }

    const p2pMaxIncompleteRetries = 3;
    var p2pIncompleteAttempt = 0;

    try {
      while (true) {
        streamed = null;

        int initialBytes = 0;
        try {
          initialBytes = file.lengthSync();
        } catch (_) {
          initialBytes = 0;
        }

        var current = await openStream(rangeStart: initialBytes);
        streamed = current;
        if (initialBytes > 0 && current.status != 206) {
          try {
            current.cancel();
          } catch (_) {}
          try {
            file.deleteSync();
          } catch (_) {}
          file.createSync(recursive: true);
          initialBytes = 0;
          current = await openStream(rangeStart: 0);
          streamed = current;
        }

        if (current.status != 200 && current.status != 206) {
          throw Exception('http_${current.status}');
        }

        final inferred = _inferFileTotalFromP2pResponse(
          current.status,
          current.headers,
        );
        if (inferred != null) {
          mergeInferredFileTotalForChild(parentId, taskId, inferred);
        }

        final sink = file.openWrite(mode: FileMode.append);
        int receivedBytes = initialBytes;

        fileProcessedBytes[taskId] = receivedBytes;
        updateParentProgress(parent);

        try {
          await for (final data in current.stream) {
            if (canceled || parent.status == TransferStatus.paused) {
              throw Exception('p2p_canceled');
            }
            sink.add(data);
            receivedBytes += data.length;
            fileProcessedBytes[taskId] = receivedBytes;
            updateParentProgress(parent);
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              final totalSz = fileSizes[taskId] ?? 0;
              int? pct;
              if (totalSz > 0) {
                pct = ((receivedBytes / totalSz) * 100).floor().clamp(0, 100);
              }
              unawaited(
                TransferWorkNotificationHub.instance.downloadProgressThrottled(
                  displayName: name,
                  percent: pct,
                ),
              );
            }
          }
        } finally {
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
        }

        if (canceled || parent.status == TransferStatus.paused) {
          throw Exception('p2p_canceled');
        }

        final expected = fileSizes[taskId] ?? 0;
        final actualLen = file.existsSync() ? file.lengthSync() : 0;
        if (expected > 0 && actualLen < expected) {
          if (p2pIncompleteAttempt < p2pMaxIncompleteRetries) {
            p2pIncompleteAttempt++;
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }
          throw Exception('download_incomplete');
        }

        break;
      }

      final uniquePath = _getUniquePath(originalPath);
      try {
        if (file.existsSync()) {
          file.renameSync(uniquePath);
        }
      } catch (e) {
        throw Exception('rename_failed_$e');
      }

      int actualBytes = 0;
      try {
        actualBytes = File(uniquePath).lengthSync();
      } catch (_) {
        actualBytes =
            fileSizes[taskId] ?? fileProcessedBytes[taskId] ?? 0;
      }

      final childrenCount = parentToChildrenTasks[parentId]?.length ?? 0;
      String? androidP2pMovedPath;
      if (Platform.isAndroid) {
        try {
          final movedPath = await _exposeAndroidDownloadInPublicStorage(
            sourcePath: uniquePath,
            childrenCount: childrenCount,
            parentName: parent.name,
            parentLocalPath: parent.localPath,
          );
          androidP2pMovedPath = movedPath ?? uniquePath;
          if (childrenCount <= 1) {
            parent.localPath = androidP2pMovedPath;
            tasks.refresh();
          }
        } catch (_) {}
      } else if (Platform.isIOS) {
        if (childrenCount <= 1) {
          parent.localPath = uniquePath;
          tasks.refresh();
        }
      }

      if (fileSizes[taskId] == null || fileSizes[taskId] == 0) {
        fileSizes[taskId] = actualBytes;
        if (parent.totalSize <= 0) {
          parent.totalSize = actualBytes;
        } else {
          parent.totalSize += actualBytes;
        }
      }

      fileProcessedBytes[taskId] = actualBytes;
      completedChildTasks.putIfAbsent(parentId, () => <String>{});
      completedChildTasks[parentId]!.add(taskId);
      webP2pCancels.remove(taskId);

      if (!kIsWeb) {
        final ti = folderRunningTaskInfo[parentId];
        final rp = ti?['remotePath'] as String?;
        final remoteHist =
            (rp != null && rp.trim().isNotEmpty) ? rp.trim() : parent.remotePath;
        final localH = (childrenCount <= 1
                ? parent.localPath
                : (androidP2pMovedPath ?? uniquePath))
            .trim();
        if (localH.isNotEmpty) {
          DownloadHistoryStorage.trace(
            'startP2pDirectDownload calling recordCompletedFile',
            'localH=$localH remoteHist=$remoteHist size=$actualBytes',
          );
          await DownloadHistoryStorage.instance.recordCompletedFile(
            localPath: localH,
            remotePath: remoteHist,
            displayName: p.basename(localH),
            size: actualBytes,
            taskId: parent.id,
          );
          DownloadHistoryStorage.trace(
            'startP2pDirectDownload recordCompletedFile returned',
            localH,
          );
        } else {
          DownloadHistoryStorage.trace(
            'startP2pDirectDownload skip history empty localH',
            'parent.localPath=${parent.localPath}',
          );
        }
      }

      if ((Platform.isIOS || Platform.isAndroid) &&
          (_isImagePath(uniquePath) || _isVideoPath(uniquePath))) {
        DownloadHistoryStorage.trace(
          'startP2pDirectDownload save to gallery (after history)',
          uniquePath,
        );
        await _saveDownloadedMediaToGalleryIfPermitted(
          uniquePath,
          showToastOnFail: childrenCount <= 1,
        );
      }

      folderRunningChild[parentId] = null;
      folderRunningTaskInfo.remove(parentId);

      updateParentProgress(parent);
      checkParentStatus(parent);
      processNextFolderTask(parentId);
    } catch (e) {
      webP2pCancels.remove(taskId);
      try {
        streamed?.cancel();
      } catch (_) {}

      final isUserCancel =
          canceled || webP2pUserCanceled.remove(taskId) == true;

      if (folderRunningChild[parentId] == taskId) {
        folderRunningChild[parentId] = null;
      }

      if (isUserCancel || parent.status == TransferStatus.paused) {
        final info = folderRunningTaskInfo[parentId];
        if (info != null) {
          folderDownloadQueueLists.putIfAbsent(
            parentId,
            () => Queue<Map<String, dynamic>>(),
          );
          folderDownloadQueueLists[parentId]!.addFirst(info);
        }
        return;
      }

      parent.status = TransferStatus.error;
      parent.error = e.toString();
      tasks.refresh();
    }
    } finally {
      unawaited(TransferWorkNotificationHub.instance.downloadWorkEnded());
    }
  }

  /// 判断是否为 HTTP 403 权限错误（不触发重试）
  bool _isHttp403(NascabTaskException? exception) {
    if (exception == null) return false;
    if (exception is NascabTaskHttpException && exception.httpResponseCode == 403) {
      return true;
    }
    final desc = exception.description;
    return desc.contains('403') ||
        desc.toLowerCase().contains('permission_denied');
  }

  /// 处理下载状态更新
  /// 核心逻辑：监听进度和状态，更新父任务进度，处理文件重命名和队列流转
  @override
  void handleDownloadUpdate(NascabTaskUpdate update) async {
    final task = update.task;
    final taskId = task.taskId;
    final parentId = task.metaData?.trim();
    if (parentId == null || parentId.isEmpty) return;

    final parent = tasks.firstWhereOrNull((t) => t.id == parentId);
    if (parent == null) return;

    if (update is NascabTaskStatusUpdate) {
      if (update.status == NascabTaskStatus.complete) {
        DownloadHistoryStorage.trace(
          'handleDownloadUpdate complete',
          'childTaskId=$taskId parentId=$parentId '
          'task.directory=${task.directory} task.filename=${task.filename}',
        );
        // 下载完成，重命名文件（去除 .nascab_tmp 后缀）
        final taskInfo = folderRunningTaskInfo[parentId];
        final originalPath = taskInfo?['originalPath'] as String?;
        String? finalPath;
        if (originalPath != null) {
          final tempPath = p.join(task.directory, task.filename);
          try {
            final f = File(tempPath);
            if (f.existsSync()) {
              // 获取唯一路径，避免覆盖
              final uniquePath = _getUniquePath(originalPath);
              f.renameSync(uniquePath);
              finalPath = uniquePath;
            } else {
              // 如果 task.directory/filename 不准确，尝试使用保存的 savePath
              final savePath = taskInfo?['savePath'] as String?;
              if (savePath != null) {
                final f2 = File(savePath);
                if (f2.existsSync()) {
                  // 获取唯一路径，避免覆盖
                  final uniquePath = _getUniquePath(originalPath);
                  f2.renameSync(uniquePath);
                  finalPath = uniquePath;
                }
              }
            }
          } catch (e) {
            print('Error renaming file: $e');
          }
        }

        // 清理当前运行状态
        activeDownloadTasks.remove(taskId);
        if (folderRunningChild[parentId] == taskId) {
          folderRunningChild[parentId] = null;
          folderRunningTaskInfo.remove(parentId);
        }

        completedChildTasks.putIfAbsent(parentId, () => <String>{});
        completedChildTasks[parentId]!.add(taskId);

        if (finalPath == null && originalPath != null) {
          if (File(originalPath).existsSync()) {
            finalPath = originalPath;
          }
        }
        if (finalPath == null) {
          final savePath = taskInfo?['savePath'] as String?;
          if (savePath != null && File(savePath).existsSync()) {
            finalPath = savePath;
          }
        }
        if (finalPath == null) {
          final fallback = p.join(task.directory, task.filename);
          if (File(fallback).existsSync()) {
            finalPath = fallback;
          }
        }

        DownloadHistoryStorage.trace(
          'handleDownloadUpdate paths resolved',
          'originalPath=$originalPath finalPath=$finalPath '
          'savePath=${taskInfo?['savePath']} fallback=${p.join(task.directory, task.filename)}',
        );

        final previousSize = fileSizes[taskId] ?? 0;
        int? actualBytes;
        if (finalPath != null) {
          final f = File(finalPath);
          if (f.existsSync()) {
            actualBytes = f.lengthSync();
          }
        }
        if (previousSize <= 0 && actualBytes != null && actualBytes > 0) {
          fileSizes[taskId] = actualBytes;
          if (parent.totalSize <= 0) {
            parent.totalSize = actualBytes;
          } else {
            parent.totalSize += actualBytes;
          }
        }

        final total = fileSizes[taskId] ?? 0;
        fileProcessedBytes[taskId] = total > 0 ? total : (actualBytes ?? 0);

        final childrenCount = parentToChildrenTasks[parentId]?.length ?? 0;
        String? resolvedHistoryPath;
        if (finalPath != null) {
          resolvedHistoryPath = finalPath;
          if (Platform.isAndroid) {
            try {
              final movedPath = await _exposeAndroidDownloadInPublicStorage(
                sourcePath: finalPath,
                childrenCount: childrenCount,
                parentName: parent.name,
                parentLocalPath: parent.localPath,
              );
              resolvedHistoryPath = movedPath ?? finalPath;
              if (childrenCount <= 1) {
                parent.localPath = resolvedHistoryPath;
                tasks.refresh();
              }
            } catch (_) {
              resolvedHistoryPath = finalPath;
              if (childrenCount <= 1) {
                parent.localPath = finalPath;
                tasks.refresh();
              }
            }
          } else if (Platform.isIOS) {
            // 先不落相册：saveImage / 权限可能长时间挂起，会导致后面的 recordCompletedFile 永远不执行。
            resolvedHistoryPath = finalPath;
            if (childrenCount <= 1) {
              parent.localPath = finalPath;
              tasks.refresh();
            }
          } else {
            // 桌面端：最终文件路径为 [finalPath]
            resolvedHistoryPath = finalPath;
            if (childrenCount <= 1) {
              parent.localPath = finalPath;
              tasks.refresh();
            }
          }
        }

        if (!kIsWeb && finalPath != null) {
          final localHist = (childrenCount <= 1
                  ? parent.localPath
                  : (resolvedHistoryPath ?? finalPath))
              .trim();
          if (localHist.isNotEmpty) {
            final rp = taskInfo?['remotePath'] as String?;
            final remoteHist =
                (rp != null && rp.trim().isNotEmpty) ? rp.trim() : parent.remotePath;
            final sz =
                actualBytes ?? fileSizes[taskId] ?? fileProcessedBytes[taskId] ?? 0;
            DownloadHistoryStorage.trace(
              'handleDownloadUpdate calling recordCompletedFile',
              'localHist=$localHist remoteHist=$remoteHist sz=$sz',
            );
            await DownloadHistoryStorage.instance.recordCompletedFile(
              localPath: localHist,
              remotePath: remoteHist,
              displayName: p.basename(localHist),
              size: sz,
              taskId: parent.id,
            );
            DownloadHistoryStorage.trace(
              'handleDownloadUpdate recordCompletedFile returned',
              localHist,
            );
          } else {
            DownloadHistoryStorage.trace(
              'handleDownloadUpdate skip history empty localHist',
              'parent.localPath=${parent.localPath} resolved=$resolvedHistoryPath finalPath=$finalPath',
            );
          }
        } else {
          DownloadHistoryStorage.trace(
            'handleDownloadUpdate skip history branch',
            'kIsWeb=$kIsWeb finalPath=$finalPath',
          );
        }

        if (finalPath != null &&
            (Platform.isIOS || Platform.isAndroid) &&
            (_isImagePath(finalPath) || _isVideoPath(finalPath))) {
          DownloadHistoryStorage.trace(
            'handleDownloadUpdate save to gallery (after history)',
            finalPath,
          );
          await _saveDownloadedMediaToGalleryIfPermitted(
            finalPath,
            showToastOnFail: childrenCount <= 1,
          );
        }

        // 更新父任务总进度
        updateParentProgress(parent);
        checkParentStatus(parent);

        // 处理下一个任务
        processNextFolderTask(parentId);
      } else if (update.status == NascabTaskStatus.failed ||
          update.status == NascabTaskStatus.canceled) {
        activeDownloadTasks.remove(taskId);
        if (folderRunningChild[parentId] == taskId) {
          folderRunningChild[parentId] = null;

          if (update.status == NascabTaskStatus.canceled &&
              parent.status == TransferStatus.paused) {
            // 如果是暂停导致的取消，将任务放回队列头部，以便恢复时继续
            final info = folderRunningTaskInfo[parentId];
            if (info != null) {
              if (folderDownloadQueueLists[parentId] == null) {
                folderDownloadQueueLists[parentId] = Queue();
              }
              folderDownloadQueueLists[parentId]!.addFirst(info);
            }
          } else {
            folderRunningTaskInfo.remove(parentId);
          }

          if (update.status == NascabTaskStatus.failed) {
            // 任务失败，标记父任务错误；403 时错误信息便于 UI 显示 permission_denied
            final is403 = _isHttp403(update.exception);
            parent.status = TransferStatus.error;
            parent.error = update.exception?.description ?? 'Download failed';
            if (is403) parent.error = '403'; // 便于 _getFriendlyErrorMessage 显示 permission_denied.tr
            tasks.refresh();

            // 403 权限错误不重试；其他失败放回队列头部
            if (!is403) {
              final info = folderRunningTaskInfo[parentId];
              if (info != null) {
                if (folderDownloadQueueLists[parentId] == null) {
                  folderDownloadQueueLists[parentId] = Queue();
                }
                folderDownloadQueueLists[parentId]!.addFirst(info);
              }
            }
            folderRunningTaskInfo.remove(parentId);
          }
        }
      } else if (update.status == NascabTaskStatus.paused) {
        // 暂停状态
      }
    } else if (update is NascabTaskProgressUpdate) {
      final progress = update.progress; // 0.0 to 1.0
      final total = fileSizes[taskId] ?? 0;
      if (total > 0) {
        final currentBytes = (total * progress).floor();
        fileProcessedBytes[taskId] = currentBytes;
        updateParentProgress(parent);
      }
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        int? pct;
        if (total > 0) {
          pct = (progress * 100).floor().clamp(0, 100);
        }
        unawaited(
          TransferWorkNotificationHub.instance.downloadProgressThrottled(
            displayName: update.task.displayName,
            percent: pct,
          ),
        );
      }
    }
  }

  /// 更新父任务进度
  /// 遍历所有子任务的已下载字节数进行汇总
  void updateParentProgress(TransferTask parent) {
    int totalProcessed = 0;

    final children = parentToChildrenTasks[parent.id];
    if (children != null) {
      for (final childId in children) {
        totalProcessed += fileProcessedBytes[childId] ?? 0;
      }
    }

    // 计算本次更新的增量，用于节流判断
    final delta = totalProcessed - parent.processedSize;
    parent.processedSize = totalProcessed;

    if (parent.processedSize > parent.totalSize) {
      // 容错处理，防止超过总大小
      if (parent.totalSize > 0) {
        parent.processedSize = parent.totalSize;
      }
    }
    if (parent.processedSize < 0) {
      parent.processedSize = 0;
    }

    final sinceLast = (bytesSinceLastUpdate[parent] ?? 0) + delta;
    bytesSinceLastUpdate[parent] = sinceLast;

    final now = DateTime.now();
    // 达到阈值或时间间隔才刷新UI
    if (sinceLast.abs() >= DownloadStateMixin.updateThresholdBytes ||
        now.difference(lastUpdate).inMilliseconds > 500) {
      tasks.refresh();
      bytesSinceLastUpdate[parent] = 0;
      lastUpdate = now;
    }
  }

  /// 检查父任务是否完成
  void checkParentStatus(TransferTask parent) {
    if (parent.status == TransferStatus.paused ||
        parent.status == TransferStatus.error) {
      return;
    }

    final children = parentToChildrenTasks[parent.id];
    if (children != null && children.isNotEmpty) {
      final completed = completedChildTasks[parent.id];
      final hasRunning = folderRunningChild[parent.id] != null;
      final queue = folderDownloadQueueLists[parent.id];
      final queueEmpty = queue == null || queue.isEmpty;
      if (queueEmpty &&
          !hasRunning &&
          completed != null &&
          completed.length >= children.length) {
        parent.status = TransferStatus.completed;
        tasks.refresh();
      }
      return;
    }

    if (parent.totalSize <= 0) {
      parent.status = TransferStatus.completed;
      tasks.refresh();
      return;
    }

    if (parent.processedSize >= parent.totalSize) {
      parent.status = TransferStatus.completed;
      tasks.refresh();
    }
  }
}
