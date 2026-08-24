part of '../video_player_controller.dart';

extension PlayerListener on PlayerController {
  /// 视频监听
  void _videoListener() {
    final engine = playbackEngine.value;
    if (engine == null || !engine.value.isInitialized) {
      return;
    }

    if (isClosed) return;
    if (_isClosingPlayer) return;

    final pv = engine.value;
    if (pv.hasError) {
      unawaited(_handlePlaybackFailure(pv.errorDescription ?? 'unknown'));
      return;
    }

    isPlaying.value = pv.isPlaying;

    if (currentQuality.value == 'original') {
      var pos = pv.position;
      if (pos.isNegative) pos = Duration.zero;
      position.value = pos;
      if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
        duration.value = Duration(seconds: _sourceDurationSeconds!);
      } else {
        duration.value = pv.duration;
      }
    } else {
      final pendingSeekSeconds = _pendingTranscodeSeekSeconds;
      if (pendingSeekSeconds != null) {
        position.value = Duration(seconds: pendingSeekSeconds);
        if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
          duration.value = Duration(seconds: _sourceDurationSeconds!);
        }
        return;
      }
      // 转码重载期间保持 UI 进度，避免进度条圆点闪回起点。
      if (!isInitialized.value) {
        return;
      }
      var pos = pv.position;
      if (pos.isNegative) pos = Duration.zero;
      position.value = _transcodeTimelinePosition(pos);
      if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
        duration.value = Duration(seconds: _sourceDurationSeconds!);
      }
    }

    if (pv.buffered.isNotEmpty) {
      final end = pv.buffered.last.end;
      if (currentQuality.value == 'original') {
        buffered.value = end;
      } else {
        buffered.value = _transcodeTimelinePosition(end);
      }
    }

    _webUpdateActiveCue();

    final dur = duration.value;
    final pos2 = position.value;
    if (dur > Duration.zero &&
        pos2 >= dur - const Duration(seconds: 1) &&
        !pv.isPlaying) {
      if (_singleLoopCooldown) return;
      _handlePlaybackComplete();
    }
  }

  void _handlePlaybackComplete() {
    if (isClosed) return;
    if (_isClosingPlayer) return;
    final mode = loopMode.value;
    if (mode == 'single') {
      _singleLoopCooldownTimer?.cancel();
      _singleLoopCooldown = true;
      _singleLoopCooldownTimer = Timer(const Duration(milliseconds: 1500), () {
        _singleLoopCooldown = false;
        _singleLoopCooldownTimer = null;
      });
      seekTo(Duration.zero);
      unawaited(() async {
        await _ensureMacosAudioOutputActive();
        await playbackEngine.value?.play();
      }());
      return;
    }

    if (mode == 'shuffle') {
      if (playlist.length <= 1) return;
      final next = _pickShuffleIndex();
      playAt(next);
      return;
    }

    if (mode == 'all') {
      if (playlist.isEmpty) return;
      if (currentIndex.value >= playlist.length - 1) {
        playAt(0);
        return;
      }
      playNext();
      return;
    }

    playNext();
  }

  int _pickShuffleIndex() {
    final len = playlist.length;
    if (len <= 1) return currentIndex.value;
    final r = Random();
    var next = r.nextInt(len);
    if (next == currentIndex.value) {
      next = (next + 1) % len;
    }
    return next;
  }

  Future<void> _handlePlaybackFailure(Object _) async {
    if (isClosed) return;
    // 播放器正在关闭时禁止重试，防止生成新 play_id 并向服务端发起新的转码请求
    if (_isClosingPlayer) return;
    if (_isRecoveringFromError) return;

    final isAndroidMedia3Original =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        playbackEngineType.value == PlaybackEngineType.media3 &&
        currentQuality.value == 'original';

    // Android 原画：原生层已先硬解再 FFmpeg 软解，上报错误时勿再用 openUrl 重置为硬解重试。
    if (isAndroidMedia3Original) {
      if (!_autoSwitchedToTranscode) {
        _autoSwitchedToTranscode = true;
        _isRecoveringFromError = true;
        isInitialized.value = false;
        _reloadRetryCount = 0;
        currentQuality.value = defaultTranscodeQuality;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (isClosed) return;
        _isRecoveringFromError = false;
        await _initializePlayer(keepPosition: true);
        return;
      }
    } else {
      final canRetry = _reloadRetryCount < maxReloadRetries;
      if (canRetry) {
        _isRecoveringFromError = true;
        isInitialized.value = false; // Show loading immediately
        _reloadRetryCount++;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (isClosed) return;
        _isRecoveringFromError = false;
        await _initializePlayer(keepPosition: true);
        return;
      }
    }

    if (_isPlaybackErrorDialogOpen) return;
    _isPlaybackErrorDialogOpen = true;

    final isOriginal = currentQuality.value == 'original';
    if (isOriginal) {
      final choice = await DialogUtil.showConfirmThreeButtonsDialog(
        title: 'player_playback_error'.tr,
        content: 'player_if_retry'.tr,
        cancelText: 'cancel'.tr,
        option1Text: 'player_test_transcode'.tr,
        option2Text: 'retry'.tr,
        option2IsPrimary: true,
      );
      _isPlaybackErrorDialogOpen = false;

      if (choice == 0) {
        _reloadRetryCount = 0;
        currentQuality.value = defaultTranscodeQuality;
        await _initializePlayer(keepPosition: true);
      } else if (choice == 1) {
        _reloadRetryCount = 0;
        await _initializePlayer(keepPosition: true);
      }
      return;
    }

    final ok = await DialogUtil.showConfirmDialog(
      title: 'player_playback_error'.tr,
      content: 'player_if_retry'.tr,
      cancelText: 'cancel'.tr,
      confirmText: 'retry'.tr,
    );
    _isPlaybackErrorDialogOpen = false;
    if (ok == true) {
      _reloadRetryCount = 0;
      await _initializePlayer(keepPosition: true);
    }
  }
}
