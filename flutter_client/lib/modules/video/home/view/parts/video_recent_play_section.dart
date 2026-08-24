import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/beans/video_item_bean.dart';
import '../../../base/views/video_item_poster.dart';
import '../../../list/controller/video_list_controller.dart';
import 'video_horizontal_scroller.dart';

class VideoRecentPlaySection extends StatelessWidget {
  final List<VideoHomeItemBean> items;
  final ValueChanged<VideoHomeItemBean>? onDeleted;

  const VideoRecentPlaySection({
    super.key,
    required this.items,
    this.onTap,
    this.onDeleted,
  });
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    VideoListController.ensureSharedPosterScaleLoaded();
    final theme = Theme.of(context);
    final shown = items.take(20).toList(growable: false);
    if (shown.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Text(
              "${'video_home_recent_play'.tr} >",
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 10),
          Obx(() {
            final posterScale = VideoListController.sharedPosterScale.value;
            final itemWidth = 160.0 * posterScale;
            final scrollerHeight = itemWidth * 1.5 + 70;
            return VideoHorizontalScroller(
              height: scrollerHeight,
              children: [
                ...shown.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: VideoItemPoster(
                      item: e,
                      width: itemWidth,
                      contentPadding: EdgeInsets.zero,
                      progress: e.progress,
                      onTitleTap: () {},
                      onTap: () => {AppRoutes.toVideoDetail(e.id)},
                      onDeleted: onDeleted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            );
          }),
        ],
      ),
    );
  }
}
