import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'playback_engine_type.dart';
import 'playback_value.dart';

/// 播放内核抽象：控制层只依赖本接口，不直接依赖 FVP / Media3。
abstract class PlaybackEngine extends ChangeNotifier {
  PlaybackEngineType get type;

  PlaybackValue get value;

  /// FVP 实现返回底层 [VideoPlayerController]，供 [VideoPlayer] 渲染；原生实现为 null。
  VideoPlayerController? get fvpVideoController;

  /// 原生 PlatformView 实例 id（仅 [PlaybackEngineType.media3]）。
  int? get nativeViewId;

  bool get supportsRuntimeTrackSwitch;

  /// Media3 在 PlatformView 已就绪时可热换源（画质切换），避免销毁重建。
  bool get canHotSwapSource => false;

  Future<void> initialize({
    required Uri uri,
    VideoFormat? formatHint,
  });

  Future<void> disposeEngine();

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setLooping(bool looping);

  Future<void> setAudioTracks(List<int> trackIndices);
  Future<void> setSubtitleTracks(List<int> trackIndices);
  Future<void> setExternalSubtitle(
    String url, {
    String? label,
    String? sourcePath,
  });

  /// 绑定原生 PlatformView（由 [PlaybackVideoSurface] 在创建后调用）。
  Future<void> attachNativeView(int viewId);

  /// 不销毁原生视图，仅更换播放地址（默认不支持）。
  Future<void> switchSource({
    required Uri uri,
    VideoFormat? formatHint,
    Duration startPosition = Duration.zero,
  }) async {
    throw UnsupportedError('switchSource is not supported by ${type.name}');
  }
}
