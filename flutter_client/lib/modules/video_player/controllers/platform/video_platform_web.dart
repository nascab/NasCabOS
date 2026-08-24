import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;
import '../../../../core/api/api_controller.dart';
import '../../../../core/api/p2p_rtc_stub.dart'
    if (dart.library.html) '../../../../core/api/p2p_rtc_web.dart';

// Stub for WindowListener
mixin WindowListener {}

// Stub for windowManager
class WindowManagerStub {
  Future<void> ensureInitialized() async {}
  Future<void> setMinimumSize(Size size) async {}
  Future<void> setTitle(String title) async {}
  Future<void> setFullScreen(bool isFullScreen) async {}
  Future<bool> isMinimized() async => false;
  Future<bool> isMaximized() async => false;
  Future<void> maximize() async {}
  Future<void> unmaximize() async {}
  Future<void> restore() async {}
  Future<void> show() async {}
  Future<void> focus() async {}
  Future<void> bringToFront() async {}
  void addListener(WindowListener listener) {}
  void removeListener(WindowListener listener) {}
}

final windowManager = WindowManagerStub();

bool _p2pFetchResponderInstalled = false;
bool _webVideoSizingCssInstalled = false;

/// Web 端：保持与 IO 端 API 对齐，避免条件导出导致编译缺符号。
/// - Web 不存在 Media3 原生内核；这里直接返回原始 URL。
String resolveDirectPlaybackUrl(String url) => url.trim();

/// Web 端：不需要/不支持原生层本地代理，保持签名一致。
Future<({String url, bool holdVideoLocalProxy})> resolveP2pProxyForNative(
  String url,
) async {
  final raw = resolveDirectPlaybackUrl(url);
  return (url: raw, holdVideoLocalProxy: false);
}

/// 兼容旧调用：Web 端直接返回原 URL。
Future<String> resolveP2pProxyUrlForNativeIfNeeded(String url) async {
  final r = await resolveP2pProxyForNative(url);
  return r.url;
}

/// 关闭播放器时切断 Safari/WebKit 可能残留的媒体下载（仅清 src + load，不限于当前 controller）
void stopWebVideoElementNetworking() {
  if (!kIsWeb) return;
  try {
    final nodes = web.document.querySelectorAll('video');
    for (var i = 0; i < nodes.length; i++) {
      final el = nodes.item(i);
      if (el == null) continue;
      final v = el as web.HTMLVideoElement;
      try {
        v.pause();
      } catch (_) {}
      try {
        v.removeAttribute('src');
      } catch (_) {}
      try {
        v.srcObject = null;
      } catch (_) {}
      try {
        v.load();
      } catch (_) {}
    }
  } catch (_) {}
}

/// Web 端 stub：Windows 软解相关 API 在 Web 不可用。
const List<String> windowsHardwareVideoDecoders = [];
const List<String> windowsSoftwareVideoDecoders = [];

bool isHighBitDepthVideoStream(Map<String, dynamic> videoStream) => false;

bool audioTracksContainProblematicAndroidHardwareCodec(
  List<Map<String, dynamic>> audioTracks,
) => false;

bool needsWindowsSoftwareVideoDecode({
  required List<Map<String, dynamic>> videoTracks,
  String sourcePath = '',
}) => false;

bool needsSoftwareVideoDecodeForHighBitDepth({
  required List<Map<String, dynamic>> videoTracks,
  String sourcePath = '',
}) => false;

bool androidLegacyContainerNeedsFvpEngine(String sourcePath) => false;

bool androidLegacyVideoCodecNeedsFvpEngine(
  List<Map<String, dynamic>> videoTracks,
) => false;

bool androidH264HighBitDepthNeedsFvpEngine(
  List<Map<String, dynamic>> videoTracks,
) => false;

bool androidMedia3SourceNeedsFvpEngine({
  required List<Map<String, dynamic>> videoTracks,
  required String sourcePath,
}) => false;

void registerFvp({List<String>? videoDecoders}) {
  if (!kIsWeb) return;
  _ensureWebVideoSizingCssInstalled();
  _ensureP2pFetchResponderInstalled();
}


void _ensureWebVideoSizingCssInstalled() {
  if (_webVideoSizingCssInstalled) return;
  _webVideoSizingCssInstalled = true;
  try {
    const styleId = 'nascab_web_video_sizing_fix';
    const css = '''
flt-platform-view,
flt-platform-view-slot,
.flt-platform-view,
.flt-platform-view-slot {
  display: block;
  position: relative;
  width: 100% !important;
  height: 100% !important;
  min-width: 100% !important;
  min-height: 100% !important;
  max-width: 100% !important;
  max-height: 100% !important;
  overflow: hidden;
}

flt-platform-view {
  position: absolute !important;
  inset: 0 !important;
}

flt-platform-view video,
flt-platform-view-slot video,
.flt-platform-view video,
.flt-platform-view-slot video {
  display: block;
  position: absolute;
  top: 0;
  left: 0;
  width: 100% !important;
  height: 100% !important;
  min-width: 100% !important;
  min-height: 100% !important;
  max-width: none !important;
  max-height: none !important;
  object-fit: contain;
}
''';

    void installIntoHead() {
      final existing = web.document.getElementById(styleId);
      if (existing != null) return;
      final styleEl = web.HTMLStyleElement()
        ..id = styleId
        ..textContent = css;
      web.document.head?.append(styleEl);
    }

    void installIntoShadowRoots() {
      final nodes = web.document.querySelectorAll('flutter-view');
      for (var i = 0; i < nodes.length; i++) {
        final el = nodes.item(i);
        if (el == null) continue;
        final sr = (el as web.Element).shadowRoot;
        if (sr == null) continue;
        if (sr.querySelector('#$styleId') != null) continue;
        final styleEl = web.HTMLStyleElement()
          ..id = styleId
          ..textContent = css;
        sr.append(styleEl);
      }

      final glass = web.document.querySelector('flt-glass-pane');
      final glassSr = glass?.shadowRoot;
      if (glassSr != null && glassSr.querySelector('#$styleId') == null) {
        final styleEl = web.HTMLStyleElement()
          ..id = styleId
          ..textContent = css;
        glassSr.append(styleEl);
      }
    }

    installIntoHead();
    installIntoShadowRoots();
    var attempt = 0;
    Timer.periodic(const Duration(milliseconds: 250), (t) {
      attempt++;
      installIntoShadowRoots();
      if (attempt >= 20) t.cancel();
    });
  } catch (_) {}
}

final Map<int, _WebP2pVideoResource> _p2pVideoResources = {};
final Map<String, void Function()> _p2pVideoInitCancels = {};
final Map<String, void Function()> _activeP2pFetches = {};

/// 专门追踪视频路径的 P2P fetch，用于播放器关闭时主动取消
final Map<String, void Function()> _activeVideoP2pFetches = {};

/// 播放器关闭后拒绝新的视频 fetch 请求，防止 HLS.js 重试触发 sendP2pStreamRequest
/// 进而因视频 link 错误被误判为主 P2P 断连，引发 _forceReconnectP2p → session/create 级联
bool _videoFetchesRejecting = false;

void disposeVideoController(VideoPlayerController controller) {
  final key = identityHashCode(controller);
  final res = _p2pVideoResources.remove(key);
  if (res == null) return;
  try {
    res.subscription?.cancel();
  } catch (_) {}
  try {
    res.p2pCancel();
  } catch (_) {}
  try {
    web.URL.revokeObjectURL(res.objectUrl);
  } catch (_) {}
}

void cancelVideoControllerInit(String initKey) {
  final key = initKey.trim();
  if (key.isEmpty) return;
  final fn = _p2pVideoInitCancels.remove(key);
  if (fn == null) return;
  try {
    fn();
  } catch (_) {}
}

/// 取消所有活跃的视频请求，防止 pending 的 segment 请求继续触发服务端转码。
/// - P2P 模式：取消 _activeVideoP2pFetches 中注册的 player_closed 取消函数，并通知 SW 返回错误
/// - 直连模式：向 index.html 发送 cancel_video_fetches 消息，触发 AbortController 批量取消
/// 同时设置 _videoFetchesRejecting = true，让后续 HLS.js 重试请求在进入 sendP2pStreamRequest 之前
/// 即刻被拒绝，避免视频 link 错误被误判为主 P2P 断连而触发 _forceReconnectP2p → session/create
void cancelVideoP2pFetches() {
  _videoFetchesRejecting = true;
  // P2P 模式：取消通过 /__p2p__/ 代理的视频请求
  final entries = _activeVideoP2pFetches.entries.toList();
  _activeVideoP2pFetches.clear();
  for (final entry in entries) {
    try {
      entry.value();
    } catch (_) {}
  }
  // 直连模式：通知 index.html 中的 AbortController 批量取消视频 fetch
  try {
    web.window.postMessage(
      jsonEncode(<String, dynamic>{'__p2p': 'cancel_video_fetches'}).toJS,
      '*'.toJS,
    );
  } catch (_) {}
}

Future<VideoPlayerController> createVideoController(
  String url, {
  String? requestKey,
}) async {
  // 新视频打开时解除拒绝状态，允许新的视频 fetch 请求通过
  _videoFetchesRejecting = false;
  if (kIsWeb && ApiController.instance.isP2pMode && url.isNotEmpty) {
    _ensureP2pFetchResponderInstalled();

    final proxyUrl = _toP2pProxyUrl(url);
    if (proxyUrl != null) {
      final lowerUrl = url.toLowerCase();
      final isHls =
          lowerUrl.contains('.m3u8') ||
          lowerUrl.contains('/api/videoplayer/transcode') ||
          lowerUrl.contains('/api/videoplayer/hls/');
      return VideoPlayerController.networkUrl(
        Uri.parse(proxyUrl),
        formatHint: isHls ? VideoFormat.hls : null,
      );
    }

    final lowerUrl = url.toLowerCase();
    final isHls =
        lowerUrl.contains('.m3u8') ||
        lowerUrl.contains('/api/videoplayer/transcode') ||
        lowerUrl.contains('/api/videoplayer/hls/');
    if (isHls) {
      return VideoPlayerController.networkUrl(
        Uri.parse(url),
        formatHint: VideoFormat.hls,
      );
    }

    String p2pPath = '';
    try {
      final uri = Uri.parse(url);
      p2pPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    } catch (_) {
      p2pPath = '';
    }
    if (p2pPath.isNotEmpty) {
      final req = http.Request(
        'GET',
        Uri.parse(
          '${ApiController.p2pBaseUrl}'
          '${p2pPath.startsWith('/') ? p2pPath : '/$p2pPath'}',
        ),
      );
      final token = ApiController.instance.accessToken?.trim() ?? '';
      if (token.isNotEmpty) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      final res = await ApiController.instance.sendP2pStreamRequest(
        req,
        timeout: const Duration(minutes: 30),
        channel: P2pRtcChannel.video,
      );
      if (res.status < 200 || res.status >= 300) {
        res.cancel();
        throw Exception('p2p_video_http_${res.status}');
      }
      var mime = res.headers['content-type']?.trim() ?? '';
      if (mime.isEmpty) {
        mime = _guessVideoMime(url);
      } else {
        final semi = mime.indexOf(';');
        if (semi != -1) {
          mime = mime.substring(0, semi).trim();
        }
      }
      final parts = <JSAny>[];
      StreamSubscription<Uint8List>? sub;
      final done = Completer<void>();
      final initKey = requestKey?.trim() ?? '';
      if (initKey.isNotEmpty) {
        _p2pVideoInitCancels[initKey] = () {
          try {
            sub?.cancel();
          } catch (_) {}
          try {
            res.cancel();
          } catch (_) {}
          if (!done.isCompleted) {
            done.completeError(Exception('p2p_video_init_canceled'));
          }
        };
      }
      sub = res.stream.listen(
        (chunk) {
          final jsBuf = Uint8List.fromList(chunk).buffer.toJS;
          parts.add(jsBuf);
        },
        onError: (e) {
          if (!done.isCompleted) done.completeError(e);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      await done.future;
      if (initKey.isNotEmpty) {
        _p2pVideoInitCancels.remove(initKey);
      }

      final blob = web.Blob(parts.toJS, web.BlobPropertyBag(type: mime));
      final objUrl = web.URL.createObjectURL(blob);
      final controller = VideoPlayerController.networkUrl(Uri.parse(objUrl));
      _p2pVideoResources[identityHashCode(controller)] = _WebP2pVideoResource(
        objectUrl: objUrl,
        subscription: sub,
        p2pCancel: res.cancel,
      );
      return controller;
    }
  }

  final lowerUrl = url.toLowerCase();
  final isHls =
      lowerUrl.contains('.m3u8') ||
      lowerUrl.contains('/api/videoplayer/transcode') ||
      lowerUrl.contains('/api/videoplayer/hls/');
  return VideoPlayerController.networkUrl(
    Uri.parse(url),
    formatHint: isHls ? VideoFormat.hls : null,
  );
}

/// 当前页面的路径前缀（如 "" 根目录 或 "/client/"），用于与 SW 同 scope，公网部署时 base href 可能为 /client/
String get _webP2pBasePath {
  final p = Uri.base.path;
  return p.endsWith('/') ? p : '$p/';
}

String? _toP2pProxyUrl(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  final basePath = _webP2pBasePath;
  final prefix =
      '${Uri.base.origin}$basePath'
      '__p2p__/';
  if (raw.startsWith(prefix)) return raw;
  if (!raw.startsWith(ApiController.p2pBaseUrl)) return null;
  try {
    final uri = Uri.parse(raw);
    final path = uri.path;
    final pathNorm = path.startsWith('/') ? path.substring(1) : path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${Uri.base.origin}$basePath'
        '__p2p__/$pathNorm$query';
  } catch (_) {
    return null;
  }
}

void _ensureP2pFetchResponderInstalled() {
  if (_p2pFetchResponderInstalled) return;
  _p2pFetchResponderInstalled = true;

  web.window.addEventListener(
    'message',
    ((web.Event event) {
      if (!ApiController.instance.isP2pMode) return;
      final e = event as web.MessageEvent;
      final raw = e.data?.toString() ?? '';
      if (raw.isEmpty) return;
      Map<String, dynamic> msg;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) return;
        msg = decoded;
      } catch (_) {
        return;
      }
      if (msg['__p2p'] == 'fetch_abort') {
        final id = msg['id']?.toString();
        if (id != null) {
          final fn = _activeP2pFetches.remove(id);
          if (fn != null) {
            try {
              fn();
            } catch (_) {}
          }
        }
        return;
      }
      if (msg['__p2p'] != 'fetch') return;
      unawaited(_handleP2pFetchMessage(msg));
    }).toJS,
  );
}

Future<void> _handleP2pFetchMessage(Map<String, dynamic> msg) async {
  final id = msg['id']?.toString() ?? '';
  final url = msg['url']?.toString() ?? '';
  final method = msg['method']?.toString().trim().toUpperCase() ?? 'GET';

  if (id.isEmpty || url.isEmpty) return;
  final p2pUrl = _normalizeP2pFetchUrl(url);
  if (p2pUrl == null) return;

  try {
    final req = http.Request(method, Uri.parse(p2pUrl));
    final headers = msg['headers'];
    if (headers is Map) {
      for (final entry in headers.entries) {
        final k = entry.key?.toString();
        final v = entry.value?.toString();
        if (k == null || v == null) continue;
        req.headers[k] = v;
      }
    }

    final bodyText = msg['body']?.toString();
    final bodyBase64 = msg['bodyBase64']?.toString();
    if (bodyBase64 != null && bodyBase64.trim().isNotEmpty) {
      try {
        req.bodyBytes = base64Decode(bodyBase64.trim());
      } catch (_) {}
    } else if (bodyText != null && bodyText.isNotEmpty) {
      req.body = bodyText;
    }

    final parsed = Uri.tryParse(p2pUrl);
    final p = parsed?.path ?? '';

    // 播放器已关闭（_videoFetchesRejecting=true）时，立即拒绝视频路径的新请求。
    // 防止 HLS.js 重试触发 sendP2pStreamRequest，进而因视频 link 错误被误判为
    // 主 P2P 断连，引发 _forceReconnectP2p → session/create 级联重连。
    if (_videoFetchesRejecting && p.startsWith('/api/videoPlayer/')) {
      web.window.postMessage(
        jsonEncode(<String, dynamic>{
          '__p2p': 'fetch_res_error',
          'id': id,
          'error': 'player_closed',
        }).toJS,
        '*'.toJS,
      );
      return;
    }

    final channel = p.startsWith('/api/videoPlayer/')
        ? P2pRtcChannel.video
        : (p.startsWith('/api/file/download')
              ? P2pRtcChannel.download
              : (p.startsWith('/api/file/')
                    ? P2pRtcChannel.file
                    : P2pRtcChannel.api));

    final isLong =
        p.startsWith('/api/videoPlayer/') ||
        p.startsWith('/api/file/rawFile') ||
        p.startsWith('/api/file/download');
    final res = await ApiController.instance.sendP2pStreamRequest(
      req,
      timeout: isLong
          ? const Duration(minutes: 30)
          : const Duration(seconds: 60),
      channel: channel,
    );

    // Rewrite m3u8 content to enforce P2P routing for segments
    final isM3u8 =
        p2pUrl.toLowerCase().contains('.m3u8') ||
        (res.headers['content-type']?.contains('mpegurl') ?? false) ||
        (res.headers['content-type']?.contains(
              'application/vnd.apple.mpegurl',
            ) ??
            false);

    if (isM3u8) {
      final done = Completer<void>();
      // SW 发起的 abort（HLS.js 已知晓，无需回复）
      _activeP2pFetches[id] = () {
        try {
          res.cancel();
        } catch (_) {}
        if (!done.isCompleted) done.completeError(Exception('aborted'));
      };
      // 播放器主动关闭时的取消（需通知 SW 返回错误，避免 pending 请求继续驱动转码）
      bool m3u8PlayerClosed = false;
      if (p.startsWith('/api/videoPlayer/')) {
        _activeVideoP2pFetches[id] = () {
          _activeP2pFetches.remove(id);
          m3u8PlayerClosed = true;
          try {
            res.cancel();
          } catch (_) {}
          if (!done.isCompleted) {
            done.completeError(Exception('player_closed'));
          }
        };
      }

      try {
        final bytes = await http.ByteStream(res.stream).toBytes();
        // 播放器已关闭（done 已因 player_closed 完成），跳过发送部分 m3u8 数据
        if (m3u8PlayerClosed || done.isCompleted) return;
        var content = utf8.decode(bytes);

        final basePath = _webP2pBasePath;
        final p2pPrefix = basePath == '/' ? '/__p2p__' : '${basePath}__p2p__';
        final lines = content.split('\n');
        final newLines = lines.map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return line;
          if (trimmed.startsWith('#')) return line;
          if (trimmed.startsWith('/')) {
            if (trimmed.startsWith(p2pPrefix)) return line;
            if (trimmed.startsWith('/__p2p__/'))
              return p2pPrefix + trimmed.substring('/__p2p__'.length);
            return '$p2pPrefix/${trimmed.substring(1)}';
          }
          return line;
        }).toList();
        content = newLines.join('\n');
        final newBytes = utf8.encode(content);

        web.window.postMessage(
          jsonEncode(<String, dynamic>{
            '__p2p': 'fetch_res_begin',
            'id': id,
            'status': res.status,
            'headers': res.headers,
          }).toJS,
          '*'.toJS,
        );

        final jsChunk = Uint8List.fromList(newBytes).toJS;
        final payload = <String, Object?>{
          '__p2p': 'fetch_res_chunk',
          'id': id,
          'chunk': jsChunk,
        }.jsify();
        web.window.postMessage(payload, '*'.toJS);

        web.window.postMessage(
          jsonEncode(<String, dynamic>{
            '__p2p': 'fetch_res_end',
            'id': id,
          }).toJS,
          '*'.toJS,
        );
        done.complete();
      } catch (e) {
        if (!done.isCompleted) done.completeError(e);
      }

      try {
        await done.future;
        _activeP2pFetches.remove(id);
        _activeVideoP2pFetches.remove(id);
      } catch (e) {
        _activeP2pFetches.remove(id);
        _activeVideoP2pFetches.remove(id);
        if (e.toString().contains('aborted')) return;
        web.window.postMessage(
          jsonEncode(<String, dynamic>{
            '__p2p': 'fetch_res_error',
            'id': id,
            'error': e.toString(),
          }).toJS,
          '*'.toJS,
        );
      }
      return;
    }

    web.window.postMessage(
      jsonEncode(<String, dynamic>{
        '__p2p': 'fetch_res_begin',
        'id': id,
        'status': res.status,
        'headers': res.headers,
      }).toJS,
      '*'.toJS,
    );

    StreamSubscription<Uint8List>? sub;
    final done = Completer<void>();
    // playerClosed 标志：防止 sync StreamController.close() 同步触发 onDone→done.complete()
    // 竞争导致 player_closed 的 completeError 变成 no-op，使 fetch_res_end 代替 fetch_res_error 发出
    bool playerClosed = false;

    // SW 发起的 abort（HLS.js 已知晓，无需回复）
    _activeP2pFetches[id] = () {
      try {
        sub?.cancel();
      } catch (_) {}
      try {
        res.cancel();
      } catch (_) {}
      if (!done.isCompleted) done.completeError(Exception('aborted'));
    };
    // 播放器主动关闭时的取消（需通知 SW 返回错误，避免 pending segment 继续驱动转码）
    if (p.startsWith('/api/videoPlayer/')) {
      _activeVideoP2pFetches[id] = () {
        _activeP2pFetches.remove(id);
        // 必须在 sub?.cancel()/res.cancel() 之前置标志，否则 sync onDone 会先 done.complete()
        playerClosed = true;
        try {
          sub?.cancel();
        } catch (_) {}
        try {
          res.cancel();
        } catch (_) {}
        if (!done.isCompleted) done.completeError(Exception('player_closed'));
      };
    }

    const maxChunkBytes = 32 * 1024;
    sub = res.stream.listen(
      (chunk) {
        int offset = 0;
        while (offset < chunk.length) {
          final end = (offset + maxChunkBytes) > chunk.length
              ? chunk.length
              : (offset + maxChunkBytes);
          final piece = chunk.sublist(offset, end);

          final jsChunk = Uint8List.fromList(piece).toJS;
          final payload = <String, Object?>{
            '__p2p': 'fetch_res_chunk',
            'id': id,
            'chunk': jsChunk,
          }.jsify();

          web.window.postMessage(payload, '*'.toJS);
          offset = end;
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          // playerClosed=true 时：sync controller.close() 在 cancel 函数中同步触发了本回调，
          // 此时应完成 error 而非 success，确保 catch 块发出 fetch_res_error
          if (playerClosed) {
            done.completeError(Exception('player_closed'));
          } else {
            done.complete();
          }
        }
      },
      onError: (e) {
        if (!done.isCompleted) done.completeError(e);
      },
      cancelOnError: true,
    );

    try {
      await done.future;
      _activeP2pFetches.remove(id);
      _activeVideoP2pFetches.remove(id);

      web.window.postMessage(
        jsonEncode(<String, dynamic>{'__p2p': 'fetch_res_end', 'id': id}).toJS,
        '*'.toJS,
      );
    } catch (e) {
      _activeP2pFetches.remove(id);
      _activeVideoP2pFetches.remove(id);
      if (e.toString().contains('aborted')) return;

      web.window.postMessage(
        jsonEncode(<String, dynamic>{
          '__p2p': 'fetch_res_error',
          'id': id,
          'error': e.toString(),
        }).toJS,
        '*'.toJS,
      );
    }
  } catch (e) {
    _activeP2pFetches.remove(id);
    _activeVideoP2pFetches.remove(id);
    web.window.postMessage(
      jsonEncode(<String, dynamic>{
        '__p2p': 'fetch_res_error',
        'id': id,
        'error': e.toString(),
      }).toJS,
      '*'.toJS,
    );
  }
}

String? _normalizeP2pFetchUrl(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  if (raw.toLowerCase().startsWith(ApiController.p2pBaseUrl)) return raw;
  try {
    final u = Uri.parse(raw);
    final p = u.path;
    // 支持部署在子路径（如 /client/__p2p__/api/...），不要求路径必须以 /__p2p__ 开头
    const marker = '/__p2p__/';
    final idx = p.indexOf(marker);
    if (idx < 0) return null;
    final rest = p.substring(idx + marker.length);
    final path = rest.isEmpty ? '/' : (rest.startsWith('/') ? rest : '/$rest');
    final query = u.hasQuery ? '?${u.query}' : '';
    return '${ApiController.p2pBaseUrl}$path$query';
  } catch (_) {
    return null;
  }
}

String _guessVideoMime(String url) {
  final u = url.toLowerCase();
  if (u.contains('.mp4') || u.contains('video/mp4')) return 'video/mp4';
  if (u.contains('.webm')) return 'video/webm';
  if (u.contains('.mov')) return 'video/quicktime';
  return 'application/octet-stream';
}

class _WebP2pVideoResource {
  final String objectUrl;
  final StreamSubscription<Uint8List>? subscription;
  final void Function() p2pCancel;

  const _WebP2pVideoResource({
    required this.objectUrl,
    required this.subscription,
    required this.p2pCancel,
  });
}

void setFvpAudioTracks(VideoPlayerController controller, List<int> tracks) {
  // Web no-op
}

void setFvpSubtitleTracks(VideoPlayerController controller, List<int> tracks) {
  // Web no-op
}

void setFvpExternalSubtitle(
  VideoPlayerController controller,
  String url, {
  String? label,
}) {
  // Web no-op
}
