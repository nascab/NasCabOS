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
    await ApiController.instance.refreshAuthToken();
    await _ensurePlaylistUpToDate(force: true);
  }
}
