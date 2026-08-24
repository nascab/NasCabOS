part of '../video_player_controller.dart';

extension PlayerControls on PlayerController {
  /// 播放/暂停
  Future<void> togglePlay() async {
    if (playbackEngine.value == null || !isInitialized.value) {
      resetControlsTimer();
      return;
    }

    if (isPlaying.value) {
      await pausePlayback();
    } else {
      await _ensureMacosAudioOutputActive();
      await playbackEngine.value!.play();
    }
    resetControlsTimer();
  }

  /// 上一个
  void playPrev() {
    if (currentIndex.value > 0) {
      currentIndex.value--;
      _initializePlayer();
    }
  }

  /// 下一个
  void playNext() {
    if (currentIndex.value < playlist.length - 1) {
      currentIndex.value++;
      _initializePlayer();
    }
  }

  void playAt(int index) {
    if (index < 0 || index >= playlist.length) return;
    if (currentIndex.value == index) return;
    currentIndex.value = index;
    _initializePlayer(keepPosition: false);
  }

  /// 快退
  void rewind({int seconds = 10}) {
    if (playbackEngine.value == null) return;
    final newPos = position.value - Duration(seconds: seconds);
    seekTo(newPos < Duration.zero ? Duration.zero : newPos);
  }

  /// 快进
  void fastForward({int seconds = 30}) {
    if (playbackEngine.value == null) return;
    final newPos = position.value + Duration(seconds: seconds);
    seekTo(newPos > duration.value ? duration.value : newPos);
  }

  /// 跳转
  void seekTo(Duration pos) {
    final clamped = pos < Duration.zero
        ? Duration.zero
        : pos > duration.value
        ? duration.value
        : pos;

    if (currentQuality.value != 'original') {
      _pendingTranscodeSeekSeconds = clamped.inSeconds;
      position.value = clamped;
      _transcodeSeekTimer?.cancel();
      _transcodeSeekTimer = Timer(const Duration(milliseconds: 300), () {
        if (isClosed) return;
        _initializePlayer(keepPosition: true);
      });
      resetControlsTimer();
      return;
    }

    playbackEngine.value?.seekTo(clamped);
    resetControlsTimer();
  }

  /// 设置速度
  void setSpeed(double speed) {
    playbackEngine.value?.setPlaybackSpeed(speed);
    playbackSpeed.value = speed;
  }

  /// 按住 Ctrl 时加速 2x，松开恢复
  void setCtrlSpeedBoost(bool held) {
    if (held) {
      if (!isCtrlSpeedBoost.value) {
        _speedBeforeCtrlBoost = playbackSpeed.value;
        setSpeed(2.0);
        isCtrlSpeedBoost.value = true;
      }
    } else {
      if (isCtrlSpeedBoost.value) {
        setSpeed(_speedBeforeCtrlBoost);
        isCtrlSpeedBoost.value = false;
      }
    }
  }

  /// 设置音量
  void setVolume(double vol) {
    playbackEngine.value?.setVolume(vol);
    volume.value = vol;
  }

  /// 增加音量
  void increaseVolume() {
    double newVol = volume.value + 0.1;
    if (newVol > 1.0) newVol = 1.0;
    setVolume(newVol);
  }

  /// 减少音量
  void decreaseVolume() {
    double newVol = volume.value - 0.1;
    if (newVol < 0.0) newVol = 0.0;
    setVolume(newVol);
  }

  Future<void> setLoopMode(String mode) async {
    final nextMode = mode;
    loopMode.value = nextMode;
    final nextLooping = nextMode == 'single';
    isLooping.value = nextLooping;
    final engine = playbackEngine.value;
    if (engine != null && engine.value.isInitialized) {
      await engine.setLooping(nextLooping);
    }
    await _saveLoopMode(nextMode);
  }

  Future<void> _saveLoopMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('video_player_loop_mode', mode);
    } catch (_) {}
  }

  Future<void> loadLoopMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('video_player_loop_mode');
      if (v == null || v.isEmpty) {
        loopMode.value = 'sequence';
        isLooping.value = false;
        return;
      }
      loopMode.value = v;
      isLooping.value = v == 'single';
    } catch (_) {
      loopMode.value = 'sequence';
      isLooping.value = false;
    }
  }

  /// 切换画质
  void changeQuality(String quality) {
    if (currentQuality.value == quality) return;
    final wasTranscode = currentQuality.value != 'original';
    final willBeOriginal = quality == 'original';
    // 须在修改 currentQuality 之前采样；Media3 以 UI 时间轴为准（HLS 引擎位可能与 base 叠加方式不同）。
    final switchPosition =
        playbackEngineType.value == PlaybackEngineType.media3
        ? position.value
        : _absolutePlaybackPosition();
    // Media3 可在 HLS 转码与 rawFile 原画间热换源；FVP 仍需完整重建。
    _disallowEngineHotSwap =
        playbackEngineType.value != PlaybackEngineType.media3 &&
        (currentQuality.value == 'original') != (quality == 'original');
    _deferOriginalTracksUntilPlaying = wasTranscode && willBeOriginal;
    currentQuality.value = quality;
    position.value = switchPosition;
    // keepPosition=true 时 _initializePlayer 不会拉 stream info，需在此补跑 Web 端规则
    //（否则 Safari+HEVC 手动切「原画」会跳过自动转码，仅原生探测后报错；与首次打开行为不一致）
    if (kIsWeb) {
      checkWebIfNeedTranscode();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      checkAndroidIfNeedTranscode();
      applyAndroidFvpEngineIfNeeded();
    }
    _initializePlayer(keepPosition: true, switchPosition: switchPosition);
  }
}
