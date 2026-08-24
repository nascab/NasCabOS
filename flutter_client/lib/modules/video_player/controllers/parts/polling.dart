part of '../video_player_controller.dart';

extension PlayerPolling on PlayerController {
  void _stopPositionPolling() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    _isPollingPosition = false;
  }

  void _startPositionPolling() {
    _stopPositionPolling();
    _positionPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (isClosed) return;
      final engine = playbackEngine.value;
      if (engine == null || !isInitialized.value) return;
      if (currentQuality.value == 'original') return;
      if (_pendingTranscodeSeekSeconds != null) return;
      if (_isPollingPosition) return;
      _isPollingPosition = true;

      void applyPosition(Duration? pos) {
        if (isClosed) return;
        if (pos == null) return;
        final safePos = pos.isNegative ? Duration.zero : pos;
        position.value = _transcodeTimelinePosition(safePos);

        if (_sourceDurationSeconds != null && _sourceDurationSeconds! > 0) {
          duration.value = Duration(seconds: _sourceDurationSeconds!);
        } else if (engine.value.isInitialized) {
          duration.value = engine.value.duration;
        }

        if (engine.value.buffered.isNotEmpty) {
          final end = engine.value.buffered.last.end;
          buffered.value = _transcodeTimelinePosition(end);
        }
        _webUpdateActiveCue();
      }

      final fvc = engine.fvpVideoController;
      if (fvc != null) {
        unawaited(
          fvc.position
              .then(applyPosition)
              .whenComplete(() => _isPollingPosition = false),
        );
      } else {
        applyPosition(engine.value.position);
        _isPollingPosition = false;
      }
    });
  }
}
