import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/core/api/api_parts/p2p_channel_util.dart';
import 'package:NasCabOS/core/api/p2p_rtc_stub.dart'
    if (dart.library.html) 'package:NasCabOS/core/api/p2p_rtc_web.dart';
import 'package:NasCabOS/modules/video_player/cache/video_range_memory_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Media3 等原生播放器经本地代理时附加；仅用于跳过 Range 内存缓存，转发前会剥离。
const String nascabNoRangeCacheQueryKey = 'nascabNoRangeCache';

bool isNascabNoRangeCacheRequest(Uri uri) {
  final v = uri.queryParameters[nascabNoRangeCacheQueryKey]?.trim().toLowerCase();
  return v == '1' || v == 'true';
}

String upstreamQueryForProxy(Uri uri) {
  if (!uri.hasQuery) return '';
  final qp = Map<String, String>.from(uri.queryParameters);
  qp.remove(nascabNoRangeCacheQueryKey);
  if (qp.isEmpty) return '';
  return Uri(queryParameters: qp).query;
}

class _P2pStallDetector {
  final void Function() onCancel;
  final void Function() onForceReconnect;
  final Duration stallThreshold;
  final Duration reconnectThreshold;
  final int minBytesThreshold;

  int _idleTicks = 0;
  int _totalBytes = 0;
  bool _stallCanceled = false;
  bool _stallRecovered = false;
  Timer? _timer;
  DateTime? _lastForcedReconnectAt;
  bool _started = false;

  _P2pStallDetector({required this.onCancel, required this.onForceReconnect})
    : stallThreshold = const Duration(seconds: 4),
      reconnectThreshold = const Duration(seconds: 6),
      minBytesThreshold = 256 * 1024;

  void start({
    required bool isLongRequest,
    required bool isRelay,
    required P2pRtcChannel channel,
  }) {
    if (!isLongRequest) return;
    if (channel != P2pRtcChannel.video &&
        channel != P2pRtcChannel.file &&
        channel != P2pRtcChannel.upload &&
        channel != P2pRtcChannel.download) {
      return;
    }

    _started = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick(isRelay: isRelay);
    });
  }

  void onData(int bytes) {
    if (!_started) return;
    if (bytes > 0) {
      _idleTicks = 0;
      _totalBytes += bytes;
      _stallCanceled = false;
      _stallRecovered = false;
    }
  }

  void _tick({required bool isRelay}) {
    _idleTicks += 1;

    if (!_stallCanceled &&
        _idleTicks >= stallThreshold.inSeconds &&
        _totalBytes >= minBytesThreshold) {
      _stallCanceled = true;
      onCancel();
    }

    if (!_stallRecovered &&
        isRelay &&
        _idleTicks >= reconnectThreshold.inSeconds &&
        _totalBytes >= minBytesThreshold) {
      final now = DateTime.now();
      if (_lastForcedReconnectAt == null ||
          now.difference(_lastForcedReconnectAt!) >=
              const Duration(seconds: 12)) {
        _lastForcedReconnectAt = now;
        _stallRecovered = true;
        onForceReconnect();
      }
    }
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  int get totalBytes => _totalBytes;
  int get idleTicks => _idleTicks;
}

/// 本地 HTTP 代理，仅用于「必须拿到 http(s) URL」的 P2P 场景（如地图瓦片、本地视频播放器）。
/// 普通 P2P 图片/API 走 [ApiController.sendP2pRequest] / [sendP2pRequestOnChannel]，不经过本 server。
///
/// 启停由 P2P 连接状态驱动：P2P 连接时保持开启，切回直连时关闭；由 [ApiController.setBaseUrl] 通过 [setP2pActive] 同步。
class LocalWebAssetServer {
  LocalWebAssetServer._();

  static final LocalWebAssetServer instance = LocalWebAssetServer._();

  HttpServer? _server;
  Uri? _baseUri;
  Future<Uri>? _starting;
  bool _p2pActive = false;
  int _videoRefCount = 0;
  Timer? _stopTimer;

  bool get isRunning => _server != null && _baseUri != null;
  int get videoRefCount => _videoRefCount;

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[LocalWebAssetServer] $message');
  }

  /// 由 [ApiController] 在 setBaseUrl 时调用：P2P 模式为 true，直连为 false。
  void setP2pActive(bool active) {
    if (kIsWeb) return;
    if (_p2pActive == active) return;
    _p2pActive = active;
    _stopTimer?.cancel();
    _stopTimer = null;
    if (active) {
      _log('p2p active -> ensure start');
      unawaited(ensureStarted());
    } else {
      _log('p2p inactive -> schedule stop');
      _stopTimer = Timer(const Duration(milliseconds: 800), () async {
        _stopTimer = null;
        if (_p2pActive) return;
        await _maybeStop();
      });
    }
  }

  /// 原画 rawFile 播放持有本地代理（直连也走 127.0.0.1 + Range 内存缓存）。
  Future<Uri> acquireForVideo() async {
    if (kIsWeb) {
      throw UnsupportedError('LocalWebAssetServer only available on IO');
    }
    _videoRefCount += 1;
    _stopTimer?.cancel();
    _stopTimer = null;
    _log('video acquire ref=$_videoRefCount');
    return ensureStarted();
  }

  Future<void> releaseForVideo() async {
    if (kIsWeb) return;
    if (_videoRefCount > 0) _videoRefCount -= 1;
    _log('video release ref=$_videoRefCount');
    await _maybeStop();
  }

  Future<void> _maybeStop() async {
    if (_p2pActive || _videoRefCount > 0) return;
    await stop();
  }

  String _redactUriForLog(Uri uri) {
    if (!uri.hasQuery) return uri.toString();
    final qp = Map<String, String>.from(uri.queryParameters);
    if (qp.containsKey('accessToken')) {
      qp['accessToken'] = '***';
    }
    final sanitized = uri.replace(queryParameters: qp);
    return sanitized.toString();
  }

  String _redactUrlForLog(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return raw;
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return raw;
    return _redactUriForLog(parsed);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0B';
    if (bytes < 1024) return '${bytes}B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KiB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)}MiB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)}GiB';
  }

  String _formatRate(int bytesPerSec) {
    if (bytesPerSec <= 0) return '0B/s';
    return '${_formatBytes(bytesPerSec)}/s';
  }

  /// 获取本地代理 base URI，仅在 P2P 模式下有效；启停由 [setP2pActive] 控制，无需再 release。
  Future<Uri> acquire() {
    if (kIsWeb) {
      throw UnsupportedError('LocalWebAssetServer only available on IO');
    }
    return ensureStarted();
  }

  /// 已废弃：启停由 P2P 状态驱动，无需手动 release；保留仅为兼容旧调用，无副作用。
  Future<void> release() async {
    if (kIsWeb) return;
    // no-op，由 setP2pActive(false) 统一关闭
  }

  Future<Uri> ensureStarted() {
    if (kIsWeb) {
      throw UnsupportedError('LocalWebAssetServer only available on IO');
    }
    final existing = _baseUri;
    if (existing != null) {
      _log('reuse base=$existing');
      return Future.value(existing);
    }
    final starting = _starting;
    if (starting != null) return starting;
    final task = _start();
    _starting = task;
    return task.whenComplete(() {
      _starting = null;
    });
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    final srv = _server;
    _server = null;
    _baseUri = null;
    if (srv != null) {
      _log('stop port=${srv.port}');
      await srv.close(force: true);
    }
  }

  Future<Uri> _start() async {
    if (_server != null && _baseUri != null) return _baseUri!;

    HttpServer? srv;
    try {
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (_) {
      for (var i = 0; i < 10; i++) {
        final port = 46000 + (DateTime.now().microsecondsSinceEpoch % 12000);
        try {
          srv = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
          break;
        } catch (_) {}
      }
    }
    if (srv == null) {
      throw Exception('local_server_bind_failed');
    }

    _server = srv;
    _baseUri = Uri.parse('http://127.0.0.1:${srv.port}');

    _log('started base=$_baseUri');
    unawaited(_serveLoop(srv));

    return _baseUri!;
  }

  Future<void> _serveLoop(HttpServer srv) async {
    await for (final req in srv) {
      unawaited(_handle(req));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    _log('${req.method} ${_redactUriForLog(req.uri)}');
    try {
      final path = req.uri.path;
      if (path == '/reader' || path == '/reader/') {
        final redirect = Uri(
          path: '/reader/reader.html',
          query: req.uri.hasQuery ? req.uri.query : null,
        );
        _log('302 -> $redirect');
        req.response.statusCode = HttpStatus.found;
        req.response.headers.set(
          HttpHeaders.locationHeader,
          redirect.toString(),
        );
        await req.response.close();
        return;
      }
      if (path.startsWith('/api/')) {
        if (isVideoRawFilePath(path) &&
            VideoRangeCacheManager.instance.options.enabled &&
            !isNascabNoRangeCacheRequest(req.uri)) {
          final served = await _tryServeRawFileWithCache(req);
          if (served) return;
        }
        await _proxy(req);
        return;
      }

      final assetPath = _mapToAssetPath(path);
      if (assetPath == null) {
        _log('404 unmapped path=$path');
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final bytes = await _loadAssetBytes(assetPath);
      if (bytes == null) {
        _log('404 asset not found assetPath=$assetPath');
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      final contentType = _contentTypeForAsset(assetPath);
      if (contentType != null) {
        req.response.headers.contentType = contentType;
      } else {
        req.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/octet-stream',
        );
      }
      req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      req.response.add(bytes);
      await req.response.close();
      _log('200 asset=$assetPath bytes=${bytes.length}');
    } catch (_) {
      _log('500 exception uri=${req.uri}');
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// 将 HTTP 请求路径映射为 Flutter asset key（供 rootBundle.load 使用）。
  /// 此处始终用 assets/web/...，与 pubspec 一致；与 Web 平台 URL 的 assets/assets/web/... 无关。
  String? _mapToAssetPath(String requestPath) {
    String normalized = requestPath.trim();
    if (!normalized.startsWith('/')) normalized = '/$normalized';

    if (normalized.startsWith('/reader/')) {
      final rest = normalized.substring('/reader/'.length);
      if (rest.isEmpty || rest.contains('..')) return null;
      return 'assets/web/reader/$rest';
    }

    if (normalized.startsWith('/web/viewer/')) {
      final rest = normalized.substring('/web/viewer/'.length);
      if (rest.isEmpty || rest.contains('..')) return null;
      return 'assets/web/viewer/$rest';
    }

    return null;
  }

  Future<Uint8List?> _loadAssetBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (e) {
      _log('load asset failed assetPath=$assetPath err=$e');
      return null;
    }
  }

  ContentType? _contentTypeForAsset(String assetPath) {
    final lower = assetPath.toLowerCase();
    if (lower.endsWith('.html')) {
      return ContentType('text', 'html', charset: 'utf-8');
    }
    if (lower.endsWith('.js')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (lower.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (lower.endsWith('.json')) {
      return ContentType('application', 'json', charset: 'utf-8');
    }
    if (lower.endsWith('.txt')) {
      return ContentType('text', 'plain', charset: 'utf-8');
    }
    if (lower.endsWith('.svg')) {
      return ContentType('image', 'svg+xml', charset: 'utf-8');
    }
    if (lower.endsWith('.png')) return ContentType('image', 'png');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return ContentType('image', 'jpeg');
    }
    if (lower.endsWith('.gif')) return ContentType('image', 'gif');
    if (lower.endsWith('.webp')) return ContentType('image', 'webp');
    if (lower.endsWith('.woff2')) return ContentType('font', 'woff2');
    if (lower.endsWith('.woff')) return ContentType('font', 'woff');
    if (lower.endsWith('.ttf')) return ContentType('font', 'ttf');
    if (lower.endsWith('.otf')) return ContentType('font', 'otf');
    if (lower.endsWith('.bcmap')) {
      return ContentType('application', 'octet-stream');
    }
    if (lower.endsWith('.wasm')) return ContentType('application', 'wasm');
    return null;
  }

  Future<bool> _tryServeRawFileWithCache(HttpRequest clientReq) async {
    final api = ApiController.instance;
    final base = api.baseUrl.trim();
    if (base.isEmpty) return false;
    try {
      return await VideoRangeCacheManager.instance.handleRawFileRequest(
        clientReq: clientReq,
        baseUrl: base,
        fetcher: ({
          required String method,
          required Map<String, String> clientHeaders,
          required String? rangeHeader,
        }) {
          return _fetchUpstreamForRawFile(
            clientReq,
            method: method,
            clientHeaders: clientHeaders,
            rangeHeader: rangeHeader,
          );
        },
      );
    } catch (e) {
      _log('rawFile cache failed: $e');
      return false;
    }
  }

  Future<UpstreamRangeResponse> _fetchUpstreamForRawFile(
    HttpRequest clientReq, {
    required String method,
    required Map<String, String> clientHeaders,
    required String? rangeHeader,
  }) async {
    final api = ApiController.instance;
    final base = api.baseUrl.trim();
    if (base.isEmpty) {
      return UpstreamRangeResponse(
        status: HttpStatus.badGateway,
        headers: const {},
        body: Stream<List<int>>.empty(),
      );
    }

    final shouldUseP2p = api.isP2pMode && base == ApiController.p2pBaseUrl;
    if (shouldUseP2p) {
      return _fetchUpstreamP2p(
        clientReq,
        method: method,
        clientHeaders: clientHeaders,
        rangeHeader: rangeHeader,
      );
    }
    return _fetchUpstreamDirect(
      clientReq,
      method: method,
      clientHeaders: clientHeaders,
      rangeHeader: rangeHeader,
    );
  }

  Future<UpstreamRangeResponse> _fetchUpstreamDirect(
    HttpRequest clientReq, {
    required String method,
    required Map<String, String> clientHeaders,
    required String? rangeHeader,
  }) async {
    final api = ApiController.instance;
    final baseUri = Uri.parse(api.baseUrl.trim());
    final target = baseUri.replace(
      path: clientReq.uri.path,
      query: upstreamQueryForProxy(clientReq.uri),
    );

    final httpClient = HttpClient();
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;

    HttpClientRequest upstream;
    try {
      upstream = await httpClient.openUrl(method, target);
    } catch (_) {
      httpClient.close(force: true);
      return UpstreamRangeResponse(
        status: HttpStatus.badGateway,
        headers: const {},
        body: Stream<List<int>>.empty(),
      );
    }

    clientHeaders.forEach((name, value) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.hostHeader) return;
      if (key == HttpHeaders.rangeHeader && rangeHeader != null) return;
      upstream.headers.set(name, value);
    });
    if (rangeHeader != null && rangeHeader.isNotEmpty) {
      upstream.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    }

    final authHeader = clientHeaders[HttpHeaders.authorizationHeader];
    final qpAccessToken = clientReq.uri.queryParameters['accessToken'];
    final token = (api.accessToken ?? '').trim();
    if ((authHeader == null || authHeader.trim().isEmpty) &&
        (qpAccessToken == null || qpAccessToken.trim().isEmpty) &&
        token.isNotEmpty) {
      upstream.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    HttpClientResponse upstreamRes;
    try {
      upstreamRes = await upstream.close();
    } catch (_) {
      httpClient.close(force: true);
      return UpstreamRangeResponse(
        status: HttpStatus.badGateway,
        headers: const {},
        body: Stream<List<int>>.empty(),
      );
    }

    final headers = <String, String>{};
    upstreamRes.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });

    Stream<List<int>> bodyStream() async* {
      try {
        await for (final chunk in upstreamRes) {
          yield chunk;
        }
      } finally {
        httpClient.close(force: true);
      }
    }

    return UpstreamRangeResponse(
      status: upstreamRes.statusCode,
      headers: headers,
      body: bodyStream(),
    );
  }

  Future<UpstreamRangeResponse> _fetchUpstreamP2p(
    HttpRequest clientReq, {
    required String method,
    required Map<String, String> clientHeaders,
    required String? rangeHeader,
  }) async {
    final api = ApiController.instance;

    if (!api.isP2pReady) {
      try {
        await api.ensureP2pConnected(timeout: const Duration(seconds: 12));
      } catch (_) {}
    }
    if (!api.isP2pReady) {
      return UpstreamRangeResponse(
        status: HttpStatus.serviceUnavailable,
        headers: const {},
        body: Stream<List<int>>.empty(),
      );
    }

    final target = Uri.parse(ApiController.p2pBaseUrl).replace(
      path: clientReq.uri.path,
      query: upstreamQueryForProxy(clientReq.uri),
    );

    final headers = Map<String, String>.from(clientHeaders);
    if (rangeHeader != null && rangeHeader.isNotEmpty) {
      headers[HttpHeaders.rangeHeader] = rangeHeader;
    }

    final token = (api.accessToken ?? '').trim();
    final authHeader = headers[HttpHeaders.authorizationHeader];
    final qpAccessToken = clientReq.uri.queryParameters['accessToken'];
    if ((authHeader == null || authHeader.trim().isEmpty) &&
        (qpAccessToken == null || qpAccessToken.trim().isEmpty) &&
        token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }

    final p = target.path;
    final channel =
        P2pChannelUtil.parseMark(clientReq.uri.queryParameters['p2pChannel']) ??
        P2pChannelUtil.fallbackForPath(p);
    final range = rangeHeader ?? '';
    final isLong =
        channel == P2pRtcChannel.video ||
        channel == P2pRtcChannel.download ||
        channel == P2pRtcChannel.upload ||
        range.isNotEmpty;

    final req = http.Request(method, target);
    if (headers.isNotEmpty) req.headers.addAll(headers);

    P2pStreamedResponse upstreamRes;
    try {
      upstreamRes = await api.sendP2pStreamRequest(
        req,
        timeout: isLong
            ? const Duration(minutes: 30)
            : const Duration(seconds: 60),
        channel: channel,
      );
    } catch (_) {
      return UpstreamRangeResponse(
        status: HttpStatus.badGateway,
        headers: const {},
        body: Stream<List<int>>.empty(),
      );
    }

    final resHeaders = <String, String>{};
    upstreamRes.headers.forEach((name, value) {
      resHeaders[name] = value;
    });

    return UpstreamRangeResponse(
      status: upstreamRes.status,
      headers: resHeaders,
      body: upstreamRes.stream,
      cancel: () {
        try {
          upstreamRes.cancel();
        } catch (_) {}
      },
    );
  }

  Future<void> _proxy(HttpRequest clientReq) async {
    final api = ApiController.instance;
    final base = api.baseUrl.trim();
    if (base.isEmpty) {
      _log('502 proxy baseUrl empty');
      clientReq.response.statusCode = HttpStatus.badGateway;
      await clientReq.response.close();
      return;
    }

    final shouldUseP2pProxy = api.isP2pMode && base == ApiController.p2pBaseUrl;
    if (shouldUseP2pProxy) {
      await _proxyViaP2p(clientReq);
      return;
    }

    final baseUri = Uri.parse(base);
    final target = baseUri.replace(
      path: clientReq.uri.path,
      query: upstreamQueryForProxy(clientReq.uri),
    );
    _log('proxy -> ${_redactUriForLog(target)}');

    final httpClient = HttpClient();
    httpClient.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;

    HttpClientRequest upstream;
    try {
      upstream = await httpClient.openUrl(clientReq.method, target);
    } catch (_) {
      _log('proxy openUrl failed target=$target');
      clientReq.response.statusCode = HttpStatus.badGateway;
      await clientReq.response.close();
      httpClient.close(force: true);
      return;
    }

    clientReq.headers.forEach((name, values) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.hostHeader) return;
      if (key == HttpHeaders.contentLengthHeader) return;
      if (key == HttpHeaders.connectionHeader) return;
      for (final v in values) {
        upstream.headers.add(name, v);
      }
    });
    final authHeader = clientReq.headers.value(HttpHeaders.authorizationHeader);
    final qpAccessToken = clientReq.uri.queryParameters['accessToken'];
    final token = (api.accessToken ?? '').trim();
    if ((authHeader == null || authHeader.trim().isEmpty) &&
        (qpAccessToken == null || qpAccessToken.trim().isEmpty) &&
        token.isNotEmpty) {
      upstream.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }

    try {
      await upstream.addStream(clientReq);
    } catch (_) {}

    HttpClientResponse upstreamRes;
    try {
      upstreamRes = await upstream.close();
    } catch (_) {
      _log('proxy upstream close failed target=$target');
      clientReq.response.statusCode = HttpStatus.badGateway;
      await clientReq.response.close();
      httpClient.close(force: true);
      return;
    }

    clientReq.response.statusCode = upstreamRes.statusCode;
    _log('proxy status=${upstreamRes.statusCode} target=$target');

    upstreamRes.headers.forEach((name, values) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.transferEncodingHeader) return;
      if (key == HttpHeaders.connectionHeader) return;
      for (final v in values) {
        try {
          clientReq.response.headers.add(name, v);
        } catch (_) {}
      }
    });

    try {
      await clientReq.response.addStream(upstreamRes);
    } catch (_) {}
    try {
      await clientReq.response.close();
    } catch (_) {}
    httpClient.close(force: true);
  }

  Future<void> _proxyViaP2p(HttpRequest clientReq) async {
    final api = ApiController.instance;
    final base = api.baseUrl.trim();
    if (base.isEmpty) {
      _log('502 proxy baseUrl empty(p2p)');
      clientReq.response.statusCode = HttpStatus.badGateway;
      await clientReq.response.close();
      return;
    }

    final p0 = clientReq.uri.path;
    final channel0 =
        P2pChannelUtil.parseMark(clientReq.uri.queryParameters['p2pChannel']) ??
        P2pChannelUtil.fallbackForPath(p0);
    final range0 = clientReq.headers.value(HttpHeaders.rangeHeader) ?? '';
    final isLong0 =
        channel0 == P2pRtcChannel.video ||
        channel0 == P2pRtcChannel.download ||
        channel0 == P2pRtcChannel.upload ||
        range0.isNotEmpty;

    if (!api.isP2pReady) {
      if (isLong0) {
        try {
          await api.ensureP2pConnected(timeout: const Duration(seconds: 12));
        } catch (_) {}
      }

      if (!api.isP2pReady) {
        final maxWait = isLong0
            ? const Duration(seconds: 12)
            : const Duration(milliseconds: 1500);
        try {
          await api.onP2pReadyChanged
              .firstWhere((ready) => ready)
              .timeout(maxWait);
        } on TimeoutException {
          // 超时继续检查
        } catch (_) {
          // 其他错误
        }
      }
    }
    if (!api.isP2pReady) {
      _log('503 proxy(p2p) not ready');
      clientReq.response.statusCode = HttpStatus.serviceUnavailable;
      try {
        clientReq.response.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
      } catch (_) {}
      try {
        clientReq.response.write('{"code":-1,"message":"p2p_not_ready"}');
      } catch (_) {}
      await clientReq.response.close();
      return;
    }

    final target = Uri.parse(ApiController.p2pBaseUrl).replace(
      path: clientReq.uri.path,
      query: upstreamQueryForProxy(clientReq.uri),
    );
    _log('proxy(p2p) -> ${_redactUriForLog(target)}');

    final headers = <String, String>{};
    clientReq.headers.forEach((name, values) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.hostHeader) return;
      if (key == HttpHeaders.contentLengthHeader) return;
      if (key == HttpHeaders.connectionHeader) return;
      if (values.isEmpty) return;
      headers[name] = values.join(',');
    });
    final authHeader = clientReq.headers.value(HttpHeaders.authorizationHeader);
    final qpAccessToken = clientReq.uri.queryParameters['accessToken'];
    final token = (api.accessToken ?? '').trim();
    if ((authHeader == null || authHeader.trim().isEmpty) &&
        (qpAccessToken == null || qpAccessToken.trim().isEmpty) &&
        token.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }

    Uint8List bodyBytes = Uint8List(0);
    try {
      final bb = BytesBuilder(copy: false);
      await for (final chunk in clientReq) {
        bb.add(chunk);
      }
      bodyBytes = bb.takeBytes();
    } catch (_) {
      bodyBytes = Uint8List(0);
    }

    final req = http.Request(clientReq.method, target);
    if (headers.isNotEmpty) req.headers.addAll(headers);
    if (bodyBytes.isNotEmpty) req.bodyBytes = bodyBytes;

    final p = target.path;
    final channel =
        P2pChannelUtil.parseMark(clientReq.uri.queryParameters['p2pChannel']) ??
        P2pChannelUtil.fallbackForPath(p);
    final range = clientReq.headers.value(HttpHeaders.rangeHeader) ?? '';
    final isLong =
        channel == P2pRtcChannel.video ||
        channel == P2pRtcChannel.download ||
        channel == P2pRtcChannel.upload ||
        range.isNotEmpty;

    final reqId =
        '${DateTime.now().millisecondsSinceEpoch}_${clientReq.hashCode & 0xffff}';
    final rangeLog = range;
    final isRelay = api.p2pTransportKind == P2pTransportKind.relay;
    final relayAddress = api.p2pRelayAddress.trim();
    final pathOnly = clientReq.uri.hasQuery
        ? '${clientReq.uri.path}?${clientReq.uri.query}'
        : clientReq.uri.path;
    final safePath = _redactUrlForLog(pathOnly);
    if (kDebugMode && isLong) {
      _log(
        'p2p[$reqId] start ch=$channel '
        '${isRelay ? 'relay${relayAddress.isNotEmpty ? "=$relayAddress" : ""}' : 'direct'} '
        'method=${clientReq.method} path=$safePath'
        '${rangeLog.isNotEmpty ? ' range=$rangeLog' : ''} '
        'up=${_formatBytes(bodyBytes.length)}',
      );
      unawaited(() async {
        final stats = await api.getP2pTransportStats();
        if (stats.isEmpty) return;
        final brief = <String, String>{};
        final kPrefix = channel == P2pRtcChannel.api
            ? 'api'
            : (channel == P2pRtcChannel.file
                  ? 'file'
                  : (channel == P2pRtcChannel.upload
                        ? 'upload'
                        : (channel == P2pRtcChannel.download
                              ? 'download'
                              : 'video')));
        for (final k in <String>[
          'type',
          'protocol',
          'rttMs',
          'availableOutgoingBitrate',
          'availableIncomingBitrate',
          '${kPrefix}DcBuffered',
          '${kPrefix}TxPackets',
          '${kPrefix}RxPackets',
        ]) {
          final v = stats[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            brief[k] = v.toString();
          }
        }
        _log('p2p[$reqId] transport=$brief');
      }());
    }

    P2pStreamedResponse upstreamRes;
    try {
      upstreamRes = await ApiController.instance.sendP2pStreamRequest(
        req,
        timeout: isLong
            ? const Duration(minutes: 30)
            : const Duration(seconds: 60),
        channel: channel,
      );
    } catch (e) {
      _log('proxy(p2p) failed target=${_redactUriForLog(target)} err=$e');
      clientReq.response.statusCode = HttpStatus.badGateway;
      await clientReq.response.close();
      return;
    }

    clientReq.response.statusCode = upstreamRes.status;
    _log(
      'proxy(p2p) status=${upstreamRes.status} target=${_redactUriForLog(target)}',
    );

    upstreamRes.headers.forEach((name, value) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.transferEncodingHeader) return;
      if (key == HttpHeaders.connectionHeader) return;
      try {
        clientReq.response.headers.set(name, value);
      } catch (_) {}
    });
    try {
      clientReq.response.bufferOutput = false;
    } catch (_) {}

    final startedAt = DateTime.now();
    int downBytes = 0;
    int downChunks = 0;
    int minChunk = 0;
    int maxChunk = 0;
    DateTime? firstByteAt;
    int lastLoggedBytes = 0;
    Timer? trafficTimer;

    late final _P2pStallDetector stallDetector;
    stallDetector = _P2pStallDetector(
      onCancel: () {
        _log('p2p[$reqId] stallCancel idleTicks=${stallDetector.idleTicks}');
        try {
          upstreamRes.cancel();
        } catch (_) {}
      },
      onForceReconnect: () {
        _log(
          'p2p[$reqId] stallRecover idleTicks=${stallDetector.idleTicks} forcingReconnect=1',
        );
        try {
          upstreamRes.cancel();
        } catch (_) {}
        unawaited(api.forceReconnectP2p(timeout: const Duration(seconds: 15)));
      },
    );

    stallDetector.start(
      isLongRequest: isLong,
      isRelay: isRelay,
      channel: channel,
    );

    final shouldLogTraffic = kDebugMode && isLong;
    if (shouldLogTraffic) {
      final ct = upstreamRes.headers[HttpHeaders.contentTypeHeader] ?? '';
      final cl = upstreamRes.headers[HttpHeaders.contentLengthHeader] ?? '';
      final cr = upstreamRes.headers[HttpHeaders.contentRangeHeader] ?? '';
      if (ct.isNotEmpty || cl.isNotEmpty || cr.isNotEmpty) {
        _log(
          'p2p[$reqId] resHeaders '
          '${ct.isNotEmpty ? 'content-type=$ct ' : ''}'
          '${cl.isNotEmpty ? 'content-length=$cl ' : ''}'
          '${cr.isNotEmpty ? 'content-range=$cr' : ''}',
        );
      }
      trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final delta = downBytes - lastLoggedBytes;
        lastLoggedBytes = downBytes;
        if (delta <= 0 && downBytes <= 0) return;
        _log(
          'p2p[$reqId] down=${_formatRate(delta)} total=${_formatBytes(downBytes)} chunks=$downChunks '
          'chunk[min=${_formatBytes(minChunk)} max=${_formatBytes(maxChunk)}]',
        );
        if (delta <= 0 && stallDetector.idleTicks >= 3) {
          unawaited(() async {
            final stats = await api.getP2pTransportStats();
            if (stats.isEmpty) return;
            final brief = <String, String>{};
            final kPrefix = channel == P2pRtcChannel.api
                ? 'api'
                : (channel == P2pRtcChannel.file
                      ? 'file'
                      : (channel == P2pRtcChannel.download
                            ? 'download'
                            : 'video'));
            for (final k in <String>[
              'type',
              'protocol',
              'rttMs',
              'availableOutgoingBitrate',
              'availableIncomingBitrate',
              '${kPrefix}RxIdleMs',
              '${kPrefix}DcBuffered',
              '${kPrefix}RxBinaryPackets',
              '${kPrefix}RxTextPackets',
              '${kPrefix}RxPackets',
              '${kPrefix}RxBytes',
            ]) {
              final v = stats[k];
              if (v != null && v.toString().trim().isNotEmpty) {
                brief[k] = v.toString();
              }
            }
            _log('p2p[$reqId] stalled transport=$brief');
          }());
        }
      });
    }

    final trackedStream = upstreamRes.stream.map((chunk) {
      if (firstByteAt == null && chunk.isNotEmpty) {
        firstByteAt = DateTime.now();
      }
      downBytes += chunk.length;
      downChunks += 1;
      if (minChunk == 0 || chunk.length < minChunk) minChunk = chunk.length;
      if (chunk.length > maxChunk) maxChunk = chunk.length;
      stallDetector.onData(chunk.length);
      return chunk;
    });

    try {
      await clientReq.response.addStream(trackedStream);
    } catch (e) {
      if (shouldLogTraffic) {
        _log('p2p[$reqId] addStreamError=$e');
      }
    }
    try {
      await clientReq.response.close();
    } catch (_) {}
    try {
      upstreamRes.cancel();
    } catch (_) {}

    stallDetector.stop();
    if (trafficTimer != null) {
      trafficTimer.cancel();
    }

    if (shouldLogTraffic) {
      final dur = DateTime.now().difference(startedAt);
      final durMs = dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds;
      final avgBps = (downBytes * 1000 ~/ durMs);
      final ttfbMs = firstByteAt == null
          ? -1
          : firstByteAt!.difference(startedAt).inMilliseconds;
      _log(
        'p2p[$reqId] done status=${upstreamRes.status} '
        'ttfbMs=$ttfbMs durMs=$durMs '
        'down=${_formatBytes(downBytes)} avg=${_formatRate(avgBps)} chunks=$downChunks '
        'chunk[min=${_formatBytes(minChunk)} max=${_formatBytes(maxChunk)}]',
      );
      unawaited(() async {
        final stats = await api.getP2pTransportStats();
        if (stats.isEmpty) return;
        final brief = <String, String>{};
        final kPrefix = channel == P2pRtcChannel.api
            ? 'api'
            : (channel == P2pRtcChannel.file
                  ? 'file'
                  : (channel == P2pRtcChannel.download ? 'download' : 'video'));
        for (final k in <String>[
          'type',
          'protocol',
          'rttMs',
          'bytesSent',
          'bytesReceived',
          'packetsSent',
          'packetsReceived',
          '${kPrefix}DcBuffered',
          '${kPrefix}TxPackets',
          '${kPrefix}TxBytes',
          '${kPrefix}RxPackets',
          '${kPrefix}RxBytes',
          '${kPrefix}RxIdleMs',
        ]) {
          final v = stats[k];
          if (v != null && v.toString().trim().isNotEmpty) {
            brief[k] = v.toString();
          }
        }
        _log('p2p[$reqId] transportEnd=$brief');
      }());
    }
  }
}
