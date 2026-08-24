import 'package:flutter/material.dart';
import '../../../base/components/custom_extended_image.dart';
import '../beans/video_item_bean.dart';
import 'video_item_common.dart';
import '../../../../core/routes/app_routes.dart';
import '../video_utils/video_utils.dart';
import '../video_utils/video_item_utils.dart';

class VideoItemRecommend extends StatefulWidget {
  final VideoHomeItemBean item;
  final double width;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;
  final ValueChanged<VideoHomeItemBean>? onDeleted;

  const VideoItemRecommend({
    super.key,
    required this.item,
    this.width = 330,
    this.height = 192,
    this.borderRadius = 16,
    this.onTap,
    this.onDeleted,
  });

  @override
  State<VideoItemRecommend> createState() => _VideoItemRecommendState();
}

class _VideoItemRecommendState extends State<VideoItemRecommend> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final title = item.nfoName.isNotEmpty ? item.nfoName : item.filename;
    final year = item.nfoYear > 0 ? item.nfoYear.toString() : '';
    final meta = buildVideoHomeMeta(item);
    final fanartUrl = VideoUtils.getFanartUrl(item);

    final bg = fanartUrl.isNotEmpty
        ? AnimatedScale(
            scale: _hovered ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: CustomExtendedImage(
              imageUrl: fanartUrl,
              fit: BoxFit.cover,
              showLoading: false,
              borderRadius: widget.borderRadius,
            ),
          )
        : Container(color: theme.colorScheme.surfaceContainerHighest);

    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            onTap: widget.onTap ?? () => AppRoutes.toVideoDetail(item.id),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  bg,
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.78),
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 42,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ] else if (year.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            year,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Row(
                      children: [
                        if (item.nfoScore > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color.fromARGB(
                                  255,
                                  229,
                                  181,
                                  39,
                                ).withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              item.nfoScore.toStringAsFixed(1),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color.fromARGB(
                                  255,
                                  229,
                                  181,
                                  39,
                                ).withValues(alpha: 0.92),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (videoMediaTypeText(
                          item.mediaType,
                        ).trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              videoMediaTypeText(item.mediaType),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
      child: child,
    );
  }
}
