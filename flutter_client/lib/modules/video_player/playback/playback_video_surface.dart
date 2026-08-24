import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'playback_engine.dart';
import 'playback_engine_type.dart';

/// 根据当前 [PlaybackEngine] 类型渲染 FVP 画面或 Android Media3 PlatformView。
class PlaybackVideoSurface extends StatefulWidget {
  const PlaybackVideoSurface({
    super.key,
    required this.engine,
    this.onNativeViewCreated,
    this.onSurfaceTap,
  });

  final PlaybackEngine? engine;

  /// Media3：PlatformView 创建后回调，用于完成原生侧 open。
  final Future<void> Function(int viewId)? onNativeViewCreated;

  /// 点击画面（Media3 PlatformView 会吞掉外层 GestureDetector，需单独处理）。
  final VoidCallback? onSurfaceTap;

  @override
  State<PlaybackVideoSurface> createState() => _PlaybackVideoSurfaceState();
}

class _PlaybackVideoSurfaceState extends State<PlaybackVideoSurface> {
  static const String _viewType = 'nascab_media3_player';

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    if (engine == null) {
      return const SizedBox.shrink();
    }

    if (engine.type == PlaybackEngineType.fvp) {
      final vc = engine.fvpVideoController;
      if (vc == null || !vc.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      if (kIsWeb) {
        return ClipRect(
          child: SizedBox.expand(
            child: VideoPlayer(vc, key: ValueKey(identityHashCode(vc))),
          ),
        );
      }
      final ar = vc.value.aspectRatio;
      final safeAr = (ar > 0 && ar.isFinite) ? ar : (16 / 9);
      return Center(
        child: AspectRatio(
          aspectRatio: safeAr,
          child: VideoPlayer(vc, key: ValueKey(identityHashCode(vc))),
        ),
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      return SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AndroidView(
              viewType: _viewType,
              creationParams: <String, dynamic>{},
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (id) async {
                await engine.attachNativeView(id);
                await widget.onNativeViewCreated?.call(id);
              },
            ),
            if (widget.onSurfaceTap != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onSurfaceTap,
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
