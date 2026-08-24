import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../list/models/music_list_models.dart';
import '../../app_components/music_play_disc_cover.dart';

class MusicPlayCtrlBottomLeftArea extends StatelessWidget {
  final MusicListItem item;
  final bool isPlaying;
  final bool favoriteLoading;
  final bool downloading;
  final double downloadProgress;
  final String coverUrl;
  final String discAsset;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onOpenFullscreen;

  const MusicPlayCtrlBottomLeftArea({
    super.key,
    required this.item,
    required this.isPlaying,
    required this.favoriteLoading,
    required this.downloading,
    required this.downloadProgress,
    required this.coverUrl,
    required this.discAsset,
    required this.onToggleFavorite,
    this.onOpenFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = item.isSeries ? '' : item.artist.trim();
    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final progressText = downloading
        ? '${(downloadProgress.clamp(0, 1) * 100).toStringAsFixed(0)}%'
        : '';
    final canShowIndexActions =
        item.id > 0 &&
        !item.isFromFile &&
        item.showType.trim().toLowerCase() != 'file_browser';

    final title = MusicPlayCtrlBottomMarqueeText(
      text: item.displayTitle,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );

    final meta = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: double.infinity, child: title),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            if (canShowIndexActions && onToggleFavorite != null) ...[
              IconButton(
                tooltip: item.isFavorite ? 'unfavorite'.tr : 'favorites'.tr,
                onPressed: favoriteLoading ? null : onToggleFavorite,
                icon: favoriteLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 1,
                          color: Colors.red,
                        ),
                      )
                    : Icon(
                        item.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 18,
                        color: item.isFavorite ? Colors.red : subtitleColor,
                      ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              const SizedBox(width: 6),
            ],
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
    );

    return Row(
      children: [
        MusicPlayDiscCover(
          coverUrl: coverUrl,
          isPlaying: isPlaying,
          discAsset: discAsset,
          onTap: onOpenFullscreen,
        ),
        const SizedBox(width: 10),
        Expanded(child: meta),
      ],
    );
  }
}

class MusicPlayCtrlBottomMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const MusicPlayCtrlBottomMarqueeText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<MusicPlayCtrlBottomMarqueeText> createState() =>
      _MusicPlayCtrlBottomMarqueeTextState();
}

class _MusicPlayCtrlBottomMarqueeTextState
    extends State<MusicPlayCtrlBottomMarqueeText> {
  final ScrollController _scrollController = ScrollController();
  int _runId = 0;
  String _lastText = '';
  double _lastAvailable = -1;
  bool _running = false;

  @override
  void dispose() {
    _runId++;
    _scrollController.dispose();
    super.dispose();
  }

  double _measureTextWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  Future<void> _start(int runId) async {
    _running = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      while (mounted && _runId == runId && _scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        if (max <= 0) break;
        await _scrollController.animateTo(
          max,
          duration: Duration(milliseconds: max.round() * 28),
          curve: Curves.linear,
        );
        if (!mounted || _runId != runId || !_scrollController.hasClients) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted || _runId != runId || !_scrollController.hasClients) {
          return;
        }
        _scrollController.jumpTo(0);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      if (mounted && _runId == runId) {
        _running = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        if (available <= 0) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        final textWidth = _measureTextWidth(context);
        final shouldScroll = textWidth > available + 2;
        final textChanged = _lastText != widget.text;
        final widthChanged = (_lastAvailable - available).abs() > 0.5;
        _lastText = widget.text;
        _lastAvailable = available;

        if (!shouldScroll) {
          if (_running || textChanged || widthChanged) {
            _runId++;
            _running = false;
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          }
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        if ((textChanged || widthChanged) && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }

        if ((textChanged || widthChanged) && !_running) {
          final id = ++_runId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_runId != id) return;
            if (!_scrollController.hasClients) return;
            _scrollController.jumpTo(0);
            unawaited(_start(id));
          });
        }

        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _scrollController,
            physics: const NeverScrollableScrollPhysics(),
            child: Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: widget.style,
            ),
          ),
        );
      },
    );
  }
}
