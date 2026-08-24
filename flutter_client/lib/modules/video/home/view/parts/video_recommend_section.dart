import 'package:flutter/material.dart';
import '../../../base/beans/video_item_bean.dart';
import '../../../base/views/video_item_recommend.dart';
import 'video_horizontal_scroller.dart';

class VideoRecommendSection extends StatelessWidget {
  final List<VideoHomeItemBean> items;
  final ValueChanged<VideoHomeItemBean>? onDeleted;

  const VideoRecommendSection({super.key, required this.items, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final targetWidth = w >= 1600
            ? 420.0
            : w >= 1200
            ? 390.0
            : w >= 900
            ? 360.0
            : 330.0;
        final height = w >= 1600
            ? 260.0
            : w >= 1200
            ? 244.0
            : w >= 900
            ? 232.0
            : 214.0;
        final itemWidth = targetWidth * 1.2;
        final itemHeight = height * 1.2;
        final shown = items.take(20).toList(growable: false);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Text('video_home_recommend'.tr, style: theme.textTheme.titleMedium),
              // const SizedBox(height: 10),
              VideoHorizontalScroller(
                height: itemHeight,
                children: [
                  ...shown.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: VideoItemRecommend(
                        item: e,
                        width: itemWidth,
                        height: itemHeight,
                        onDeleted: onDeleted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
