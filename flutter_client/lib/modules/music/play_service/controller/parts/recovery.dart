part of '../music_play_service_controller.dart';

extension MusicPlayServiceRecovery on MusicPlayServiceController {
  void _scheduleStallRecoveryIfNeeded({required bool isBuffering}) {
    final stalling = isBuffering;
    if (!stalling || !_desiredPlaying) {
      _stallTimer?.cancel();
      _stallTimer = null;
      return;
    }
    if (_stallTimer != null) return;
    _stallTimer = Timer(const Duration(seconds: 12), () {
      _stallTimer = null;
      if (isClosed) return;
      final p = _player;
      final stillStalling = p != null && p.isBuffering;
      if (!stillStalling || !_desiredPlaying) return;
      unawaited(_attemptRecovery(reason: 'stall'));
    });
  }

  Future<void> _ensurePlaylistUpToDate({bool force = false}) async {
    if (playlist.isEmpty) return;
    final token = ApiController.instance.accessToken?.trim() ?? '';
    final last = _lastPlaylistAccessToken ?? '';
    if (!force && token == last) return;

    final idx = currentIndex.value.clamp(0, playlist.length - 1);
    final keepPos = position.value;
    final wasDesired = _desiredPlaying;
    final myToken = ++_rebuildToken;

    await _openTrack(idx, autoPlay: false, initialPosition: keepPos);
    if (isClosed || myToken != _rebuildToken) return;
    if (wasDesired) {
      await _player?.play();
    }
  }

  Future<void> _attemptRecovery({required String reason}) async {
    if (isClosed) return;
    if (playlist.isEmpty) return;
    final lastAt = _lastRecoveryAt;
    final now = DateTime.now();
    if (lastAt != null && now.difference(lastAt).inMilliseconds < 2000) {
      return;
    }
    _lastRecoveryAt = now;
    try {
      await ApiController.instance.refreshAuthToken();
      await _ensurePlaylistUpToDate(force: true);
    } catch (_) {
      // 恢复失败不向轮询抛出未处理异常，交给兜底重试继续尝试
      if (!isClosed && _desiredPlaying) _scheduleOpenRetry();
    }
  }

  /// 打开曲目失败后的兜底重试：间隔 8s，最多 5 次。
  /// 只要用户仍希望播放（_desiredPlaying），就继续尝试恢复，避免后台静默停止。
  void _scheduleOpenRetry() {
    if (isClosed || !_desiredPlaying || playlist.isEmpty) return;
    if (_openRetryTimer != null) return;
    if (_openRetryAttempt >= 5) return;
    _openRetryTimer = Timer(const Duration(seconds: 8), () {
      _openRetryTimer = null;
      if (isClosed || !_desiredPlaying || playlist.isEmpty) return;
      if (_player != null || _isOpeningTrack) return;
      _openRetryAttempt++;
      unawaited(
        _openTrack(
          currentIndex.value.clamp(0, playlist.length - 1),
          autoPlay: true,
        ).catchError((_) {}),
      );
    });
  }

  void _cancelOpenRetry() {
    _openRetryTimer?.cancel();
    _openRetryTimer = null;
  }

  /// P2P 模式下主动保持通道就绪，避免下一首自动切歌时因通道断开而建流失败。
  void _maybePrewarmP2p() {
    if (kIsWeb) return;
    final api = ApiController.instance;
    if (!api.isP2pMode || api.isP2pReady) return;
    final now = DateTime.now();
    final last = _lastP2pPrewarmAt;
    if (last != null && now.difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastP2pPrewarmAt = now;
    unawaited(() async {
      try {
        // 下一首已在本地缓存时无需为它建立 P2P 通道
        final next = currentIndex.value + 1;
        if (next >= 0 && next < playlist.length) {
          final hash = playlist[next].fileHash.trim();
          if (hash.isNotEmpty && await _audioCache.hasCached(hash)) return;
        }
        await api.ensureP2pConnected(timeout: const Duration(seconds: 12));
      } catch (_) {}
    }());
  }
}
