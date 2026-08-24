import 'package:flutter/material.dart';
import '../beans/video_item_bean.dart';
import 'video_item_common.dart';
import '../../../../core/routes/app_routes.dart';
import '../video_utils/video_utils.dart';
import '../video_utils/video_item_utils.dart';
import '../../favorite/service/video_favorite_api_service.dart';

class VideoItemPoster extends StatefulWidget {
  final VideoHomeItemBean item;
  final double width;
  final double borderRadius;
  final double imageRadius;
  final EdgeInsets contentPadding;
  final double? progress;
  final int? currentAlbumId;
  final VoidCallback? onRemovedFromCurrentAlbum;
  final VoidCallback? onTap;
  final VoidCallback? onTitleTap;
  final ValueChanged<bool>? onFavoriteChanged;
  final ValueChanged<VideoHomeItemBean>? onDeleted;

  const VideoItemPoster({
    super.key,
    required this.item,
    this.width = 192,
    this.borderRadius = 16,
    this.imageRadius = 12,
    this.contentPadding = const EdgeInsets.all(10),
    this.progress,
    this.currentAlbumId,
    this.onRemovedFromCurrentAlbum,
    this.onTap,
    this.onTitleTap,
    this.onFavoriteChanged,
    this.onDeleted,
  });

  @override
  State<VideoItemPoster> createState() => _VideoItemPosterState();
}

class _VideoItemPosterState extends State<VideoItemPoster> {
  bool _hovered = false;
  bool? _isFavorite;
  bool _favoriteLoading = false;

  bool get _effectiveFavorite => _isFavorite ?? widget.item.isFavorite;

  @override
  void didUpdateWidget(covariant VideoItemPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.isFavorite != widget.item.isFavorite) {
      if (_isFavorite == null) return;
      _isFavorite = null;
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) return;
    final id = widget.item.id;
    if (id <= 0) return;

    final prev = _effectiveFavorite;
    final next = !prev;

    setState(() {
      _favoriteLoading = true;
      _isFavorite = next;
    });

    try {
      final ok = next
          ? await VideoFavoriteApiService.instance.addFavorite(id)
          : await VideoFavoriteApiService.instance.removeFavorite(id);
      if (!ok) {
        setState(() {
          _isFavorite = prev;
        });
        return;
      }
      widget.onFavoriteChanged?.call(next);
    } finally {
      if (mounted) {
        setState(() {
          _favoriteLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final title = item.nfoName.isNotEmpty ? item.nfoName : item.filename;
    final year = item.nfoYear > 0 ? item.nfoYear.toString() : '';
    final posterUrl = VideoUtils.getPosterUrl(item, size: 500);

    final p = widget.progress;
    final safeProgress = p?.clamp(0, 1).toDouble();

    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap ?? () => AppRoutes.toVideoDetail(item.id),
            child: Container(
              padding: widget.contentPadding,
              decoration: BoxDecoration(
                // color: theme.colorScheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoItemCoverImage(
                          imageUrl: posterUrl,
                          borderRadius: widget.imageRadius,
                          rating: item.nfoScore,
                          typeText: videoMediaTypeText(item.mediaType),
                          hovered: _hovered,
                        ),
                        if (_hovered || _effectiveFavorite)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: _toggleFavorite,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface.withValues(
                                      alpha: 0.75,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: Icon(
                                    _effectiveFavorite
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 18,
                                    color: _effectiveFavorite
                                        ? Colors.red
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (safeProgress != null && safeProgress > 0)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: FractionallySizedBox(
                                  widthFactor: 0.8,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: safeProgress,
                                      minHeight: 5,
                                      backgroundColor: theme
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.12),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (safeProgress != null)
                    const SizedBox(height: 10)
                  else
                    const SizedBox(height: 4),
                  InkWell(
                    // onTap:
                    //     widget.onTitleTap ??
                    //     () => AppRoutes.toVideoDetail(item.id),
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  if (year.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      year,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final itemOpen = widget.onTap ?? () => AppRoutes.toVideoDetail(item.id);
    return VideoItemContextMenuRegion(
      item: item,
      onOpen: itemOpen,
      onDeleted: widget.onDeleted,
      currentAlbumId: widget.currentAlbumId,
      onRemovedFromCurrentAlbum: widget.onRemovedFromCurrentAlbum,
      child: child,
    );
  }
}
