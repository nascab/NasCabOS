import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:http/http.dart' as http;
import '../../../core/api/api_controller.dart';
import '../../../core/api/http_client_factory.dart'
    if (dart.library.html) '../../../core/api/http_client_factory_web.dart'
    if (dart.library.io) '../../../core/api/http_client_factory_io.dart';
import '../../../core/api/api_parts/p2p_channel_util.dart';
import '../../../core/cache/cache_manager_factory.dart';
import 'image_cache_size_util.dart'
    if (dart.library.io) 'image_cache_size_util_io.dart';
import 'p2p_image_cache.dart' if (dart.library.io) 'p2p_image_cache_io.dart';

class CustomExtendedImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Alignment alignment;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;
  final double? width;
  final double? height;
  final bool showLoading;
  final double borderRadius;
  final bool cache;
  final ExtendedImageMode mode;
  final InitGestureConfigHandler? initGestureConfigHandler;
  final DoubleTap? onDoubleTap;
  final Key? extendedImageKey;

  const CustomExtendedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.loadingBuilder,
    this.width,
    this.height,
    this.borderRadius = 4.0,
    this.cache = true,
    this.mode = ExtendedImageMode.none,
    this.initGestureConfigHandler,
    this.onDoubleTap,
    this.showLoading = true,
    this.alignment = Alignment.center,
    this.extendedImageKey,
  });

  @override
  State<CustomExtendedImage> createState() => _CustomExtendedImageState();

  /// 非 tiny 图片内存缓存最大字节数，默认 500MB，可配置（所有端生效）
  static int generalImageMemoryCacheMaxBytes = 500 * 1024 * 1024;

  /// 切换服务器或退出登录时清理会话相关内存缓存，避免跨服务器复用旧图片/失败请求。
  static void invalidateSessionCaches() {
    _inFlightLoads.clear();
    _generalImageMemoryCache.clear();
    _webTinyImageMemoryCache.clear();
  }

  /// 清理缓存
  static Future<void> clearCache() async {
    /// 清理内存缓存
    clearMemoryImageCache();

    /// 清理磁盘缓存
    if (!kIsWeb) {
      clearDiskCachedImages();
    } else {
      _webTinyImageMemoryCache.clear();
    }
    _generalImageMemoryCache.clear();
    try {
      await CustomCacheManager.clearCache();
    } catch (_) {}
  }

  static Future<int> getCacheSizeBytes() async {
    if (kIsWeb) return 0;
    return getImageDiskCacheSizeBytes();
  }

  /// 进行中的加载 Future，按 url 去重，避免预加载未完成时滑到该页重复请求。
  static final Map<String, Future<Uint8List>> _inFlightLoads = {};

  /// 获取或创建加载 Future：先查缓存，再查进行中请求，否则发起加载并登记。预加载与组件共用此方法，保证同一 url 只请求一次。
  static Future<Uint8List> getOrCreateLoadFuture(String imageUrl) async {
    final url = imageUrl.trim();
    if (url.isEmpty) throw Exception('empty_image_url');
    if (_shouldUseP2pStatic(url)) {
      return _getOrCreateLoadFutureP2p(url);
    }
    return _getOrCreateLoadFutureDirect(url);
  }

  /// 预加载图片到内存/磁盘缓存，供 gallery 等场景提前加载下一张，滑动时即显。
  /// 与组件共用 getOrCreateLoadFuture，未完成时滑到该页会复用同一请求，不会重复加载。
  static Future<void> preload(String imageUrl) async {
    final url = imageUrl.trim();
    if (url.isEmpty) return;
    try {
      await getOrCreateLoadFuture(url);
    } catch (_) {
      // 预加载失败静默忽略，避免影响主流程
    }
  }

  static Map<String, String> _staticGetHeaders() {
    final headers = <String, String>{};
    try {
      final token = ApiController.instance.accessToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  static bool _shouldUseP2pStatic(String url) {
    if (!ApiController.instance.isP2pMode) return false;
    final u = url.trim();
    if (u.isEmpty) return false;
    if (u.startsWith('/')) return true;
    if (u.startsWith(ApiController.p2pBaseUrl)) return true;
    return false;
  }

  static String _extractP2pPathStatic(String url) {
    final u = url.trim();
    if (u.startsWith('/')) return u;
    if (u.startsWith(ApiController.p2pBaseUrl)) {
      try {
        final uri = Uri.parse(u);
        if (uri.hasQuery) return '${uri.path}?${uri.query}';
        return uri.path;
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  static Future<Uint8List> _loadP2pBytesStatic(String path) async {
    final p = path.startsWith('/') ? path : '/$path';
    Uri uri;
    try {
      uri = Uri.parse('${ApiController.p2pBaseUrl}$p');
    } catch (_) {
      uri = Uri();
    }
    final resolved = P2pChannelUtil.resolve(uri: uri);
    final req = http.Request('GET', Uri.parse('${ApiController.p2pBaseUrl}$p'));
    req.headers.addAll(_staticGetHeaders());
    final neverCompletes = Completer<void>();
    final streamed = await ApiController.instance.sendP2pRequestOnChannel(
      req,
      channel: resolved.channel,
      cancelFuture: neverCompletes.future,
    );
    final body = await http.ByteStream(streamed.stream).toBytes();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('p2p_image_http_${streamed.statusCode}');
    }
    if (streamed.statusCode == 202) {
      throw Exception('p2p_image_http_202');
    }
    return body;
  }

  static String _p2pCacheKeyStatic(String url) =>
      md5.convert(utf8.encode(url.trim())).toString();

  static Future<Uint8List> _getOrCreateLoadFutureP2p(String url) async {
    final path = _extractP2pPathStatic(url);
    if (path.isEmpty) throw Exception('p2p_empty_path');
    final tinyCache = _computeTinyImageCache(url);
    final cacheKey = (tinyCache.useCache && tinyCache.cacheKey != null)
        ? tinyCache.cacheKey!
        : _p2pCacheKeyStatic(url);
    final cached = await readP2pImageCache(cacheKey);
    if (cached != null && cached.isNotEmpty) return cached;
    if (_inFlightLoads.containsKey(url)) return _inFlightLoads[url]!;
    final completer = Completer<Uint8List>();
    _loadP2pBytesStatic(path)
        .then((bytes) async {
          await writeP2pImageCache(cacheKey, bytes);
          if (!completer.isCompleted) {
            completer.complete(bytes);
          }
        })
        .catchError((Object e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        })
        .catchError((_) {}); // 吸收 catchError 回调内可能的异常，避免未捕获错误
    final future = completer.future;
    _inFlightLoads[url] = future;
    future.whenComplete(() => _inFlightLoads.remove(url));
    return future;
  }

  static Future<Uint8List> _getOrCreateLoadFutureDirect(String url) async {
    final tinyCache = _computeTinyImageCache(url);
    if (tinyCache.useCache && tinyCache.cacheKey != null && kIsWeb) {
      final key = tinyCache.cacheKey!;
      final cached = _webTinyImageMemoryCache.get(key);
      if (cached != null && cached.isNotEmpty) return cached;
    } else {
      final key = _generalImageCacheKey(url);
      final cached = _generalImageMemoryCache.get(key);
      if (cached != null && cached.isNotEmpty) return cached;
    }
    if (_inFlightLoads.containsKey(url)) return _inFlightLoads[url]!;
    final completer = Completer<Uint8List>();
    _loadDirectBytesStatic(url)
        .then((bytes) {
          if (tinyCache.useCache && tinyCache.cacheKey != null && kIsWeb) {
            _webTinyImageMemoryCache.put(tinyCache.cacheKey!, bytes);
          } else {
            _generalImageMemoryCache.put(_generalImageCacheKey(url), bytes);
          }
          if (!completer.isCompleted) {
            completer.complete(bytes);
          }
        })
        .catchError((Object e) {
          // 显式 catchError 避免 Flutter zone 将异常上报为 Unhandled Exception
          // 实际错误会由 FutureBuilder 的 snapshot.hasError 捕获并触发重试
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        })
        .catchError((_) {}); // 吸收 catchError 回调内可能的异常，避免未捕获错误
    final future = completer.future;
    _inFlightLoads[url] = future;
    future.whenComplete(() => _inFlightLoads.remove(url));
    return future;
  }

  static Future<Uint8List> _loadDirectBytesStatic(String url) async {
    Uri uri;
    try {
      uri = Uri.parse(url.trim());
    } catch (_) {
      throw Exception('direct_image_invalid_url');
    }
    final client = createHttpClient();
    try {
      final resp = await client.get(uri, headers: _staticGetHeaders());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('direct_image_http_${resp.statusCode}');
      }
      if (resp.statusCode == 202) {
        throw Exception('direct_image_http_202');
      }
      return resp.bodyBytes;
    } finally {
      client.close();
    }
  }
}

/// /api/file/tiny 接口路径，仅此类 URL 参与自定义缓存
const String _kTinyImagePath = '/api/file/tiny';

/// 仅对 /api/file/tiny?aes=xxx 的图片做缓存；cacheKey = server_id + "/api/file/tiny?aes=xxx"。
/// 若 url 非 tiny、或无 aes 参数、或无 server_id，则返回 useCache:false 并打日志。
({bool useCache, String? cacheKey}) _computeTinyImageCache(String url) {
  final u = url.trim();
  if (u.isEmpty) return (useCache: false, cacheKey: null);
  Uri uri;
  try {
    uri = Uri.parse(u);
  } catch (_) {
    return (useCache: false, cacheKey: null);
  }
  final path = uri.path;
  if (path != _kTinyImagePath) {
    return (useCache: false, cacheKey: null);
  }
  final aes = uri.queryParameters['aes'];
  if (aes == null || aes.isEmpty) {
    if (kDebugMode) {
      debugPrint('CustomExtendedImage: 跳过缓存，URL 不包含 aes 参数: $u');
    }
    return (useCache: false, cacheKey: null);
  }
  String serverId;
  try {
    serverId = ApiController.instance.state.serverId;
  } catch (_) {
    serverId = '';
  }
  if (serverId.isEmpty) {
    if (kDebugMode) {
      debugPrint('CustomExtendedImage: 跳过缓存，无 server_id: $u');
    }
    return (useCache: false, cacheKey: null);
  }
  // 逻辑 key = server_id + "/api/file/tiny?aes=xxx"，用于区分服务器与资源
  final logicalKey = '$serverId$_kTinyImagePath?aes=$aes';
  // 对逻辑 key 做 MD5，得到文件系统安全的 cacheKey，避免 "/"、"?" 等被当作路径导致 404
  final cacheKey = md5.convert(utf8.encode(logicalKey)).toString();
  // if (kDebugMode) {
  //   debugPrint('CustomExtendedImage [直连] cacheKey: $cacheKey  logicalKey: $logicalKey');
  // }
  return (useCache: true, cacheKey: cacheKey);
}

/// 判断 URL 是否指向 /api/file/tiny 缩略图接口
bool _isTinyUrl(String url) {
  try {
    final uri = Uri.parse(url.trim());
    return uri.path == _kTinyImagePath;
  } catch (_) {
    return false;
  }
}

/// 缩略图 404 重试配置：服务端可能返回 404 但后台正在异步生成缩略图，
/// 需要指数退避重试等待生成完成。
const int _kTiny404MaxRetries = 5;
const Duration _kTiny404InitialDelay = Duration(milliseconds: 500);

/// Web 端 tiny 图片的内存缓存，仅用于直连 tiny（/api/file/tiny?aes=xxx）。
/// 最大占用约 200MB，先进先出。
const int _kWebTinyImageMaxBytes = 200 * 1024 * 1024;

class _WebTinyImageMemoryCache {
  _WebTinyImageMemoryCache(this._maxBytes);

  final int _maxBytes;
  final Map<String, Uint8List> _store = <String, Uint8List>{};
  final List<String> _order = <String>[];
  int _currentBytes = 0;

  Uint8List? get(String key) {
    final value = _store[key];
    if (kDebugMode) {
      debugPrint(
        'CustomExtendedImage[WebTinyCache] get key=$key '
        'hit=${value != null} '
        'current=${_currentBytes ~/ 1024}KB '
        'max=${_maxBytes ~/ 1024}KB',
      );
    }
    return value;
  }

  void put(String key, Uint8List bytes) {
    final size = bytes.lengthInBytes;
    // 单个资源超过上限则直接跳过，不缓存
    if (size > _maxBytes) {
      if (kDebugMode) {
        debugPrint(
          'CustomExtendedImage[WebTinyCache] skip put key=$key '
          'reason=too_large size=${size ~/ 1024}KB '
          'max=${_maxBytes ~/ 1024}KB',
        );
      }
      return;
    }

    final existing = _store[key];
    if (existing != null) {
      _currentBytes -= existing.lengthInBytes;
      // 保持原有顺序（FIFO），不移动到队尾
    } else {
      _order.add(key);
    }

    _store[key] = bytes;
    _currentBytes += size;
    _evictIfNeeded();
    if (kDebugMode) {
      debugPrint(
        'CustomExtendedImage[WebTinyCache] put key=$key '
        'size=${size ~/ 1024}KB '
        'current=${_currentBytes ~/ 1024}KB '
        'max=${_maxBytes ~/ 1024}KB',
      );
    }
  }

  void clear() {
    _store.clear();
    _order.clear();
    _currentBytes = 0;
    if (kDebugMode) {
      debugPrint('CustomExtendedImage[WebTinyCache] cleared');
    }
  }

  void _evictIfNeeded() {
    if (!kDebugMode) {
      while (_currentBytes > _maxBytes && _order.isNotEmpty) {
        final oldestKey = _order.removeAt(0);
        final removed = _store.remove(oldestKey);
        if (removed != null) {
          _currentBytes -= removed.lengthInBytes;
        }
      }
      return;
    }

    int evictedCount = 0;
    int evictedBytes = 0;
    while (_currentBytes > _maxBytes && _order.isNotEmpty) {
      final oldestKey = _order.removeAt(0);
      final removed = _store.remove(oldestKey);
      if (removed != null) {
        final sz = removed.lengthInBytes;
        _currentBytes -= sz;
        evictedCount += 1;
        evictedBytes += sz;
      }
    }
    if (evictedCount > 0) {
      debugPrint(
        'CustomExtendedImage[WebTinyCache] evict count=$evictedCount '
        'bytesFreed=${evictedBytes ~/ 1024}KB '
        'current=${_currentBytes ~/ 1024}KB '
        'max=${_maxBytes ~/ 1024}KB',
      );
    }
  }
}

final _webTinyImageMemoryCache = _WebTinyImageMemoryCache(
  _kWebTinyImageMaxBytes,
);

/// 非 tiny 图片的通用内存缓存（所有端），容量可配置，FIFO 淘汰
class _GeneralImageMemoryCache {
  _GeneralImageMemoryCache(this._getMaxBytes);

  final int Function() _getMaxBytes;
  int get _maxBytes => _getMaxBytes();

  final Map<String, Uint8List> _store = <String, Uint8List>{};
  final List<String> _order = <String>[];
  int _currentBytes = 0;

  Uint8List? get(String key) => _store[key];

  void put(String key, Uint8List bytes) {
    final size = bytes.lengthInBytes;
    if (size > _maxBytes) return;
    final existing = _store[key];
    if (existing != null) {
      _currentBytes -= existing.lengthInBytes;
    } else {
      _order.add(key);
    }
    _store[key] = bytes;
    _currentBytes += size;
    _evictIfNeeded();
  }

  void clear() {
    _store.clear();
    _order.clear();
    _currentBytes = 0;
  }

  void _evictIfNeeded() {
    while (_currentBytes > _maxBytes && _order.isNotEmpty) {
      final oldestKey = _order.removeAt(0);
      final removed = _store.remove(oldestKey);
      if (removed != null) {
        _currentBytes -= removed.lengthInBytes;
      }
    }
  }
}

final _generalImageMemoryCache = _GeneralImageMemoryCache(
  () => CustomExtendedImage.generalImageMemoryCacheMaxBytes,
);

/// 非 tiny 图片的缓存 key：URL 的 MD5
String _generalImageCacheKey(String url) =>
    md5.convert(utf8.encode(url.trim())).toString();

class _CustomExtendedImageState extends State<CustomExtendedImage> {
  Future<Uint8List>? _p2pBytesFuture;
  String _p2pKey = '';
  Future<Uint8List>? _directBytesFuture;
  String _directUrlKey = '';
  http.Client? _webDirectClient;
  CancellationToken? _nonWebDirectCancelToken;
  Completer<void>? _p2pCancelCompleter;

  /// 缩略图 404 重试计数，URL 变化时重置
  int _tiny404RetryCount = 0;

  /// 缩略图 404 重试定时器，dispose 时取消
  Timer? _tiny404RetryTimer;

  /// 获取认证头信息
  Map<String, String> _getHeaders() {
    final headers = <String, String>{};
    try {
      final token = ApiController.instance.accessToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  bool _shouldUseP2pBytes(String url) {
    if (!ApiController.instance.isP2pMode) return false;
    final u = url.trim();
    if (u.isEmpty) return false;
    if (u.startsWith('/')) return true;
    if (u.startsWith(ApiController.p2pBaseUrl)) return true;
    return false;
  }

  String _extractP2pPath(String url) {
    final u = url.trim();
    if (u.startsWith('/')) return u;
    if (u.startsWith(ApiController.p2pBaseUrl)) {
      try {
        final uri = Uri.parse(u);
        if (uri.hasQuery) return '${uri.path}?${uri.query}';
        return uri.path;
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  Future<Uint8List> _loadBytesViaP2p(String path) async {
    final p = path.startsWith('/') ? path : '/$path';
    Uri uri;
    try {
      uri = Uri.parse('${ApiController.p2pBaseUrl}$p');
    } catch (_) {
      uri = Uri();
    }
    final resolved = P2pChannelUtil.resolve(uri: uri);
    final channel = resolved.channel;
    final req = http.Request('GET', Uri.parse('${ApiController.p2pBaseUrl}$p'));
    req.headers.addAll(_getHeaders());

    // 为当前 P2P 请求创建/重置取消句柄，组件销毁或路径切换时会调用 _cancelP2pRequestIfNeeded。
    _cancelP2pRequestIfNeeded();
    final cancel = Completer<void>();
    _p2pCancelCompleter = cancel;

    try {
      final streamed = await ApiController.instance.sendP2pRequestOnChannel(
        req,
        channel: channel,
        cancelFuture: cancel.future,
      );
      final body = await http.ByteStream(streamed.stream).toBytes();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception('p2p_image_http_${streamed.statusCode}');
      }
      if (streamed.statusCode == 202) {
        throw Exception('p2p_image_http_202');
      }
      return body;
    } catch (e) {
      // 对于主动取消（p2p_canceled），视为正常结束，不抛错给上层，避免控制台红错。
      final s = e.toString();
      if (s.contains('p2p_canceled')) {
        return Uint8List(0);
      }
      rethrow;
    } finally {
      // 请求结束（无论成功/失败/取消），清理取消句柄
      if (identical(_p2pCancelCompleter, cancel)) {
        _p2pCancelCompleter = null;
      }
    }
  }

  bool _isReconnectableP2pError(Object e) {
    final s = e.toString();
    return s.contains('p2p_not_connected') ||
        s.contains('p2p_disconnected') ||
        s.contains('p2p_dc_closed') ||
        s.contains('p2p_dc_error') ||
        s.contains('p2p_ws_error') ||
        s.contains('p2p_ws_closed') ||
        s.contains('p2p_dc_not_open');
  }

  bool _isRetryableP2pImageHttpError(Object e) {
    final s = e.toString();
    return s.contains('p2p_image_http_502') ||
        s.contains('p2p_image_http_503') ||
        s.contains('p2p_image_http_504');
  }

  Future<Uint8List> _loadBytesViaP2pWithRetry(String path) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      if (attempt > 0) {
        final delay = attempt == 1
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 800);
        await Future<void>.delayed(delay);
      }

      try {
        return await _loadBytesViaP2p(path);
      } catch (e) {
        lastError = e;

        final shouldRetry =
            _isReconnectableP2pError(e) || _isRetryableP2pImageHttpError(e);
        if (!shouldRetry) rethrow;

        try {
          await ApiController.instance.ensureP2pConnected(
            timeout: const Duration(seconds: 15),
          );
        } catch (_) {}
      }
    }
    throw lastError ?? Exception('p2p_image_failed');
  }

  /// 与直连一致：用 url 的 md5 作为磁盘缓存 key（与 extended_image_library 同目录）
  static String _p2pCacheKey(String url) =>
      md5.convert(utf8.encode(url)).toString();

  /// P2P 模式下先读磁盘缓存，未命中再请求并写入缓存。
  /// 对 /api/file/tiny?aes=xxx 使用与直连相同的 cacheKey（serverId + path + aes 的 MD5），以便与直连共用缓存。
  Future<Uint8List> _loadP2pBytesWithCache(String path) async {
    if (!widget.cache || kIsWeb) {
      return await _loadBytesViaP2pWithRetry(path);
    }
    final url = widget.imageUrl.trim();
    final tinyCache = _computeTinyImageCache(url);
    final key = (tinyCache.useCache && tinyCache.cacheKey != null)
        ? tinyCache.cacheKey!
        : _p2pCacheKey(url);
    // if (kDebugMode) {
    //   debugPrint('CustomExtendedImage [P2P] cacheKey: $key  url: $url');
    // }
    final cached = await readP2pImageCache(key);
    if (cached != null && cached.isNotEmpty) return cached;
    final bytes = await _loadBytesViaP2pWithRetry(path);
    await writeP2pImageCache(key, bytes);
    return bytes;
  }

  void _cancelP2pRequestIfNeeded() {
    final c = _p2pCancelCompleter;
    if (c != null && !c.isCompleted) {
      try {
        c.complete();
        print("取消P2P请求 避免流量消耗");
      } catch (_) {
        print("取消P2P异常");
      }
    }
    _p2pCancelCompleter = null;
  }

  /// Web 直连加载图片字节（带认证头）。
  Future<Uint8List> _loadDirectBytes(String url) async {
    Uri uri;
    try {
      uri = Uri.parse(url.trim());
    } catch (_) {
      throw Exception('direct_image_invalid_url');
    }
    _webDirectClient ??= createHttpClient();
    final client = _webDirectClient!;

    if (kDebugMode) {
      debugPrint('CustomExtendedImage[WebDirect] GET $uri');
    }
    final resp = await client.get(uri, headers: _getHeaders());
    if (kDebugMode) {
      debugPrint(
        'CustomExtendedImage[WebDirect] status=${resp.statusCode} '
        'bytes=${resp.bodyBytes.lengthInBytes}',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('direct_image_http_${resp.statusCode}');
    }
    if (resp.statusCode == 202) {
      throw Exception('direct_image_http_202');
    }
    return resp.bodyBytes;
  }

  /// 直连加载图片字节：tiny 在 Web 上用 tiny 内存缓存；非 tiny 在所有端用通用内存缓存（可配置容量）。
  Future<Uint8List> _loadDirectBytesWithCache(String url) async {
    if (!widget.cache) {
      return _loadDirectBytes(url);
    }
    final tinyCache = _computeTinyImageCache(url);
    // tiny 仅 Web 使用 200MB 内存缓存
    if (tinyCache.useCache && tinyCache.cacheKey != null && kIsWeb) {
      final key = tinyCache.cacheKey!;
      final cached = _webTinyImageMemoryCache.get(key);
      if (cached != null && cached.isNotEmpty) return cached;
      final bytes = await _loadDirectBytes(url);
      _webTinyImageMemoryCache.put(key, bytes);
      return bytes;
    }
    // 非 tiny：所有端使用通用内存缓存（500MB 可配置）
    final key = _generalImageCacheKey(url);
    final cached = _generalImageMemoryCache.get(key);
    if (cached != null && cached.isNotEmpty) return cached;
    final bytes = await _loadDirectBytes(url);
    _generalImageMemoryCache.put(key, bytes);
    return bytes;
  }

  void _maybeInitP2pFuture() {
    final url = widget.imageUrl.trim();
    if (!_shouldUseP2pBytes(url)) {
      _cancelP2pRequestIfNeeded();
      _p2pBytesFuture = null;
      _p2pKey = '';
      return;
    }
    final path = _extractP2pPath(url);
    if (path.isEmpty) {
      _cancelP2pRequestIfNeeded();
      _p2pBytesFuture = null;
      _p2pKey = '';
      return;
    }
    if (_p2pKey == path && _p2pBytesFuture != null) return;
    _p2pKey = path;
    // 与预加载共用 getOrCreateLoadFuture，避免未完成时滑到该页重复请求；无缓存时仍走原逻辑以保留取消能力
    if (widget.cache && !kIsWeb) {
      _p2pBytesFuture = CustomExtendedImage.getOrCreateLoadFuture(
        widget.imageUrl,
      );
    } else {
      _p2pBytesFuture = _loadP2pBytesWithCache(path);
    }
  }

  void _maybeInitDirectFuture() {
    final url = widget.imageUrl.trim();
    if (url.isEmpty || _shouldUseP2pBytes(url)) {
      _directBytesFuture = null;
      _directUrlKey = '';
      return;
    }
    // Web：直连一律走字节加载（tiny 用 tiny 缓存，非 tiny 用通用缓存）
    // 非 Web：开启 cache 时走字节加载 + 通用内存缓存（含 tiny），以支持 404 重试
    final useDirectBytes = kIsWeb || widget.cache;
    if (!useDirectBytes) {
      _directBytesFuture = null;
      _directUrlKey = '';
      return;
    }
    if (_directUrlKey == url && _directBytesFuture != null) {
      return;
    }
    _directUrlKey = url;
    // 与预加载共用 getOrCreateLoadFuture，避免未完成时滑到该页重复请求
    _directBytesFuture = CustomExtendedImage.getOrCreateLoadFuture(url);
  }

  /// 缩略图 404 重试：指数退避，最多 [_kTiny404MaxRetries] 次。
  /// 仅对当前可见的组件生效，dispose 时自动取消定时器。
  /// 返回 true 表示已安排重试，返回 false 表示重试次数已耗尽。
  bool _scheduleTiny404Retry() {
    if (_tiny404RetryTimer != null) return true; // 已有定时器在等待
    if (_tiny404RetryCount >= _kTiny404MaxRetries) return false;
    final delay = _kTiny404InitialDelay * (1 << _tiny404RetryCount);
    _tiny404RetryTimer = Timer(delay, () {
      _tiny404RetryTimer = null;
      _tiny404RetryCount++;
      // 重置 key 以强制重新发起请求
      _directUrlKey = '';
      _p2pKey = '';
      _directBytesFuture = null;
      _p2pBytesFuture = null;
      _maybeInitP2pFuture();
      _maybeInitDirectFuture();
      if (mounted) setState(() {});
    });
    return true;
  }

  /// 判断错误是否为缩略图接口的 202/404（服务端正在异步生成中，可重试）
  bool _isTinyPendingError(String url, Object? error) {
    if (!_isTinyUrl(url)) return false;
    final s = error.toString();
    return s.contains('direct_image_http_404') ||
        s.contains('direct_image_http_202') ||
        s.contains('p2p_image_http_404') ||
        s.contains('p2p_image_http_202');
  }

  @override
  void initState() {
    super.initState();
    _maybeInitP2pFuture();
    _maybeInitDirectFuture();
  }

  @override
  void dispose() {
    // 取消缩略图 404 重试定时器（组件不可见时不再重试）
    _tiny404RetryTimer?.cancel();
    _tiny404RetryTimer = null;
    // 关闭 Web 直连的 Client，中止未完成的 HTTP 请求
    _webDirectClient?.close();
    _webDirectClient = null;
    // 取消正在进行的非 Web 直连请求
    try {
      _nonWebDirectCancelToken?.cancel();
    } catch (_) {}
    _nonWebDirectCancelToken = null;
    // 取消正在进行的 P2P 请求
    _cancelP2pRequestIfNeeded();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomExtendedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      // URL 变化时重置重试计数
      _tiny404RetryCount = 0;
      _tiny404RetryTimer?.cancel();
      _tiny404RetryTimer = null;
    }
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _maybeInitP2pFuture();
      _maybeInitDirectFuture();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildErrorPlaceholder() {
      return Image.asset(
        'assets/icons/404.png',
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        // filterQuality: FilterQuality.high, // 高画质滤波，解决缩放锯齿
        // isAntiAlias: true, // 显式开启抗锯齿（Flutter 3.10+支持）
        errorBuilder: (context, error, stackTrace) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, error, stackTrace);
          }
          return Icon(
            Icons.broken_image_outlined,
            size: ((widget.width ?? widget.height ?? 48) * 0.8)
                .clamp(18, 120)
                .toDouble(),
            color: Theme.of(context).disabledColor,
          );
        },
      );
    }

    Widget buildLoadingPlaceholder({
      required Widget child,
      required ImageChunkEvent? loadingProgress,
    }) {
      if (loadingProgress == null) {
        return child;
      }
      if (!widget.showLoading) {
        return child;
      }
      if (widget.loadingBuilder != null) {
        return widget.loadingBuilder!(context, child, loadingProgress);
      }
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    int? computeCacheDimension(double? logical, double dpr) {
      if (logical == null || !logical.isFinite || logical <= 0) return null;
      final px = (logical * dpr).ceil();
      if (px <= 0) return null;
      return px;
    }

    ({int? cacheWidth, int? cacheHeight}) computeWebCacheDimensions(
      double? logicalWidth,
      double? logicalHeight,
      double dpr,
    ) {
      final w = computeCacheDimension(logicalWidth, dpr);
      final h = computeCacheDimension(logicalHeight, dpr);
      if (w == null || h == null) {
        return (cacheWidth: w, cacheHeight: h);
      }
      final maxSide = w > h ? w : h;
      return (cacheWidth: maxSide, cacheHeight: null);
    }

    if (widget.imageUrl.trim().isEmpty) {
      return buildErrorPlaceholder();
    }

    final url = widget.imageUrl.trim();
    final useP2pBytes = _shouldUseP2pBytes(url);

    if (useP2pBytes) {
      final fut = _p2pBytesFuture;
      if (fut == null) return buildErrorPlaceholder();
      return FutureBuilder<Uint8List>(
        future: fut,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            if (!widget.showLoading) return const SizedBox.shrink();
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            if (_isTinyPendingError(url, snapshot.error)) {
              if (_scheduleTiny404Retry()) {
                if (!widget.showLoading) return const SizedBox.shrink();
                return SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
            }
            return buildErrorPlaceholder();
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return buildErrorPlaceholder();

          if (kIsWeb) {
            final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
            final dims = computeWebCacheDimensions(
              widget.width,
              widget.height,
              dpr,
            );
            Widget image;
            if (widget.mode == ExtendedImageMode.gesture) {
              image = ExtendedImage.memory(
                bytes,
                key: widget.extendedImageKey,
                alignment: widget.alignment,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                cacheWidth: dims.cacheWidth,
                cacheHeight: dims.cacheHeight,
                filterQuality: FilterQuality.low,
                mode: widget.mode,
                shape: BoxShape.rectangle,
                initGestureConfigHandler: widget.initGestureConfigHandler,
                borderRadius: BorderRadius.all(
                  Radius.circular(widget.borderRadius),
                ),
                onDoubleTap: widget.onDoubleTap,
                loadStateChanged: (ExtendedImageState state) {
                  switch (state.extendedImageLoadState) {
                    case LoadState.loading:
                      if (!widget.showLoading) {
                        return null;
                      }
                      if (widget.loadingBuilder != null) {
                        return widget.loadingBuilder!(
                          context,
                          SizedBox(width: widget.width, height: widget.height),
                          state.loadingProgress,
                        );
                      }
                      return SizedBox(
                        width: widget.width,
                        height: widget.height,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    case LoadState.completed:
                      return null;
                    case LoadState.failed:
                      if (widget.errorBuilder != null) {
                        return widget.errorBuilder!(
                          context,
                          Exception('Failed to load image'),
                          null,
                        );
                      }
                      return buildErrorPlaceholder();
                  }
                },
              );
            } else {
              image = Image.memory(
                bytes,
                key: widget.extendedImageKey,
                alignment: widget.alignment,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                cacheWidth: dims.cacheWidth,
                cacheHeight: dims.cacheHeight,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  if (widget.errorBuilder != null) {
                    return widget.errorBuilder!(context, error, stackTrace);
                  }
                  return buildErrorPlaceholder();
                },
              );
            }

            if (widget.borderRadius <= 0) {
              return image;
            }

            return ClipRRect(
              borderRadius: BorderRadius.all(
                Radius.circular(widget.borderRadius),
              ),
              child: image,
            );
          }

          return ExtendedImage.memory(
            bytes,
            key: widget.extendedImageKey,
            alignment: widget.alignment,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            filterQuality: FilterQuality.low,
            mode: widget.mode,
            shape: BoxShape.rectangle,
            initGestureConfigHandler: widget.initGestureConfigHandler,
            borderRadius: BorderRadius.all(
              Radius.circular(widget.borderRadius),
            ),
            onDoubleTap: widget.onDoubleTap,
            loadStateChanged: (ExtendedImageState state) {
              switch (state.extendedImageLoadState) {
                case LoadState.loading:
                  if (!widget.showLoading) {
                    return null;
                  }
                  if (widget.loadingBuilder != null) {
                    return widget.loadingBuilder!(
                      context,
                      SizedBox(width: widget.width, height: widget.height),
                      state.loadingProgress,
                    );
                  }
                  return SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                case LoadState.completed:
                  return null;
                case LoadState.failed:
                  if (widget.errorBuilder != null) {
                    return widget.errorBuilder!(
                      context,
                      Exception('Failed to load image'),
                      null,
                    );
                  }
                  return buildErrorPlaceholder();
              }
            },
          );
        },
      );
    }

    final tinyCache = _computeTinyImageCache(url);
    final effectiveCache = tinyCache.useCache && widget.cache;
    final cacheKey = tinyCache.cacheKey;

    // Web 直连 或 非 Web 下非 tiny 且开启 cache：走字节加载 + 内存缓存，用 FutureBuilder
    if (_directBytesFuture != null) {
      return FutureBuilder<Uint8List>(
        future: _directBytesFuture!,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            if (!widget.showLoading) return const SizedBox.shrink();
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            if (_isTinyPendingError(url, snapshot.error)) {
              if (_scheduleTiny404Retry()) {
                if (!widget.showLoading) return const SizedBox.shrink();
                return SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
            }
            return buildErrorPlaceholder();
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) return buildErrorPlaceholder();

          final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
          final dims = computeWebCacheDimensions(
            widget.width,
            widget.height,
            dpr,
          );

          Widget image;
          if (widget.mode == ExtendedImageMode.gesture) {
            image = ExtendedImage.memory(
              bytes,
              key: widget.extendedImageKey,
              alignment: widget.alignment,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              cacheWidth: dims.cacheWidth,
              cacheHeight: dims.cacheHeight,
              filterQuality: FilterQuality.low,
              mode: widget.mode,
              shape: BoxShape.rectangle,
              initGestureConfigHandler: widget.initGestureConfigHandler,
              borderRadius: BorderRadius.all(
                Radius.circular(widget.borderRadius),
              ),
              onDoubleTap: widget.onDoubleTap,
              loadStateChanged: (ExtendedImageState state) {
                switch (state.extendedImageLoadState) {
                  case LoadState.loading:
                    if (!widget.showLoading) {
                      return null;
                    }
                    if (widget.loadingBuilder != null) {
                      return widget.loadingBuilder!(
                        context,
                        SizedBox(width: widget.width, height: widget.height),
                        state.loadingProgress,
                      );
                    }
                    return SizedBox(
                      width: widget.width,
                      height: widget.height,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  case LoadState.completed:
                    return null;
                  case LoadState.failed:
                    if (widget.errorBuilder != null) {
                      return widget.errorBuilder!(
                        context,
                        Exception('Failed to load image'),
                        null,
                      );
                    }
                    return buildErrorPlaceholder();
                }
              },
            );
          } else {
            image = Image.memory(
              bytes,
              key: widget.extendedImageKey,
              alignment: widget.alignment,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              cacheWidth: dims.cacheWidth,
              cacheHeight: dims.cacheHeight,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                if (widget.errorBuilder != null) {
                  return widget.errorBuilder!(context, error, stackTrace);
                }
                return buildErrorPlaceholder();
              },
            );
          }

          if (widget.borderRadius <= 0) {
            return image;
          }

          return ClipRRect(
            borderRadius: BorderRadius.all(
              Radius.circular(widget.borderRadius),
            ),
            child: image,
          );
        },
      );
    }

    return ExtendedImage.network(
      widget.imageUrl,
      key: widget.extendedImageKey,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      headers: _getHeaders(),
      cache: effectiveCache,
      cacheKey: cacheKey,
      mode: widget.mode,
      shape: BoxShape.rectangle,
      initGestureConfigHandler: widget.initGestureConfigHandler,
      borderRadius: BorderRadius.all(Radius.circular(widget.borderRadius)),
      onDoubleTap: widget.onDoubleTap,
      loadStateChanged: (ExtendedImageState state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            if (!widget.showLoading) {
              return null;
            }
            if (widget.loadingBuilder != null) {
              return widget.loadingBuilder!(
                context,
                SizedBox(width: widget.width, height: widget.height),
                state.loadingProgress,
              );
            }
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(child: CircularProgressIndicator()),
            );
          case LoadState.completed:
            return null;
          case LoadState.failed:
            if (widget.errorBuilder != null) {
              return widget.errorBuilder!(
                context,
                Exception('Failed to load image'),
                null,
              );
            }
            return buildErrorPlaceholder();
        }
      },
      cancelToken: _nonWebDirectCancelToken ??= CancellationToken(),
    );
  }
}
