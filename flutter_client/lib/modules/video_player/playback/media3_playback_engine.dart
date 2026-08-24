import 'dart:async';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'playback_engine.dart';
import 'playback_engine_type.dart';
import 'playback_value.dart';

/// Android Media3 原生播放内核（MethodChannel + PlatformView）。
class Media3PlaybackEngine extends PlaybackEngine {
  static const MethodChannel _channel = MethodChannel('com.nascabos/playback');

  PlaybackValue _value = const PlaybackValue();
  int? _viewId;
  Uri? _pendingUri;
  VideoFormat? _pendingFormatHint;
  Map<String, String> _httpHeaders = const {};
  int _pendingStartPositionMs = 0;
  String? _pendingExternalSubtitleUrl;
  String? _pendingExternalSubtitleSourcePath;
  String? _pendingExternalSubtitleLabel;
  bool _initialized = false;
  StreamSubscription<dynamic>? _eventSub;

  @override
  PlaybackEngineType get type => PlaybackEngineType.media3;

  @override
  PlaybackValue get value => _value;

  @override
  VideoPlayerController? get fvpVideoController => null;

  @override
  int? get nativeViewId => _viewId;

  @override
  bool get supportsRuntimeTrackSwitch => true;

  @override
  bool get canHotSwapSource => _viewId != null && _initialized;

  int get _playerId => _viewId ?? -1;

  Future<dynamic> _invoke(String method, [Map<String, dynamic>? args]) {
    final payload = <String, dynamic>{
      'playerId': _playerId,
      if (args != null) ...args,
    };
    return _channel.invokeMethod<dynamic>(method, payload);
  }

  void _startEventListener() {
    _eventSub?.cancel();
    _eventSub = EventChannel('com.nascabos/playback_events/$_playerId')
        .receiveBroadcastStream()
        .listen(
      (event) {
        if (event is! Map) return;
        _applyNativeEvent(Map<Object?, Object?>.from(event));
      },
      onError: (_) {},
    );
  }

  void _applyNativeEvent(Map<Object?, Object?> event) {
    final err = event['error']?.toString();
    if (err != null && err.isNotEmpty) {
      _value = _value.copyWith(
        hasError: true,
        errorDescription: err,
        isPlaying: false,
      );
      notifyListeners();
      return;
    }

    final posMs = event['positionMs'];
    final durMs = event['durationMs'];
    final bufferedMs = event['bufferedPositionMs'];
    final playing = event['isPlaying'] == true;
    final initialized = event['isInitialized'] == true;

    final pos = posMs is int
        ? Duration(milliseconds: posMs)
        : _value.position;
    final dur = durMs is int
        ? Duration(milliseconds: durMs)
        : _value.duration;
    final bufferedEnd = bufferedMs is int
        ? Duration(milliseconds: bufferedMs)
        : Duration.zero;

    _value = _value.copyWith(
      isInitialized: initialized || _value.isInitialized,
      isPlaying: playing,
      hasError: false,
      errorDescription: null,
      position: pos.isNegative ? Duration.zero : pos,
      duration: dur,
      buffered: bufferedEnd > Duration.zero
          ? [DurationRange(Duration.zero, bufferedEnd)]
          : _value.buffered,
    );
    notifyListeners();
  }

  /// 在 PlatformView 创建前登记播放地址；[attachNativeView] 后真正初始化。
  void prepareSource({
    required Uri uri,
    VideoFormat? formatHint,
    Map<String, String> httpHeaders = const {},
    Duration startPosition = Duration.zero,
    String? externalSubtitleUrl,
    String? externalSubtitleSourcePath,
    String? externalSubtitleLabel,
  }) {
    _pendingUri = uri;
    _pendingFormatHint = formatHint;
    _httpHeaders = Map<String, String>.from(httpHeaders);
    _pendingStartPositionMs = startPosition.inMilliseconds.clamp(0, 1 << 31);
    _pendingExternalSubtitleUrl = externalSubtitleUrl?.trim().isNotEmpty == true
        ? externalSubtitleUrl!.trim()
        : null;
    _pendingExternalSubtitleSourcePath =
        externalSubtitleSourcePath?.trim().isNotEmpty == true
            ? externalSubtitleSourcePath!.trim()
            : null;
    _pendingExternalSubtitleLabel =
        externalSubtitleLabel?.trim().isNotEmpty == true
            ? externalSubtitleLabel!.trim()
            : null;
  }

  @override
  Future<void> initialize({
    required Uri uri,
    VideoFormat? formatHint,
  }) async {
    prepareSource(uri: uri, formatHint: formatHint);
    if (_viewId != null) {
      await _openOnNative();
    }
  }

  Future<void> _openOnNative() async {
    final uri = _pendingUri;
    if (uri == null || _viewId == null || _initialized) return;
    _startEventListener();
    await _invoke('create', {
      'url': uri.toString(),
      'startPositionMs': _pendingStartPositionMs,
      'formatHint': _pendingFormatHint?.name,
      if (_httpHeaders.isNotEmpty) 'headers': _httpHeaders,
      if (_pendingExternalSubtitleUrl != null)
        'externalSubtitleUrl': _pendingExternalSubtitleUrl,
      if (_pendingExternalSubtitleSourcePath != null)
        'externalSubtitleSourcePath': _pendingExternalSubtitleSourcePath,
      if (_pendingExternalSubtitleLabel != null)
        'externalSubtitleLabel': _pendingExternalSubtitleLabel,
    });
    _initialized = true;
    _value = _value.copyWith(isInitialized: true);
    notifyListeners();
  }

  @override
  Future<void> attachNativeView(int viewId) async {
    _viewId = viewId;
    await _openOnNative();
  }

  @override
  Future<void> switchSource({
    required Uri uri,
    VideoFormat? formatHint,
    Duration startPosition = Duration.zero,
  }) async {
    prepareSource(
      uri: uri,
      formatHint: formatHint,
      startPosition: startPosition,
    );
    if (_viewId == null) {
      return;
    }
    await _invoke('create', {
      'url': uri.toString(),
      'startPositionMs': startPosition.inMilliseconds.clamp(0, 1 << 31),
      'formatHint': formatHint?.name,
      if (_httpHeaders.isNotEmpty) 'headers': _httpHeaders,
    });
    _value = _value.copyWith(
      isInitialized: true,
      hasError: false,
      errorDescription: null,
    );
    notifyListeners();
  }

  @override
  Future<void> disposeEngine() async {
    await _eventSub?.cancel();
    _eventSub = null;
    if (_viewId != null) {
      try {
        await _invoke('dispose');
      } catch (_) {}
    }
    _viewId = null;
    _initialized = false;
    _pendingUri = null;
    _pendingFormatHint = null;
    _value = const PlaybackValue();
  }

  @override
  Future<void> play() async {
    await _invoke('play');
  }

  @override
  Future<void> pause() async {
    await _invoke('pause');
  }

  @override
  Future<void> seekTo(Duration position) async {
    await _invoke('seekTo', {'positionMs': position.inMilliseconds});
  }

  @override
  Future<void> setVolume(double volume) async {
    await _invoke('setVolume', {'volume': volume});
    _value = _value.copyWith(volume: volume);
    notifyListeners();
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _invoke('setPlaybackSpeed', {'speed': speed});
    _value = _value.copyWith(playbackSpeed: speed);
    notifyListeners();
  }

  @override
  Future<void> setLooping(bool looping) async {
    await _invoke('setLooping', {'looping': looping});
    _value = _value.copyWith(isLooping: looping);
    notifyListeners();
  }

  @override
  Future<void> setAudioTracks(List<int> trackIndices) async {
    await _invoke('setAudioTracks', {'indices': trackIndices});
  }

  @override
  Future<void> setSubtitleTracks(List<int> trackIndices) async {
    await _invoke('setSubtitleTracks', {'indices': trackIndices});
  }

  @override
  Future<void> setExternalSubtitle(
    String url, {
    String? label,
    String? sourcePath,
  }) async {
    await _invoke('setExternalSubtitle', {
      'url': url,
      if (label != null) 'label': label,
      if (sourcePath != null) 'sourcePath': sourcePath,
    });
  }
}
