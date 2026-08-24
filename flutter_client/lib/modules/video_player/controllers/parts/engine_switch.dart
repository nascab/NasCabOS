part of '../video_player_controller.dart';

extension PlayerEngineSwitch on PlayerController {
  static const _prefKey = 'video_player_playback_engine';

  /// Android 是否允许使用 Media3 内核。
  bool get canUseMedia3Engine =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> loadPlaybackEnginePreference() async {
    if (!canUseMedia3Engine) {
      playbackEngineType.value = PlaybackEngineType.fvp;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      playbackEngineType.value = saved == null
          ? defaultPlaybackEngineType()
          : PlaybackEngineTypeX.fromPreference(saved);
    } catch (_) {
      playbackEngineType.value = defaultPlaybackEngineType();
    }
  }

  Future<void> switchPlaybackEngine(PlaybackEngineType type) async {
    if (!canUseMedia3Engine && type == PlaybackEngineType.media3) {
      return;
    }
    if (playbackEngineType.value == type) return;
    playbackEngineType.value = type;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, type.preferenceKey);
    } catch (_) {}
    await _initializePlayer(keepPosition: true);
  }

  /// 按当前片源临时切换内核（不写 SharedPreferences，不影响用户默认设置）。
  bool applyPlaybackEngineForCurrentSource(PlaybackEngineType type) {
    if (!canUseMedia3Engine && type == PlaybackEngineType.media3) {
      return false;
    }
    if (playbackEngineType.value == type) return false;
    playbackEngineType.value = type;
    return true;
  }

  /// [PlaybackVideoSurface] 在 Media3 PlatformView 就绪后调用。
  Future<void> onMedia3SurfaceReady(int viewId) async {
    if (_media3WaitInitGeneration == null ||
        _media3WaitInitGeneration != _initGeneration) {
      return;
    }
    final engine = playbackEngine.value;
    if (engine == null || engine.type != PlaybackEngineType.media3) return;
    final c = _media3SurfaceReady;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }
}
