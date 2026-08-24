part of '../music_play_service_controller.dart';

class _MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final MusicPlayServiceController controller;
  bool? _lastPlaying;
  AudioProcessingState? _lastProcessingState;
  int? _lastQueueIndex;
  DateTime? _lastPositionUpdate;

  _MusicAudioHandler(this.controller);

  @override
  Future<void> skipToQueueItem(int index) async {
    await controller.playAt(index);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        if (controller.loopMode.value != MusicLoopMode.shuffle) {
          await controller.setLoopMode(MusicLoopMode.sequence);
        }
        return;
      case AudioServiceRepeatMode.one:
        await controller.setLoopMode(MusicLoopMode.singleLoop);
        return;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        if (controller.loopMode.value != MusicLoopMode.shuffle) {
          await controller.setLoopMode(MusicLoopMode.listLoop);
        }
        return;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    if (enable) {
      await controller.setLoopMode(MusicLoopMode.shuffle);
      return;
    }
    if (controller.loopMode.value == MusicLoopMode.shuffle) {
      final repeat = playbackState.value.repeatMode;
      switch (repeat) {
        case AudioServiceRepeatMode.one:
          await controller.setLoopMode(MusicLoopMode.singleLoop);
          return;
        case AudioServiceRepeatMode.all:
        case AudioServiceRepeatMode.group:
          await controller.setLoopMode(MusicLoopMode.listLoop);
          return;
        case AudioServiceRepeatMode.none:
          await controller.setLoopMode(MusicLoopMode.sequence);
          return;
      }
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    queue.add(newQueue);
  }

  @override
  Future<void> play() async {
    await controller.play();
  }

  @override
  Future<void> pause() async {
    await controller.pause();
  }

  @override
  Future<void> stop() async {
    await controller.stop();
    await super.stop();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button == MediaButton.media) {
      final playing = controller._player?.isPlaying ?? controller.isPlaying.value;
      if (playing) {
        await pause();
      } else {
        await play();
      }
      return;
    }
    await super.click(button);
  }

  @override
  Future<void> seek(Duration position) async {
    await controller.seekTo(position);
  }

  @override
  Future<void> skipToNext() async {
    try {
      await controller.playNext(forcePlay: true);
    } catch (_) {
      controller._syncHandlerPlaybackState();
      rethrow;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      await controller.playPrevious(forcePlay: true);
    } catch (_) {
      controller._syncHandlerPlaybackState();
      rethrow;
    }
  }

  void _syncPlaybackState({
    required bool playing,
    required AudioProcessingState processingState,
    required Duration updatePosition,
    required Duration bufferedPosition,
    required int queueIndex,
  }) {
    final playingChanged = _lastPlaying != playing;
    final stateChanged = _lastProcessingState != processingState;
    final indexChanged = _lastQueueIndex != queueIndex;
    final criticalChanged = playingChanged || stateChanged || indexChanged;

    final now = DateTime.now();
    final lastUpdate = _lastPositionUpdate;
    final positionUpdateInterval = const Duration(seconds: 1);
    final shouldUpdatePosition =
        lastUpdate == null ||
        now.difference(lastUpdate) >= positionUpdateInterval;

    _lastPlaying = playing;
    _lastProcessingState = processingState;
    _lastQueueIndex = queueIndex;
    if (criticalChanged || shouldUpdatePosition) {
      _lastPositionUpdate = now;
    }

    final mode = controller.loopMode.value;
    final repeatMode = switch (mode) {
      MusicLoopMode.singleLoop => AudioServiceRepeatMode.one,
      MusicLoopMode.listLoop => AudioServiceRepeatMode.all,
      MusicLoopMode.shuffle => AudioServiceRepeatMode.all,
      MusicLoopMode.sequence => AudioServiceRepeatMode.none,
    };
    final shuffleMode = mode == MusicLoopMode.shuffle
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;
    final controls = [
      MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ];

    // 首次同步或关键状态变化时强制更新，确保 OPPO ColorOS 能正确接收状态
    final isFirstSync = _lastPlaying == null || _lastProcessingState == null;
    if (isFirstSync || criticalChanged || shouldUpdatePosition) {
      playbackState.add(
        PlaybackState(
          controls: controls,
          systemActions: const {
            MediaAction.play,
            MediaAction.pause,
            MediaAction.playPause,
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
            MediaAction.skipToNext,
            MediaAction.skipToPrevious,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: processingState,
          playing: playing,
          updatePosition: updatePosition,
          bufferedPosition: bufferedPosition,
          speed: 1.0,
          queueIndex: queueIndex,
          repeatMode: repeatMode,
          shuffleMode: shuffleMode,
        ),
      );
    }
  }
}
