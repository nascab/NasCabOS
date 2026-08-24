import 'package:flutter/foundation.dart';

/// 播放内核类型。控制层通过 [PlaybackEngine] 与具体实现解耦。
enum PlaybackEngineType {
  /// Flutter FVP（mdk/FFmpeg），桌面与 iOS 默认；Android 可手动切换。
  fvp,

  /// Android Media3 + FFmpeg extension（ExoPlayer）。
  media3,
}

PlaybackEngineType defaultPlaybackEngineType() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return PlaybackEngineType.media3;
  }
  return PlaybackEngineType.fvp;
}

extension PlaybackEngineTypeX on PlaybackEngineType {
  String get preferenceKey => name;

  static PlaybackEngineType fromPreference(String? raw) {
    switch (raw) {
      case 'media3':
        return PlaybackEngineType.media3;
      case 'fvp':
      default:
        return PlaybackEngineType.fvp;
    }
  }
}
