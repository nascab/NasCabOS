import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:fvp/fvp.dart' as fvp_lib;
import 'package:fvp/fvp.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/local_web_asset_server.dart';

export 'package:window_manager/window_manager.dart';

final Map<int, bool> _ioVideoProxiedControllers = {};
final Map<String, void Function()> _ioP2pVideoInitCancels = {};

bool _isFvpProxyCacheAllowedExt(String ext) {
  final e = ext.toLowerCase().trim();
  return e == '.mp4' || e == '.mov' ;
}

String _extHintFromRawFileUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final p = (uri.queryParameters['path'] ?? '').trim();
    if (p.isNotEmpty) return _lowerExtFromSource(p);
    final internal = (uri.queryParameters['internalPath'] ?? '').trim();
    if (internal.isNotEmpty) return _lowerExtFromSource(internal);
  } catch (_) {}
  return '';
}

String _mediaExtHintFromPlaybackUrl(String url) {
  if (_isRawFilePlaybackUrl(url)) {
    final ext = _extHintFromRawFileUrl(url);
    if (ext.isNotEmpty) return ext;
  }
  return _lowerExtFromSource(url);
}


bool audioTracksContainProblematicAndroidHardwareCodec(
  List<Map<String, dynamic>> audioTracks,
) {
  for (final t in audioTracks) {
    final c = (t['codec_name']?.toString() ?? '').toLowerCase().trim();
    if (c.isEmpty) continue;
    // truehd 常对应 ffprobe 的 codec_name=truehd / mlp（Meridian Lossless Packing）
    if (c == 'truehd' || c == 'mlp') return true;
    // 一些设备对 HD 音频在硬解链路上也更容易出问题（可按反馈再扩展）
    if (c == 'dts-hd' || c == 'dtshd') return true;
  }
  return false;
}

String _lowerExtFromSource(String src) {
  final s = src.trim();
  if (s.isEmpty) return '';
  // URL/路径都处理：取 path 部分的扩展名
  try {
    final u = Uri.tryParse(s);
    final p = (u != null && u.path.isNotEmpty) ? u.path : s;
    final dot = p.lastIndexOf('.');
    if (dot < 0 || dot == p.length - 1) return '';
    return p.substring(dot).toLowerCase();
  } catch (_) {
    final dot = s.lastIndexOf('.');
    if (dot < 0 || dot == s.length - 1) return '';
    return s.substring(dot).toLowerCase();
  }
}

/// Media3/ExoPlayer 无原生解封装器的旧容器（如 AVI），原画应改走 FVP。
const Set<String> androidMedia3LegacyContainerExtensions = {
  'avi',
  'wmv',
  'asf',
  'mpg',
  'mpeg',
};

bool androidLegacyContainerNeedsFvpEngine(String sourcePath) {
  final ext = _lowerExtFromSource(sourcePath).replaceFirst('.', '');
  return androidMedia3LegacyContainerExtensions.contains(ext);
}

/// DivX/XviD 等 MPEG-4 Part 2，Media3 硬解与 FFmpeg 直链均不可靠。
bool androidLegacyVideoCodecNeedsFvpEngine(
  List<Map<String, dynamic>> videoTracks,
) {
  for (final v in videoTracks) {
    final codec = v['codec_name']?.toString().toLowerCase().trim() ?? '';
    if (codec != 'mpeg4') continue;
    final tag = v['codec_tag_string']?.toString().toUpperCase().trim() ?? '';
    if (tag == 'XVID' || tag == 'DIVX' || tag == 'DX50') return true;
    final profile = v['profile']?.toString().toLowerCase() ?? '';
    if (profile.contains('advanced simple')) return true;
  }
  return false;
}

/// 仅 10-bit H.264：Media3 FFmpeg 软解黑屏；10-bit HEVC 多数机型硬解正常，不自动切 FVP。
bool androidH264HighBitDepthNeedsFvpEngine(
  List<Map<String, dynamic>> videoTracks,
) {
  for (final v in videoTracks) {
    final codec = v['codec_name']?.toString().toLowerCase().trim() ?? '';
    if (codec != 'h264' && codec != 'avc') continue;
    if (isHighBitDepthVideoStream(v)) return true;
  }
  return false;
}

bool androidMedia3SourceNeedsFvpEngine({
  required List<Map<String, dynamic>> videoTracks,
  required String sourcePath,
}) {
  if (androidLegacyContainerNeedsFvpEngine(sourcePath)) return true;
  if (androidH264HighBitDepthNeedsFvpEngine(videoTracks)) return true;
  return androidLegacyVideoCodecNeedsFvpEngine(videoTracks);
}

/// Media3 等原生内核：始终使用服务端原始 URL，不走 [LocalWebAssetServer]。
String resolveDirectPlaybackUrl(String url) => url.trim();

/// 原生内核（Media3）在 P2P 模式下仅走本地 HTTP 透传代理，不使用 Range 内存缓存。
Future<({String url, bool holdVideoLocalProxy})> resolveP2pProxyForNative(
  String url,
) async {
  final raw = resolveDirectPlaybackUrl(url);
  if (!raw.startsWith('http')) {
    return (url: raw, holdVideoLocalProxy: false);
  }
  final api = ApiController.instance;
  if (!api.isP2pMode || !raw.startsWith(ApiController.p2pBaseUrl)) {
    return (url: raw, holdVideoLocalProxy: false);
  }
  Uri remote;
  try {
    remote = Uri.parse(raw);
  } catch (_) {
    remote = Uri();
  }
  if (remote.path.isEmpty) {
    return (url: raw, holdVideoLocalProxy: false);
  }
  final localBase = await LocalWebAssetServer.instance.acquire();
  final qp = Map<String, String>.from(remote.queryParameters);
  if (_isRawFilePlaybackUrl(raw)) {
    qp[nascabNoRangeCacheQueryKey] = '1';
  }
  final proxied = localBase
      .replace(path: remote.path, queryParameters: qp)
      .toString();
  return (url: proxied, holdVideoLocalProxy: false);
}

/// 兼容旧调用。
Future<String> resolveP2pProxyUrlForNativeIfNeeded(String url) async {
  final r = await resolveP2pProxyForNative(url);
  return r.url;
}

/// FVP / 音乐播放器共用：原画 rawFile / P2P 可走本地代理 + Range 内存缓存。
///
/// P2P 模式下所有格式都必须走本地代理，因为 [ApiController.p2pBaseUrl]
/// 是虚拟域名，底层播放器无法直接解析。音乐播放器（桌面端 video_player）
/// 也通过此函数获取代理 URL，因此不能仅按 .mp4/.mov 过滤。
Future<String> resolveProxiedPlaybackUrlForFvp(
  String url, {
  String? requestKey,
}) async {
  if (!url.startsWith('http')) {
    return url;
  }
  final api = ApiController.instance;
  final shouldUseP2pProxy = api.isP2pMode;
  final raw = url.trim();

  // P2P 模式下所有请求必须走本地代理，否则底层播放器无法解析 p2pBaseUrl 虚拟域名。
  if (shouldUseP2pProxy && raw.startsWith(ApiController.p2pBaseUrl)) {
    Uri remote;
    try {
      remote = Uri.parse(raw);
    } catch (_) {
      remote = Uri();
    }
    if (remote.path.isNotEmpty) {
      final localBase = await LocalWebAssetServer.instance.acquire();
      return localBase
          .replace(path: remote.path, query: remote.query)
          .toString();
    }
  }

  // 非 P2P 模式下仅允许 mp4/mov 走本地代理 + Range 内存缓存；其它格式直接请求服务器。
  final extHint = _mediaExtHintFromPlaybackUrl(raw);
  final allowProxy = _isFvpProxyCacheAllowedExt(extHint);
  if (!allowProxy) return raw;

  if (_isRawFilePlaybackUrl(raw)) {
    Uri remote;
    try {
      remote = Uri.parse(raw);
    } catch (_) {
      remote = Uri();
    }
    if (remote.path.isNotEmpty) {
      final localBase = await LocalWebAssetServer.instance.acquireForVideo();
      return localBase.replace(path: remote.path, query: remote.query).toString();
    }
  }
  return raw;
}

bool _isRawFilePlaybackUrl(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('/api/videoplayer/transcode') ||
      lower.contains('/api/videoplayer/hls/') ||
      lower.contains('.m3u8')) {
    return false;
  }
  return lower.contains('/api/videoplayer/rawfile') ||
      lower.contains('/api/file/rawfile');
}

/// Windows 默认硬件解码链（原画常规 8-bit 源）。
const List<String> windowsHardwareVideoDecoders = [
  'MFT:d3d=11',
  'D3D11',
  'DXVA',
  'CUDA',
  'hap',
  'FFmpeg',
  'dav1d',
];

/// Windows 10/12-bit 等高 bit depth 源：硬件解码易出现花屏，改走 FFmpeg 软解。
const List<String> windowsSoftwareVideoDecoders = ['FFmpeg', 'dav1d'];

/// 与转码服务 [isHighBitDepthVideoStream] 对齐：10/12-bit x264 等在 Windows 硬解易异常。
bool isHighBitDepthVideoStream(Map<String, dynamic> videoStream) {
  final bits = num.tryParse('${videoStream['bits_per_raw_sample'] ?? ''}');
  if (bits != null && bits > 8) return true;
  final pixFmt = (videoStream['pix_fmt']?.toString() ?? '').toLowerCase();
  if (RegExp(r'10le|12le|p010|p016|yuv444p1[02]|gbrap1[02]').hasMatch(pixFmt)) {
    return true;
  }
  final profile = (videoStream['profile']?.toString() ?? '').toLowerCase();
  if (RegExp(r'\b10\b|high 10|main 10|main10').hasMatch(profile)) {
    return true;
  }
  // avc1.6E = H.264 High 10（手机硬解常报 NO_EXCEEDS_CAPABILITIES）
  final codecTag = (videoStream['codec_tag_string']?.toString() ?? '').toLowerCase();
  if (RegExp(r'avc1\.6e').hasMatch(codecTag)) return true;
  return false;
}

bool _pathHintsHighBitDepth(String path) {
  final lower = path.toLowerCase();
  return lower.contains('10bit') ||
      lower.contains('hi10') ||
      lower.contains('high10') ||
      lower.contains('yuv420p10');
}

/// 原画在 Windows 上是否应强制软件解码（高位深 H.264/HEVC 等）。
bool needsWindowsSoftwareVideoDecode({
  required List<Map<String, dynamic>> videoTracks,
  String sourcePath = '',
}) {
  if (!Platform.isWindows) return false;
  return needsSoftwareVideoDecodeForHighBitDepth(
    videoTracks: videoTracks,
    sourcePath: sourcePath,
  );
}

/// 10/12-bit 等高位深源：硬解易失败，应优先软件解码（Windows FVP / Android Media3）。
bool needsSoftwareVideoDecodeForHighBitDepth({
  required List<Map<String, dynamic>> videoTracks,
  String sourcePath = '',
}) {
  for (final track in videoTracks) {
    if (isHighBitDepthVideoStream(track)) return true;
  }
  if (videoTracks.isEmpty && _pathHintsHighBitDepth(sourcePath)) return true;
  return false;
}

void registerFvp({List<String>? videoDecoders}) {
  if (kIsWeb) {
    fvp_lib.registerWith(
      options: {
        'global': {'log': 'off'},
      },
    );
  } else {
    final options = <String, Object?>{
      'global': <String, Object>{'log': 'off'},
      'subtitleFontFile': 'assets/subfont.ttf',
    };
    if (Platform.isWindows) {
      options['video.decoders'] =
          videoDecoders ?? windowsHardwareVideoDecoders;
    } else if (Platform.isMacOS) {
      options['video.decoders'] = ['VT', 'hap', 'FFmpeg', 'dav1d'];
    }
    fvp_lib.registerWith(options: options);
  }
}

Future<VideoPlayerController> createVideoController(
  String url, {
  String? requestKey,
}) async {
  if (url.startsWith('http')) {
    final lowerUrl = url.toLowerCase();
    final isHls =
        lowerUrl.contains('.m3u8') ||
        lowerUrl.contains('/api/videoplayer/transcode') ||
        lowerUrl.contains('/api/videoplayer/hls/');

    final initKey = requestKey?.trim() ?? '';
    bool canceled = false;
    void Function()? cancelFn;
    bool needsVideoRelease = false;
    if (initKey.isNotEmpty) {
      cancelFn = () {
        canceled = true;
      };
      _ioP2pVideoInitCancels[initKey] = cancelFn;
    }

    try {
      final raw = resolveDirectPlaybackUrl(url);
      final proxied = await resolveProxiedPlaybackUrlForFvp(
        raw,
        requestKey: initKey,
      );
      // P2P 代理由 LocalWebAssetServer.acquire() 维持（不受视频引用计数管理），
      // 只有 rawFile 视频代理才需要 acquireForVideo()/releaseForVideo() 配对。
      final isP2pProxy =
          ApiController.instance.isP2pMode &&
          raw.startsWith(ApiController.p2pBaseUrl);
      needsVideoRelease = proxied != raw && !isP2pProxy;

      if (canceled) {
        throw Exception('p2p_video_init_canceled');
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(proxied),
        formatHint: isHls ? VideoFormat.hls : null,
      );
      if (needsVideoRelease) {
        _ioVideoProxiedControllers[identityHashCode(controller)] = true;
      }
      return controller;
    } finally {
      if (initKey.isNotEmpty) {
        final existing = _ioP2pVideoInitCancels[initKey];
        if (existing == null || identical(existing, cancelFn)) {
          _ioP2pVideoInitCancels.remove(initKey);
        }
      }
      if (canceled && needsVideoRelease) {
        unawaited(LocalWebAssetServer.instance.releaseForVideo());
      }
    }
  }
  return VideoPlayerController.file(File(url));
}

void cancelVideoControllerInit(String initKey) {
  final key = initKey.trim();
  if (key.isEmpty) return;
  final fn = _ioP2pVideoInitCancels.remove(key);
  if (fn == null) return;
  try {
    fn();
  } catch (_) {}
}

void cancelVideoP2pFetches() {
  // Non-web: no-op
}

/// 非 Web 空操作；Web 实现在 video_platform_web.dart
void stopWebVideoElementNetworking() {}

void disposeVideoController(VideoPlayerController controller) {
  final key = identityHashCode(controller);
  final needsRelease = _ioVideoProxiedControllers.remove(key) ?? false;
  if (!needsRelease) return;
  unawaited(LocalWebAssetServer.instance.releaseForVideo());
}

void setFvpAudioTracks(VideoPlayerController controller, List<int> tracks) {
  controller.setAudioTracks(tracks);
}

void setFvpSubtitleTracks(VideoPlayerController controller, List<int> tracks) {
  print("设置内置字幕 $tracks");
  controller.setSubtitleTracks(tracks);
}

void setFvpExternalSubtitle(
  VideoPlayerController controller,
  String url, {
  String? label,
}) {
  controller.setExternalSubtitle(url);
  print("设置外挂字幕 $url");
}
