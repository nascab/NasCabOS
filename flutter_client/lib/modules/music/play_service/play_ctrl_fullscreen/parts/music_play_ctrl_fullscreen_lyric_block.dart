import 'dart:async';

import 'package:NasCabOS/modules/base/components/custom_outlined_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:get/get.dart';

import 'music_play_ctrl_fullscreen_dynamic_lyric_parser.dart';
import 'music_play_ctrl_fullscreen_dynamic_lyric_view.dart';
import 'music_play_ctrl_fullscreen_lyric_search_dialog.dart';

class MusicPlayCtrlFullScreenLyricBlock extends StatefulWidget {
  final String musicPath;
  final String title;
  final String album;
  final String artist;
  final String lyrics;
  final Duration trackDuration;
  final Duration position;
  final Future<void> Function(Duration position) onSeekTo;
  final bool centerMode;

  const MusicPlayCtrlFullScreenLyricBlock({
    super.key,
    required this.musicPath,
    required this.title,
    required this.album,
    required this.artist,
    required this.lyrics,
    required this.trackDuration,
    required this.position,
    required this.onSeekTo,
    this.centerMode = false,
  });

  @override
  State<MusicPlayCtrlFullScreenLyricBlock> createState() =>
      _MusicPlayCtrlFullScreenLyricBlockState();
}

class _MusicPlayCtrlFullScreenLyricBlockState
    extends State<MusicPlayCtrlFullScreenLyricBlock> {
  static const Color _lyricHighlightColor = Colors.white;
  late final LyricController _controller;
  LyricModel? _dynamicLyricModel;

  void _loadLyric(String lyric) {
    final parsed = MusicPlayCtrlFullScreenDynamicLyricParser.tryParse(lyric);
    if (parsed != null) {
      _dynamicLyricModel = parsed;
      _controller.loadLyricModel(parsed);
      return;
    }
    _dynamicLyricModel = null;
    _controller.loadLyric(lyric);
  }

  Future<void> _showLyricSearchDialog() async {
    final openedMusicPath = widget.musicPath;
    final lrc = await MusicPlayCtrlFullScreenLyricSearchDialog.show(
      context,
      musicPath: widget.musicPath,
      title: widget.title,
      artist: widget.artist,
      trackDuration: widget.trackDuration,
    );
    final next = (lrc ?? '').trim();
    if (next.isEmpty) return;
    if (!mounted || widget.musicPath != openedMusicPath) return;
    setState(() {
      _loadLyric(next);
    });
    _controller.setProgress(widget.position);
  }

  @override
  void initState() {
    super.initState();
    _controller = LyricController();
    _controller.setOnTapLineCallback((position) {
      unawaited(widget.onSeekTo(position));
    });
    final lyric = widget.lyrics.trim();
    if (lyric.isNotEmpty) {
      _loadLyric(lyric);
    }
    _controller.setProgress(widget.position);
  }

  @override
  void didUpdateWidget(covariant MusicPlayCtrlFullScreenLyricBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onSeekTo != oldWidget.onSeekTo) {
      _controller.setOnTapLineCallback((position) {
        unawaited(widget.onSeekTo(position));
      });
    }
    final nextLyric = widget.lyrics.trim();
    if (nextLyric != oldWidget.lyrics.trim()) {
      _loadLyric(nextLyric);
    }
    if (widget.position != oldWidget.position) {
      _controller.setProgress(widget.position);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  LyricStyle _buildLyricStyle(ThemeData theme) {
    final base = LyricStyles.default1;
    final normal = base.textStyle;
    final active = base.activeStyle;

    return base.copyWith(
      textAlign: widget.centerMode ? TextAlign.center : TextAlign.left,
      contentAlignment: widget.centerMode
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      highlightAlign: widget.centerMode
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      activeAlignment: widget.centerMode
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      fadeRange: FadeRange(
        top: (base.fadeRange?.top ?? 80) * 0.35,
        bottom: (base.fadeRange?.bottom ?? 80),
      ),
      contentPadding: widget.centerMode
          ? const EdgeInsets.fromLTRB(0, 64, 0, 20)
          : const EdgeInsets.fromLTRB(0, 64, 10, 20),
      activeHighlightColor: _lyricHighlightColor,
      textStyle: normal.copyWith(
        fontSize: (normal.fontSize ?? 16) + 2,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      activeStyle: active.copyWith(
        fontSize: (active.fontSize ?? 18) + 8,
        fontWeight: FontWeight.w700,
        color: _lyricHighlightColor,
      ),
      selectedColor: _lyricHighlightColor,
      translationStyle: (base.translationStyle).copyWith(
        fontSize: ((base.translationStyle).fontSize ?? 14) + 2,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );
  }

  Widget _buildLyricArea(ThemeData theme, {required double height}) {
    final lyricText = widget.lyrics.trim();
    final lyricStyle = _buildLyricStyle(theme);
    if (lyricText.isEmpty) {
      return Align(
        alignment: widget.centerMode ? Alignment.topCenter : Alignment.topLeft,
        child: Text(
          'music_no_lyric'.tr,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.5,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      );
    }

    if (_dynamicLyricModel != null) {
      return SizedBox(
        height: height,
        child: MusicPlayCtrlFullScreenDynamicLyricView(
          controller: _controller,
          model: _dynamicLyricModel!,
          style: lyricStyle,
          centerMode: widget.centerMode,
          onSeekTo: widget.onSeekTo,
        ),
      );
    }

    return LyricView(
      controller: _controller,
      style: lyricStyle,
      width: double.infinity,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget metaLine(String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '$label: $value',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded =
              constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

          final header = Column(
            crossAxisAlignment: widget.centerMode
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                textAlign: widget.centerMode
                    ? TextAlign.center
                    : TextAlign.left,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
                ),
              ),
              metaLine('music_label_album'.tr, widget.album),
              metaLine('music_label_singer'.tr, widget.artist),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: widget.centerMode
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  CustomOutlinedButton(
                    text: 'music_search_lyric'.tr,
                    icon: const Icon(Icons.search),
                    borderColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.65,
                    ),
                    foregroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.65,
                    ),
                    onPressed: _showLyricSearchDialog,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          );

          if (!bounded) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                SizedBox(
                  height: 360,
                  child: _buildLyricArea(theme, height: 360),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final h = c.maxHeight <= 0 ? 1.0 : c.maxHeight;
                    return _buildLyricArea(theme, height: h);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
