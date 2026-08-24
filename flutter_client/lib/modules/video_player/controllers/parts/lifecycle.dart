part of '../video_player_controller.dart';

class _PlayerFullScreenRelay with FullScreenListener {
  final void Function(bool enabled, SystemUiMode? systemUiMode) onChanged;

  _PlayerFullScreenRelay({required this.onChanged});

  @override
  void onFullScreenChanged(bool enabled, SystemUiMode? systemUiMode) {
    onChanged(enabled, systemUiMode);
  }
}

extension PlayerLifecycle on PlayerController {
  static final Map<int, Future<void>> _activeDisposals = {};
  static Future<void> _globalDisposeQueue = Future<void>.value();

  static Future<void> _awaitGlobalDisposeQueueIfAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _globalDisposeQueue.timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// 切换画质/片源前：取消进行中的 FVP 创建、安全释放内核并清理叠层字幕状态。
  Future<void> _teardownPlaybackEngineForReinit() async {
    _webSubtitleLoading = false;
    _webClearSubtitle();

    final initKey = _pendingInitKey;
    if (initKey != null && initKey.isNotEmpty) {
      cancelVideoControllerInit(initKey);
      _pendingInitKey = null;
    }

    final engine = playbackEngine.value;
    if (engine == null) return;
    try {
      engine.removeListener(_videoListener);
    } catch (_) {}
    if (!kIsWeb) {
      await _disposePlaybackEngineSafely(engine);
    } else {
      disposePlaybackEngine(engine);
      try {
        await engine.disposeEngine();
      } catch (_) {}
    }
    playbackEngine.value = null;
    isInitialized.value = false;
    isPlaying.value = false;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _disposePlaybackEngineSafely(PlaybackEngine engine) async {
    final key = identityHashCode(engine);
    final existing = _activeDisposals[key];
    if (existing != null) return existing;

    final fut = () async {
      // 关闭阶段最怕的是「pause 还在 PAUSING → dispose 导致 native flush/close」
      // 策略：
      // - 给 pause 更长时间完成
      // - pause 超时则延后 dispose（不要立刻 dispose）
      bool paused = false;
      try {
        await engine.pause().timeout(const Duration(seconds: 3));
        paused = true;
      } catch (_) {
        paused = false;
      }

      if (!paused) {
        try {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        } catch (_) {}
        try {
          await engine.pause().timeout(const Duration(seconds: 2));
        } catch (_) {}
      } else {
        try {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        } catch (_) {}
      }

      try {
        disposePlaybackEngine(engine);
        await engine.disposeEngine().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }();

    _activeDisposals[key] = fut;
    // Android 上底层 mdk/AAudio 全局状态更敏感：把 dispose 串行化，避免快速进出时多路并发释放/初始化
    _globalDisposeQueue = _globalDisposeQueue.then((_) => fut);
    try {
      await fut;
    } finally {
      _activeDisposals.remove(key);
    }
  }

  void _onControllerInit() {
    if (Get.isRegistered<MusicPlayServiceController>()) {
      final music = Get.find<MusicPlayServiceController>();
      if (music.isReady.value && music.isPlaying.value) {
        unawaited(music.stop());
      }
    }
    registerFvp();

    FullScreen.addListener(_fullScreenRelay);

    if (DeviceUtils.isDesktop) {
      windowManager.addListener(this);
      _initWindow();
    }

    WakelockPlus.enable();
    unawaited(loadLoopMode());
    unawaited(loadPlaybackEnginePreference());
    _autoSkipWorker = ever<Duration>(position, _handleAutoSkipPositionChanged);

    // 播放列表与首次初始化必须由页面在 Get.put 之后调用 openPlaylist 完成。
    // 若在此处根据全局 Get.arguments 再触发 _initializePlayer，会与 initState 里的
    // openPlaylist 形成两次并发初始化，_initGeneration 互相打断，表现为偶发「初始化后立刻清理」。
  }

  void _onControllerClose() {
    print(
      "----------------------------------关闭播放器----------------------------------",
    );
    if (_isClosingPlayer) return;
    _isClosingPlayer = true;
    _initGeneration += 1;
    isInitialized.value = false;
    isPlaying.value = false;
    final initKey = _pendingInitKey;
    if (initKey != null && initKey.isNotEmpty) {
      cancelVideoControllerInit(initKey);
      _pendingInitKey = null;
    }
    saveProgress();
    stopAutoSave();
    _stopPositionPolling();
    _singleLoopCooldownTimer?.cancel();
    _singleLoopCooldownTimer = null;
    _singleLoopCooldown = false;
    _autoSkipWorker?.dispose();
    _autoSkipWorker = null;
    cancelResumeTip();
    if (isCtrlSpeedBoost.value) setCtrlSpeedBoost(false);
    _stopTranscoding();
    cancelVideoP2pFetches();
    if (!kIsWeb) {
      VideoRangeCacheManager.instance.clear();
    }
    if (DeviceUtils.isWeb) {
      stopWebVideoElementNetworking();
    }
    _transcodeSeekTimer?.cancel();
    restoreOrientation();
    exitFullscreen();

    final engine = playbackEngine.value;
    if (engine != null) {
      try {
        engine.removeListener(_videoListener);
      } catch (_) {}
      try {
        unawaited(_disposePlaybackEngineSafely(engine));
      } catch (_) {}
      playbackEngine.value = null;
    }

    if (DeviceUtils.isDesktop) {
      windowManager.removeListener(this);
    }

    FullScreen.removeListener(_fullScreenRelay);
    WakelockPlus.disable();
    unawaited(_deactivateMacosAudioOutput());
  }
}
