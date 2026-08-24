import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import '../../../video_player/controllers/platform/video_platform.dart';
import 'music_player_adapter.dart';

/// 使用 video_player 的实现（Web、Desktop）
class MusicPlayerVideoAdapter extends MusicPlayerAdapter {
  MusicPlayerVideoAdapter(this._controller);

  final VideoPlayerController _controller;

  VideoPlayerValue get _value => _controller.value;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double value) => _controller.setVolume(value);

  @override
  Future<void> setLooping(bool looping) => _controller.setLooping(looping);

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _controller.removeListener(listener);

  @override
  Future<void> dispose() async {
    disposeVideoController(_controller);
    await _controller.dispose();
  }

  @override
  Duration get duration => _value.duration;

  @override
  Duration get position =>
      _value.position.isNegative ? Duration.zero : _value.position;

  @override
  Duration get buffered =>
      _value.buffered.isEmpty ? Duration.zero : _value.buffered.last.end;

  @override
  bool get isPlaying => _value.isPlaying;

  @override
  bool get isBuffering => _value.isBuffering;

  @override
  bool get hasError => _value.hasError;

  @override
  bool get isInitialized => _value.isInitialized;
}
