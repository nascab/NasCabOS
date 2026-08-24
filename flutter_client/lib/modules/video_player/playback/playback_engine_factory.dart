import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../core/api/api_controller.dart';
import '../controllers/platform/video_platform.dart';
import 'fvp_playback_engine.dart';
import 'media3_playback_engine.dart';
import 'playback_engine.dart';
import 'playback_engine_type.dart';

/// 创建播放内核实例。
Future<PlaybackEngine> createPlaybackEngine({
  required PlaybackEngineType type,
  required String url,
  String? requestKey,
  VideoFormat? formatHint,
  Duration startPosition = Duration.zero,
  bool forceSoftwareVideoDecode = false,
  String? externalSubtitleUrl,
  String? externalSubtitleSourcePath,
  String? externalSubtitleLabel,
}) async {
  switch (type) {
    case PlaybackEngineType.fvp:
      var restoreHardwareDecoders = false;
      if (forceSoftwareVideoDecode && Platform.isWindows) {
        registerFvp(videoDecoders: windowsSoftwareVideoDecoders);
        restoreHardwareDecoders = true;
      }
      try {
        final controller = await createVideoController(
          url,
          requestKey: requestKey,
        );
        final engine = FvpPlaybackEngine(controller);
        final uri = _uriFromUrl(url);
        await engine.initialize(uri: uri, formatHint: formatHint);
        return engine;
      } finally {
        if (restoreHardwareDecoders) {
          registerFvp();
        }
      }
    case PlaybackEngineType.media3:
      if (kIsWeb || !Platform.isAndroid) {
        throw UnsupportedError('Media3 engine is only available on Android');
      }
      final directUrl = resolveDirectPlaybackUrl(url);
      final proxy = await resolveP2pProxyForNative(directUrl);
      final engine = Media3PlaybackEngine();
      engine.prepareSource(
        uri: _uriFromUrl(proxy.url),
        formatHint: formatHint,
        httpHeaders: buildPlaybackHttpHeaders(),
        startPosition: startPosition,
        externalSubtitleUrl: externalSubtitleUrl,
        externalSubtitleSourcePath: externalSubtitleSourcePath,
        externalSubtitleLabel: externalSubtitleLabel,
      );
      return engine;
  }
}

Uri _uriFromUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return Uri.parse(url);
  }
  return Uri.file(url);
}

VideoFormat? formatHintFromUrl(String url) {
  final lower = url.toLowerCase();
  final isHls = lower.contains('.m3u8') ||
      lower.contains('/api/videoplayer/transcode') ||
      lower.contains('/api/videoplayer/hls/');
  return isHls ? VideoFormat.hls : null;
}

Map<String, String> buildPlaybackHttpHeaders() {
  final token = ApiController.instance.accessToken?.trim() ?? '';
  if (token.isEmpty) return const {};
  return {'Authorization': 'Bearer $token'};
}

void disposePlaybackEngine(PlaybackEngine engine) {
  if (engine is FvpPlaybackEngine) {
    final vc = engine.fvpVideoController;
    if (vc != null) {
      disposeVideoController(vc);
    }
  }
}
