part of '../music_play_service_controller.dart';

extension MusicPlayServicePlayback on MusicPlayServiceController {
  bool _isWebUnsupportedByPath(String path) {
    if (!kIsWeb) return false;
    final base = path.split(RegExp(r'[?#]')).first;
    final name = base.split('/').last.toLowerCase();
    return name.endsWith('.ape') || name.endsWith('.wma');
  }

  bool _preferTranscodeByExt(String ext) {
    final e = ext.trim().toLowerCase();
    if (e.isEmpty) return false;
    return e == 'ape' || e == 'wma';
  }

  String _toTranscodeCacheKey(String originalHash) {
    final h = originalHash.trim();
    if (h.isEmpty) return '';
    return '${h}_mp3';
  }

  bool _isPlayableItem(MusicListItem item) {
    final path = _resolvePlayablePath(item).trim();
    if (path.isEmpty) return false;
    return true;
  }

  Future<void> _handleNoPlayableItems() async {
    playlist.clear();
    playlist.refresh();
    currentIndex.value = 0;
    currentLyrics.value = '';
    position.value = Duration.zero;
    duration.value = Duration.zero;
    buffered.value = Duration.zero;
    _paging = null;
    _pagingToken++;
    _pagingLoading = false;
    _shuffleHistory.clear();
    _desiredPlaying = false;
    await _disposePlayer();
    isPlaying.value = false;
    _handler?.updateQueue(const <MediaItem>[]);
    _syncHandlerPlaybackState();
  }

  String get discAsset {
    final assets = MusicPlayServiceController.discAssets;
    final idx = discStyleIndex.value.clamp(0, assets.length - 1);
    return assets[idx];
  }

  void nextDiscStyle() {
    final max = MusicPlayServiceController.discAssets.length;
    final next = max <= 0 ? 0 : (discStyleIndex.value + 1) % max;
    discStyleIndex.value = next;
    CacheManager().setInt(CacheKeys.musicDiscStyleIndex, next);
  }

  void toggleMute() {
    final v = volume.value;
    if (v > 0.01) {
      _volumeBeforeMute = v;
      CacheManager().setDouble(CacheKeys.musicVolumeBeforeMute, v);
      setVolume(0);
      return;
    }
    final restore = (_volumeBeforeMute > 0.01 ? _volumeBeforeMute : 1.0);
    setVolume(restore);
  }

  void addProgressListener(MusicProgressListener listener) {
    _progressListeners.add(listener);
  }

  void removeProgressListener(MusicProgressListener listener) {
    _progressListeners.remove(listener);
  }

  Future<void> playFromList({
    required List<MusicListItem> items,
    required MusicListItem startItem,
    bool autoPlay = true,
    MusicPlaylistPaging? paging,
  }) async {
    final playable = _filterPlayable(items);
    if (playable.isEmpty) {
      await _handleNoPlayableItems();
      return;
    }
    final startPath = _resolvePlayablePath(startItem).trim();
    final startInOriginal = startItem.id > 0
        ? items.indexWhere((e) => e.id == startItem.id)
        : (startPath.isNotEmpty
              ? items.indexWhere(
                  (e) => _resolvePlayablePath(e).trim() == startPath,
                )
              : -1);

    var resolvedStartInOriginal = -1;
    if (startInOriginal >= 0 && startInOriginal < items.length) {
      for (var i = startInOriginal; i < items.length; i++) {
        if (_isPlayableItem(items[i])) {
          resolvedStartInOriginal = i;
          break;
        }
      }
      if (resolvedStartInOriginal < 0) {
        resolvedStartInOriginal = items.indexWhere(_isPlayableItem);
      }
    } else {
      resolvedStartInOriginal = items.indexWhere(_isPlayableItem);
    }
    final resolvedItem = resolvedStartInOriginal >= 0
        ? items[resolvedStartInOriginal]
        : null;
    final resolvedPath = resolvedItem == null
        ? ''
        : _resolvePlayablePath(resolvedItem).trim();
    final idx = resolvedItem == null
        ? 0
        : (resolvedItem.id > 0
              ? playable.indexWhere((e) => e.id == resolvedItem.id)
              : (resolvedPath.isNotEmpty
                    ? playable.indexWhere(
                        (e) => _resolvePlayablePath(e).trim() == resolvedPath,
                      )
                    : -1));
    await setPlaylist(
      playable,
      startIndex: idx >= 0 ? idx : 0,
      autoPlay: autoPlay,
      paging: paging,
    );
  }

  Future<void> setPlaylist(
    List<MusicListItem> items, {
    int startIndex = 0,
    bool autoPlay = true,
    MusicPlaylistPaging? paging,
  }) async {
    final playable = _filterPlayable(items);
    if (playable.isEmpty) {
      await _handleNoPlayableItems();
      return;
    }
    await _initService();
    _paging = paging;
    _pagingToken++;
    _pagingLoading = false;
    _shuffleHistory.clear();
    playlist.assignAll(playable);
    final safeIndex = startIndex.clamp(0, playable.length - 1);
    currentIndex.value = safeIndex;
    _invalidateMediaItemCache();
    await _ensureNotificationPermission();
    await _refreshDetailForIndex(safeIndex);
    _handler?.updateQueue(_buildQueueMediaItems());
    if (autoPlay) {
      await _activateIosAudioSessionForPlayback();
    }
    await _openTrack(safeIndex, autoPlay: autoPlay);
    unawaited(
      _handleIndexChangeForPaging(prevIndex: safeIndex, nextIndex: safeIndex),
    );
    unawaited(_maybePrefetchNextPageForPaging(safeIndex));
  }

  Future<void> playAt(int index) async {
    if (playlist.isEmpty) return;
    await _initService();
    _desiredPlaying = true;
    await _activateIosAudioSessionForPlayback();
    await _ensurePlaylistUpToDate();
    final safeIndex = index.clamp(0, playlist.length - 1);
    final prev = currentIndex.value;
    currentIndex.value = safeIndex;
    _invalidateMediaItemCache();
    _syncMediaItem(safeIndex);
    // 立即更新 playbackState 的 queueIndex，确保锁屏控制正确响应
    _syncHandlerPlaybackState();
    await _refreshDetailForIndex(safeIndex);
    await _openTrack(safeIndex, autoPlay: true, initialPosition: Duration.zero);
    unawaited(
      _handleIndexChangeForPaging(prevIndex: prev, nextIndex: safeIndex),
    );
    unawaited(_maybePrefetchNextPageForPaging(safeIndex));
  }

  Future<void> play() async {
    await _initService();
    _desiredPlaying = true;
    await _activateIosAudioSessionForPlayback();
    await _ensureNotificationPermission();
    // 不在此处主动刷新 token/重建 URL：
    // 1) token 未变时 _ensurePlaylistUpToDate 本身是 no-op，但也会引入 await 延迟；
    // 2) token 变化时重建 URL 会打断/重新加载当前曲目，导致 OPPO 等机型从控制中心恢复播放偶发失败；
    // URL 失效时会经由 stall 恢复路径（_attemptRecovery）重建，无需在此预防性调用。
    if (playlist.isEmpty) return;
    final p = _player;
    if (p == null) {
      await _openTrack(
        currentIndex.value.clamp(0, playlist.length - 1),
        autoPlay: true,
      );
      return;
    }
    if (_isCompleted) {
      await p.seekTo(Duration.zero);
      _isCompleted = false;
    }
    await p.play();
    _syncHandlerPlaybackState();
  }

  Future<void> pause() async {
    await _initService();
    _desiredPlaying = false;
    await _player?.pause();
    _syncHandlerPlaybackState();
  }

  Future<void> resume() async {
    _desiredPlaying = true;
    await _activateIosAudioSessionForPlayback();
    await _ensureNotificationPermission();
    await play();
  }

  Future<void> stop() async {
    await _initService();
    _desiredPlaying = false;
    final p = _player;
    if (p != null) {
      await p.pause();
      await p.seekTo(Duration.zero);
    }
    _isCompleted = false;
    _syncHandlerPlaybackState();
    await _deactivateIosAudioSessionForPlayback();
  }

  Future<void> playNext({bool forcePlay = false}) async {
    if (playlist.isEmpty) return;
    await _initService();
    await _activateIosAudioSessionForPlayback();
    _suppressCompletedUntil = DateTime.now().add(const Duration(seconds: 4));
    _isSkippingTrack = true;
    try {
      final wasPlaying = forcePlay || (_player?.isPlaying ?? false);
      _desiredPlaying = wasPlaying;
      final prev = currentIndex.value;
      final next = _resolveNextIndex(forward: true);
      if (next == null) return;
      if (loopMode.value == MusicLoopMode.shuffle) {
        _shuffleHistory.add(prev);
      }
      currentIndex.value = next;
      _invalidateMediaItemCache();
      _syncMediaItem(next);
      // 立即更新 playbackState 的 queueIndex，确保锁屏控制正确响应
      _syncHandlerPlaybackState();
      await _refreshDetailForIndex(next);
      await _openTrack(next, autoPlay: wasPlaying);
      unawaited(_handleIndexChangeForPaging(prevIndex: prev, nextIndex: next));
      unawaited(_maybePrefetchNextPageForPaging(next));
    } finally {
      _isSkippingTrack = false;
      _syncHandlerPlaybackState();
    }
  }

  Future<void> playPrevious({bool forcePlay = false}) async {
    if (playlist.isEmpty) return;
    await _initService();
    await _activateIosAudioSessionForPlayback();
    _suppressCompletedUntil = DateTime.now().add(const Duration(seconds: 4));
    _isSkippingTrack = true;
    try {
      final wasPlaying = forcePlay || (_player?.isPlaying ?? false);
      _desiredPlaying = wasPlaying;
      final prev = currentIndex.value;
      final next = _resolveNextIndex(forward: false);
      if (next == null) return;
      currentIndex.value = next;
      _invalidateMediaItemCache();
      _syncMediaItem(next);
      // 立即更新 playbackState 的 queueIndex，确保锁屏控制正确响应
      _syncHandlerPlaybackState();
      await _refreshDetailForIndex(next);
      await _openTrack(next, autoPlay: wasPlaying);
      unawaited(_handleIndexChangeForPaging(prevIndex: prev, nextIndex: next));
      unawaited(_maybePrefetchNextPageForPaging(next));
    } finally {
      _isSkippingTrack = false;
      _syncHandlerPlaybackState();
    }
  }

  Future<void> seekTo(Duration position) async {
    final p = _player;
    if (p == null) return;
    final d = p.duration;
    final safe = d <= Duration.zero
        ? (position.isNegative ? Duration.zero : position)
        : (position.isNegative ? Duration.zero : (position > d ? d : position));
    await p.seekTo(safe);
    this.position.value = safe;
    _syncHandlerPlaybackState();
  }

  Future<void> setVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    volume.value = next;
    await _player?.setVolume(next);
    await CacheManager().setDouble(CacheKeys.musicVolume, next);
    if (next > 0.01) {
      _volumeBeforeMute = next;
      await CacheManager().setDouble(
        CacheKeys.musicVolumeBeforeMute,
        _volumeBeforeMute,
      );
    }
  }

  Future<void> setLoopMode(MusicLoopMode mode) async {
    if (loopMode.value == mode) return;
    loopMode.value = mode;
    await CacheManager().setInt(CacheKeys.musicLoopModeIndex, mode.index);
    await _applyLoopModeToPlayer();
  }

  Future<void> _maybePrefetchNextPageForPaging(int index) async {
    final mode = loopMode.value;
    if (mode != MusicLoopMode.sequence && mode != MusicLoopMode.listLoop) {
      return;
    }
    final paging = _paging;
    if (paging == null) return;
    if (_pagingLoading) return;
    if (!paging.hasMore()) return;
    if (playlist.isEmpty) return;
    final last = playlist.length - 1;
    if (index != last) return;
    await _loadMoreAndAppendInPlace(currentIndex: index);
  }

  Future<void> _handleIndexChangeForPaging({
    required int prevIndex,
    required int nextIndex,
  }) async {
    if (loopMode.value != MusicLoopMode.listLoop) return;
    final paging = _paging;
    if (paging == null) return;
    if (_pagingLoading) return;
    if (!paging.hasMore()) return;
    if (playlist.isEmpty) return;
    final last = playlist.length - 1;
    if (prevIndex != last || nextIndex != 0) return;
    final startIndexAfterAppend = playlist.length;
    await _loadMoreAndRebuild(
      startIndexAfterAppend: startIndexAfterAppend,
      initialPosition: Duration.zero,
      autoPlay: false,
      resumeIfWasPlaying: _player?.isPlaying ?? false,
    );
  }

  Future<void> _loadMoreAndAppendInPlace({required int currentIndex}) async {
    final paging = _paging;
    if (paging == null) return;

    final token = ++_pagingToken;
    _pagingLoading = true;
    try {
      final more = await paging.loadMore();
      if (isClosed || token != _pagingToken) return;
      if (more.isEmpty) return;

      final existingPaths = playlist
          .map((e) => _resolvePlayablePath(e).trim())
          .toSet();
      final extra = more
          .map((e) => e)
          .where((e) => !e.isSeries)
          .where((e) => _resolvePlayablePath(e).trim().isNotEmpty)
          .where((e) => !existingPaths.contains(_resolvePlayablePath(e).trim()))
          .toList(growable: false);
      if (extra.isEmpty) return;

      playlist.addAll(extra);
      playlist.refresh();
      _handler?.updateQueue(_buildQueueMediaItems());
    } catch (_) {
    } finally {
      if (!isClosed && token == _pagingToken) {
        _pagingLoading = false;
      }
    }
  }

  Future<void> _loadMoreAndRebuild({
    required int startIndexAfterAppend,
    required Duration initialPosition,
    required bool autoPlay,
    bool resumeIfWasPlaying = false,
  }) async {
    final paging = _paging;
    if (paging == null) return;

    final token = ++_pagingToken;
    _pagingLoading = true;
    try {
      final more = await paging.loadMore();
      if (isClosed || token != _pagingToken) return;
      if (more.isEmpty) return;

      final existingPaths = playlist
          .map((e) => _resolvePlayablePath(e).trim())
          .toSet();
      final extra = more
          .map((e) => e)
          .where((e) => !e.isSeries)
          .where((e) => _resolvePlayablePath(e).trim().isNotEmpty)
          .where((e) => !existingPaths.contains(_resolvePlayablePath(e).trim()))
          .toList(growable: false);
      if (extra.isEmpty) return;

      final oldLen = playlist.length;
      playlist.addAll(extra);
      playlist.refresh();
      _handler?.updateQueue(_buildQueueMediaItems());

      final safeIndex = startIndexAfterAppend.clamp(0, playlist.length - 1);
      currentIndex.value = safeIndex;
      await _openTrack(
        safeIndex,
        autoPlay: autoPlay,
        initialPosition: initialPosition,
      );
      await _refreshDetailForIndex(safeIndex);
      if (!autoPlay && resumeIfWasPlaying) {
        await _player?.play();
      }
      if (!autoPlay && safeIndex == 0 && oldLen > 0) {
        currentIndex.refresh();
      }
    } catch (_) {
    } finally {
      if (!isClosed && token == _pagingToken) {
        _pagingLoading = false;
      }
    }
  }

  Future<void> _openTrack(
    int index, {
    bool autoPlay = true,
    Duration initialPosition = Duration.zero,
  }) async {
    if (playlist.isEmpty) return;
    final safeIndex = index.clamp(0, playlist.length - 1);

    final token = ++_rebuildToken;
    _isOpeningTrack = true;
    _suppressCompletedUntil = DateTime.now().add(const Duration(seconds: 4));
    _syncHandlerPlaybackState();
    try {
      await cancelDownload();
      await _disposePlayer();
      if (isClosed || token != _rebuildToken) return;

      final item = playlist[safeIndex];

      String resolveExt(MusicListItem item) {
        final e = item.ext.trim();
        if (e.isNotEmpty) return e;
        final name = item.filename.trim();
        final dot = name.lastIndexOf('.');
        if (dot >= 0 && dot < name.length - 1) {
          return name.substring(dot + 1);
        }
        return 'dat';
      }

      Future<String> buildOriginalUrl() async {
        _lastPlaylistAccessToken = ApiController.instance.accessToken?.trim();
        return _buildPlayUrl(item);
      }

      Future<String> buildTranscodeUrl() async {
        _lastPlaylistAccessToken = ApiController.instance.accessToken?.trim();
        return ApiController.instance.getMusicTranscodeUrl(
          _resolvePlayablePath(item),
          withAccessToken: true,
          p2pChannel: 'download',
        );
      }

      final ext = resolveExt(item);
      final hash = item.fileHash.trim();
      final expectedSize = item.size;
      final preferTranscode =
          _isWebUnsupportedByPath(_resolvePlayablePath(item)) ||
          _preferTranscodeByExt(ext);

      String cacheHash({required bool transcode}) =>
          transcode ? _toTranscodeCacheKey(hash) : hash;
      String fileExt({required bool transcode}) => transcode ? 'mp3' : ext;
      int fileSize({required bool transcode}) => transcode ? 0 : expectedSize;
      Future<String> buildUrl({required bool transcode}) =>
          transcode ? buildTranscodeUrl() : buildOriginalUrl();

      void onProgress(MusicAudioCacheProgress p) {
        if (isClosed || token != _rebuildToken) return;
        final active = _audioCache.activeHash?.trim() ?? '';
        if (active.isEmpty) return;
        if (active == hash || active == _toTranscodeCacheKey(hash)) {
          if (p.finished) {
            _setDownloadUi(
              downloading: false,
              fileHash: '',
              received: 0,
              total: 0,
            );
            return;
          }
          _setDownloadUi(
            downloading: true,
            fileHash: hash,
            received: p.receivedBytes,
            total: p.totalBytes,
          );
        }
      }

      Future<void> openWithJustAudio({required bool transcode}) async {
        final h = cacheHash(transcode: transcode);
        final e = fileExt(transcode: transcode);
        final s = fileSize(transcode: transcode);

        MusicPlaySource source;
        try {
          source = await _audioCache.prepareSource(
            fileHash: h,
            fileExt: e,
            fileSize: s,
            buildUrl: () => buildUrl(transcode: transcode),
            refreshAuthToken: ApiController.instance.refreshAuthToken,
            onProgress: onProgress,
          );
        } on MusicAudioCacheCanceled {
          rethrow;
        } catch (_) {
          final url = await buildUrl(transcode: transcode);
          source = MusicPlaySource(url: url, fileExt: e);
        }
        if (isClosed || token != _rebuildToken) return;

        final adapter = MusicPlayerJustAudioAdapter();
        try {
          await adapter.loadFromSource(source);
          await adapter.setVolume(volume.value.clamp(0.0, 1.0));
          await _applyLoopModeToPlayer();
          await adapter.initialize();
        } catch (_) {
          final canRemoveCache = audioCacheEnabled.value && h.isNotEmpty;
          if (canRemoveCache && await _audioCache.hasCached(h)) {
            await _audioCache.remove(h);
            if (isClosed || token != _rebuildToken) return;
            final retrySource = await _audioCache.prepareSource(
              fileHash: h,
              fileExt: e,
              fileSize: s,
              buildUrl: () => buildUrl(transcode: transcode),
              refreshAuthToken: ApiController.instance.refreshAuthToken,
              onProgress: onProgress,
            );
            await _disposePlayer();
            if (isClosed || token != _rebuildToken) return;
            await adapter.loadFromSource(retrySource);
          } else {
            final refreshed = await ApiController.instance.refreshAuthToken();
            if (!refreshed) rethrow;
            final retryUrl = await buildUrl(transcode: transcode);
            await adapter.loadFromSource(
              MusicPlaySource(url: retryUrl, fileExt: e),
            );
          }
          await adapter.setVolume(volume.value.clamp(0.0, 1.0));
          await _applyLoopModeToPlayer();
          await adapter.initialize();
        }
        _player = adapter;
      }

      Future<void> openWithVideoPlayer({required bool transcode}) async {
        final h = cacheHash(transcode: transcode);
        final e = fileExt(transcode: transcode);
        final s = fileSize(transcode: transcode);

        VideoPlayerController controller;
        try {
          controller = await _audioCache.prepareController(
            fileHash: h,
            fileExt: e,
            fileSize: s,
            buildUrl: () => buildUrl(transcode: transcode),
            refreshAuthToken: ApiController.instance.refreshAuthToken,
            onProgress: onProgress,
          );
        } on MusicAudioCacheCanceled {
          rethrow;
        } catch (_) {
          final url = await buildUrl(transcode: transcode);
          controller = await createVideoController(url);
        }
        if (isClosed || token != _rebuildToken) return;

        _player = MusicPlayerVideoAdapter(controller);
        try {
          await _player!.setVolume(volume.value.clamp(0.0, 1.0));
          await _applyLoopModeToPlayer();
          await _player!.initialize();
        } catch (_) {
          final canRemoveCache =
              !kIsWeb && audioCacheEnabled.value && h.isNotEmpty;
          if (canRemoveCache && await _audioCache.hasCached(h)) {
            await _audioCache.remove(h);
            if (isClosed || token != _rebuildToken) return;
            final retryController = await _audioCache.prepareController(
              fileHash: h,
              fileExt: e,
              fileSize: s,
              buildUrl: () => buildUrl(transcode: transcode),
              refreshAuthToken: ApiController.instance.refreshAuthToken,
              onProgress: onProgress,
            );
            await _disposePlayer();
            if (isClosed || token != _rebuildToken) return;
            _player = MusicPlayerVideoAdapter(retryController);
            await _player!.setVolume(volume.value.clamp(0.0, 1.0));
            await _applyLoopModeToPlayer();
            await _player!.initialize();
          } else {
            final refreshed = await ApiController.instance.refreshAuthToken();
            if (!refreshed) rethrow;
            final retryUrl = await buildUrl(transcode: transcode);
            await _disposePlayer();
            if (isClosed || token != _rebuildToken) return;
            final retryController = await createVideoController(retryUrl);
            _player = MusicPlayerVideoAdapter(retryController);
            await _player!.setVolume(volume.value.clamp(0.0, 1.0));
            await _applyLoopModeToPlayer();
            await _player!.initialize();
          }
        }
      }

      if (_useJustAudio) {
        try {
          await openWithJustAudio(transcode: preferTranscode);
        } on MusicAudioCacheCanceled {
          return;
        } catch (_) {
          if (!preferTranscode) {
            try {
              await openWithJustAudio(transcode: true);
            } on MusicAudioCacheCanceled {
              return;
            }
          } else {
            rethrow;
          }
        }
      } else {
        try {
          await openWithVideoPlayer(transcode: preferTranscode);
        } on MusicAudioCacheCanceled {
          return;
        } catch (_) {
          if (!preferTranscode) {
            try {
              await openWithVideoPlayer(transcode: true);
            } on MusicAudioCacheCanceled {
              return;
            }
          } else {
            rethrow;
          }
        }
      }

      if (isClosed || token != _rebuildToken) return;

      _attachPlayer(_player!);

      final d = _player!.duration;
      if (d > Duration.zero) {
        duration.value = d;
      }
      if (d > Duration.zero && initialPosition > Duration.zero) {
        final seek = initialPosition.isNegative
            ? Duration.zero
            : (initialPosition > d ? d : initialPosition);
        await _player?.seekTo(seek);
      } else if (initialPosition > Duration.zero) {
        await _player?.seekTo(initialPosition);
      }

      _isCompleted = false;
      _syncMediaItem(safeIndex);
      _syncHandlerPlaybackState();

      if (autoPlay) {
        _desiredPlaying = true;
        await _activateIosAudioSessionForPlayback();
        _isOpeningTrack = false;
        await _player?.play();
      } else {
        _isOpeningTrack = false;
      }
    } finally {
      if (!isClosed && token == _rebuildToken) {
        _isOpeningTrack = false;
        _syncHandlerPlaybackState();
      }
    }
  }

  void _attachPlayer(MusicPlayerAdapter controller) {
    _playerListener = () {
      if (isClosed) return;
      if (controller.hasError) {
        unawaited(_attemptRecovery(reason: 'player_error'));
        return;
      }
      final d = controller.duration;
      if (duration.value != d) {
        duration.value = d;
        if (d > Duration.zero) {
          _syncMediaItem(currentIndex.value, forceUpdate: true);
        }
      }
      _syncHandlerPlaybackState();
    };
    controller.addListener(_playerListener!);
  }

  Future<void> _disposePlayer() async {
    final p = _player;
    if (p == null) return;
    try {
      if (_playerListener != null) {
        p.removeListener(_playerListener!);
      }
    } catch (_) {}
    _playerListener = null;
    _player = null;
    try {
      await p.dispose();
    } catch (_) {}
  }

  void _syncMediaItem(int index, {bool forceUpdate = false}) {
    if (_handler == null) return;
    if (index < 0 || index >= playlist.length) return;
    final base = _buildMediaItem(playlist[index]);
    final d = duration.value;
    final item =
        (base.duration == null || base.duration! <= Duration.zero) &&
            d > Duration.zero
        ? base.copyWith(duration: d)
        : base;
    final key =
        '$index:${item.title}:${item.artist}:${item.duration?.inSeconds ?? -1}';
    final shouldUpdate = forceUpdate || key != _lastSentMediaItemKey;
    if (shouldUpdate) {
      _lastSentMediaItemKey = key;
      // 先更新 queue（含当前项 duration），再设当前 mediaItem，确保控制中心/锁屏能拿到总时长
      if (item.duration != null && item.duration! > Duration.zero) {
        _handler!.updateQueue(_buildQueueMediaItems());
      }
      _handler!.mediaItem.add(item);
    }
  }

  void _invalidateMediaItemCache() {
    _lastSentMediaItemKey = null;
  }

  /// 构建用于 updateQueue 的列表，当前项会注入 controller 的 duration，确保控制中心/锁屏显示总时长。
  List<MediaItem> _buildQueueMediaItems() {
    final list = playlist.map(_buildMediaItem).toList();
    final idx = currentIndex.value.clamp(0, list.length - 1);
    if (idx >= list.length) return list;
    final base = list[idx];
    final d = duration.value;
    if ((base.duration == null || base.duration! <= Duration.zero) &&
        d > Duration.zero) {
      list[idx] = base.copyWith(duration: d);
    }
    return list;
  }

  List<MusicListItem> _filterPlayable(List<MusicListItem> items) {
    return items
        .where((e) => _resolvePlayablePath(e).trim().isNotEmpty)
        .toList();
  }

  MediaItem _buildMediaItem(MusicListItem item) {
    final coverPath = item.isSeries
        ? item.firstFilePath.trim()
        : (item.fullPath.trim().isNotEmpty
              ? item.fullPath.trim()
              : _resolvePlayablePath(item));
    final coverUrl =
        !ApiController.instance.isP2pMode &&
            coverPath.isNotEmpty &&
            item.hasInnerCover == 1
        ? ApiController.instance.getMusicCoverUrl(
            filePath: coverPath,
            size: 500,
          )
        : '';
    return MediaItem(
      id: _buildPlayUrl(item),
      title: item.displayTitle,
      artist: item.artist.trim().isNotEmpty ? item.artist.trim() : null,
      album: item.album.trim().isNotEmpty ? item.album.trim() : null,
      artUri: coverUrl.isNotEmpty ? Uri.parse(coverUrl) : null,
      // 与库/API 一致：duration 字段为整秒（非毫秒）
      duration: item.duration > 0 ? Duration(seconds: item.duration) : null,
    );
  }

  String _resolvePlayablePath(MusicListItem item) {
    if (item.isSeries) {
      final p = item.firstFilePath.trim();
      if (p.isNotEmpty) return p;
    }
    final full = item.fullPath.trim();
    if (full.isNotEmpty) return full;
    final base = item.path.trim();
    final name = item.filename.trim();
    if (base.isNotEmpty && name.isNotEmpty) return '$base/$name';
    return base;
  }

  String _buildPlayUrl(MusicListItem item) {
    final path = _resolvePlayablePath(item);
    return ApiController.instance.getRawFileUrl(
      path,
      withAccessToken: true,
      isRawFile: true,
      p2pChannel: 'download',
    );
  }

  void _notifyProgress() {
    for (final listener in _progressListeners) {
      listener(position.value, duration.value, buffered.value);
    }
  }

  Future<void> _applyLoopModeToPlayer() async {
    final mode = loopMode.value;
    final p = _player;
    if (p == null) return;
    if (mode == MusicLoopMode.singleLoop) {
      await p.setLooping(true);
      return;
    }
    await p.setLooping(false);
  }

  void _syncHandlerPlaybackState() {
    final handler = _handler;
    if (handler == null) return;

    final p = _player;
    final playing = p?.isPlaying ?? false;
    final buffering = p?.isBuffering ?? false;
    final processingState = _isOpeningTrack
        ? AudioProcessingState.loading
        : (_isCompleted
              ? AudioProcessingState.completed
              : (p == null
                    ? AudioProcessingState.idle
                    : (!p.isInitialized
                          ? AudioProcessingState.loading
                          : (playing
                                ? AudioProcessingState.ready
                                : (buffering
                                      ? AudioProcessingState.buffering
                                      : AudioProcessingState.ready)))));

    handler._syncPlaybackState(
      playing: playing,
      processingState: processingState,
      updatePosition: position.value,
      bufferedPosition: buffered.value,
      queueIndex: currentIndex.value.clamp(
        0,
        playlist.isEmpty ? 0 : playlist.length - 1,
      ),
    );
  }

  int? _resolveNextIndex({required bool forward}) {
    if (playlist.isEmpty) return null;
    final idx = currentIndex.value.clamp(0, playlist.length - 1);
    final mode = loopMode.value;

    if (mode == MusicLoopMode.shuffle) {
      if (!forward && _shuffleHistory.isNotEmpty) {
        return _shuffleHistory.removeLast().clamp(0, playlist.length - 1);
      }
      if (playlist.length <= 1) return idx;
      var next = idx;
      var guard = 0;
      while (next == idx && guard++ < 10) {
        next = _shuffleRandom.nextInt(playlist.length);
      }
      return next;
    }

    if (forward) {
      if (idx < playlist.length - 1) return idx + 1;
      if (mode == MusicLoopMode.listLoop) return 0;
      return null;
    } else {
      if (idx > 0) return idx - 1;
      if (mode == MusicLoopMode.listLoop) return playlist.length - 1;
      return null;
    }
  }

  Future<void> _handleTrackCompleted() async {
    if (playlist.isEmpty) return;
    final idx = currentIndex.value.clamp(0, playlist.length - 1);
    final mode = loopMode.value;

    if (mode == MusicLoopMode.singleLoop) return;

    if (mode == MusicLoopMode.shuffle) {
      final next = _resolveNextIndex(forward: true);
      if (next == null) return;
      _shuffleHistory.add(idx);
      await playAt(next);
      return;
    }

    if (idx == playlist.length - 1) {
      if (mode == MusicLoopMode.sequence) {
        final paging = _paging;
        if (paging != null && !_pagingLoading && paging.hasMore()) {
          await _loadMoreAndRebuild(
            startIndexAfterAppend: playlist.length,
            initialPosition: Duration.zero,
            autoPlay: true,
          );
          return;
        }
        _desiredPlaying = false;
        await stop();
        _isCompleted = true;
        _syncHandlerPlaybackState();
        return;
      }

      if (mode == MusicLoopMode.listLoop) {
        final paging = _paging;
        if (paging != null && !_pagingLoading && paging.hasMore()) {
          await _loadMoreAndRebuild(
            startIndexAfterAppend: playlist.length,
            initialPosition: Duration.zero,
            autoPlay: true,
          );
          return;
        }
        await playAt(0);
        return;
      }
    }

    final next = idx + 1;
    if (next >= 0 && next < playlist.length) {
      await playAt(next);
    }
  }
}
