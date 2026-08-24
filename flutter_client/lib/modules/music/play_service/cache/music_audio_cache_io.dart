import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/api/api_controller.dart';
import '../../../../core/api/dio_bad_certificate_compat.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/local_web_asset_server.dart';
import '../../../video_player/controllers/platform/video_platform.dart';
import '../player/music_player_adapter.dart';

class MusicAudioCacheOptions {
  final bool enabled;
  final int maxItems;

  const MusicAudioCacheOptions({required this.enabled, required this.maxItems});

  MusicAudioCacheOptions copyWith({bool? enabled, int? maxItems}) {
    return MusicAudioCacheOptions(
      enabled: enabled ?? this.enabled,
      maxItems: maxItems ?? this.maxItems,
    );
  }
}

class MusicAudioCacheProgress {
  final int receivedBytes;
  final int totalBytes;
  final bool finished;

  const MusicAudioCacheProgress({
    required this.receivedBytes,
    required this.totalBytes,
    this.finished = false,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    final p = receivedBytes / totalBytes;
    if (p.isNaN || p.isInfinite) return 0;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }
}

typedef MusicAudioCacheProgressCallback =
    void Function(MusicAudioCacheProgress progress);

class MusicAudioCacheCanceled implements Exception {}

class MusicAudioCacheStats {
  final int count;
  final int totalBytes;

  const MusicAudioCacheStats({required this.count, required this.totalBytes});
}

class MusicAudioCacheService {
  MusicAudioCacheOptions options;

  MusicAudioCacheService({required this.options});

  final dio.Dio _dio = createDioWithBadCertificateCompat();

  Directory? _cacheDir;
  final Map<String, Map<String, dynamic>> _index = {};
  dio.CancelToken? _cancelToken;
  String? _activeHash;
  bool _downloading = false;

  bool get isDownloading => _downloading;

  String? get activeHash => _activeHash;

  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'music_audio_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    _loadIndex();
    await _reconcileIndexWithDisk();
  }

  void updateOptions(MusicAudioCacheOptions options) {
    this.options = options;
  }

  Future<MusicAudioCacheStats> getStats() async {
    final dir = _cacheDir;
    if (dir == null) return const MusicAudioCacheStats(count: 0, totalBytes: 0);

    var count = 0;
    var totalBytes = 0;
    final removeKeys = <String>[];

    for (final e in _index.entries) {
      final v = e.value;
      if (v['completed'] != true) continue;
      final filename = (v['filename'] ?? '').toString();
      if (filename.trim().isEmpty) {
        removeKeys.add(e.key);
        continue;
      }
      final f = File(p.join(dir.path, filename));
      if (!await f.exists()) {
        removeKeys.add(e.key);
        continue;
      }
      count++;
      try {
        totalBytes += await f.length();
      } catch (_) {}
    }

    if (removeKeys.isNotEmpty) {
      for (final k in removeKeys) {
        _index.remove(k);
      }
      await _persistIndex();
    }
    return MusicAudioCacheStats(count: count, totalBytes: totalBytes);
  }

  Future<void> clearAll() async {
    await cancelActiveDownload();
    final dir = _cacheDir;
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    _index.clear();
    await CacheManager().setJson(CacheKeys.musicAudioCacheIndex, {});
  }

  Future<void> remove(String fileHash) async {
    final dir = _cacheDir;
    if (dir == null) return;
    final entry = _index.remove(fileHash);
    if (entry == null) return;
    final filename = (entry['filename'] ?? '').toString();
    if (filename.trim().isNotEmpty) {
      final f = File(p.join(dir.path, filename));
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      final part = File(p.join(dir.path, '$filename.part'));
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
    await _persistIndex();
  }

  Future<void> cancelActiveDownload() async {
    final token = _cancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
    _cancelToken = null;
    _activeHash = null;
    _downloading = false;
  }

  Future<bool> hasCached(String fileHash) async {
    final dir = _cacheDir;
    if (dir == null) return false;
    final entry = _index[fileHash];
    if (entry == null) return false;
    if (entry['completed'] != true) return false;
    final filename = (entry['filename'] ?? '').toString();
    if (filename.trim().isEmpty) return false;
    final f = File(p.join(dir.path, filename));
    return await f.exists();
  }

  /// 为 just_audio 等播放器准备播放源（iOS/Android 后台播放用）
  Future<MusicPlaySource> prepareSource({
    required String fileHash,
    required String fileExt,
    required int fileSize,
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    if (!options.enabled) {
      final url = await buildUrl();
      return MusicPlaySource(url: url);
    }
    final dir = _cacheDir;
    if (dir == null) {
      final url = await buildUrl();
      return MusicPlaySource(url: url);
    }
    final hash = fileHash.trim();
    if (hash.isEmpty) {
      final url = await buildUrl();
      return MusicPlaySource(url: url);
    }

    final ext = _normalizeExt(fileExt);
    final filename = '$hash.$ext';
    final finalPath = p.join(dir.path, filename);
    final partPath = p.join(dir.path, '$filename.part');

    final completeFile = File(finalPath);
    if (await completeFile.exists()) {
      final okSize = fileSize <= 0 || (await completeFile.length()) == fileSize;
      if (okSize) {
        await _touch(hash, filename: filename, completed: true);
        await _enforceMax();
        final url = await buildUrl();
        return MusicPlaySource(filePath: finalPath, url: url, fileExt: ext);
      }
      await completeFile.delete();
    }

    await _touch(hash, filename: filename, completed: false);
    await _startBackgroundDownload(
      fileHash: hash,
      filename: filename,
      partPath: partPath,
      finalPath: finalPath,
      totalHint: fileSize > 0 ? fileSize : 0,
      buildUrl: buildUrl,
      refreshAuthToken: refreshAuthToken,
      onProgress: onProgress,
    );
    final url = await buildUrl();
    return MusicPlaySource(url: url, fileExt: ext);
  }

  Future<VideoPlayerController> prepareController({
    required String fileHash,
    required String fileExt,
    required int fileSize,
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    if (!options.enabled) {
      final url = await buildUrl();
      return createVideoController(url);
    }
    final dir = _cacheDir;
    if (dir == null) {
      final url = await buildUrl();
      return createVideoController(url);
    }
    final hash = fileHash.trim();
    if (hash.isEmpty) {
      final url = await buildUrl();
      return createVideoController(url);
    }

    final ext = _normalizeExt(fileExt);
    final filename = '$hash.$ext';
    final finalPath = p.join(dir.path, filename);
    final partPath = p.join(dir.path, '$filename.part');

    final completeFile = File(finalPath);
    if (await completeFile.exists()) {
      final okSize = fileSize <= 0 || (await completeFile.length()) == fileSize;
      if (okSize) {
        await _touch(hash, filename: filename, completed: true);
        await _enforceMax();
        return VideoPlayerController.file(completeFile);
      }
      await completeFile.delete();
    }

    await _touch(hash, filename: filename, completed: false);
    await _startBackgroundDownload(
      fileHash: hash,
      filename: filename,
      partPath: partPath,
      finalPath: finalPath,
      totalHint: fileSize > 0 ? fileSize : 0,
      buildUrl: buildUrl,
      refreshAuthToken: refreshAuthToken,
      onProgress: onProgress,
    );
    final url = await buildUrl();
    return createVideoController(url);
  }

  Future<void> _startBackgroundDownload({
    required String fileHash,
    required String filename,
    required String partPath,
    required String finalPath,
    required int totalHint,
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    await cancelActiveDownload();
    final partFile = File(partPath);
    final finalFile = File(finalPath);
    final received = await partFile.exists() ? await partFile.length() : 0;
    onProgress(
      MusicAudioCacheProgress(
        receivedBytes: received,
        totalBytes: totalHint,
        finished: false,
      ),
    );

    final cancelToken = dio.CancelToken();
    _cancelToken = cancelToken;
    _activeHash = fileHash;
    _downloading = true;
    unawaited(
      _runBackgroundDownload(
        fileHash: fileHash,
        filename: filename,
        partFile: partFile,
        finalFile: finalFile,
        initialBytes: received,
        totalHint: totalHint,
        buildUrl: buildUrl,
        refreshAuthToken: refreshAuthToken,
        cancelToken: cancelToken,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _runBackgroundDownload({
    required String fileHash,
    required String filename,
    required File partFile,
    required File finalFile,
    required int initialBytes,
    required int totalHint,
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required dio.CancelToken cancelToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    try {
      await _downloadWithAuthRetry(
        buildUrl: buildUrl,
        refreshAuthToken: refreshAuthToken,
        partFile: partFile,
        finalFile: finalFile,
        initialBytes: initialBytes,
        totalHint: totalHint,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      await _touch(fileHash, filename: filename, completed: true);
      await _enforceMax();
    } on dio.DioException catch (e) {
      if (!dio.CancelToken.isCancel(e)) {
        await _touch(fileHash, filename: filename, completed: false);
      }
    } catch (_) {
      await _touch(fileHash, filename: filename, completed: false);
    } finally {
      int received = initialBytes;
      try {
        if (await partFile.exists()) {
          received = await partFile.length();
        } else if (await finalFile.exists()) {
          received = await finalFile.length();
        }
      } catch (_) {}
      onProgress(
        MusicAudioCacheProgress(
          receivedBytes: received,
          totalBytes: totalHint,
          finished: true,
        ),
      );
      if (identical(_cancelToken, cancelToken)) {
        _downloading = false;
        _cancelToken = null;
        _activeHash = null;
      }
    }
  }

  String _normalizeExt(String ext) {
    final raw = ext.trim().toLowerCase();
    if (raw.isEmpty) return 'dat';
    return raw.startsWith('.') ? raw.substring(1) : raw;
  }

  void _loadIndex() {
    final data = CacheManager().getJson(CacheKeys.musicAudioCacheIndex);
    if (data is Map) {
      for (final e in data.entries) {
        final k = e.key.toString();
        final v = e.value;
        if (v is Map) {
          _index[k] = v.cast<String, dynamic>();
        }
      }
    }
  }

  Future<void> _persistIndex() async {
    await CacheManager().setJson(CacheKeys.musicAudioCacheIndex, _index);
  }

  Future<void> _reconcileIndexWithDisk() async {
    final dir = _cacheDir;
    if (dir == null) return;

    final removeKeys = <String>[];
    for (final entry in _index.entries) {
      final v = entry.value;
      if (v['completed'] != true) continue;
      final filename = (v['filename'] ?? '').toString();
      if (filename.trim().isEmpty) {
        removeKeys.add(entry.key);
        continue;
      }
      final f = File(p.join(dir.path, filename));
      if (!await f.exists()) {
        removeKeys.add(entry.key);
      }
    }

    for (final k in removeKeys) {
      _index.remove(k);
    }
    if (removeKeys.isNotEmpty) {
      await _persistIndex();
    }
  }

  Future<void> _touch(
    String fileHash, {
    required String filename,
    required bool completed,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _index[fileHash] ?? <String, dynamic>{};
    prev['filename'] = filename;
    prev['completed'] = completed;
    prev['lastAccessMs'] = now;
    _index[fileHash] = prev;
    await _persistIndex();
  }

  Future<void> _enforceMax() async {
    final max = options.maxItems <= 0 ? 0 : options.maxItems;
    if (max <= 0) return;
    final dir = _cacheDir;
    if (dir == null) return;

    final completedEntries = _index.entries
        .where((e) => e.value['completed'] == true)
        .toList(growable: false);
    if (completedEntries.length <= max) return;

    completedEntries.sort((a, b) {
      final am = (a.value['lastAccessMs'] as num?)?.toInt() ?? 0;
      final bm = (b.value['lastAccessMs'] as num?)?.toInt() ?? 0;
      return am.compareTo(bm);
    });

    final overflow = completedEntries.length - max;
    final remove = completedEntries.take(overflow).toList(growable: false);
    for (final e in remove) {
      final filename = (e.value['filename'] ?? '').toString();
      if (filename.trim().isNotEmpty) {
        final f = File(p.join(dir.path, filename));
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
        final part = File(p.join(dir.path, '$filename.part'));
        if (await part.exists()) {
          try {
            await part.delete();
          } catch (_) {}
        }
      }
      _index.remove(e.key);
    }
    await _persistIndex();
  }

  Future<void> _downloadWithAuthRetry({
    required Future<String> Function() buildUrl,
    required Future<bool> Function() refreshAuthToken,
    required File partFile,
    required File finalFile,
    required int initialBytes,
    required int totalHint,
    required dio.CancelToken cancelToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    Uri? localProxyBase;
    var proxyAcquired = false;

    Future<String> mapUrl(String raw) async {
      final url = raw.trim();
      if (!ApiController.instance.isP2pMode) return url;
      if (!url.startsWith(ApiController.p2pBaseUrl)) return url;
      Uri remote;
      try {
        remote = Uri.parse(url);
      } catch (_) {
        return url;
      }
      localProxyBase ??= await LocalWebAssetServer.instance.acquire();
      proxyAcquired = true;
      return localProxyBase!
          .replace(path: remote.path, query: remote.query)
          .toString();
    }

    try {
      final url = await mapUrl(await buildUrl());
      await _downloadOnce(
        url: url,
        partFile: partFile,
        finalFile: finalFile,
        initialBytes: initialBytes,
        totalHint: totalHint,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    } on dio.DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      if (code != 401 && code != 403) rethrow;
      final refreshed = await refreshAuthToken();
      if (!refreshed) rethrow;
      final url = await mapUrl(await buildUrl());
      final retryBytes = await partFile.exists() ? await partFile.length() : 0;
      await _downloadOnce(
        url: url,
        partFile: partFile,
        finalFile: finalFile,
        initialBytes: retryBytes,
        totalHint: totalHint,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    } finally {
      if (proxyAcquired) {
        await LocalWebAssetServer.instance.release();
      }
    }
  }

  Future<void> _downloadOnce({
    required String url,
    required File partFile,
    required File finalFile,
    required int initialBytes,
    required int totalHint,
    required dio.CancelToken cancelToken,
    required MusicAudioCacheProgressCallback onProgress,
  }) async {
    if (!await partFile.parent.exists()) {
      await partFile.parent.create(recursive: true);
    }

    var received = initialBytes;
    var totalBytes = totalHint;

    Future<dio.Response<dio.ResponseBody>> request({required int startBytes}) {
      final headers = startBytes > 0 ? {'Range': 'bytes=$startBytes-'} : null;
      return _dio.get<dio.ResponseBody>(
        url,
        options: dio.Options(
          responseType: dio.ResponseType.stream,
          headers: headers,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
        cancelToken: cancelToken,
      );
    }

    dio.Response<dio.ResponseBody> resp = await request(startBytes: received);

    if (received > 0 && resp.statusCode != 206) {
      if (await partFile.exists()) {
        await partFile.delete();
      }
      received = 0;
      resp = await request(startBytes: 0);
    }

    final status = resp.statusCode ?? 0;
    if (status != 200 && status != 206) {
      throw dio.DioException(
        requestOptions: resp.requestOptions,
        response: resp,
        type: dio.DioExceptionType.badResponse,
      );
    }

    totalBytes = _inferTotalBytes(resp, received, totalBytes);
    onProgress(
      MusicAudioCacheProgress(
        receivedBytes: received,
        totalBytes: totalBytes,
        finished: false,
      ),
    );

    final sink = partFile.openWrite(
      mode: received > 0 ? FileMode.append : FileMode.writeOnly,
    );
    var lastNotifyAt = DateTime.now().millisecondsSinceEpoch;

    try {
      final stream = resp.data?.stream;
      if (stream == null) {
        throw dio.DioException(
          requestOptions: resp.requestOptions,
          response: resp,
          type: dio.DioExceptionType.unknown,
        );
      }
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastNotifyAt > 120) {
          lastNotifyAt = now;
          onProgress(
            MusicAudioCacheProgress(
              receivedBytes: received,
              totalBytes: totalBytes,
              finished: false,
            ),
          );
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    onProgress(
      MusicAudioCacheProgress(
        receivedBytes: received,
        totalBytes: totalBytes,
        finished: false,
      ),
    );

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await partFile.rename(finalFile.path);
  }

  int _inferTotalBytes(
    dio.Response<dio.ResponseBody> resp,
    int receivedBefore,
    int hint,
  ) {
    if (hint > 0) return hint;
    final headers = resp.headers.map;
    final cr = headers['content-range']?.first;
    if (cr != null) {
      final m = RegExp(r'bytes\\s+\\d+-\\d+/(\\d+)').firstMatch(cr);
      if (m != null) {
        final t = int.tryParse(m.group(1) ?? '');
        if (t != null && t > 0) return t;
      }
    }
    final cl = headers['content-length']?.first;
    final len = cl != null ? int.tryParse(cl) : null;
    if (len != null && len > 0) {
      if ((resp.statusCode ?? 0) == 206 && receivedBefore > 0) {
        return receivedBefore + len;
      }
      return len;
    }
    return 0;
  }
}
