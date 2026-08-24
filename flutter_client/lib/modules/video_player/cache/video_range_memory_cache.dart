import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// 原画 rawFile Range 内存缓存配置。
class VideoRangeCacheOptions {
  static const int defaultMaxBytes = 1024 * 1024 * 1024;

  final bool enabled;
  final int maxBytes;
  final int blockSize;

  /// 同时进行的上游 Range 拉取上限（过大易卡播放器）。
  final int maxConcurrentUpstream;

  const VideoRangeCacheOptions({
    this.enabled = true,
    this.maxBytes = defaultMaxBytes,
    this.blockSize = 256 * 1024,
    this.maxConcurrentUpstream = 4,
  });

  VideoRangeCacheOptions copyWith({
    bool? enabled,
    int? maxBytes,
    int? blockSize,
    int? maxConcurrentUpstream,
  }) {
    return VideoRangeCacheOptions(
      enabled: enabled ?? this.enabled,
      maxBytes: maxBytes ?? this.maxBytes,
      blockSize: blockSize ?? this.blockSize,
      maxConcurrentUpstream:
          maxConcurrentUpstream ?? this.maxConcurrentUpstream,
    );
  }
}

/// 解析后的 HTTP Range（闭区间 end；openEnded 表示 bytes=start-）。
class ParsedByteRange {
  final int start;
  final int? end;
  final bool openEnded;

  const ParsedByteRange({
    required this.start,
    this.end,
    this.openEnded = false,
  });
}

/// 上游拉取结果（直连或 P2P）。
class UpstreamRangeResponse {
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;
  final void Function()? cancel;

  const UpstreamRangeResponse({
    required this.status,
    required this.headers,
    required this.body,
    this.cancel,
  });
}

/// 对齐后的上游拉取计划（客户端 Range 与 NAS Range 可能不同）。
class _UpstreamFetchPlan {
  final String upstreamRange;
  final int clientStart;
  final int clientEnd;
  final int fetchStart;
  final int fetchEnd;
  final int skipToClient;
  final int clientLength;

  const _UpstreamFetchPlan({
    required this.upstreamRange,
    required this.clientStart,
    required this.clientEnd,
    required this.fetchStart,
    required this.fetchEnd,
    required this.skipToClient,
    required this.clientLength,
  });
}

typedef UpstreamRangeFetcher = Future<UpstreamRangeResponse> Function({
  required String method,
  required Map<String, String> clientHeaders,
  required String? rangeHeader,
});

bool isVideoRawFilePath(String path) {
  return path == '/api/videoPlayer/rawFile' || path == '/api/file/rawFile';
}

String buildVideoRangeSessionKey(Uri uri, String baseUrl) {
  final path = uri.queryParameters['path']?.trim() ?? '';
  final internal = uri.queryParameters['internalPath']?.trim() ?? '';
  return '$baseUrl|$path|$internal';
}

/// 按媒体文件扩展名推断 Content-Type（避免一律 video/mp4 误导 ExoPlayer）。
String videoContentTypeFromMediaPath(String mediaPath) {
  final s = mediaPath.trim();
  if (s.isEmpty) return 'application/octet-stream';
  final dot = s.lastIndexOf('.');
  if (dot < 0 || dot == s.length - 1) {
    return 'application/octet-stream';
  }
  switch (s.substring(dot).toLowerCase()) {
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.mkv':
      return 'video/x-matroska';
    case '.webm':
      return 'video/webm';
    case '.avi':
      return 'video/x-msvideo';
    case '.wmv':
      return 'video/x-ms-wmv';
    case '.flv':
      return 'video/x-flv';
    case '.ts':
    case '.m2ts':
      return 'video/mp2t';
    case '.mpeg':
    case '.mpg':
      return 'video/mpeg';
    case '.3gp':
      return 'video/3gpp';
    default:
      return 'application/octet-stream';
  }
}

/// 稀疏块 Range 内存缓存（单会话）。
class VideoRangeMemoryCache {
  VideoRangeMemoryCache({
    required this.sessionKey,
    required this.options,
    this.mediaContentType = 'application/octet-stream',
  });

  final String sessionKey;
  final VideoRangeCacheOptions options;
  final String mediaContentType;

  final LinkedHashMap<int, Uint8List> _blocks = LinkedHashMap();
  int _totalBytes = 0;
  int? _knownFileSize;

  int _cacheHits = 0;
  int _prefixHits = 0;
  int _upstreamFetches = 0;
  int _activeUpstream = 0;
  final List<Completer<void>> _upstreamWaiters = [];
  /// 与 NAS 对齐后的上游 Range（如 bytes=432013312-436061311）去重，避免重叠 FVP 请求重复拉取。
  final Map<String, Future<void>> _upstreamRangeInflight = {};
  final Map<String, Future<void>> _exactRangeInflight = {};

  int get totalBytes => _totalBytes;
  int? get knownFileSize => _knownFileSize;

  int get blockSize => options.blockSize;

  void bindFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return;
    _knownFileSize = bytes;
  }

  void _log(String msg) {
    if (!kDebugMode) return;
    debugPrint('[VideoRangeCache] $msg');
  }

  void _touchBlock(int index) {
    final data = _blocks.remove(index);
    if (data != null) {
      _blocks[index] = data;
    }
  }

  void _evictIfNeeded({bool force = false}) {
    final max = options.maxBytes;
    while (_blocks.isNotEmpty && (force || _totalBytes > max)) {
      final first = _blocks.keys.first;
      final removed = _blocks.remove(first);
      if (removed != null) {
        _totalBytes -= removed.length;
      }
    }
  }

  void putBlock(int index, Uint8List data) {
    final existing = _blocks[index];
    if (existing != null) {
      _totalBytes -= existing.length;
      _blocks.remove(index);
    }
    _blocks[index] = data;
    _totalBytes += data.length;
    _touchBlock(index);
    _evictIfNeeded();
  }

  void ingestBytes(int absoluteOffset, List<int> chunk) {
    if (chunk.isEmpty) return;
    var off = absoluteOffset;
    var idx = 0;
    while (idx < chunk.length) {
      final blockIndex = off ~/ blockSize;
      final inBlock = off % blockSize;
      final take = math.min(blockSize - inBlock, chunk.length - idx);
      final slice = chunk.sublist(idx, idx + take);

      Uint8List block;
      final existing = _blocks[blockIndex];
      if (existing != null && existing.length == blockSize) {
        block = Uint8List.fromList(existing);
      } else {
        block = Uint8List(blockSize);
        if (existing != null) {
          block.setRange(0, existing.length, existing);
        }
      }
      block.setRange(inBlock, inBlock + take, slice);
      if (inBlock + take >= blockSize) {
        putBlock(blockIndex, block);
      } else {
        final partial = Uint8List(inBlock + take);
        partial.setRange(0, inBlock + take, block.sublist(0, inBlock + take));
        final prev = _blocks[blockIndex];
        if (prev != null) _totalBytes -= prev.length;
        _blocks[blockIndex] = partial;
        _totalBytes += partial.length;
        _touchBlock(blockIndex);
      }

      off += take;
      idx += take;
    }
  }

  void updateFileSizeFromHeaders(Map<String, String> headers) {
    final cr = headers[HttpHeaders.contentRangeHeader];
    if (cr != null && cr.isNotEmpty) {
      final parsed = _parseContentRangeTotal(cr);
      if (parsed != null) _knownFileSize = parsed;
      return;
    }
    final cl = headers[HttpHeaders.contentLengthHeader];
    if (cl != null && cl.isNotEmpty) {
      final n = int.tryParse(cl.trim());
      if (n != null &&
          n > 0 &&
          headers[HttpHeaders.contentRangeHeader] == null) {
        _knownFileSize = n;
      }
    }
  }

  static int? _parseContentRangeTotal(String value) {
    final m = RegExp(r'bytes\s+\d+-\d+/(\d+|\*)', caseSensitive: false)
        .firstMatch(value.trim());
    if (m == null) return null;
    final g = m.group(1);
    if (g == null || g == '*') return null;
    return int.tryParse(g);
  }

  static ParsedByteRange? parseRangeHeader(String? header, int? fileSize) {
    if (header == null || header.trim().isEmpty) return null;
    final v = header.trim();
    if (!v.toLowerCase().startsWith('bytes=')) return null;
    final spec = v.substring(6).trim();
    final dash = spec.indexOf('-');
    if (dash < 0) return null;
    final left = spec.substring(0, dash).trim();
    final right = spec.substring(dash + 1).trim();

    if (left.isEmpty) {
      final suffix = int.tryParse(right);
      if (suffix == null || suffix <= 0) return null;
      if (fileSize == null || fileSize <= 0) return null;
      final start = fileSize - suffix;
      return ParsedByteRange(
        start: start < 0 ? 0 : start,
        end: fileSize - 1,
      );
    }

    final start = int.tryParse(left);
    if (start == null || start < 0) return null;
    if (right.isEmpty) {
      final end = fileSize != null && fileSize > 0 ? fileSize - 1 : null;
      return ParsedByteRange(
        start: start,
        end: end,
        openEnded: true,
      );
    }
    final end = int.tryParse(right);
    if (end == null || end < start) return null;
    return ParsedByteRange(start: start, end: end);
  }

  /// 偏移 [offset] 处是否已有缓存字节（曾由上游写入，不论当时向 FVP 实际发了多少）。
  bool hasCachedByteAt(int offset) {
    if (offset < 0) return false;
    final blockIndex = offset ~/ blockSize;
    final inBlock = offset % blockSize;
    final block = _blocks[blockIndex];
    return block != null && inBlock < block.length;
  }

  /// 从 [start] 起连续可读的缓存字节数（不超过 [maxEnd]）。
  int cachedPrefixLength(int start, int maxEnd) {
    if (maxEnd < start) return 0;
    var pos = start;
    while (pos <= maxEnd) {
      final blockIndex = pos ~/ blockSize;
      final inBlock = pos % blockSize;
      final block = _blocks[blockIndex];
      if (block == null || inBlock >= block.length) break;
      final availableInBlock = block.length - inBlock;
      final need = maxEnd - pos + 1;
      final take = math.min(availableInBlock, need);
      pos += take;
      if (block.length < blockSize) break;
    }
    return pos - start;
  }

  bool isRangeFullyCached(int start, int end) {
    if (end < start) return false;
    return cachedPrefixLength(start, end) >= (end - start + 1);
  }

  Uint8List? readRangeFromCache(int start, int length) {
    if (length <= 0) return Uint8List(0);
    final maxEnd = start + length - 1;
    if (cachedPrefixLength(start, maxEnd) < length) return null;
    final out = Uint8List(length);
    var written = 0;
    var pos = start;
    while (written < length) {
      final blockIndex = pos ~/ blockSize;
      final inBlock = pos % blockSize;
      final block = _blocks[blockIndex]!;
      final take = math.min(block.length - inBlock, length - written);
      out.setRange(written, written + take, block.sublist(inBlock, inBlock + take));
      written += take;
      pos += take;
    }
    return out;
  }

  void clear() {
    _blocks.clear();
    _totalBytes = 0;
    _knownFileSize = null;
    _cacheHits = 0;
    _prefixHits = 0;
    _upstreamFetches = 0;
    _activeUpstream = 0;
    for (final w in _upstreamWaiters) {
      if (!w.isCompleted) w.complete();
    }
    _upstreamWaiters.clear();
    _upstreamRangeInflight.clear();
    _exactRangeInflight.clear();
  }

  /// 尾部 moov 探测：单次上游开放 Range 上限。
  static const int _maxTailUpstreamChunkBytes = 1024 * 1024;

  /// 正常播放读取：单次上游块更大，减少 Range 往返造成的卡顿。
  static const int _maxPlaybackUpstreamChunkBytes = 4 * 1024 * 1024;

  static const int _maxPrefixServeBytes = 4 * 1024 * 1024;

  static const int _tailCoalesceBytes = 512 * 1024;

  /// 播放段上游 Range 按 1MB 对齐，重叠请求可复用同一次 NAS 拉取。
  static const int _playbackAlignBytes = 1024 * 1024;

  bool _isTailProbe(int start) {
    final fs = _knownFileSize;
    if (fs != null && fs > 0) {
      return start > (fs * 0.6).round();
    }
    return start > 1500000000;
  }

  int _minPrefixForStart(int start) {
    if (_isTailProbe(start)) return 4096;
    return 32 * 1024;
  }

  String? _upstreamInflightKey(_UpstreamFetchPlan? plan, int start) {
    if (plan != null) return plan.upstreamRange;
    if (_isTailProbe(start)) {
      final bucket = start ~/ _tailCoalesceBytes;
      return 'tail:$bucket';
    }
    final bucket = start ~/ _playbackAlignBytes;
    return 'play:$bucket';
  }

  int _maxUpstreamChunkForStart(int start) {
    return _isTailProbe(start)
        ? _maxTailUpstreamChunkBytes
        : _maxPlaybackUpstreamChunkBytes;
  }

  /// 客户端 Range 与对齐后的上游 Range（单次最多 chunk 字节，禁止拖到 EOF）。
  _UpstreamFetchPlan? _resolveUpstreamPlan(String? rangeHeader) {
    if (rangeHeader == null || rangeHeader.trim().isEmpty) return null;
    final parsed = parseRangeHeader(rangeHeader, _knownFileSize);
    if (parsed == null) return null;

    final clientStart = parsed.start;
    final chunk = _maxUpstreamChunkForStart(clientStart);
    final fileEnd =
        _knownFileSize != null && _knownFileSize! > 0 ? _knownFileSize! - 1 : null;

    // 本次响应只承诺最多 chunk 字节（开放 Range 不得扩到 EOF，否则 FVP/NAS 风暴 + 卡顿）
    int responseEnd;
    if (parsed.openEnded) {
      responseEnd = clientStart + chunk - 1;
    } else if (parsed.end != null) {
      responseEnd = parsed.end!;
      final span = responseEnd - clientStart + 1;
      if (span > chunk) {
        responseEnd = clientStart + chunk - 1;
      }
    } else {
      return null;
    }
    if (fileEnd != null && responseEnd > fileEnd) {
      responseEnd = fileEnd;
    }
    if (responseEnd < clientStart) return null;

    final fetchStart = _isTailProbe(clientStart)
        ? clientStart
        : (clientStart ~/ _playbackAlignBytes) * _playbackAlignBytes;
    var fetchEnd = fetchStart + chunk - 1;
    if (fetchEnd < responseEnd) fetchEnd = responseEnd;
    if (fileEnd != null && fetchEnd > fileEnd) fetchEnd = fileEnd;

    return _UpstreamFetchPlan(
      upstreamRange: 'bytes=$fetchStart-$fetchEnd',
      clientStart: clientStart,
      clientEnd: responseEnd,
      fetchStart: fetchStart,
      fetchEnd: fetchEnd,
      skipToClient: clientStart - fetchStart,
      clientLength: responseEnd - clientStart + 1,
    );
  }

  Future<void> _acquireUpstreamSlot() async {
    final max = options.maxConcurrentUpstream;
    if (max <= 0 || _activeUpstream < max) {
      _activeUpstream += 1;
      return;
    }
    final waiter = Completer<void>();
    _upstreamWaiters.add(waiter);
    await waiter.future;
    _activeUpstream += 1;
  }

  void _releaseUpstreamSlot() {
    if (_activeUpstream > 0) _activeUpstream -= 1;
    if (_upstreamWaiters.isEmpty) return;
    final next = _upstreamWaiters.removeAt(0);
    if (!next.isCompleted) next.complete();
  }

  int _probeEndForPrefix(int start, int? end, bool openEnded) {
    if (end != null) {
      final cap = start + _maxPrefixServeBytes - 1;
      return end < cap ? end : cap;
    }
    if (openEnded && _knownFileSize != null && _knownFileSize! > 0) {
      final fileEnd = _knownFileSize! - 1;
      final cap = start + _maxPrefixServeBytes - 1;
      return fileEnd < cap ? fileEnd : cap;
    }
    return start + _maxPrefixServeBytes - 1;
  }

  void _copyResponseHeaders(
    HttpResponse clientRes,
    Map<String, String> headers, {
    bool skipContentLength = false,
    bool skipContentRange = false,
  }) {
    headers.forEach((name, value) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.transferEncodingHeader) return;
      if (key == HttpHeaders.connectionHeader) return;
      if (skipContentLength && key == HttpHeaders.contentLengthHeader) return;
      if (skipContentRange && key == HttpHeaders.contentRangeHeader) return;
      try {
        clientRes.headers.set(name, value);
      } catch (_) {}
    });
  }

  Future<bool> tryServeRangeRequest({
    required HttpRequest clientReq,
    required UpstreamRangeFetcher fetcher,
  }) async {
    final method = clientReq.method.toUpperCase();
    final clientHeaders = _collectClientHeaders(clientReq);
    final rangeHeader = clientReq.headers.value(HttpHeaders.rangeHeader);

    if (method == 'HEAD') {
      return _passthrough(clientReq, fetcher, clientHeaders, rangeHeader);
    }

    if (rangeHeader == null || rangeHeader.trim().isEmpty) {
      return _passthrough(clientReq, fetcher, clientHeaders, null);
    }

    final parsed = parseRangeHeader(rangeHeader, _knownFileSize);
    if (parsed == null) {
      return _passthrough(clientReq, fetcher, clientHeaders, rangeHeader);
    }

    final plan = _resolveUpstreamPlan(rangeHeader);
    final start = parsed.start;
    final end = plan?.clientEnd ?? parsed.end;
    final relaxMin = hasCachedByteAt(start);

    final served = await _tryServeClientRangeFromCache(
      clientReq: clientReq,
      start: start,
      end: end,
      openEnded: parsed.openEnded,
      rangeHeader: rangeHeader,
      relaxMinPrefix: relaxMin,
    );
    if (served) return true;

    final rangeKey = rangeHeader.trim();
    final exactInflight = _exactRangeInflight[rangeKey];
    if (exactInflight != null) {
      try {
        await exactInflight;
      } catch (_) {}
      if (await _tryServeClientRangeFromCache(
        clientReq: clientReq,
        start: start,
        end: end,
        openEnded: parsed.openEnded,
        rangeHeader: rangeHeader,
        relaxMinPrefix: relaxMin || hasCachedByteAt(start),
      )) {
        return true;
      }
    }

    final upstreamKey = _upstreamInflightKey(plan, start);
    if (upstreamKey != null) {
      final inflight = _upstreamRangeInflight[upstreamKey];
      if (inflight != null) {
        try {
          await inflight;
        } catch (_) {}
        if (await _tryServeClientRangeFromCache(
          clientReq: clientReq,
          start: start,
          end: end,
          openEnded: parsed.openEnded,
          rangeHeader: rangeHeader,
          relaxMinPrefix: relaxMin || hasCachedByteAt(start),
        )) {
          return true;
        }
      }
    }

    return _passthrough(
      clientReq,
      fetcher,
      clientHeaders,
      rangeHeader,
      upstreamInflightKey: upstreamKey,
      exactRangeKey: rangeKey,
    );
  }

  int? _effectiveClientEnd(int start, int? end, bool openEnded) {
    if (end != null) return end;
    return _probeEndForPrefix(start, null, openEnded);
  }

  /// 统一：FVP 区间已连续在缓存则流式返回；否则在允许时返回连续前缀。
  Future<bool> _tryServeClientRangeFromCache({
    required HttpRequest clientReq,
    required int start,
    required int? end,
    required bool openEnded,
    required String rangeHeader,
    bool relaxMinPrefix = false,
    bool allowPrefixOnly = true,
  }) async {
    final effectiveEnd = _effectiveClientEnd(start, end, openEnded);
    if (effectiveEnd == null || effectiveEnd < start) return false;

    if (isRangeFullyCached(start, effectiveEnd)) {
      return _streamCachedRangeToClient(
        clientReq: clientReq,
        start: start,
        end: effectiveEnd,
        rangeHeader: rangeHeader,
        logTag: 'fullHit',
        countAsPrefix: false,
      );
    }

    if (!allowPrefixOnly) return false;

    var prefixLen = cachedPrefixLength(start, effectiveEnd);
    final minPrefix = relaxMinPrefix && hasCachedByteAt(start)
        ? 1
        : _minPrefixForStart(start);
    if (prefixLen < minPrefix) return false;
    if (prefixLen > _maxPrefixServeBytes) {
      prefixLen = _maxPrefixServeBytes;
    }

    return _streamCachedRangeToClient(
      clientReq: clientReq,
      start: start,
      end: start + prefixLen - 1,
      rangeHeader: rangeHeader,
      logTag: 'prefixOnly',
      countAsPrefix: true,
    );
  }

  /// 按块流式写出 [start..end]（调用前须保证已连续缓存）。
  Future<bool> _streamCachedRangeToClient({
    required HttpRequest clientReq,
    required int start,
    required int end,
    required String rangeHeader,
    required String logTag,
    required bool countAsPrefix,
  }) async {
    final length = end - start + 1;
    if (length <= 0) return false;
    if (!isRangeFullyCached(start, end)) return false;

    final total = _knownFileSize;
    clientReq.response.statusCode = HttpStatus.partialContent;
    clientReq.response.headers.set(
      HttpHeaders.contentTypeHeader,
      mediaContentType,
    );
    clientReq.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    clientReq.response.headers.set(
      HttpHeaders.contentLengthHeader,
      '$length',
    );
    if (total != null && total > 0) {
      clientReq.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }
    clientReq.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      clientReq.response.bufferOutput = false;
    } catch (_) {}

    try {
      var pos = start;
      while (pos <= end) {
        final blockIndex = pos ~/ blockSize;
        final inBlock = pos % blockSize;
        final block = _blocks[blockIndex]!;
        final take = math.min(block.length - inBlock, end - pos + 1);
        clientReq.response.add(block.sublist(inBlock, inBlock + take));
        pos += take;
      }
      await clientReq.response.close();
    } catch (_) {
      try {
        await clientReq.response.close();
      } catch (_) {}
      return true;
    }

    _cacheHits += 1;
    if (countAsPrefix) _prefixHits += 1;
    _log(
      '$logTag range=$rangeHeader bytes=$length '
      'hits=$_cacheHits prefixHits=$_prefixHits '
      'upstream=$_upstreamFetches totalCached=$_totalBytes',
    );
    return true;
  }

  /// 上游对齐区间已有连续前缀时，仅返回需向 NAS 拉取的尾部 Range；全在缓存则 null。
  String? _gapOnlyUpstreamRange(_UpstreamFetchPlan plan) {
    if (isRangeFullyCached(plan.fetchStart, plan.fetchEnd)) return null;
    final prefixLen = cachedPrefixLength(plan.fetchStart, plan.fetchEnd);
    if (prefixLen <= 0) return plan.upstreamRange;
    final gapStart = plan.fetchStart + prefixLen;
    if (gapStart > plan.fetchEnd) return null;
    return 'bytes=$gapStart-${plan.fetchEnd}';
  }

  int? _gapUpstreamStart(String? rangeHeader) {
    if (rangeHeader == null) return null;
    final parsed = parseRangeHeader(rangeHeader, _knownFileSize);
    return parsed?.start;
  }

  int _rangeBaseOffset(Map<String, String> headers) {
    final cr = headers[HttpHeaders.contentRangeHeader];
    if (cr == null) return 0;
    final m = RegExp(r'bytes\s+(\d+)-', caseSensitive: false).firstMatch(cr);
    if (m == null) return 0;
    return int.tryParse(m.group(1) ?? '') ?? 0;
  }

  void _setClientRangeResponseHeaders({
    required HttpResponse response,
    required int clientStart,
    required int clientEnd,
    required String? contentType,
  }) {
    final total = _knownFileSize;
    final len = clientEnd - clientStart + 1;
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      contentType ?? mediaContentType,
    );
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentLengthHeader, '$len');
    if (total != null && total > 0) {
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $clientStart-$clientEnd/$total',
      );
    }
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  }

  Future<void> _pipeUpstreamToClient({
    required HttpRequest clientReq,
    required UpstreamRangeResponse res,
    required int baseOffset,
    int skipToClient = 0,
    int? maxBytesToClient,
  }) async {
    var clientClosed = false;
    unawaited(
      clientReq.response.done.then((_) {
        clientClosed = true;
      }),
    );

    try {
      clientReq.response.bufferOutput = false;
    } catch (_) {}

    var offset = baseOffset;
    var skip = skipToClient;
    var sentToClient = 0;
    try {
      await for (final chunk in res.body) {
        if (clientClosed) break;
        ingestBytes(offset, chunk);
        offset += chunk.length;

        var out = chunk;
        if (skip > 0) {
          if (out.length <= skip) {
            skip -= out.length;
            continue;
          }
          out = out.sublist(skip);
          skip = 0;
        }
        if (maxBytesToClient != null) {
          final remain = maxBytesToClient - sentToClient;
          if (remain <= 0) break;
          if (out.length > remain) {
            out = out.sublist(0, remain);
          }
        }
        if (out.isEmpty) continue;

        try {
          clientReq.response.add(out);
          sentToClient += out.length;
        } catch (_) {
          clientClosed = true;
          break;
        }
      }
    } catch (_) {
      clientClosed = true;
    } finally {
      if (clientClosed) {
        try {
          res.cancel?.call();
        } catch (_) {}
      }
      try {
        await clientReq.response.close();
      } catch (_) {}
    }
  }

  /// 客户端区间有连续前缀：先流式写缓存，再仅拉取尾部缺口（单次 HTTP 响应）。
  Future<bool> _passthroughClientGapFill({
    required HttpRequest clientReq,
    required UpstreamRangeFetcher fetcher,
    required Map<String, String> clientHeaders,
    required _UpstreamFetchPlan plan,
    required String? rangeHeader,
  }) async {
    final clientPrefix = cachedPrefixLength(plan.clientStart, plan.clientEnd);
    if (clientPrefix <= 0 || clientPrefix >= plan.clientLength) {
      return false;
    }

    final gapStart = plan.clientStart + clientPrefix;
    final gapRange = 'bytes=$gapStart-${plan.clientEnd}';

    await _acquireUpstreamSlot();
    _upstreamFetches += 1;
    try {
      final res = await fetcher(
        method: clientReq.method,
        clientHeaders: clientHeaders,
        rangeHeader: gapRange,
      );
      updateFileSizeFromHeaders(res.headers);

      if (res.status != HttpStatus.partialContent && res.status != HttpStatus.ok) {
        return false;
      }

      final ct = res.headers[HttpHeaders.contentTypeHeader];
      _setClientRangeResponseHeaders(
        response: clientReq.response,
        clientStart: plan.clientStart,
        clientEnd: plan.clientEnd,
        contentType: ct,
      );

      final cachedEnd = gapStart - 1;
      if (!isRangeFullyCached(plan.clientStart, cachedEnd)) {
        return false;
      }
      try {
        clientReq.response.bufferOutput = false;
      } catch (_) {}
      var pos = plan.clientStart;
      while (pos <= cachedEnd) {
        final blockIndex = pos ~/ blockSize;
        final inBlock = pos % blockSize;
        final block = _blocks[blockIndex]!;
        final take = math.min(block.length - inBlock, cachedEnd - pos + 1);
        clientReq.response.add(block.sublist(inBlock, inBlock + take));
        pos += take;
      }

      await _pipeUpstreamToClient(
        clientReq: clientReq,
        res: res,
        baseOffset: gapStart,
        skipToClient: 0,
        maxBytesToClient: plan.clientEnd - gapStart + 1,
      );

      _log(
        'clientGapFill clientRange=${rangeHeader ?? "(none)"} '
        'cached=$clientPrefix gap=$gapRange totalCached=$_totalBytes',
      );
      return true;
    } catch (e) {
      _log('clientGapFill error: $e');
      return false;
    } finally {
      _releaseUpstreamSlot();
    }
  }

  Future<bool> _passthrough(
    HttpRequest clientReq,
    UpstreamRangeFetcher fetcher,
    Map<String, String> clientHeaders,
    String? rangeHeader, {
    String? upstreamInflightKey,
    String? exactRangeKey,
  }) async {
    final plan = _resolveUpstreamPlan(rangeHeader);

    if (plan != null) {
      if (await _tryServeClientRangeFromCache(
        clientReq: clientReq,
        start: plan.clientStart,
        end: plan.clientEnd,
        openEnded: false,
        rangeHeader: rangeHeader ?? '',
        relaxMinPrefix: true,
      )) {
        return true;
      }

      if (hasCachedByteAt(plan.clientStart) &&
          cachedPrefixLength(plan.clientStart, plan.clientEnd) > 0 &&
          !isRangeFullyCached(plan.clientStart, plan.clientEnd)) {
        final filled = await _passthroughClientGapFill(
          clientReq: clientReq,
          fetcher: fetcher,
          clientHeaders: clientHeaders,
          plan: plan,
          rangeHeader: rangeHeader,
        );
        if (filled) return true;
      }
    }

    var upstreamRange = plan?.upstreamRange ?? rangeHeader;
    var baseOffset = plan?.fetchStart ?? 0;
    var skipToClient = plan?.skipToClient ?? 0;
    var maxToClient = plan?.clientLength;
    int? cacheBeforeGapEnd;

    if (plan != null) {
      final gapRange = _gapOnlyUpstreamRange(plan);
      if (gapRange == null) {
        if (await _tryServeClientRangeFromCache(
          clientReq: clientReq,
          start: plan.clientStart,
          end: plan.clientEnd,
          openEnded: false,
          rangeHeader: rangeHeader ?? '',
          relaxMinPrefix: true,
        )) {
          _log(
            'upstreamCachedOnly clientRange=${rangeHeader ?? "(none)"} '
            'upstreamRange=${plan.upstreamRange} totalCached=$_totalBytes',
          );
          return true;
        }
      } else if (gapRange != plan.upstreamRange) {
        upstreamRange = gapRange;
        final gapStart = _gapUpstreamStart(gapRange) ?? plan.fetchStart;
        baseOffset = gapStart;
        skipToClient = 0;
        if (plan.clientStart < gapStart) {
          cacheBeforeGapEnd = math.min(plan.clientEnd, gapStart - 1);
        }
        _log(
          'upstreamGapOnly full=${plan.upstreamRange} gap=$gapRange '
          'cacheThrough=$cacheBeforeGapEnd',
        );
      }
    }

    final upstreamKey = upstreamInflightKey ??
        _upstreamInflightKey(plan, plan?.clientStart ?? 0) ??
        upstreamRange;
    Completer<void>? upstreamDone;
    if (upstreamKey != null) {
      upstreamDone = Completer<void>();
      _upstreamRangeInflight[upstreamKey] = upstreamDone.future;
    }
    Completer<void>? exactDone;
    final exactKey = exactRangeKey?.trim() ?? '';
    if (exactKey.isNotEmpty) {
      exactDone = Completer<void>();
      _exactRangeInflight[exactKey] = exactDone.future;
    }

    await _acquireUpstreamSlot();
    _upstreamFetches += 1;
    try {
      final res = await fetcher(
        method: clientReq.method,
        clientHeaders: clientHeaders,
        rangeHeader: upstreamRange,
      );
      updateFileSizeFromHeaders(res.headers);

      if (plan != null &&
          (res.status == HttpStatus.partialContent || res.status == HttpStatus.ok)) {
        final ct = res.headers[HttpHeaders.contentTypeHeader];
        _setClientRangeResponseHeaders(
          response: clientReq.response,
          clientStart: plan.clientStart,
          clientEnd: plan.clientEnd,
          contentType: ct,
        );

        final cachedEnd = cacheBeforeGapEnd ??
            (skipToClient > 0 &&
                    hasCachedByteAt(plan.clientStart) &&
                    cachedPrefixLength(plan.clientStart, plan.clientEnd) > 0
                ? plan.clientStart +
                    cachedPrefixLength(plan.clientStart, plan.clientEnd) -
                    1
                : null);
        if (cachedEnd != null &&
            cachedEnd >= plan.clientStart &&
            isRangeFullyCached(plan.clientStart, cachedEnd)) {
          try {
            clientReq.response.bufferOutput = false;
          } catch (_) {}
          var pos = plan.clientStart;
          while (pos <= cachedEnd) {
            final blockIndex = pos ~/ blockSize;
            final inBlock = pos % blockSize;
            final block = _blocks[blockIndex]!;
            final take = math.min(block.length - inBlock, cachedEnd - pos + 1);
            clientReq.response.add(block.sublist(inBlock, inBlock + take));
            pos += take;
          }
          skipToClient = 0;
        }

        await _pipeUpstreamToClient(
          clientReq: clientReq,
          res: res,
          baseOffset: baseOffset,
          skipToClient: skipToClient,
          maxBytesToClient: maxToClient,
        );
      } else if (res.status >= HttpStatus.badRequest) {
        clientReq.response.statusCode = res.status;
        _copyResponseHeaders(clientReq.response, res.headers);
        try {
          await clientReq.response.close();
        } catch (_) {}
      } else {
        clientReq.response.statusCode = res.status;
        _copyResponseHeaders(clientReq.response, res.headers);
        final baseOffset = _rangeBaseOffset(res.headers);
        await _pipeUpstreamToClient(
          clientReq: clientReq,
          res: res,
          baseOffset: baseOffset,
        );
      }

      _log(
        'passthrough clientRange=${rangeHeader ?? "(none)"} '
        'upstreamRange=${upstreamRange ?? "(none)"} '
        'alignSkip=${plan?.skipToClient ?? 0} status=${res.status} '
        'active=$_activeUpstream upstream=$_upstreamFetches totalCached=$_totalBytes',
      );
      return true;
    } catch (e) {
      _log('passthrough error: $e');
      try {
        clientReq.response.statusCode = HttpStatus.badGateway;
        await clientReq.response.close();
      } catch (_) {}
      return true;
    } finally {
      _releaseUpstreamSlot();
      if (upstreamKey != null) {
        if (upstreamDone != null && !upstreamDone.isCompleted) {
          upstreamDone.complete();
        }
        _upstreamRangeInflight.remove(upstreamKey);
      }
      if (exactKey.isNotEmpty) {
        if (exactDone != null && !exactDone.isCompleted) {
          exactDone.complete();
        }
        _exactRangeInflight.remove(exactKey);
      }
    }
  }

  static Map<String, String> _collectClientHeaders(HttpRequest req) {
    final out = <String, String>{};
    req.headers.forEach((name, values) {
      final key = name.toLowerCase();
      if (key == HttpHeaders.hostHeader) return;
      if (key == HttpHeaders.contentLengthHeader) return;
      if (key == HttpHeaders.connectionHeader) return;
      if (values.isEmpty) return;
      out[name] = values.join(',');
    });
    return out;
  }
}

/// 播放器 Range 缓存门面（单例）。
class VideoRangeCacheManager {
  VideoRangeCacheManager._();

  static final VideoRangeCacheManager instance = VideoRangeCacheManager._();

  VideoRangeCacheOptions options = const VideoRangeCacheOptions();
  VideoRangeMemoryCache? _session;

  VideoRangeMemoryCache? get session => _session;

  void updateOptions(VideoRangeCacheOptions value) {
    options = value;
  }

  void resetSession(
    String sessionKey, {
    int? fileSizeBytes,
    String? mediaPath,
  }) {
    final contentType = videoContentTypeFromMediaPath(mediaPath ?? '');
    if (_session?.sessionKey == sessionKey) {
      _session!.bindFileSize(fileSizeBytes);
      return;
    }
    _session?.clear();
    _session = VideoRangeMemoryCache(
      sessionKey: sessionKey,
      options: options,
      mediaContentType: contentType,
    );
    _session!.bindFileSize(fileSizeBytes);
    if (kDebugMode) {
      debugPrint(
        '[VideoRangeCache] session=$sessionKey fileSize=$fileSizeBytes',
      );
    }
  }

  void clear() {
    _session = null;
    if (kDebugMode) {
      debugPrint('[VideoRangeCache] cleared');
    }
  }

  /// 处理 rawFile 请求；返回 true 表示已写响应（含透传+写入缓存）。
  Future<bool> handleRawFileRequest({
    required HttpRequest clientReq,
    required String baseUrl,
    required UpstreamRangeFetcher fetcher,
  }) async {
    if (!options.enabled) return false;
    if (!isVideoRawFilePath(clientReq.uri.path)) return false;

    final sessionKey = buildVideoRangeSessionKey(clientReq.uri, baseUrl);
    if (_session == null || _session!.sessionKey != sessionKey) {
      resetSession(sessionKey);
    }

    return _session!.tryServeRangeRequest(
      clientReq: clientReq,
      fetcher: fetcher,
    );
  }
}
