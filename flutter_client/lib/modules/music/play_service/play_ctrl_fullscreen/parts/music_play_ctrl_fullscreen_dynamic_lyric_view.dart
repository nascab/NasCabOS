import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_lyric/core/lyric_style.dart';

double resolveMusicPlayCtrlFullScreenDynamicLyricHighlightProgress({
  required Duration progress,
  required Duration start,
  required Duration? end,
  required Duration? nextStart,
}) {
  final resolvedEnd =
      end ?? nextStart ?? start + const Duration(milliseconds: 450);
  if (progress < start) {
    return 0;
  }
  if (resolvedEnd <= start) {
    return progress >= start ? 1 : 0;
  }
  if (progress >= resolvedEnd) {
    return 1;
  }
  final total = resolvedEnd.inMilliseconds - start.inMilliseconds;
  final current = progress.inMilliseconds - start.inMilliseconds;
  return Curves.easeOut.transform((current / total).clamp(0, 1));
}

class MusicPlayCtrlFullScreenDynamicLyricView extends StatefulWidget {
  final LyricController controller;
  final LyricModel model;
  final LyricStyle style;
  final bool centerMode;
  final Future<void> Function(Duration position) onSeekTo;

  const MusicPlayCtrlFullScreenDynamicLyricView({
    super.key,
    required this.controller,
    required this.model,
    required this.style,
    required this.centerMode,
    required this.onSeekTo,
  });

  @override
  State<MusicPlayCtrlFullScreenDynamicLyricView> createState() =>
      _MusicPlayCtrlFullScreenDynamicLyricViewState();
}

class _MusicPlayCtrlFullScreenDynamicLyricViewState
    extends State<MusicPlayCtrlFullScreenDynamicLyricView> {
  late List<GlobalKey> _lineKeys;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _lineKeys = List.generate(widget.model.lines.length, (_) => GlobalKey());
    widget.controller.activeIndexNotifiter.addListener(_handleActiveIndexChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureActiveLineVisible();
    });
  }

  @override
  void didUpdateWidget(
    covariant MusicPlayCtrlFullScreenDynamicLyricView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _lastActiveIndex = -1;
      _lineKeys = List.generate(widget.model.lines.length, (_) => GlobalKey());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureActiveLineVisible();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.activeIndexNotifiter.removeListener(
      _handleActiveIndexChanged,
    );
    super.dispose();
  }

  void _handleActiveIndexChanged() {
    _ensureActiveLineVisible();
  }

  void _ensureActiveLineVisible() {
    final index = widget.controller.activeIndexNotifiter.value;
    if (!mounted || index < 0 || index >= _lineKeys.length) return;
    if (_lastActiveIndex == index) return;
    _lastActiveIndex = index;
    final context = _lineKeys[index].currentContext;
    if (context == null) return;
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignment: 0.32,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.progressNotifier,
      builder: (context, progress, child) {
        return ValueListenableBuilder<int>(
          valueListenable: widget.controller.activeIndexNotifiter,
          builder: (context, activeIndex, child) {
            return SingleChildScrollView(
              child: Padding(
                padding: widget.centerMode
                    ? const EdgeInsets.fromLTRB(0, 64, 0, 20)
                    : const EdgeInsets.fromLTRB(0, 64, 10, 20),
                child: Column(
                  crossAxisAlignment: widget.centerMode
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: List.generate(widget.model.lines.length, (index) {
                    final line = widget.model.lines[index];
                    final isActive = index == activeIndex;
                    return KeyedSubtree(
                      key: _lineKeys[index],
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => unawaited(widget.onSeekTo(line.start)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: widget.centerMode
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.start,
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 160),
                                opacity: isActive ? 1 : 0.9,
                                child: _buildLineText(line, progress, isActive),
                              ),
                              if ((line.translation ?? '').trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    line.translation!,
                                    textAlign: widget.centerMode
                                        ? TextAlign.center
                                        : TextAlign.left,
                                    style: widget.style.translationStyle.copyWith(
                                      color: isActive
                                          ? widget.style.translationStyle.color
                                          : widget.style.translationStyle.color
                                                ?.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLineText(LyricLine line, Duration progress, bool isActive) {
    final baseStyle = widget.style.textStyle;
    final activeStyle = widget.style.activeStyle;
    final highlightColor = activeStyle.color ?? Colors.white;
    if (!isActive || line.words == null || line.words!.isEmpty) {
      return Text(
        line.text,
        textAlign: widget.centerMode ? TextAlign.center : TextAlign.left,
        style: isActive ? activeStyle : baseStyle,
      );
    }

    final spans = <InlineSpan>[];
    final words = line.words!;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final nextStart = i + 1 < words.length ? words[i + 1].start : null;
      final highlightProgress =
          resolveMusicPlayCtrlFullScreenDynamicLyricHighlightProgress(
        progress: progress,
        start: word.start,
        end: word.end,
        nextStart: nextStart,
      );
      final inactiveActiveLineColor =
          activeStyle.color?.withValues(alpha: 0.36) ??
          baseStyle.color?.withValues(alpha: 0.36) ??
          Colors.white.withValues(alpha: 0.36);
      final color = Color.lerp(
        inactiveActiveLineColor,
        highlightColor,
        highlightProgress,
      );
      spans.add(
        TextSpan(
          text: word.text,
          style: activeStyle.copyWith(
            fontSize: activeStyle.fontSize,
            color: color,
            fontWeight: activeStyle.fontWeight,
          ),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: widget.centerMode ? TextAlign.center : TextAlign.left,
    );
  }
}
