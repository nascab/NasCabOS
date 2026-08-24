import 'package:flutter/foundation.dart';

/// 音乐播放源：本地文件路径或网络 URL
class MusicPlaySource {
  final String? filePath;
  final String url;
  final String fileExt;

  const MusicPlaySource({this.filePath, required this.url, this.fileExt = ''});

  bool get isLocal => filePath != null && filePath!.isNotEmpty;
}

/// 音乐播放器适配器抽象基类，用于统一 video_player 与 just_audio
abstract class MusicPlayerAdapter {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double value);
  Future<void> setLooping(bool looping);
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  Future<void> dispose();

  Duration get duration;
  Duration get position;
  Duration get buffered;
  bool get isPlaying;
  bool get isBuffering;
  bool get hasError;
  bool get isInitialized;

  bool get isCompleted => false;
}
