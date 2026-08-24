import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../utils/format_util.dart';
import '../../controller/music_play_service_controller.dart';

class MusicPlayCtrlBottomCenterArea extends StatelessWidget {
  final bool isPlaying;
  final MusicLoopMode loopMode;
  final IconData loopIcon;
  final VoidCallback onToggleLoopMode;
  final bool showLoopButton;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback? onAddToPlayList;
  final bool showAddToPlayListButton;

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool dragging;
  final double dragValueMs;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  const MusicPlayCtrlBottomCenterArea({
    super.key,
    required this.isPlaying,
    required this.loopMode,
    required this.loopIcon,
    required this.onToggleLoopMode,
    this.showLoopButton = true,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
    required this.onAddToPlayList,
    this.showAddToPlayListButton = true,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.dragging,
    required this.dragValueMs,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MusicPlayCtrlBottomCenterControls(
            isPlaying: isPlaying,
            loopMode: loopMode,
            loopIcon: loopIcon,
            onToggleLoopMode: onToggleLoopMode,
            showLoopButton: showLoopButton,
            onPrev: onPrev,
            onNext: onNext,
            onPlayPause: onPlayPause,
            onAddToPlayList: onAddToPlayList,
            showAddToPlayListButton: showAddToPlayListButton,
          ),
          MusicPlayCtrlBottomSeekBarWithTime(
            position: position,
            duration: duration,
            buffered: buffered,
            dragging: dragging,
            dragValueMs: dragValueMs,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class MusicPlayCtrlBottomSeekBarWithTime extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool dragging;
  final double dragValueMs;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  const MusicPlayCtrlBottomSeekBarWithTime({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.dragging,
    required this.dragValueMs,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durMs = duration.inMilliseconds;
    final maxMs = max(1, durMs).toDouble();
    final posMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final value = dragging ? dragValueMs.clamp(0.0, maxMs) : posMs;
    final enabled = durMs > 0;

    final leftLabel = FormatUtil.formatDuration(
      Duration(milliseconds: value.round()),
      autoPadZero: true,
    );
    final rightLabel = FormatUtil.formatDuration(duration, autoPadZero: true);

    return Row(
      children: [
        Text(
          leftLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: SizedBox(
            // height: 8,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.dividerColor.withValues(alpha: 0.5),
                thumbColor: theme.colorScheme.primary,
              ),
              child: Slider(
                value: value,
                min: 0,
                max: maxMs,
                onChanged: enabled ? onDragUpdate : null,
                onChangeStart: enabled ? onDragStart : null,
                onChangeEnd: enabled ? onDragEnd : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: 1),
        Text(
          rightLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class MusicPlayCtrlBottomCenterControls extends StatelessWidget {
  final bool isPlaying;
  final MusicLoopMode loopMode;
  final IconData loopIcon;
  final VoidCallback onToggleLoopMode;
  final bool showLoopButton;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback? onAddToPlayList;
  final bool showAddToPlayListButton;
  final bool isNarrow;

  const MusicPlayCtrlBottomCenterControls({
    super.key,
    required this.isPlaying,
    required this.loopMode,
    required this.loopIcon,
    required this.onToggleLoopMode,
    this.showLoopButton = true,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
    required this.onAddToPlayList,
    this.showAddToPlayListButton = true,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final loopTip = switch (loopMode) {
      MusicLoopMode.sequence => 'music_loop_sequence'.tr,
      MusicLoopMode.listLoop => 'music_loop_list_loop'.tr,
      MusicLoopMode.singleLoop => 'music_loop_single_loop'.tr,
      MusicLoopMode.shuffle => 'music_loop_shuffle'.tr,
    };

    final iconSize = isNarrow ? 32.0 : 24.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLoopButton)
          IconButton(
            tooltip: loopTip,
            onPressed: onToggleLoopMode,
            iconSize: iconSize,
            icon: Icon(loopIcon, size: iconSize),
          ),
        IconButton(
          tooltip: 'music_prev_track'.tr,
          onPressed: onPrev,
          iconSize: iconSize,
          icon: Icon(Icons.skip_previous, size: iconSize),
        ),
        MusicPlayCtrlBottomPlayPauseButton(
          isPlaying: isPlaying,
          onPressed: onPlayPause,
          isNarrow: isNarrow,
        ),
        IconButton(
          tooltip: 'music_next_track'.tr,
          onPressed: onNext,
          iconSize: iconSize,
          icon: Icon(Icons.skip_next, size: iconSize),
        ),
        if (showAddToPlayListButton && onAddToPlayList != null)
          IconButton(
            tooltip: 'add_to_play_list'.tr,
            onPressed: onAddToPlayList,
            iconSize: iconSize,
            icon: Icon(Icons.playlist_add, size: iconSize),
          ),
      ],
    );
  }
}

class MusicPlayCtrlBottomPlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final bool isNarrow;

  const MusicPlayCtrlBottomPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = isNarrow ? 46.8 : 36.0;
    return IconButton(
      tooltip: isPlaying ? 'pause'.tr : 'play'.tr,
      onPressed: onPressed,
      iconSize: size,
      icon: Icon(
        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
        color: theme.colorScheme.primary,
        size: size,
      ),
    );
  }
}
