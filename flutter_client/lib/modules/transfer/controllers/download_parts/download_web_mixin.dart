part of '../download_controller.dart';

/// Web端下载 Mixin
/// 专门处理Web平台的下载逻辑，通过浏览器原生下载
mixin DownloadWebMixin on DownloadStateMixin {
  /// Web端下载逻辑
  /// 直接调用浏览器下载链接
  Future<void> downloadWeb(List<String> paths) async {
    if (paths.isEmpty) return;

    final apiController = ApiController.instance;
    final isP2p = apiController.isP2pMode;

    if (!isP2p) {
      final baseUrl = apiController.baseUrl;
      final token = apiController.accessToken;
      for (final path in paths) {
        final uri = Uri.tryParse(path);
        final isUrl =
            uri != null &&
            uri.hasScheme &&
            (uri.scheme == 'http' || uri.scheme == 'https');
        if (isUrl) {
          launchUrl(uri);
          continue;
        }
        var url =
            '$baseUrl/api/file/download?path=${Uri.encodeComponent(path)}';
        if (token != null) {
          url += '&accessToken=$token';
        }
        launchUrl(Uri.parse(url));
      }
      return;
    }

    final urlItems = <String>[];
    final pathItems = <String>[];

    for (final item in paths) {
      final uri = Uri.tryParse(item);
      final isUrl =
          uri != null &&
          uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https');
      if (isUrl) {
        urlItems.add(item);
      } else {
        pathItems.add(item);
      }
    }

    if (pathItems.isNotEmpty) {
      final url = apiController.getDownloadUrl(pathItems);
      final fallbackName = pathItems.length > 1
          ? 'download.zip'
          : (p.basename(pathItems.first).trim().isEmpty
                ? 'download'
                : p.basename(pathItems.first).trim());
      await _p2pStreamAndDownload(
        url: url,
        fallbackName: fallbackName,
        task: _createWebTask(name: fallbackName, remotePath: url),
      );
    }

    for (final u in urlItems) {
      final uri = Uri.tryParse(u);
      if (uri == null) continue;
      if (uri.origin.trim() != ApiController.p2pBaseUrl) {
        launchUrl(uri);
        continue;
      }
      final resolved = _maybeAuthedP2pUrl(u);
      final fallbackName = _fallbackNameFromUrl(resolved);
      await _p2pStreamAndDownload(
        url: resolved,
        fallbackName: fallbackName,
        task: _createWebTask(name: fallbackName, remotePath: resolved),
      );
    }
  }

  Future<void> restartWebTask(TransferTask task) async {
    final remote = task.remotePath.trim();
    if (remote.isEmpty) return;
    task.status = TransferStatus.uploading;
    task.error = null;
    task.processedSize = 0;
    tasks.refresh();
    final fallbackName = task.name.trim().isEmpty
        ? _fallbackNameFromUrl(remote)
        : task.name;
    await _p2pStreamAndDownload(
      url: remote,
      fallbackName: fallbackName,
      task: task,
    );
  }

  String _fallbackNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'download';
    // 部分接口用路径末尾作动作名（如 …/imageCompress/file），真实文件名在 query 的 fileName
    final fromQuery = (uri.queryParameters['fileName'] ??
            uri.queryParameters['filename'] ??
            '')
        .trim();
    if (fromQuery.isNotEmpty) {
      return _sanitizeFilename(fromQuery);
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('/api/file/download')) {
      final qpAll = uri.queryParametersAll;
      final paths = qpAll['paths'];
      if (paths != null && paths.length > 1) return 'download.zip';
      return 'download';
    }
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final name = Uri.decodeComponent(last);
    return name.trim().isEmpty ? 'download' : name.trim();
  }

  String _maybeAuthedP2pUrl(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    final origin = uri.origin.trim();
    if (origin != ApiController.p2pBaseUrl) return raw;
    return ApiController.instance.getAuthedUrl(raw);
  }

  TransferTask _createWebTask({
    required String name,
    required String remotePath,
  }) {
    final safeName = name.trim().isEmpty ? 'download' : name.trim();
    final task = TransferTask(
      id: '${DateTime.now().microsecondsSinceEpoch}_$safeName',
      name: safeName,
      localPath: 'Browser',
      remotePath: remotePath,
      type: TransferType.download,
      status: TransferStatus.uploading,
    );
    tasks.add(task);
    tasks.refresh();
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
    return task;
  }

  Future<void> _p2pStreamAndDownload({
    required String url,
    required String fallbackName,
    required TransferTask task,
  }) async {
    final raw = url.trim();
    if (raw.isEmpty) return;

    P2pStreamedResponse streamed;
    final suggestedName = (fallbackName.trim().isEmpty)
        ? 'download'
        : fallbackName.trim();
    task.name = suggestedName;
    task.status = TransferStatus.uploading;
    task.error = null;
    task.processedSize = 0;
    tasks.refresh();

    dynamic fileHandle;
    dynamic streamSaverWriter;

    // basename 无扩展名时，服务端常见情况是「单路径目录→zip」；另存为建议名用 *.zip，避免先 GET 再在对话框里磨蹭时 P2P 已开始推流、内存堆积。
    // （极少数无扩展名单文件会建议成 xxx.zip，用户可在对话框里改后缀；若后续从列表传入 isDir 可再精确化。）
    final savePickerSuggestedName =
        !_webDownloadBasenameHasExtension(suggestedName)
            ? '$suggestedName.zip'
            : suggestedName;

    if (web_file_download.supportsFileSystemAccess) {
      try {
        fileHandle = await web_file_download.pickSaveFileHandle(
          filename: savePickerSuggestedName,
        );
        task.name = savePickerSuggestedName;
        tasks.refresh();
      } catch (_) {
        task.status = TransferStatus.paused;
        tasks.refresh();
        return;
      }
    }

    if (fileHandle != null && _p2pDownloadUrlSupportsResumeRange(raw)) {
      await _p2pStreamAndDownloadWithResumeFsa(
        rawUrl: raw,
        suggestedName: savePickerSuggestedName,
        task: task,
        fileHandle: fileHandle,
      );
      return;
    }

    try {
      final req = http.Request('GET', Uri.parse(raw));
      streamed = await ApiController.instance.sendP2pStreamRequest(
        req,
        timeout: const Duration(minutes: 30),
        channel: P2pRtcChannel.download,
      );
    } catch (e) {
      task.status = TransferStatus.error;
      task.error = e.toString();
      tasks.refresh();
      return;
    }

    if (streamed.status < 200 || streamed.status >= 300) {
      try {
        streamed.cancel();
      } catch (_) {}
      task.status = TransferStatus.error;
      task.error = 'http_${streamed.status}';
      tasks.refresh();
      return;
    }

    final headers = streamed.headers;
    final contentType = _headerValue(headers, 'content-type');
    final contentDisposition = _headerValue(headers, 'content-disposition');
    final lenStr = _headerValue(headers, 'content-length');
    final len = lenStr == null ? null : int.tryParse(lenStr.trim());
    var filename = suggestedName;
    filename =
        _parseContentDispositionFilename(contentDisposition) ?? suggestedName;
    final ct = (contentType ?? '').toLowerCase();
    if (!filename.contains('.') &&
        (ct.contains('application/zip') || ct.contains('zip'))) {
      filename = '$filename.zip';
    }
    task.name = filename;
    tasks.refresh();

    if (fileHandle == null && web_file_download.supportsStreamSaver) {
      try {
        streamSaverWriter = web_file_download.createStreamSaverWriter(
          filename: filename,
          mimeType: contentType,
          size: len,
        );
      } catch (_) {
        streamSaverWriter = null;
      }
    }
    if (len != null && len > 0) {
      task.totalSize = len;
    }
    tasks.refresh();

    webP2pUserCanceled.remove(task.id);
    webP2pCancels[task.id] = () {
      webP2pUserCanceled[task.id] = true;
      streamed.cancel();
    };
    int processed = 0;
    var lastUiUpdate = DateTime.now();

    Stream<Uint8List> progressStream(Stream<Uint8List> src) {
      return src.transform(
        StreamTransformer.fromHandlers(
          handleData: (chunk, sink) {
            processed += chunk.length;
            task.processedSize = processed;
            final now = DateTime.now();
            if (now.difference(lastUiUpdate).inMilliseconds >= 200) {
              lastUiUpdate = now;
              tasks.refresh();
            }
            sink.add(chunk);
          },
          handleError: (e, st, sink) {
            sink.addError(e, st);
          },
          handleDone: (sink) => sink.close(),
        ),
      );
    }

    if (fileHandle != null) {
      try {
        await web_file_download.saveStreamWithHandle(
          progressStream(streamed.stream),
          handle: fileHandle,
        );
        final canceled = webP2pUserCanceled.remove(task.id) == true;
        if (canceled) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          webP2pCancels.remove(task.id);
          return;
        }
        if (_p2pWebDownloadSizeMismatch(len, processed)) {
          task.status = TransferStatus.error;
          task.error = 'download_incomplete';
          tasks.refresh();
          webP2pCancels.remove(task.id);
          return;
        }
        task.status = TransferStatus.completed;
        task.processedSize = task.totalSize > 0 ? task.totalSize : processed;
        tasks.refresh();
        webP2pCancels.remove(task.id);
        return;
      } catch (e) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        if (webP2pUserCanceled.remove(task.id) == true) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        final msg = e.toString();
        if (msg.contains('AbortError') || msg.contains('aborted')) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        task.status = TransferStatus.error;
        task.error = e.toString();
        tasks.refresh();
        return;
      }
    }

    if (streamSaverWriter != null) {
      try {
        await web_file_download.writeStreamToStreamSaverWriter(
          progressStream(streamed.stream),
          writer: streamSaverWriter,
        );
        final canceled = webP2pUserCanceled.remove(task.id) == true;
        if (canceled) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          webP2pCancels.remove(task.id);
          return;
        }
        if (_p2pWebDownloadSizeMismatch(len, processed)) {
          task.status = TransferStatus.error;
          task.error = 'download_incomplete';
          tasks.refresh();
          webP2pCancels.remove(task.id);
          return;
        }
        task.status = TransferStatus.completed;
        task.processedSize = task.totalSize > 0 ? task.totalSize : processed;
        tasks.refresh();
        webP2pCancels.remove(task.id);
        return;
      } catch (e) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        if (webP2pUserCanceled.remove(task.id) == true) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        final msg = e.toString();
        if (msg.contains('AbortError') || msg.contains('aborted')) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        task.status = TransferStatus.error;
        task.error = e.toString();
        tasks.refresh();
        return;
      }
    }

    const maxBlobBytes = 32 * 1024 * 1024;
    if (len != null && len <= maxBlobBytes) {
      try {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in progressStream(streamed.stream)) {
          builder.add(chunk);
        }
        final bytes = builder.takeBytes();
        await web_file_download.triggerDownloadFromBytes(
          Uint8List.fromList(bytes),
          filename: filename,
          mimeType: contentType,
        );
        final canceled = webP2pUserCanceled.remove(task.id) == true;
        if (canceled) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          webP2pCancels.remove(task.id);
          return;
        }
        if (_p2pWebDownloadSizeMismatch(len, processed)) {
          task.status = TransferStatus.error;
          task.error = 'download_incomplete';
          tasks.refresh();
          webP2pCancels.remove(task.id);
          return;
        }
        task.status = TransferStatus.completed;
        task.processedSize = task.totalSize > 0 ? task.totalSize : processed;
        tasks.refresh();
        webP2pCancels.remove(task.id);
        return;
      } catch (e) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        if (webP2pUserCanceled.remove(task.id) == true) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        task.status = TransferStatus.error;
        task.error = 'download_failed';
        tasks.refresh();
        return;
      }
    }

    try {
      streamed.cancel();
    } catch (_) {}
    webP2pCancels.remove(task.id);
    webP2pUserCanceled.remove(task.id);
    task.status = TransferStatus.error;
    task.error = 'browser_not_supported_for_large_file';
    tasks.refresh();
  }

  /// basename 是否含「正常」扩展名（最后一个点不在首尾）。无扩展名时 P2P 下载推迟另存为，等 Content-Disposition 再 pick。
  bool _webDownloadBasenameHasExtension(String pathOrName) {
    final b = p.basename(pathOrName.trim());
    final i = b.lastIndexOf('.');
    return i > 0 && i < b.length - 1;
  }

  /// 单文件下载 URL 可尝试 HTTP Range 续传（多文件 zip 等不支持）。
  bool _p2pDownloadUrlSupportsResumeRange(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return false;
    final paths = u.queryParametersAll['paths'];
    if (paths != null && paths.length > 1) return false;
    return true;
  }

  bool _isP2pDownloadStreamRetriable(Object e) {
    final s = e.toString();
    return s.contains('p2p_disconnected') ||
        s.contains('p2p_dc_closed') ||
        s.contains('p2p_dc_error') ||
        s.contains('p2p_closed') ||
        s.contains('p2p_not_connected');
  }

  int? _parseContentRangeTotal(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final m = RegExp(
      r'bytes\s+(\d+)\s*-\s*(\d+)\s*/\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(3) ?? '');
  }

  Future<void> _p2pSleepAndEnsureP2p() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await ApiController.instance.ensureP2pConnected(
        timeout: const Duration(seconds: 25),
      );
    } catch (_) {}
  }

  /// FSA 下单文件 P2P 下载：通道切换/断连后自动 `Range` 续传并追加写入。
  Future<void> _p2pStreamAndDownloadWithResumeFsa({
    required String rawUrl,
    required String suggestedName,
    required TransferTask task,
    required dynamic fileHandle,
  }) async {
    const maxRounds = 120;
    var round = 0;
    var processed = 0;
    int? totalLen;
    var lastUiUpdate = DateTime.now();
    webP2pUserCanceled.remove(task.id);

    while (true) {
      round++;
      if (round > maxRounds) {
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.error;
        task.error = 'p2p_download_resume_exhausted';
        tasks.refresh();
        return;
      }

      if (webP2pUserCanceled[task.id] == true) {
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.paused;
        tasks.refresh();
        return;
      }

      final req = http.Request('GET', Uri.parse(rawUrl));
      if (processed > 0) {
        req.headers['Range'] = 'bytes=$processed-';
      }

      P2pStreamedResponse streamed;
      try {
        streamed = await ApiController.instance.sendP2pStreamRequest(
          req,
          timeout: const Duration(minutes: 30),
          channel: P2pRtcChannel.download,
        );
      } catch (e) {
        if (_isP2pDownloadStreamRetriable(e)) {
          await _p2pSleepAndEnsureP2p();
          continue;
        }
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.error;
        task.error = e.toString();
        tasks.refresh();
        return;
      }

      if (streamed.status == 416) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.error;
        task.error = 'http_416';
        tasks.refresh();
        return;
      }

      if (streamed.status < 200 || streamed.status >= 300) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.error;
        task.error = 'http_${streamed.status}';
        tasks.refresh();
        return;
      }

      if (processed == 0 && streamed.status != 200) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.error;
        task.error = 'http_${streamed.status}';
        tasks.refresh();
        return;
      }
      if (processed > 0 && streamed.status != 206) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        task.status = TransferStatus.error;
        task.error = 'p2p_range_rejected';
        tasks.refresh();
        return;
      }

      final headers = streamed.headers;
      if (processed == 0) {
        final contentDisposition = _headerValue(headers, 'content-disposition');
        var fn =
            _parseContentDispositionFilename(contentDisposition) ?? suggestedName;
        final contentType = _headerValue(headers, 'content-type');
        final ct = (contentType ?? '').toLowerCase();
        if (!fn.contains('.') &&
            (ct.contains('application/zip') || ct.contains('zip'))) {
          fn = '$fn.zip';
        }
        task.name = fn;
        final lenStr = _headerValue(headers, 'content-length');
        final cl = lenStr == null ? null : int.tryParse(lenStr.trim());
        if (cl != null && cl > 0) {
          totalLen = cl;
          task.totalSize = cl;
        }
        tasks.refresh();
      }
      if (streamed.status == 206) {
        final cr = _headerValue(headers, 'content-range');
        final t = _parseContentRangeTotal(cr);
        if (t == null) {
          try {
            streamed.cancel();
          } catch (_) {}
          webP2pCancels.remove(task.id);
          task.status = TransferStatus.error;
          task.error = 'p2p_missing_content_range';
          tasks.refresh();
          return;
        }
        totalLen = t;
        task.totalSize = t;
        tasks.refresh();
      }

      final sessionStart = processed;
      var segmentDelta = 0;

      Stream<Uint8List> buildProgress(Stream<Uint8List> src) {
        return src.transform(
          StreamTransformer.fromHandlers(
            handleData: (chunk, sink) {
              segmentDelta += chunk.length;
              processed = sessionStart + segmentDelta;
              task.processedSize = processed;
              final now = DateTime.now();
              if (now.difference(lastUiUpdate).inMilliseconds >= 200) {
                lastUiUpdate = now;
                tasks.refresh();
              }
              sink.add(chunk);
            },
            handleError: (e, st, sink) {
              sink.addError(e, st);
            },
            handleDone: (sink) => sink.close(),
          ),
        );
      }

      webP2pCancels[task.id] = () {
        webP2pUserCanceled[task.id] = true;
        streamed.cancel();
      };

      try {
        await web_file_download.saveStreamWithHandle(
          buildProgress(streamed.stream),
          handle: fileHandle,
          startByteOffset: sessionStart,
        );
      } catch (e) {
        try {
          streamed.cancel();
        } catch (_) {}
        webP2pCancels.remove(task.id);
        if (webP2pUserCanceled.remove(task.id) == true) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        final msg = e.toString();
        if (msg.contains('AbortError') || msg.contains('aborted')) {
          task.status = TransferStatus.paused;
          tasks.refresh();
          return;
        }
        if (_isP2pDownloadStreamRetriable(e)) {
          processed = sessionStart + segmentDelta;
          task.processedSize = processed;
          tasks.refresh();
          await _p2pSleepAndEnsureP2p();
          continue;
        }
        task.status = TransferStatus.error;
        task.error = e.toString();
        tasks.refresh();
        return;
      }

      webP2pCancels.remove(task.id);
      final canceled = webP2pUserCanceled.remove(task.id) == true;
      if (canceled) {
        task.status = TransferStatus.paused;
        tasks.refresh();
        return;
      }

      if (totalLen != null && processed < totalLen) {
        await _p2pSleepAndEnsureP2p();
        continue;
      }
      if (totalLen != null && processed > totalLen) {
        task.status = TransferStatus.error;
        task.error = 'download_incomplete';
        tasks.refresh();
        return;
      }

      task.status = TransferStatus.completed;
      task.processedSize = totalLen ?? processed;
      if (totalLen != null) {
        task.totalSize = totalLen;
      }
      tasks.refresh();
      return;
    }
  }

  String? _parseContentDispositionFilename(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    final star = RegExp(
      r'filename\*\s*=\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1)?.trim();
    if (star != null && star.isNotEmpty) {
      var v = _stripQuotes(star);
      final idx = v.indexOf("''");
      if (idx != -1) {
        v = v.substring(idx + 2);
      }
      try {
        final decoded = Uri.decodeFull(v).trim();
        if (decoded.isNotEmpty) return _sanitizeFilename(decoded);
      } catch (_) {}
      final cleaned = v.trim();
      if (cleaned.isNotEmpty) return _sanitizeFilename(cleaned);
    }

    final normal = RegExp(
      r'filename\s*=\s*("([^"]+)"|([^;]+))',
      caseSensitive: false,
    ).firstMatch(raw);
    final v = (normal?.group(2) ?? normal?.group(3) ?? '').trim();
    if (v.isEmpty) return null;
    return _sanitizeFilename(_stripQuotes(v));
  }

  String _stripQuotes(String input) {
    var s = input.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    return s.trim();
  }

  String _sanitizeFilename(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    s = s.replaceAll('\u0000', '');
    return s.trim();
  }

  String? _headerValue(Map<String, String> headers, String key) {
    final target = key.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }

  /// 已知 Content-Length 时校验是否写满，防止流被提前结束仍标为完成。
  bool _p2pWebDownloadSizeMismatch(int? contentLength, int processed) {
    return contentLength != null && contentLength > 0 && processed != contentLength;
  }
}
