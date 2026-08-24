import 'dart:math';
import 'dart:ui';

import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';

import '../../../../../utils/format_util.dart';
import '../../../list/models/music_list_models.dart';
import '../../controller/music_play_service_controller.dart';
import '../../play_ctrl_bottom/parts/music_play_ctrl_bottom_center_area.dart';
import '../../play_ctrl_bottom/parts/music_play_ctrl_bottom_left_area.dart';
import '../../play_ctrl_bottom/parts/music_play_ctrl_bottom_volume_control.dart';

class MusicPlayCtrlFullScreenBottomBar extends StatefulWidget {
  final MusicPlayServiceController controller;
  final MusicListItem item;
  final bool isPlaying;
  final String discAsset;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final IconData loopIcon;
  final MusicLoopMode loopMode;
  final double volume;
  final bool favoriteLoading;
  final String coverUrl;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onToggleLoopMode;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback? onAddToPlayList;
  final ValueChanged<double> onVolumeChanged;
  final Future<void> Function(Duration position) onSeekTo;

  const MusicPlayCtrlFullScreenBottomBar({
    super.key,
    required this.controller,
    required this.item,
    required this.isPlaying,
    required this.discAsset,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.loopIcon,
    required this.loopMode,
    required this.volume,
    required this.favoriteLoading,
    required this.coverUrl,
    required this.onToggleFavorite,
    required this.onToggleLoopMode,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
    required this.onAddToPlayList,
    required this.onVolumeChanged,
    required this.onSeekTo,
  });

  @override
  State<MusicPlayCtrlFullScreenBottomBar> createState() =>
      _MusicPlayCtrlFullScreenBottomBarState();
}

class _MusicPlayCtrlFullScreenBottomBarState
    extends State<MusicPlayCtrlFullScreenBottomBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNarrow = DeviceUtils.isMobile;

    final decoration = BoxDecoration(
      color: isNarrow
          ? Colors.black.withValues(alpha: 0.15)
          : Colors.black.withValues(alpha: 0.28),
      border: Border(
        top: BorderSide(
          color: Colors.white.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
    );

    final blurSigma = isNarrow ? 50.0 : 24.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(decoration: decoration),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (ctx, c) {
              final isNarrow = DeviceUtils.isMobile;
              final downloading =
                  widget.controller.isDownloading.value &&
                  widget.controller.downloadingFileHash.value
                      .trim()
                      .isNotEmpty &&
                  widget.controller.downloadingFileHash.value.trim() ==
                      widget.item.fileHash.trim();
              final downloadProgress = downloading
                  ? widget.controller.downloadProgress.value
                  : 0.0;

              final subtitle = widget.item.isSeries
                  ? ''
                  : widget.item.artist.trim().isNotEmpty
                  ? widget.item.artist.trim()
                  : widget.item.album.trim();
              final subtitleColor = theme.colorScheme.onSurface.withValues(
                alpha: 0.6,
              );
              final progressText = downloading
                  ? '${(downloadProgress.clamp(0, 1) * 100).toStringAsFixed(0)}%'
                  : '';

              final titleRow = Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MusicPlayCtrlBottomMarqueeText(
                      text: widget.item.displayTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (progressText.isNotEmpty)
                          Text(
                            progressText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subtitleColor,
                            ),
                          ),
                        if (progressText.isNotEmpty) const SizedBox(width: 8),
                        if (subtitle.isNotEmpty)
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: subtitleColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );

              final controls = MusicPlayCtrlBottomCenterControls(
                isPlaying: widget.isPlaying,
                loopMode: widget.loopMode,
                loopIcon: widget.loopIcon,
                onToggleLoopMode: widget.onToggleLoopMode,
                onPrev: widget.onPrev,
                onNext: widget.onNext,
                onPlayPause: widget.onPlayPause,
                onAddToPlayList: widget.onAddToPlayList,
                isNarrow: isNarrow,
              );

              final seekBar = _FullScreenHoverSeekBar(
                position: widget.position,
                duration: widget.duration,
                buffered: widget.buffered,
                onSeekTo: widget.onSeekTo,
                isNarrow: isNarrow,
                showTimeLabels: isNarrow,
              );

              if (isNarrow) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleRow,
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: seekBar,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Center(child: controls),
                    ),
                  ],
                );
              }

              final left = MusicPlayCtrlBottomLeftArea(
                item: widget.item,
                isPlaying: widget.isPlaying,
                favoriteLoading: widget.favoriteLoading,
                downloading: downloading,
                downloadProgress: downloadProgress,
                coverUrl: widget.coverUrl,
                discAsset: widget.discAsset,
                onToggleFavorite: widget.onToggleFavorite,
                onOpenFullscreen: null,
              );

              final vol = MusicPlayCtrlBottomVolumeControl(
                volume: widget.volume,
                onChanged: widget.onVolumeChanged,
                onToggleMute: widget.controller.toggleMute,
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  seekBar,
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: left),
                        Expanded(flex: 5, child: Center(child: controls)),
                        Expanded(
                          flex: 3,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: vol,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FullScreenHoverSeekBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Future<void> Function(Duration position) onSeekTo;
  final bool isNarrow;
  final bool showTimeLabels;

  const _FullScreenHoverSeekBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeekTo,
    this.isNarrow = false,
    this.showTimeLabels = false,
  });

  @override
  State<_FullScreenHoverSeekBar> createState() =>
      _FullScreenHoverSeekBarState();
}

class _FullScreenHoverSeekBarState extends State<_FullScreenHoverSeekBar> {
  bool _hover = false;
  bool _dragging = false;
  double _dragValueMs = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durMs = widget.duration.inMilliseconds;
    final maxMs = (durMs <= 0 ? 1 : durMs).toDouble();
    final posMs = widget.position.inMilliseconds.toDouble().clamp(0.0, maxMs);
    final enabled = durMs > 0;
    final value = _dragging ? _dragValueMs.clamp(0.0, maxMs) : posMs;

    final showOverlay = _hover || _dragging;
    final posText = FormatUtil.formatDuration(
      Duration(milliseconds: value.round()),
      autoPadZero: true,
    );
    final durText = FormatUtil.formatDuration(
      widget.duration,
      autoPadZero: true,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: showOverlay ? 1 : 0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          final baseTrackHeight = widget.isNarrow ? 6 : 2;
          final maxTrackHeight = widget.isNarrow ? 8 : 4;
          final baseThumbRadius = widget.isNarrow ? 8 : 4;
          final maxThumbRadius = widget.isNarrow ? 10 : 8;
          final baseOverlayRadius = widget.isNarrow ? 16 : 10;
          final maxOverlayRadius = widget.isNarrow ? 18 : 14;
          final sliderBoxHeight = widget.isNarrow ? 18.0 : 12.0;

          final trackHeight =
              baseTrackHeight + (maxTrackHeight - baseTrackHeight) * t;
          final thumbRadius =
              baseThumbRadius + (maxThumbRadius - baseThumbRadius) * t;
          final overlayRadius =
              baseOverlayRadius + (maxOverlayRadius - baseOverlayRadius) * t;
          final sliderTop = -(sliderBoxHeight / 2);
          final textStyle =
              theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ) ??
              const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              );
          final smallTextStyle = theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          );
          final tooltipText = '$posText / $durText';
          final textPainter = TextPainter(
            text: TextSpan(text: tooltipText, style: textStyle),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final tooltipWidth = textPainter.width + 32;
          final tooltipHeight = textPainter.height + 16;

          final cornerRadius = widget.isNarrow ? 4.0 : 0.0;

          final sliderWidget = SizedBox(
            height: sliderBoxHeight,
            child: LayoutBuilder(
              builder: (context, c) {
                final fraction = (value / maxMs).clamp(0.0, 1.0);
                final thumbX = c.maxWidth * fraction;
                final tooltipLeft = min(
                  max(0.0, thumbX - tooltipWidth / 2),
                  max(0.0, c.maxWidth - tooltipWidth),
                );

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: sliderTop,
                      height: sliderBoxHeight,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: trackHeight,
                          overlayShape: RoundSliderOverlayShape(
                            overlayRadius: overlayRadius,
                          ),
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: thumbRadius,
                          ),
                          trackShape: _FullWidthRectTrackShape(
                            useRoundedCorners: widget.isNarrow,
                            cornerRadius: cornerRadius,
                          ),
                          activeTrackColor: theme.colorScheme.primary,
                          inactiveTrackColor: theme.dividerColor.withValues(
                            alpha: 0.42,
                          ),
                          thumbColor: theme.colorScheme.primary,
                        ),
                        child: Slider(
                          value: value,
                          min: 0,
                          max: maxMs,
                          onChanged: enabled
                              ? (v) => setState(() {
                                  _dragging = true;
                                  _dragValueMs = v;
                                })
                              : null,
                          onChangeStart: enabled
                              ? (v) => setState(() {
                                  _dragging = true;
                                  _dragValueMs = v;
                                })
                              : null,
                          onChangeEnd: enabled
                              ? (v) async {
                                  setState(() {
                                    _dragging = false;
                                    _dragValueMs = v;
                                  });
                                  await widget.onSeekTo(
                                    Duration(milliseconds: v.round()),
                                  );
                                }
                              : null,
                        ),
                      ),
                    ),
                    Positioned(
                      left: tooltipLeft,
                      top: -tooltipHeight - 10,
                      width: tooltipWidth,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: showOverlay ? 1 : 0,
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(tooltipText, style: textStyle),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );

          if (widget.showTimeLabels) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                sliderWidget,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(posText, style: smallTextStyle),
                    Text(durText, style: smallTextStyle),
                  ],
                ),
              ],
            );
          }

          return sliderWidget;
        },
      ),
    );
  }
}

class _FullWidthRectTrackShape extends RectangularSliderTrackShape {
  final bool useRoundedCorners;
  final double cornerRadius;

  const _FullWidthRectTrackShape({
    this.useRoundedCorners = false,
    this.cornerRadius = 4.0,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    if (!useRoundedCorners) {
      super.paint(
        context,
        offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        secondaryOffset: secondaryOffset,
        isEnabled: isEnabled,
        isDiscrete: isDiscrete,
      );
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final ColorTween activeTrackColorTween = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    );
    final ColorTween inactiveTrackColorTween = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    );
    final Paint activePaint = Paint()
      ..color = activeTrackColorTween.evaluate(enableAnimation)!;
    final Paint inactivePaint = Paint()
      ..color = inactiveTrackColorTween.evaluate(enableAnimation)!;

    final Paint leftTrackPaint;
    final Paint rightTrackPaint;
    switch (textDirection) {
      case TextDirection.ltr:
        leftTrackPaint = activePaint;
        rightTrackPaint = inactivePaint;
      case TextDirection.rtl:
        leftTrackPaint = inactivePaint;
        rightTrackPaint = activePaint;
    }

    final RRect leftRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        trackRect.left,
        trackRect.top,
        thumbCenter.dx - trackRect.left,
        trackRect.height,
      ),
      topLeft: Radius.circular(cornerRadius),
      bottomLeft: Radius.circular(cornerRadius),
    );
    final RRect rightRRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        thumbCenter.dx,
        trackRect.top,
        trackRect.right - thumbCenter.dx,
        trackRect.height,
      ),
      topRight: Radius.circular(cornerRadius),
      bottomRight: Radius.circular(cornerRadius),
    );

    context.canvas.drawRRect(leftRRect, leftTrackPaint);
    context.canvas.drawRRect(rightRRect, rightTrackPaint);
  }
}
