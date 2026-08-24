import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../utils/device_utils.dart';
import '../../video_player/controllers/platform/video_platform_io.dart'
    if (dart.library.html) '../../video_player/controllers/platform/video_platform_web.dart'
    as video_platform;
import '../../video_player/playback/playback_engine.dart';
import '../../video_player/playback/playback_engine_factory.dart';
import '../../video_player/playback/playback_engine_type.dart';
import '../../video_player/playback/playback_video_surface.dart';

/// 画廊页内播放 Live Photo 视频：不跳转页面，自动播放且循环。
/// 置于 PageView 页项内，点击画面停止播放，同时仍可左右滑动切换上一张/下一张。
///
/// Android 复用主播放器的 Media3 内核（ExoPlayer 硬解），避免 FVP 软解
/// iPhone HEVC/HDR 源导致的卡顿；其余平台沿用 FVP。
class LivePhotoInlinePlayer extends StatefulWidget {
  const LivePhotoInlinePlayer({
    super.key,
    required this.videoUrl,
    this.fallbackVideoUrl,
    required this.onClose,
  });

  final String videoUrl;

  /// Web 端源文件播放失败时重试的转码 MP4 流 URL
  final String? fallbackVideoUrl;

  /// 点击画面时回调（用于停止播放）
  final VoidCallback onClose;

  @override
  State<LivePhotoInlinePlayer> createState() => _LivePhotoInlinePlayerState();
}

class _LivePhotoInlinePlayerState extends State<LivePhotoInlinePlayer> {
  /// Android 使用 Media3；其它平台使用 FVP。
  late final bool _useMedia3;

  PlaybackEngine? _media3Engine;
  VideoPlayerController? _fvpController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _useMedia3 = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (_useMedia3) {
      await _initMedia3();
    } else {
      await _initFvp();
    }
  }

  Future<void> _initMedia3() async {
    try {
      final engine = await createPlaybackEngine(
        type: PlaybackEngineType.media3,
        url: widget.videoUrl,
      );
      if (!mounted) {
        disposePlaybackEngine(engine);
        unawaited(engine.disposeEngine());
        return;
      }
      engine.addListener(_onMedia3Changed);
      setState(() {
        _media3Engine = engine;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _onMedia3Changed() {
    final engine = _media3Engine;
    if (!mounted || engine == null) return;
    if (engine.value.hasError) {
      final desc = engine.value.errorDescription?.trim() ?? '';
      setState(() => _error = desc.isNotEmpty ? desc : 'playback_failed');
    }
  }

  /// Media3 PlatformView 创建并 attach 后，开始循环播放。
  Future<void> _onMedia3SurfaceReady(int viewId) async {
    final engine = _media3Engine;
    if (engine == null || !mounted) return;
    try {
      await engine.setLooping(true);
      await engine.play();
    } catch (_) {}
  }

  Future<void> _initFvp() async {
    video_platform.registerFvp();
    final urls = [
      widget.videoUrl,
      if (widget.fallbackVideoUrl != null &&
          widget.fallbackVideoUrl != widget.videoUrl)
        widget.fallbackVideoUrl!,
    ];
    for (final url in urls) {
      try {
        final c = await video_platform.createVideoController(url);
        if (!mounted) {
          video_platform.disposeVideoController(c);
          unawaited(c.dispose());
          return;
        }
        await c.setLooping(true);
        await c.initialize();
        if (!mounted) {
          video_platform.disposeVideoController(c);
          unawaited(c.dispose());
          return;
        }
        await c.play();
        if (!mounted) {
          video_platform.disposeVideoController(c);
          unawaited(c.dispose());
          return;
        }
        setState(() {
          _fvpController = c;
          _error = null;
        });
        return;
      } catch (e) {
        if (!mounted) return;
        if (url == urls.last) {
          setState(() => _error = e.toString());
          return;
        }
      }
    }
  }

  @override
  void dispose() {
    if (_useMedia3) {
      final engine = _media3Engine;
      _media3Engine = null;
      if (engine != null) {
        engine.removeListener(_onMedia3Changed);
        disposePlaybackEngine(engine);
        unawaited(engine.disposeEngine());
      }
    } else {
      final c = _fvpController;
      _fvpController = null;
      if (c != null) {
        video_platform.disposeVideoController(c);
        unawaited(c.dispose());
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black, child: _buildContent()),
          // FVP 是普通 Flutter 组件，外层透明点击层可捕获点击停止播放；
          // Media3 是 PlatformView，会吞掉外层手势，点击由 PlaybackVideoSurface 处理。
          if (!_useMedia3)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_useMedia3) {
      final engine = _media3Engine;
      if (engine == null) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return PlaybackVideoSurface(
        engine: engine,
        onNativeViewCreated: _onMedia3SurfaceReady,
        onSurfaceTap: widget.onClose,
      );
    }

    final vc = _fvpController;
    if (vc == null || !vc.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (DeviceUtils.isWeb) {
      return ClipRect(
        child: SizedBox.expand(child: VideoPlayer(vc)),
      );
    }
    final ar = vc.value.aspectRatio;
    final safeAr = (ar > 0 && ar.isFinite) ? ar : (16 / 9);
    return Center(
      child: AspectRatio(aspectRatio: safeAr, child: VideoPlayer(vc)),
    );
  }
}
