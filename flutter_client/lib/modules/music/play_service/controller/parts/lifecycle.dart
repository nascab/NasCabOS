part of '../music_play_service_controller.dart';

extension MusicPlayServiceLifecycle on MusicPlayServiceController {
  bool get _supportBackground =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _initService() async {
    final existing = _serviceInitFuture;
    if (existing != null) {
      try {
        await existing;
      } catch (_) {
        // Previous init attempt failed (e.g. MediaBrowserCompat connection
        // failure on some devices). Clear the cached future so the next call
        // can retry with a fresh native connection attempt.
        _serviceInitFuture = null;
        await _initService();
      }
      return;
    }
    final future = () async {
      registerFvp();
      if (_supportBackground) {
        _handler = await AudioService.init(
          builder: () => _MusicAudioHandler(this),
          config: AudioServiceConfig(
            androidNotificationChannelId: 'nascab.music.playback',
            androidNotificationChannelName: 'Music Playback',
            androidNotificationChannelDescription:
                'Background music playback controls',
            androidStopForegroundOnPause: false,
            androidShowNotificationBadge: false,
            androidNotificationClickStartsActivity: true,
            androidResumeOnClick: true,
          ),
        );
      }
      // Android：配置 AudioSession，告知系统这是音乐播放器
      // 正确的 audio attributes 使得 OPPO/华为等控制中心能识别并关联本 app，
      // 同时让 Android 正确路由媒体按键事件到本 app
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _configureAndroidAudioSession();
      }
      await _loadAndApplyVolume();
      _bindStreams();
      isReady.value = true;
    }();
    _serviceInitFuture = future;
    try {
      await future;
    } catch (_) {
      _serviceInitFuture = null;
      rethrow;
    }
  }

  Future<void> _configureAndroidAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
            flags: AndroidAudioFlags.none,
          ),
          // gain（永久焦点）适合音乐播放器；系统会把媒体按键路由给持有 gain 焦点的 app
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ),
      );
      _subscribeAudioSessionEvents(session);
    } catch (_) {}
  }

  void _subscribeAudioSessionEvents(AudioSession session) {
    // 来电/其他 app 抢占焦点时自动暂停，焦点归还后恢复播放
    _audioSessionSubs.add(
      session.interruptionEventStream.listen((event) {
        if (isClosed) return;
        if (event.begin) {
          if (isPlaying.value) {
            // 记录中断前想要播放，暂停但不修改 _desiredPlaying
            unawaited(_player?.pause());
            _syncHandlerPlaybackState();
          }
        } else {
          if (event.type != AudioInterruptionType.unknown && _desiredPlaying) {
            unawaited(play());
          }
        }
      }),
    );
    // 耳机拔出时暂停（Becoming Noisy）
    _audioSessionSubs.add(
      session.becomingNoisyEventStream.listen((_) {
        if (isClosed) return;
        if (isPlaying.value) {
          unawaited(pause());
        }
      }),
    );
  }

  void _loadDiscStyleIndex() {
    try {
      final stored = CacheManager().getInt(CacheKeys.musicDiscStyleIndex);
      if (stored == null) return;
      final max = MusicPlayServiceController.discAssets.length - 1;
      discStyleIndex.value = stored.clamp(0, max);
    } catch (_) {}
  }

  void _loadLoopMode() {
    try {
      final stored = CacheManager().getInt(CacheKeys.musicLoopModeIndex);
      if (stored == null) return;
      if (stored < 0 || stored >= MusicLoopMode.values.length) return;
      loopMode.value = MusicLoopMode.values[stored];
    } catch (_) {}
  }

  Future<void> _loadAndApplyVolume() async {
    try {
      final stored = CacheManager().getDouble(CacheKeys.musicVolume);
      final storedBeforeMute = CacheManager().getDouble(
        CacheKeys.musicVolumeBeforeMute,
      );
      if (storedBeforeMute != null) {
        _volumeBeforeMute = storedBeforeMute.clamp(0.0, 1.0);
      }
      if (stored == null) return;
      final v = stored.clamp(0.0, 1.0);
      volume.value = v;
      final p = _player;
      if (p != null) {
        await p.setVolume(v);
      }
      if (v > 0.01) {
        _volumeBeforeMute = v;
      }
    } catch (_) {}
  }

  void _bindStreams() {
    _startPositionPolling();
  }

  void _startPositionPolling() {
    _stopPositionPolling();
    _positionPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (isClosed) return;
      _syncFromPlayer();
    });
  }

  void _stopPositionPolling() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
  }

  void _syncFromPlayer() {
    final p = _player;
    if (p == null) {
      if (isPlaying.value) isPlaying.value = false;
      _syncHandlerPlaybackState();
      return;
    }

    if (p.hasError) {
      unawaited(_attemptRecovery(reason: 'player_error'));
      return;
    }

    final d = p.duration;
    final prevDuration = duration.value;
    if (prevDuration != d) {
      duration.value = d;
      if (d > Duration.zero) {
        _syncMediaItem(currentIndex.value, forceUpdate: true);
        // 延迟再次同步：audio_service 异步加载封面时可能用旧 MediaItem 覆盖，导致控制中心/锁屏丢失 duration
        if (prevDuration <= Duration.zero) {
          Future.delayed(const Duration(milliseconds: 1800), () {
            if (isClosed) return;
            if (duration.value > Duration.zero &&
                currentIndex.value >= 0 &&
                currentIndex.value < playlist.length) {
              _syncMediaItem(currentIndex.value, forceUpdate: true);
            }
          });
        }
      }
      unawaited(_maybeAutoSetLyricForCurrent());
    }

    final pos = p.position.isNegative ? Duration.zero : p.position;
    position.value = pos;

    buffered.value = p.buffered;

    final playing = p.isPlaying;

    bool completed = false;

    if (_useJustAudio) {
      if (p.isCompleted) {
        completed = true;
      } else if (d > Duration.zero) {
        final posMs = pos.inMilliseconds;
        final dMs = d.inMilliseconds;
        // 仅当用户本意是播放（_desiredPlaying）但播放器停了才视为完成
        // 若用户主动暂停（_desiredPlaying=false）则不视为完成，避免接近末尾暂停时误切下一曲
        if (posMs >= dMs - 500 &&
            !playing &&
            !p.isBuffering &&
            _desiredPlaying) {
          completed = true;
        }
      }
    } else {
      completed = d > Duration.zero && !playing && !p.isBuffering && pos >= d;
    }

    if (completed && !_isCompleted) {
      final until = _suppressCompletedUntil;
      final suppress =
          _isSkippingTrack || (until != null && DateTime.now().isBefore(until));
      if (suppress) {
        isPlaying.value = false;
        _syncHandlerPlaybackState();
        return;
      }
      _isCompleted = true;
      isPlaying.value = false;
      _syncHandlerPlaybackState();
      unawaited(_handleTrackCompleted());
      return;
    }
    if (!completed) {
      _isCompleted = false;
      _suppressCompletedUntil = null;
    }

    isPlaying.value = playing;
    _scheduleStallRecoveryIfNeeded(isBuffering: p.isBuffering);
    _syncHandlerPlaybackState();
    _notifyProgress();
  }

  Future<void> _ensureNotificationPermission() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final status = await Permission.notification.status;
    if (status.isGranted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _pendingNotificationPermissionGuide = true;
      return;
    }
    if (status.isPermanentlyDenied) {
      DialogUtil.showConfirmDialog(
        title: 'permission_notification_title'.tr,
        content: 'permission_notification_content'.tr,
        confirmText: 'open_settings'.tr,
        cancelText: 'cancel'.tr,
        onConfirm: () => openAppSettings(),
      );
      return;
    }
    final result = await Permission.notification.request();
    if (result.isGranted) return;
    DialogUtil.showConfirmDialog(
      title: 'permission_notification_title'.tr,
      content: 'permission_notification_content'.tr,
      confirmText: 'open_settings'.tr,
      cancelText: 'cancel'.tr,
      onConfirm: () => openAppSettings(),
    );
  }
}
