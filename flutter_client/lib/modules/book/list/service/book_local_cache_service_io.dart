import 'dart:async';
import 'dart:io';
import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/core/api/dio_bad_certificate_compat.dart';
import 'package:NasCabOS/utils/local_web_asset_server.dart';
import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BookLocalServeSession {
  final String url;
  final Future<void> Function() _close;
  bool _closed = false;

  BookLocalServeSession._(this.url, this._close);

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _close();
  }
}

class BookCacheEntry {
  final String fileHash;
  final String filePath;
  final int size;
  final DateTime modifiedAt;

  const BookCacheEntry({
    required this.fileHash,
    required this.filePath,
    required this.size,
    required this.modifiedAt,
  });
}

class BookLocalCacheService extends GetxService {
  static BookLocalCacheService get instance =>
      Get.isRegistered<BookLocalCacheService>()
      ? Get.find<BookLocalCacheService>()
      : Get.put(BookLocalCacheService(), permanent: true);

  final RxMap<String, double> downloadProgress = <String, double>{}.obs;
  final RxSet<String> cachedFileHashes = <String>{}.obs;

  final Map<String, Future<bool>> _inflight = <String, Future<bool>>{};
  final Map<String, String> _filePathByHash = <String, String>{};

  String? _cacheDirPath;
  HttpServer? _serveServer;
  Uri? _serveBaseUri;
  Future<Uri>? _serveStarting;
  final String _serveNonce = DateTime.now().microsecondsSinceEpoch
      .toRadixString(16);

  @override
  void onInit() {
    super.onInit();
    unawaited(_scanExistingCache());
  }

  @override
  void onClose() {
    final server = _serveServer;
    _serveServer = null;
    _serveBaseUri = null;
    _serveStarting = null;
    if (server != null) {
      unawaited(server.close(force: true));
    }
    super.onClose();
  }

  bool isCached(String fileHash) {
    final h = fileHash.trim();
    return h.isNotEmpty && cachedFileHashes.contains(h);
  }

  double? progressOf(String fileHash) {
    final h = fileHash.trim();
    if (h.isEmpty) return null;
    return downloadProgress[h];
  }

  String? cachedFilePathOf(String fileHash) {
    final h = fileHash.trim();
    if (h.isEmpty) return null;
    final fp = _filePathByHash[h];
    if (fp == null || fp.trim().isEmpty) return null;
    final file = File(fp);
    if (!file.existsSync()) return null;
    return fp;
  }

  Future<String> _ensureCacheDir() async {
    final cached = _cacheDirPath;
    if (cached != null && cached.trim().isNotEmpty) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'book_cache'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirPath = dir.path;
    return dir.path;
  }

  String _normalizeExt(String ext) {
    final raw = ext.trim();
    if (raw.isEmpty) return '';
    final noSpace = raw.replaceAll(' ', '');
    if (noSpace.isEmpty) return '';
    if (noSpace.startsWith('.')) return noSpace;
    return '.$noSpace';
  }

  String _sanitizeFileName(String name) {
    var v = name.trim();
    if (v.isEmpty) return 'book';

    v = v.replaceAll(RegExp(r'[\u0000-\u001F]'), '_');
    v = v.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    v = v.replaceAll(RegExp(r'\s+'), ' ').trim();
    v = v.replaceAll(RegExp(r'[. ]+$'), '');
    if (v.isEmpty) v = 'book';

    final upper = v.toUpperCase();
    const reserved = <String>{
      'CON',
      'PRN',
      'AUX',
      'NUL',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
    };
    if (reserved.contains(upper)) {
      v = '_$v';
    }

    const maxLen = 180;
    if (v.length > maxLen) {
      v = v.substring(0, maxLen).trim();
      v = v.replaceAll(RegExp(r'[. ]+$'), '');
      if (v.isEmpty) v = 'book';
    }

    return v;
  }

  String _cacheFolderForHash({
    required String cacheDir,
    required String fileHash,
  }) {
    final safeHash = fileHash.trim();
    return p.join(cacheDir, safeHash);
  }

  String _cacheFileName({
    required String fileHash,
    required String fileName,
    required String ext,
  }) {
    final base = _sanitizeFileName(fileName);
    final normalizedExt = _normalizeExt(ext);
    if (normalizedExt.isNotEmpty &&
        !base.toLowerCase().endsWith(normalizedExt.toLowerCase())) {
      return '$base$normalizedExt';
    }
    return base;
  }

  String _cacheFilePath({
    required String cacheDir,
    required String fileHash,
    required String fileName,
    required String ext,
  }) {
    final folder = _cacheFolderForHash(cacheDir: cacheDir, fileHash: fileHash);
    final name = _cacheFileName(
      fileHash: fileHash,
      fileName: fileName,
      ext: ext,
    );
    return p.join(folder, name);
  }

  Future<File?> _pickCachedFileFromFolder(Directory folder) async {
    File? picked;
    int pickedSize = 0;
    try {
      await for (final entity in folder.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.endsWith('.nascab_tmp')) continue;
        final size = await entity.length().catchError((_) => 0);
        if (size <= 0) continue;
        if (picked == null || size > pickedSize) {
          picked = entity;
          pickedSize = size;
        }
      }
    } catch (_) {}
    return picked;
  }

  Future<void> _scanExistingCache() async {
    try {
      final cacheDir = await _ensureCacheDir();
      final dir = Directory(cacheDir);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final hash = p.basename(entity.path).trim();
          if (hash.isEmpty) continue;
          final picked = await _pickCachedFileFromFolder(entity);
          if (picked == null) continue;
          cachedFileHashes.add(hash);
          _filePathByHash[hash] = picked.path;
          continue;
        }

        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.endsWith('.nascab_tmp')) continue;
          final dot = name.indexOf('.');
          final hash = (dot > 0 ? name.substring(0, dot) : name).trim();
          if (hash.isEmpty) continue;
          final size = await entity.length().catchError((_) => 0);
          if (size <= 0) continue;

          final folderPath = _cacheFolderForHash(
            cacheDir: cacheDir,
            fileHash: hash,
          );
          final folder = Directory(folderPath);
          if (!folder.existsSync()) {
            folder.createSync(recursive: true);
          }
          final destPath = p.join(folderPath, name);
          try {
            if (!File(destPath).existsSync()) {
              await entity.rename(destPath);
            } else {
              await entity.delete().catchError((_) => entity);
            }
            cachedFileHashes.add(hash);
            _filePathByHash[hash] = destPath;
          } catch (_) {
            cachedFileHashes.add(hash);
            _filePathByHash[hash] = entity.path;
          }
        }
      }
    } catch (_) {}
  }

  Future<List<BookCacheEntry>> listCacheEntries() async {
    await _scanExistingCache();
    final hashes = cachedFileHashes.toList();
    if (hashes.isEmpty) return const <BookCacheEntry>[];

    final entries = <BookCacheEntry>[];
    for (final h in hashes) {
      final fp = _filePathByHash[h];
      if (fp == null || fp.trim().isEmpty) continue;
      final f = File(fp);
      if (!f.existsSync()) continue;
      final size = await f.length().catchError((_) => 0);
      if (size <= 0) continue;
      DateTime modifiedAt = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        modifiedAt = (await f.stat()).modified;
      } catch (_) {}
      entries.add(
        BookCacheEntry(
          fileHash: h,
          filePath: fp,
          size: size,
          modifiedAt: modifiedAt,
        ),
      );
    }

    entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return entries;
  }

  Future<int> clearAllCaches() async {
    final cacheDir = await _ensureCacheDir();
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) return 0;

    int deleted = 0;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          if (entity is Directory) {
            if (entity.existsSync()) {
              entity.deleteSync(recursive: true);
              deleted += 1;
            }
            continue;
          }
          if (entity is File) {
            if (entity.existsSync()) {
              entity.deleteSync();
              deleted += 1;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    cachedFileHashes.clear();
    downloadProgress.clear();
    _filePathByHash.clear();
    return deleted;
  }

  Future<bool> ensureCached({
    required String fileHash,
    required String fileName,
    required String ext,
    required String remoteUrl,
    required int expectedSize,
  }) async {
    final h = fileHash.trim();
    if (h.isEmpty) return false;

    if (isCached(h)) {
      final fp = _filePathByHash[h];
      if (fp != null && File(fp).existsSync()) return true;
      cachedFileHashes.remove(h);
      _filePathByHash.remove(h);
    }

    final inflight = _inflight[h];
    if (inflight != null) return await inflight;

    final future = _ensureCachedInternal(
      fileHash: h,
      fileName: fileName,
      ext: ext,
      remoteUrl: remoteUrl,
      expectedSize: expectedSize,
    );
    _inflight[h] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(h);
    }
  }

  Future<bool> _ensureCachedInternal({
    required String fileHash,
    required String fileName,
    required String ext,
    required String remoteUrl,
    required int expectedSize,
  }) async {
    final cacheDir = await _ensureCacheDir();
    final finalPath = _cacheFilePath(
      cacheDir: cacheDir,
      fileHash: fileHash,
      fileName: fileName,
      ext: ext,
    );
    final tmpPath = '$finalPath.nascab_tmp';

    try {
      final finalFile = File(finalPath);
      if (finalFile.existsSync()) {
        final len = finalFile.lengthSync();
        if (len > 0) {
          cachedFileHashes.add(fileHash);
          _filePathByHash[fileHash] = finalPath;
          return true;
        }
        finalFile.deleteSync();
      }

      final tmpFile = File(tmpPath);
      if (tmpFile.existsSync()) {
        tmpFile.deleteSync();
      }

      final folder = Directory(p.dirname(tmpPath));
      if (!folder.existsSync()) {
        folder.createSync(recursive: true);
      }

      downloadProgress[fileHash] = 0;
      final ok = await _downloadToTmpFile(
        url: remoteUrl,
        tmpFile: tmpFile,
        expectedSize: expectedSize,
        fileHash: fileHash,
      );
      if (!ok) {
        downloadProgress.remove(fileHash);
        if (tmpFile.existsSync()) tmpFile.deleteSync();
        return false;
      }

      await tmpFile.rename(finalPath);
      downloadProgress.remove(fileHash);
      cachedFileHashes.add(fileHash);
      _filePathByHash[fileHash] = finalPath;
      return true;
    } catch (_) {
      downloadProgress.remove(fileHash);
      try {
        final tmpFile = File(tmpPath);
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  Future<bool> _downloadToTmpFile({
    required String url,
    required File tmpFile,
    required int expectedSize,
    required String fileHash,
  }) async {
    String effectiveUrl = url;
    final uri = Uri.tryParse(url);
    if (uri != null &&
        ApiController.instance.isP2pMode &&
        uri.origin.trim() == ApiController.p2pBaseUrl) {
      try {
        final proxyBase = await LocalWebAssetServer.instance.acquire();
        effectiveUrl = proxyBase
            .replace(path: uri.path, query: uri.hasQuery ? uri.query : null)
            .toString();
      } catch (_) {
        effectiveUrl = url;
      }
    }

    final client = createDioWithBadCertificateCompat();
    final resp = await client.get<dio.ResponseBody>(
      effectiveUrl,
      options: dio.Options(
        responseType: dio.ResponseType.stream,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 20),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );

    final totalHeader = resp.headers.value('content-length');
    final headerSize = int.tryParse((totalHeader ?? '').trim()) ?? 0;
    final total = expectedSize > 0 ? expectedSize : headerSize;

    final sink = tmpFile.openWrite(mode: FileMode.write);
    int received = 0;
    final completer = Completer<bool>();

    void finish(bool ok) {
      if (completer.isCompleted) return;
      completer.complete(ok);
    }

    final sub = resp.data!.stream.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          downloadProgress[fileHash] = p;
        }
      },
      onDone: () async {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
        if (total > 0 && received < total) {
          finish(false);
          return;
        }
        finish(received > 0);
      },
      onError: (_) async {
        try {
          await sink.close();
        } catch (_) {}
        finish(false);
      },
      cancelOnError: true,
    );

    final ok = await completer.future;
    await sub.cancel().catchError((_) {});
    return ok;
  }

  Future<Uri> _ensureServeBaseUri() {
    final existing = _serveBaseUri;
    if (existing != null && _serveServer != null) {
      return Future.value(existing);
    }
    final starting = _serveStarting;
    if (starting != null) return starting;
    final future = _startServeServer();
    _serveStarting = future;
    return future.whenComplete(() {
      _serveStarting = null;
    });
  }

  Future<Uri> _startServeServer() async {
    if (_serveServer != null && _serveBaseUri != null) return _serveBaseUri!;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _serveServer = server;
    _serveBaseUri = Uri.parse('http://127.0.0.1:${server.port}');

    unawaited(() async {
      try {
        await for (final req in server) {
          unawaited(_handleServeRequest(req));
        }
      } finally {
        if (identical(_serveServer, server)) {
          _serveServer = null;
          _serveBaseUri = null;
        }
      }
    }());

    return _serveBaseUri!;
  }

  Future<void> _handleServeRequest(HttpRequest req) async {
    try {
      req.response.headers.set('Access-Control-Allow-Origin', '*');
      req.response.headers.set(
        'Access-Control-Allow-Methods',
        'GET,HEAD,OPTIONS',
      );
      req.response.headers.set(
        'Access-Control-Allow-Headers',
        'Range, Content-Type, Accept, Origin',
      );
      req.response.headers.set(
        'Access-Control-Expose-Headers',
        'Accept-Ranges, Content-Range, Content-Length',
      );

      if (req.method == 'OPTIONS') {
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      }

      final segments = req.uri.pathSegments;
      if (segments.length != 3 ||
          segments[0] != 'book' ||
          segments[1] != _serveNonce) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final hash = segments[2].trim();
      final fp = _filePathByHash[hash];
      if (hash.isEmpty || fp == null || fp.trim().isEmpty) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final file = File(fp);
      if (!file.existsSync()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final len = await file.length();
      req.response.headers.set('Accept-Ranges', 'bytes');
      req.response.headers.contentType = ContentType.binary;
      req.response.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-store, no-cache, must-revalidate, proxy-revalidate',
      );

      final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
      int start = 0;
      int end = len - 1;
      bool isRange = false;
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final part = rangeHeader.substring('bytes='.length).trim();
        final dash = part.indexOf('-');
        if (dash >= 0) {
          final s = part.substring(0, dash).trim();
          final e = part.substring(dash + 1).trim();
          final parsedStart = int.tryParse(s);
          final parsedEnd = int.tryParse(e);
          if (parsedStart != null) start = parsedStart;
          if (parsedEnd != null) end = parsedEnd;
          if (start < 0) start = 0;
          if (end >= len) end = len - 1;
          if (start <= end && start < len) isRange = true;
        }
      }

      if (req.method == 'HEAD') {
        if (isRange) {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/$len',
          );
          req.response.headers.contentLength = end - start + 1;
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentLength = len;
        }
        await req.response.close();
        return;
      }

      if (isRange) {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$len',
        );
        req.response.headers.contentLength = end - start + 1;
        await req.response.addStream(file.openRead(start, end + 1));
        await req.response.close();
        return;
      }

      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentLength = len;
      await req.response.addStream(file.openRead());
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<BookLocalServeSession?> openLocalServeSession({
    required String fileHash,
  }) async {
    final h = fileHash.trim();
    if (h.isEmpty) return null;
    final fp = _filePathByHash[h];
    if (fp == null || fp.trim().isEmpty) return null;
    final file = File(fp);
    if (!file.existsSync()) return null;
    final baseUri = await _ensureServeBaseUri();
    final url = baseUri.replace(path: '/book/$_serveNonce/$h').toString();
    return BookLocalServeSession._(url, () async {});
  }

  Future<bool> deleteCache({required String fileHash}) async {
    final h = fileHash.trim();
    if (h.isEmpty) return false;
    final cacheDir = await _ensureCacheDir();
    final folderPath = _cacheFolderForHash(cacheDir: cacheDir, fileHash: h);
    bool deleted = false;
    try {
      final folder = Directory(folderPath);
      if (folder.existsSync()) {
        folder.deleteSync(recursive: true);
        deleted = true;
      }
    } catch (_) {}

    cachedFileHashes.remove(h);
    downloadProgress.remove(h);
    _filePathByHash.remove(h);
    return deleted;
  }
}
