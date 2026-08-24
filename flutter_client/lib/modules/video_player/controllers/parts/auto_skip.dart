part of '../video_player_controller.dart';

extension PlayerAutoSkip on PlayerController {
  int _parseAutoSkipSeconds(dynamic value) {
    if (value is num) return value.isNegative ? 0 : value.floor();
    return int.tryParse(value?.toString() ?? '')?.clamp(0, 1 << 30) ?? 0;
  }

  void _resetAutoSkipState({bool clearSegments = false}) {
    if (clearSegments) {
      _openSkipStartSeconds = 0;
      _openSkipEndSeconds = 0;
    }
    _didApplyResumeForCurrentSource = false;
    _skipIntroConsumed = false;
    _skipOutroConsumed = false;
    _skipOutroSuppressedByResume = false;
  }

  void _applyOpenSkipData(dynamic raw) {
    var startSec = 0;
    var endSec = 0;
    if (raw is Map) {
      final data = raw.cast<String, dynamic>();
      startSec = _parseAutoSkipSeconds(data['startSec'] ?? data['start_sec']);
      endSec = _parseAutoSkipSeconds(data['endSec'] ?? data['end_sec']);
    }
    _openSkipStartSeconds = startSec;
    _openSkipEndSeconds = endSec;
    _didApplyResumeForCurrentSource = false;
    _skipIntroConsumed = false;
    _skipOutroConsumed = false;
    _skipOutroSuppressedByResume = false;
  }

  void _markResumeApplied(Duration target) {
    _didApplyResumeForCurrentSource = true;
    _skipIntroConsumed = true;
    final total = duration.value;
    if (_openSkipEndSeconds <= 0 || total <= Duration.zero) return;
    final outroStart = total - Duration(seconds: _openSkipEndSeconds);
    if (outroStart <= Duration.zero) return;
    if (target >= outroStart) {
      _skipOutroSuppressedByResume = true;
      _skipOutroConsumed = true;
    }
  }

  void _handleAutoSkipPositionChanged(Duration currentPosition) {
    if (isClosed || _isClosingPlayer) return;
    if (!isInitialized.value || !isPlaying.value) return;

    final total = duration.value;
    if (total <= Duration.zero) return;

    if (!_skipIntroConsumed && !_didApplyResumeForCurrentSource) {
      final startSec = _openSkipStartSeconds;
      if (startSec > 0) {
        final introTarget = Duration(seconds: startSec);
        if (introTarget >= total) {
          _skipIntroConsumed = true;
        } else if (currentPosition < introTarget) {
          _skipIntroConsumed = true;
          unawaited(_triggerIntroAutoSkip(introTarget));
          return;
        } else {
          _skipIntroConsumed = true;
        }
      }
    }

    if (_skipOutroConsumed || _skipOutroSuppressedByResume) return;
    final endSec = _openSkipEndSeconds;
    if (endSec <= 0) return;
    final outroStart = total - Duration(seconds: endSec);
    if (outroStart <= Duration.zero) return;
    if (currentPosition >= outroStart) {
      _skipOutroConsumed = true;
      unawaited(_triggerOutroAutoSkip());
    }
  }

  Future<void> _triggerIntroAutoSkip(Duration target) async {
    if (isClosed || _isClosingPlayer) return;
    if (!isInitialized.value || !isPlaying.value) return;
    final current = position.value;
    if (target <= current + const Duration(milliseconds: 500)) return;
    ToastUtil.show('player_skip_opening'.tr);
    seekTo(target);
  }

  Future<void> _triggerOutroAutoSkip() async {
    if (isClosed || _isClosingPlayer) return;
    if (!isInitialized.value) return;

    final hasNextBehavior =
        loopMode.value == 'single' ||
        loopMode.value == 'shuffle' ||
        loopMode.value == 'all' ||
        currentIndex.value < playlist.length - 1;
    if (hasNextBehavior) {
      ToastUtil.show('player_skip_ending'.tr);
      _handlePlaybackComplete();
      return;
    }

    final engine = playbackEngine.value;
    if (engine == null) return;
    await pausePlayback();
    ToastUtil.show('player_skip_ending'.tr);
    isPlaying.value = false;
    position.value = duration.value;
    try {
      await engine.seekTo(duration.value);
    } catch (_) {}
  }
}
