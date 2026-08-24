import 'package:fvp/fvp.dart';
import 'package:video_player/video_player.dart';

import 'playback_engine.dart';
import 'playback_engine_type.dart';
import 'playback_value.dart';

/// FVP / [VideoPlayerController] 播放内核适配。
class FvpPlaybackEngine extends PlaybackEngine {
  FvpPlaybackEngine(this._controller);

  final VideoPlayerController _controller;

  @override
  PlaybackEngineType get type => PlaybackEngineType.fvp;

  @override
  VideoPlayerController? get fvpVideoController => _controller;

  @override
  int? get nativeViewId => null;

  @override
  bool get supportsRuntimeTrackSwitch => true;

  @override
  PlaybackValue get value => _mapValue(_controller.value);

  void _onVideoUpdate() {
    notifyListeners();
  }

  @override
  Future<void> initialize({
    required Uri uri,
    VideoFormat? formatHint,
  }) async {
    await _controller.initialize();
    _controller.addListener(_onVideoUpdate);
    notifyListeners();
  }

  @override
  Future<void> disposeEngine() async {
    try {
      _controller.removeListener(_onVideoUpdate);
    } catch (_) {}
    await _controller.dispose();
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) async {
    await _controller.setVolume(volume);
    notifyListeners();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _controller.setPlaybackSpeed(speed);
    notifyListeners();
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _controller.setLooping(looping);
    notifyListeners();
  }

  @override
  Future<void> setAudioTracks(List<int> trackIndices) async {
    _controller.setAudioTracks(trackIndices);
  }

  @override
  Future<void> setSubtitleTracks(List<int> trackIndices) async {
    _controller.setSubtitleTracks(trackIndices);
  }

  @override
  Future<void> setExternalSubtitle(
    String url, {
    String? label,
    String? sourcePath,
  }) async {
    _controller.setExternalSubtitle(url);
  }

  @override
  Future<void> attachNativeView(int viewId) async {}

  static PlaybackValue _mapValue(VideoPlayerValue v) {
    final ar = v.aspectRatio;
    final safeAr = (ar > 0 && ar.isFinite) ? ar : (16 / 9);
    return PlaybackValue(
      isInitialized: v.isInitialized,
      isPlaying: v.isPlaying,
      hasError: v.hasError,
      errorDescription: v.errorDescription,
      position: v.position.isNegative ? Duration.zero : v.position,
      duration: v.duration,
      buffered: v.buffered,
      volume: v.volume,
      playbackSpeed: v.playbackSpeed,
      isLooping: v.isLooping,
      aspectRatio: safeAr,
    );
  }
}
