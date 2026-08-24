part of '../video_player_controller.dart';

extension PlayerPlayback on PlayerController {
  bool _isBitmapSubtitleCodecName(String? codecName) {
    final v = (codecName ?? '').toLowerCase().trim();
    return v == 'pgssub' ||
        v == 'hdmv_pgs_subtitle' ||
        v == 'vobsub' ||
        v == 'dvd_subtitle' ||
        v == 'dvdsub' ||
        v == 'dvb_subtitle' ||
        v == 'xsub';
  }

  bool _isBitmapExternalSubtitleExtension(String ext) {
    final v = ext.toLowerCase().trim();
    return v == '.sup' || v == '.sub' || v == '.idx';
  }

  bool _subtitleLabelNeedsTranscodeBurn(String label) {
    if (label.isEmpty || isNoSubtitle(label)) return false;
    final track = _rawSubtitleTracks.firstWhere(
      (e) => e['label'] == label,
      orElse: () => <String, dynamic>{},
    );
    if (track.isEmpty) return false;
    if (track['isExternal'] == true) {
      final subPath = track['path']?.toString() ?? '';
      final dot = subPath.lastIndexOf('.');
      final subExt = dot >= 0 ? subPath.substring(dot) : '';
      return _isBitmapExternalSubtitleExtension(subExt);
    }
    return _isBitmapSubtitleCodecName(track['codec_name']?.toString());
  }

  /// 转码中切换字幕：文本/外挂仅刷新 VTT 叠层；位图烧录或从烧录切走时才重启转码。
  Future<void> applySubtitleTrackWhileTranscoding({
    required String trackLabel,
    required String prevLabel,
  }) async {
    final prevWasBitmapBurn = _subtitleLabelNeedsTranscodeBurn(prevLabel);
    final nextNeedsBitmapBurn = _subtitleLabelNeedsTranscodeBurn(trackLabel);

    currentSubtitleTrack.value = trackLabel;
    savePreference();

    if (prevWasBitmapBurn && !nextNeedsBitmapBurn) {
      await _initializePlayer(keepPosition: true);
      await loadWebSubtitleIfNeeded(force: true);
      return;
    }

    if (!currentIsNoSubtitle && nextNeedsBitmapBurn) {
      if (kIsWeb && currentQuality.value == 'original') {
        currentQuality.value = defaultTranscodeQuality;
        _playId ??= const Uuid().v4();
      }
      await _initializePlayer(keepPosition: true);
      return;
    }

    if (currentIsNoSubtitle) {
      _webClearSubtitle();
      return;
    }

    await loadWebSubtitleIfNeeded(force: true);
  }

  /// 文本字幕（含外挂）走 subtitle-vtt + WebSubtitleOverlay；位图仍走原生/转码烧录。
  Future<void> _applyClientSubtitleOverlayIfNeeded({
    required PlaybackEngine engine,
  }) async {
    if (!_useClientSubtitleOverlay()) {
      _webClearSubtitle();
      return;
    }
    if (currentIsNoSubtitle) {
      _webClearSubtitle();
      return;
    }

    final label = currentSubtitleTrack.value;
    if (label.isEmpty) {
      _webClearSubtitle();
      return;
    }
    final track = _rawSubtitleTracks.firstWhere(
      (e) => e['label'] == label,
      orElse: () => <String, dynamic>{},
    );
    if (track.isEmpty) {
      _webClearSubtitle();
      return;
    }
    if (track['isExternal'] == true) {
      final ext = path.extension(track['path']?.toString() ?? '');
      if (_isBitmapExternalSubtitleExtension(ext)) {
        _webClearSubtitle();
        return;
      }
    } else if (currentQuality.value == 'original') {
      _webClearSubtitle();
      return;
    } else {
      final codec = track['codec_name']?.toString();
      if (_isBitmapSubtitleCodecName(codec)) {
        _webClearSubtitle();
        return;
      }
    }

    try {
      await engine.setSubtitleTracks([]);
    } catch (_) {}
    await loadWebSubtitleIfNeeded(force: true);
  }

  Future<void> pausePlayback() async {
    final engine = playbackEngine.value;
    if (engine == null) return;
    try {
      await engine.pause();
    } catch (_) {}
  }

  Future<void> _ensureMacosAudioOutputActive() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await PlayerController._macosAudioOutputChannel.invokeMethod(
        'activatePlayback',
      );
    } catch (_) {}
  }

  Future<void> _deactivateMacosAudioOutput() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await PlayerController._macosAudioOutputChannel.invokeMethod(
        'deactivatePlayback',
      );
    } catch (_) {}
  }

  /// 音轨就绪后重启 mdk 音频，配合常驻 Core Audio 输出唤醒休眠蓝牙。
  Future<void> _kickMacosPlaybackOutput(PlaybackEngine engine) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    await _ensureMacosAudioOutputActive();
    try {
      await engine.pause();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _ensureMacosAudioOutputActive();
    try {
      await engine.play();
    } catch (_) {}
  }

  Future<void> _applyOriginalTracksAfterPlay({
    required PlaybackEngine engine,
    required int initGeneration,
  }) async {
    if (currentQuality.value == 'original' && !kIsWeb) {
      if (_deferOriginalTracksUntilPlaying) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!isClosed &&
          !_isClosingPlayer &&
          initGeneration == _initGeneration &&
          identical(playbackEngine.value, engine)) {
        await setAudioTrack(currentAudioTrack.value, force: true);
        await setSubtitleTrack(currentSubtitleTrack.value, force: true);
      }
      _deferOriginalTracksUntilPlaying = false;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    if (isClosed ||
        _isClosingPlayer ||
        initGeneration != _initGeneration ||
        !identical(playbackEngine.value, engine)) {
      return;
    }
    await _kickMacosPlaybackOutput(engine);
  }

  bool _isHttpUrl(String v) {
    final s = v.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  bool _canMedia3HotSwap(bool keepPosition) {
    if (_disallowEngineHotSwap) return false;
    if (kIsWeb || playbackEngineType.value != PlaybackEngineType.media3) {
      return false;
    }
    if (!keepPosition) return false;
    final engine = playbackEngine.value;
    return engine != null && engine.canHotSwapSource;
  }

  /// 转码时间轴上的绝对进度。
  /// FVP 多为「base + 相对偏移」；Media3 HLS 常在 seek 后直接报告时间轴绝对位置，不可再加 base。
  Duration _transcodeTimelinePosition(Duration enginePosition) {
    var rel = enginePosition;
    if (rel.isNegative) rel = Duration.zero;
    final baseSec = _transcodeBaseSeconds;
    if (baseSec <= 0) return rel;
    if (rel.inSeconds >= baseSec) return rel;
    return Duration(seconds: baseSec) + rel;
  }

  /// 当前绝对播放进度（用于画质切换采样）。
  Duration _absolutePlaybackPosition() {
    final engine = playbackEngine.value;
    if (currentQuality.value != 'original') {
      if (engine != null && engine.value.isInitialized) {
        return _transcodeTimelinePosition(engine.value.position);
      }
      return position.value;
    }
    if (engine != null && engine.value.isInitialized) {
      var pos = engine.value.position;
      if (!pos.isNegative && pos > Duration.zero) return pos;
    }
    return position.value;
  }

  Future<void> _initializePlayer({
    bool keepPosition = false,
    Duration? switchPosition,
  }) async {
    print(
      "----------------------------------初始化播放器----------------------------------",
    );
    final media3HotSwap = _canMedia3HotSwap(keepPosition);
    if (!media3HotSwap) {
      await PlayerLifecycle._awaitGlobalDisposeQueueIfAndroid();
    }
    final initGeneration = ++_initGeneration;
    if (!kIsWeb && !media3HotSwap) {
      VideoRangeCacheManager.instance.clear();
    }
    _transcodeSeekTimer?.cancel();
    _stopPositionPolling();
    if (!media3HotSwap) {
      isInitialized.value = false;
    }
    isPlaying.value = false;
    final lastPosition = switchPosition ?? position.value;
    final originalSeekAfterInit =
        currentQuality.value == 'original' && keepPosition
        ? lastPosition
        : null;

    if (keepPosition) {
      _pendingResumePosition = null;
      _resumeSeekBakedIntoUrlSeconds = null;
    }

    // 先摘监听，避免停旧转码会话时 base/pending 被清空后仍收到 position=0 的事件。
    try {
      playbackEngine.value?.removeListener(_videoListener);
    } catch (_) {}

    if (currentQuality.value != 'original' && keepPosition) {
      position.value = lastPosition;
    }

    final prevPlayId = _playId;
    if (prevPlayId != null) {
      _stopTranscoding(playId: prevPlayId);
    }
    _playId = null;

    if (!media3HotSwap && playbackEngine.value != null) {
      await _teardownPlaybackEngineForReinit();
    }
    _media3SurfaceReady = null;
    _media3WaitInitGeneration = null;

    if (playlist.isEmpty || currentIndex.value >= playlist.length) {
      isUrlSource.value = false;
      return;
    }

    var fileInfo = playlist[currentIndex.value];
    var path = fileInfo['path']?.toString() ?? '';
    var isUrl = _isHttpUrl(path);
    isUrlSource.value = isUrl;

    if (!keepPosition) {
      _pendingPreference = null;
      _pendingResumePosition = null;
      _reloadRetryCount = 0;
      _isRecoveringFromError = false;
      _isPlaybackErrorDialogOpen = false;
      _autoSwitchedToTranscode = false;
      _resumeSeekBakedIntoUrlSeconds = null;
      _resetAutoSkipState(clearSegments: true);
    }

    if (isUrl && currentQuality.value != 'original') {
      currentQuality.value = 'original';
    }

    if (currentQuality.value != 'original') {
      _playId = const Uuid().v4();
    }

    if (!keepPosition && !isUrl) {
      await _fetchStreamInfo(fileInfo);
      if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
        return;
      }
      if (playlist.isEmpty || currentIndex.value >= playlist.length) return;
      fileInfo = playlist[currentIndex.value];
      path = fileInfo['path']?.toString() ?? '';
      isUrl = _isHttpUrl(path);
      isUrlSource.value = isUrl;
      const p2pRelayLargeFileBytes = 3 * 1024 * 1024 * 1024;
      if (currentQuality.value == 'original' &&
          ApiController.instance.isP2pRelayMode &&
          (_sourceFileSizeBytes ?? 0) > p2pRelayLargeFileBytes) {
        currentQuality.value = defaultTranscodeQuality;
      }
    } else if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !isUrl &&
        currentQuality.value == 'original') {
      applyAndroidFvpEngineIfNeeded();
    }

    final apiController = ApiController.instance;

    if (currentQuality.value != 'original') {
      _playId ??= const Uuid().v4();
    }

    final videoUrl = currentQuality.value == 'original'
        ? _buildOriginalVideoUrl(
            apiController,
            fileInfo,
            keepPosition,
            lastPosition,
          )
        : _buildTranscodeVideoUrl(
            apiController,
            fileInfo,
            keepPosition,
            lastPosition,
          );

    if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
      duration.value = Duration(seconds: _sourceDurationSeconds!);
    }

    // Range 内存缓存仅 FVP 原画 rawFile 使用；Media3 直连或 P2P 透传代理。
    if (!kIsWeb &&
        currentQuality.value == 'original' &&
        !isUrl &&
        playbackEngineType.value != PlaybackEngineType.media3) {
      final p = path.trim();
      final dot = p.lastIndexOf('.');
      final mediaExt = (dot >= 0 && dot < p.length - 1)
          ? p.substring(dot).toLowerCase()
          : '';
      final allowRangeCache = mediaExt == '.mp4' || mediaExt == '.mov';
      if (!allowRangeCache) {
        VideoRangeCacheManager.instance.clear();
      } else {
      final parsed = Uri.tryParse(videoUrl);
      if (parsed != null) {
        VideoRangeCacheManager.instance.resetSession(
          buildVideoRangeSessionKey(parsed, apiController.baseUrl),
          fileSizeBytes: _sourceFileSizeBytes,
          mediaPath: path,
        );
      }
      }
    }

    if (DeviceUtils.isDesktop) {
      if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
        return;
      }
    }

    if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
      _playId = null;
      return;
    }

    if (media3HotSwap) {
      try {
        await _initializePlayerMedia3HotSwap(
          initGeneration: initGeneration,
          keepPosition: keepPosition,
          lastPosition: lastPosition,
          videoUrl: videoUrl,
        );
      } catch (e) {
        isInitialized.value = false;
        isPlaying.value = false;
        await _handlePlaybackFailure(e);
      }
      return;
    }

    PlaybackEngine? localEngine;
    final engineType = playbackEngineType.value;
    final formatHint = formatHintFromUrl(videoUrl);
    final forceSoftwareVideoDecode =
        !kIsWeb &&
        engineType == PlaybackEngineType.fvp &&
        currentQuality.value == 'original' &&
        needsWindowsSoftwareVideoDecode(
          videoTracks: _rawVideoTracks,
          sourcePath: fileInfo['internalPath']?.toString().trim().isNotEmpty ==
                  true
              ? fileInfo['internalPath']!.toString()
              : path,
        );
    try {
      await _ensureMacosAudioOutputActive();
      final initKey = const Uuid().v4();
      _pendingInitKey = initKey;
      final media3StartPosition = engineType == PlaybackEngineType.media3
          ? _media3StartPositionForInit(
              keepPosition: keepPosition,
              lastPosition: lastPosition,
              originalSeekAfterInit: originalSeekAfterInit,
            )
          : Duration.zero;
      localEngine = await createPlaybackEngine(
        type: engineType,
        url: videoUrl,
        requestKey: initKey,
        formatHint: formatHint,
        startPosition: media3StartPosition,
        forceSoftwareVideoDecode: forceSoftwareVideoDecode,
      );
      _pendingInitKey = null;

      if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
        disposePlaybackEngine(localEngine);
        try {
          await localEngine.disposeEngine();
        } catch (_) {}
        return;
      }

      if (engineType == PlaybackEngineType.media3) {
        final ready = Completer<void>();
        _media3SurfaceReady = ready;
        _media3WaitInitGeneration = initGeneration;
        playbackEngine.value = localEngine;
        await WidgetsBinding.instance.endOfFrame;
        try {
          await ready.future.timeout(const Duration(seconds: 15));
        } catch (_) {
          throw Exception('media3_surface_timeout');
        }
        _media3WaitInitGeneration = null;
        if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
          disposePlaybackEngine(localEngine);
          try {
            await localEngine.disposeEngine();
          } catch (_) {}
          playbackEngine.value = null;
          return;
        }
      }

      if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
        disposePlaybackEngine(localEngine);
        try {
          await localEngine.disposeEngine();
        } catch (_) {}
        return;
      }

      playbackEngine.value = localEngine;
      isInitialized.value = true;
      _reloadRetryCount = 0;
      _isRecoveringFromError = false;

      await _applyClientSubtitleOverlayIfNeeded(engine: localEngine);

      if (currentQuality.value == 'original') {
        if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
          duration.value = Duration(seconds: _sourceDurationSeconds!);
        } else {
          duration.value = localEngine.value.duration;
        }
      } else if (_sourceDurationSeconds != null &&
          _sourceDurationSeconds! > 0) {
        duration.value = Duration(seconds: _sourceDurationSeconds!);
      } else {
        duration.value = localEngine.value.duration;
      }

      if (currentQuality.value != 'original') {
        position.value = keepPosition
            ? lastPosition
            : Duration(seconds: _transcodeBaseSeconds);
      }

      if (!keepPosition) {
        final pref = _pendingPreference;
        if (pref != null) {
          await applyPreference(pref);
          if (currentQuality.value != 'original') {
            await loadWebSubtitleIfNeeded(force: true);
          }
          if (isClosed ||
              _isClosingPlayer ||
              initGeneration != _initGeneration) {
            final engine = playbackEngine.value;
            if (engine != null && identical(engine, localEngine)) {
              try {
                engine.removeListener(_videoListener);
              } catch (_) {}
              disposePlaybackEngine(engine);
              try {
                await engine.disposeEngine();
              } catch (_) {}
              playbackEngine.value = null;
            }
            if (initGeneration == _initGeneration) {
              isInitialized.value = false;
              isPlaying.value = false;
            }
            return;
          }
        }
      }

      if (originalSeekAfterInit != null &&
          originalSeekAfterInit > Duration.zero) {
        final cap = _resumePositionCapDuration(localEngine);
        final target = originalSeekAfterInit > cap
            ? cap
            : originalSeekAfterInit;
        if (engineType != PlaybackEngineType.media3 ||
            media3StartPosition != target) {
          await localEngine.seekTo(target);
        }
        position.value = target;
        if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
          final engine = playbackEngine.value;
          if (engine != null && identical(engine, localEngine)) {
            try {
              engine.removeListener(_videoListener);
            } catch (_) {}
            disposePlaybackEngine(engine);
            try {
              await engine.disposeEngine();
            } catch (_) {}
            playbackEngine.value = null;
          }
          if (initGeneration == _initGeneration) {
            isInitialized.value = false;
            isPlaying.value = false;
          }
          return;
        }
      }

      var shouldShowResumeTip = false;
      if (!keepPosition) {
        if (_resumeSeekBakedIntoUrlSeconds != null &&
            _resumeSeekBakedIntoUrlSeconds! > 10) {
          _markResumeApplied(
            Duration(seconds: _resumeSeekBakedIntoUrlSeconds!),
          );
          shouldShowResumeTip = true;
        } else if (_pendingResumePosition != null &&
            _pendingResumePosition!.inSeconds > 10) {
          var target = _pendingResumePosition!;
          final cap = _resumePositionCapDuration(localEngine);
          if (target > cap) target = cap;
          _pendingResumePosition = null;
          if (target.inSeconds > 10) {
            _markResumeApplied(target);
            shouldShowResumeTip = true;
            if (currentQuality.value != 'original') {
              final t = target;
              Future<void>.delayed(const Duration(milliseconds: 150), () {
                if (isClosed ||
                    _isClosingPlayer ||
                    initGeneration != _initGeneration) {
                  return;
                }
                if (!identical(playbackEngine.value, localEngine)) {
                  return;
                }
                seekTo(t);
              });
            } else {
              await localEngine.seekTo(target);
              if (isClosed ||
                  _isClosingPlayer ||
                  initGeneration != _initGeneration) {
                final engine = playbackEngine.value;
                if (engine != null && identical(engine, localEngine)) {
                  try {
                    engine.removeListener(_videoListener);
                  } catch (_) {}
                  disposePlaybackEngine(engine);
                  try {
                    await engine.disposeEngine();
                  } catch (_) {}
                  playbackEngine.value = null;
                }
                if (initGeneration == _initGeneration) {
                  isInitialized.value = false;
                  isPlaying.value = false;
                }
                return;
              }
            }
          }
        }
      }

      await _ensureMacosAudioOutputActive();
      await localEngine.setVolume(volume.value);
      await localEngine.setLooping(loopMode.value == 'single');
      await localEngine.play();

      await _applyOriginalTracksAfterPlay(
        engine: localEngine,
        initGeneration: initGeneration,
      );
      if (engineType == PlaybackEngineType.media3) {
        // 外挂字幕 reload 可能把 playWhenReady 置回 false，再补一次 play。
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (!isClosed &&
            !_isClosingPlayer &&
            initGeneration == _initGeneration &&
            identical(playbackEngine.value, localEngine)) {
          await localEngine.play();
        }
      }
      if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
        final engine = playbackEngine.value;
        if (engine != null && identical(engine, localEngine)) {
          try {
            await engine.pause();
          } catch (_) {}
          try {
            engine.removeListener(_videoListener);
          } catch (_) {}
          disposePlaybackEngine(engine);
          try {
            await engine.disposeEngine();
          } catch (_) {}
          playbackEngine.value = null;
        }
        if (initGeneration == _initGeneration) {
          isInitialized.value = false;
          isPlaying.value = false;
        }
        return;
      }
      isPlaying.value = true;

      localEngine.addListener(_videoListener);

      if (currentQuality.value != 'original') {
        _startPositionPolling();
      }

      if (shouldShowResumeTip) {
        startResumeTip(10);
      }

      resetControlsTimer();
      startAutoSave();
      _disallowEngineHotSwap = false;
    } catch (e) {
      _pendingInitKey = null;
      _disallowEngineHotSwap = false;
      _deferOriginalTracksUntilPlaying = false;
      if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
        if (localEngine != null) {
          try {
            localEngine.removeListener(_videoListener);
          } catch (_) {}
          disposePlaybackEngine(localEngine);
          try {
            await localEngine.disposeEngine();
          } catch (_) {}
        }
        if (identical(playbackEngine.value, localEngine)) {
          playbackEngine.value = null;
        }
        return;
      }

      if (localEngine != null) {
        disposePlaybackEngine(localEngine);
        try {
          await localEngine.disposeEngine();
        } catch (_) {}
      }
      if (identical(playbackEngine.value, localEngine)) {
        playbackEngine.value = null;
      }
      isInitialized.value = false;
      isPlaying.value = false;
      await _handlePlaybackFailure(e);
    }
  }

  /// Media3 画质切换：复用 PlatformView/ExoPlayer，仅换 URL（对齐 TV playCurrent）。
  Future<void> _initializePlayerMedia3HotSwap({
    required int initGeneration,
    required bool keepPosition,
    required Duration lastPosition,
    required String videoUrl,
  }) async {
    final engine = playbackEngine.value;
    if (engine == null || !engine.canHotSwapSource) {
      throw StateError('media3_hot_swap_unavailable');
    }

    final formatHint = formatHintFromUrl(videoUrl);
    final directUrl = resolveDirectPlaybackUrl(videoUrl);
    final proxy = await resolveP2pProxyForNative(directUrl);
    final startPosition = _media3StartPositionForInit(
      keepPosition: keepPosition,
      lastPosition: lastPosition,
      originalSeekAfterInit: currentQuality.value == 'original' && keepPosition
          ? lastPosition
          : null,
    );

    await engine.switchSource(
      uri: Uri.parse(proxy.url),
      formatHint: formatHint,
      startPosition: startPosition,
    );

    if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
      return;
    }

    isInitialized.value = true;
    _reloadRetryCount = 0;
    _isRecoveringFromError = false;

    if (playlist.isNotEmpty && currentIndex.value < playlist.length) {
      await _applyClientSubtitleOverlayIfNeeded(engine: engine);
    }

    if (currentQuality.value == 'original') {
      if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
        duration.value = Duration(seconds: _sourceDurationSeconds!);
      } else {
        duration.value = engine.value.duration;
      }
    } else if (_sourceDurationSeconds != null &&
        _sourceDurationSeconds! > 0) {
      duration.value = Duration(seconds: _sourceDurationSeconds!);
    } else {
      duration.value = engine.value.duration;
    }

    if (currentQuality.value != 'original') {
      position.value = keepPosition
          ? lastPosition
          : Duration(seconds: _transcodeBaseSeconds);
    } else if (keepPosition && startPosition > Duration.zero) {
      position.value = startPosition;
    }

    await _ensureMacosAudioOutputActive();
    await engine.setVolume(volume.value);
    await engine.setLooping(loopMode.value == 'single');
    await engine.play();
    if (isClosed || _isClosingPlayer || initGeneration != _initGeneration) {
      return;
    }
    isPlaying.value = true;

    engine.addListener(_videoListener);

    if (currentQuality.value != 'original') {
      _startPositionPolling();
    }

    await _applyOriginalTracksAfterPlay(
      engine: engine,
      initGeneration: initGeneration,
    );
    if (engine.type == PlaybackEngineType.media3) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!isClosed &&
          !_isClosingPlayer &&
          initGeneration == _initGeneration &&
          identical(playbackEngine.value, engine)) {
        await engine.play();
      }
    }

    resetControlsTimer();
    startAutoSave();
    _disallowEngineHotSwap = false;
  }

  Duration _resumePositionCapDuration(PlaybackEngine engine) {
    if (duration.value > Duration.zero) return duration.value;
    final sec = _sourceDurationSeconds;
    if (sec != null && sec > 0) return Duration(seconds: sec);
    final d = engine.value.duration;
    if (d > Duration.zero) return d;
    return const Duration(days: 1);
  }

  Duration _media3StartPositionForInit({
    required bool keepPosition,
    required Duration lastPosition,
    Duration? originalSeekAfterInit,
  }) {
    if (!keepPosition) return Duration.zero;
    if (currentQuality.value == 'original') {
      final target = originalSeekAfterInit ?? lastPosition;
      if (target <= Duration.zero) return Duration.zero;
      final sec = _sourceDurationSeconds;
      if (sec != null && sec > 0 && target.inSeconds >= sec) {
        return Duration(seconds: max(0, sec - 1));
      }
      return target;
    }
    return Duration.zero;
  }

  int? _takeResumeSeekForInitialUrl({required bool keepPosition}) {
    if (keepPosition) return null;
    final p = _pendingResumePosition;
    if (p == null || p.inSeconds <= 10) return null;
    var sec = p.inSeconds;
    final total = _sourceDurationSeconds;
    if (total != null && total > 0) {
      sec = min(sec, max(0, total - 1));
    }
    if (sec <= 10) return null;
    _resumeSeekBakedIntoUrlSeconds = sec;
    _pendingResumePosition = null;
    return sec;
  }

  String _buildOriginalVideoUrl(
    ApiController apiController,
    Map<String, dynamic> fileInfo,
    bool keepPosition,
    Duration lastPosition,
  ) {
    _transcodeBaseSeconds = 0;
    _pendingTranscodeSeekSeconds = null;
    final path = fileInfo['path']?.toString() ?? '';
    final internalPath = fileInfo['internalPath']?.toString().trim() ?? '';
    if (_isHttpUrl(path)) return path;
    final baseUrl = apiController.baseUrl;
    final token = apiController.accessToken;
    var videoUrl =
        '$baseUrl/api/videoPlayer/rawFile?raw=1&path=${Uri.encodeComponent(path)}';
    if (internalPath.isNotEmpty) {
      videoUrl += '&internalPath=${Uri.encodeComponent(internalPath)}';
    }
    if (token != null) {
      videoUrl += '&accessToken=$token';
    }
    return videoUrl;
  }

  String _buildTranscodeVideoUrl(
    ApiController apiController,
    Map<String, dynamic> fileInfo,
    bool keepPosition,
    Duration lastPosition,
  ) {
    final path = fileInfo['path']?.toString() ?? '';
    final internalPath = fileInfo['internalPath']?.toString().trim() ?? '';
    final explicitTranscodeSeek = _pendingTranscodeSeekSeconds;
    _pendingTranscodeSeekSeconds = null;
    var seekSeconds = explicitTranscodeSeek ??
        (keepPosition ? lastPosition.inSeconds : 0);
    if (seekSeconds == 0 && !keepPosition && explicitTranscodeSeek == null) {
      final fromPref = _takeResumeSeekForInitialUrl(keepPosition: keepPosition);
      if (fromPref != null) seekSeconds = fromPref;
    }
    _transcodeBaseSeconds = seekSeconds;

    int? width;
    String? bitrate;
    final q = currentQuality.value;
    final parts = q.split('_');
    if (parts.length >= 2) {
      final res = parts[0].toLowerCase();
      final br = parts[1].toLowerCase();
      if (res == '4k') {
        width = 3840;
      } else if (res == '1080p') {
        width = 1920;
      } else if (res == '720p') {
        width = 1280;
      } else if (res == '480p') {
        width = 854;
      }

      final m = RegExp(r'^(\d+)(m|k)$').firstMatch(br);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        final unit = m.group(2);
        if (n != null && n > 0) {
          if (unit == 'm') {
            bitrate = '${n * 1000}k';
          } else {
            bitrate = '${n}k';
          }
        }
      }
    }

    int? audioIndex;
    if (currentAudioTrack.value.isNotEmpty) {
      final track = _rawAudioTracks.firstWhere(
        (e) => e['label'] == currentAudioTrack.value,
        orElse: () => {},
      );
      if (track.isNotEmpty) audioIndex = track['mapIndex'];
    }

    int? subtitleIndex;
    String? subtitlePath;
    var burn = false;
    if (currentSubtitleTrack.value.isNotEmpty && !currentIsNoSubtitle) {
      final track = _rawSubtitleTracks.firstWhere(
        (e) => e['label'] == currentSubtitleTrack.value,
        orElse: () => {},
      );
      if (track.isNotEmpty) {
        if (track['isExternal'] == true) {
          // 文本外挂字幕由客户端 VTT 叠层渲染，避免烧录导致双字幕；位图外挂仍走转码烧录
          final subPath = track['path']?.toString() ?? '';
          final dot = subPath.lastIndexOf('.');
          final subExt = dot >= 0 ? subPath.substring(dot) : '';
          if (_isBitmapExternalSubtitleExtension(subExt)) {
            subtitlePath = track['path'];
            burn = true;
          }
        } else {
          final codec = track['codec_name']?.toString();
          if (_isBitmapSubtitleCodecName(codec)) {
            subtitleIndex = track['mapIndex'];
            burn = true;
          }
        }
      }
    }

    final baseUrl = apiController.baseUrl;
    final token = apiController.accessToken;
    final deviceId = UserAgentUtil.getOrCreateVideoPlayerDeviceIdSync();

    var startUrl =
        '$baseUrl/api/videoPlayer/transcode?playId=$_playId&filePath=${Uri.encodeComponent(path)}&seek=$seekSeconds';
    if (internalPath.isNotEmpty) {
      startUrl += '&internalPath=${Uri.encodeComponent(internalPath)}';
    }
    if (deviceId.isNotEmpty) {
      startUrl += '&device_id=${Uri.encodeComponent(deviceId)}';
    }

    if (width != null) startUrl += '&width=$width';
    if (bitrate != null) startUrl += '&bitrate=$bitrate';
    if (audioIndex != null) startUrl += '&audioIndex=$audioIndex';
    if (subtitleIndex != null) startUrl += '&subtitleIndex=$subtitleIndex';
    if (subtitlePath != null) {
      startUrl += '&subtitlePath=${Uri.encodeComponent(subtitlePath)}';
    }
    if (burn) startUrl += '&subtitleBurn=true';
    if (DeviceUtils.isWeb) startUrl += '&client=web';

    if (token != null) {
      startUrl += '&accessToken=$token';
    }
    return startUrl;
  }
}
