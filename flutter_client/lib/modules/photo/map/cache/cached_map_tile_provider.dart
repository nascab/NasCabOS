import 'dart:async';
import 'dart:collection';
import 'dart:convert' show utf8;
import 'dart:math';
import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:NasCabOS/core/cache/cache_key_util.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

import 'map_tile_cache.dart'
    if (dart.library.io) 'map_tile_cache_io.dart'
    as map_tile_cache;

/// 地图瓦片缓存 key：用「去 token 的 url」的 md5，token 刷新后仍可命中
String _mapTileCacheKey(String url) =>
    md5.convert(utf8.encode(normalizeUrlForCacheKey(url))).toString();

/// 全局正在进行的网络请求，按 cacheKey 去重，避免同一瓦片并发多个 HTTP 请求
final _inFlightRequests = HashMap<String, Future<Uint8List?>>();

/// 网络请求最大重试次数
const int _maxRetries = 3;

/// 网络请求指数退避基础延迟
const Duration _retryBaseDelay = Duration(milliseconds: 200);

/// 先读磁盘缓存再请求网络，用于 P2P 下加速瓦片加载（非 Web 时落盘到 cacheimage/map_tiles）
class CachedMapNetworkImageProvider
    extends ImageProvider<CachedMapNetworkImageProvider> {
  const CachedMapNetworkImageProvider({
    required this.url,
    required this.headers,
    required this.httpClient,
    required this.startedLoading,
    required this.finishedLoadingBytes,
  });

  final String url;
  final Map<String, String> headers;
  final BaseClient httpClient;
  final void Function() startedLoading;
  final void Function() finishedLoadingBytes;

  /// 带重试的网络请求，请求期间自动合并同 URL 的并发调用
  static Future<Uint8List?> _fetchWithRetry(
    String url,
    Map<String, String> headers,
    BaseClient httpClient,
    String cacheKey,
  ) async {
    // 同 URL 的并发请求合并为一次网络调用
    if (_inFlightRequests.containsKey(cacheKey)) {
      return _inFlightRequests[cacheKey];
    }
    final completer = Completer<Uint8List?>();
    _inFlightRequests[cacheKey] = completer.future;

    try {
      for (int attempt = 0; attempt <= _maxRetries; attempt++) {
        try {
          final bytes = await httpClient.readBytes(
            Uri.parse(url),
            headers: headers,
          );
          completer.complete(bytes);
          return bytes;
        } on Exception catch (_) {
          if (attempt < _maxRetries) {
            // 指数退避：200ms, 400ms, 800ms
            await Future.delayed(
              _retryBaseDelay * pow(2, attempt).toInt(),
            );
          }
        }
      }
      // 全部重试失败
      completer.complete(null);
      return null;
    } finally {
      // 由 _fetchWithRetry 自己负责清理，避免 _load 中 finally 竞态删除导致
      // 重复 HTTP 请求和 ImageCache 误驱逐
      _inFlightRequests.remove(cacheKey);
    }
  }

  @override
  ImageStreamCompleter loadImage(
    CachedMapNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: url,
    informationCollector: () => [DiagnosticsProperty('URL', url)],
  );

  Future<Codec> _load(
    CachedMapNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final cacheKey = _mapTileCacheKey(url);
    final cached = await map_tile_cache.readMapTileCache(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return decode(await ImmutableBuffer.fromUint8List(cached));
    }
    startedLoading();
    try {
      final bytes = await _fetchWithRetry(
        url,
        headers,
        httpClient,
        cacheKey,
      );
      if (bytes != null) {
        await map_tile_cache.writeMapTileCache(cacheKey, bytes);
        return decode(await ImmutableBuffer.fromUint8List(bytes));
      }
    } catch (e, s) {
      // catch 所有错误类型（包括 Error），桌面端 Impeller 解码器可能抛出 Error
      // 而非 Exception，之前只 catch Exception 会导致 _load future 以 error 完成，
      // MultiFrameImageStreamCompleter 收不到 Codec，tile 永远不显示
      debugPrint('CachedMapNetworkImageProvider load error: $e\n$s');
    } finally {
      finishedLoadingBytes();
    }
    // 加载失败：清掉内存缓存标识，返回透明占位
    scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    return decode(
      await ImmutableBuffer.fromUint8List(TileProvider.transparentImage),
    );
  }

  @override
  SynchronousFuture<CachedMapNetworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMapNetworkImageProvider && url == other.url);

  @override
  int get hashCode => url.hashCode;
}

/// P2P 下使用的带磁盘缓存的瓦片 Provider（非 Web 时写入 cacheimage/map_tiles）
class CachedNetworkTileProvider extends TileProvider {
  CachedNetworkTileProvider({super.headers})
    : _httpClient = RetryClient(Client());

  final BaseClient _httpClient;
  final _tilesInProgress = HashMap<TileCoordinates, Completer<void>>();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedMapNetworkImageProvider(
        url: getTileUrl(coordinates, options),
        headers: headers,
        httpClient: _httpClient,
        startedLoading: () => _tilesInProgress[coordinates] = Completer(),
        finishedLoadingBytes: () {
          _tilesInProgress[coordinates]?.complete();
          _tilesInProgress.remove(coordinates);
        },
      );

  @override
  Future<void> dispose() async {
    if (_tilesInProgress.isNotEmpty) {
      await Future.wait(_tilesInProgress.values.map((c) => c.future));
    }
    _httpClient.close();
    super.dispose();
  }
}
