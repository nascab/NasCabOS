import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart' show DurationRange;

export 'package:video_player/video_player.dart' show DurationRange;

/// 与 [VideoPlayerValue] 对齐的播放状态快照，供控制层监听。
@immutable
class PlaybackValue {
  const PlaybackValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.hasError = false,
    this.errorDescription,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = const <DurationRange>[],
    this.volume = 1.0,
    this.playbackSpeed = 1.0,
    this.isLooping = false,
    this.aspectRatio = 16 / 9,
  });

  final bool isInitialized;
  final bool isPlaying;
  final bool hasError;
  final String? errorDescription;
  final Duration position;
  final Duration duration;
  final List<DurationRange> buffered;
  final double volume;
  final double playbackSpeed;
  final bool isLooping;
  final double aspectRatio;

  PlaybackValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? hasError,
    String? errorDescription,
    Duration? position,
    Duration? duration,
    List<DurationRange>? buffered,
    double? volume,
    double? playbackSpeed,
    bool? isLooping,
    double? aspectRatio,
  }) {
    return PlaybackValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      hasError: hasError ?? this.hasError,
      errorDescription: errorDescription ?? this.errorDescription,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      volume: volume ?? this.volume,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      isLooping: isLooping ?? this.isLooping,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}
