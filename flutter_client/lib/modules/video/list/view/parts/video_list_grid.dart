import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/views/video_item_poster.dart';
import '../../controller/video_list_controller.dart';

class VideoListGrid extends StatelessWidget {
  final VideoListController controller;
  const VideoListGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final posterScale = controller.posterScale.value;
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.crossAxisExtent;
          final baseWidth = maxWidth < 520 ? 150.0 : 176.0;
          final desiredWidth = baseWidth * posterScale;
          final crossAxisCount = (maxWidth / desiredWidth).floor().clamp(2, 10);
          final spacing = maxWidth < 520 ? 12.0 : 15.0;
          final totalSpacing = spacing * (crossAxisCount - 1);
          final itemWidth = ((maxWidth - totalSpacing) / crossAxisCount)
              .floorToDouble();
          final estimatedHeight = itemWidth * 1.5 + 60;
          final aspectRatio = itemWidth / estimatedHeight;

          return SliverGrid(
            delegate: SliverChildBuilderDelegate((context, idx) {
              final item = controller.items[idx];
              return VideoItemPoster(
                contentPadding: EdgeInsets.zero,
                item: item,
                width: itemWidth,
                progress: null,
                currentAlbumId: controller.albumId,
                onRemovedFromCurrentAlbum: () =>
                    controller.removeFromCurrentAlbumState(item.id),
                onFavoriteChanged: (isFav) =>
                    controller.updateFavoriteState(item.id, isFav),
                onDeleted: (deleted) {
                  controller.items.removeWhere((e) => e.id == deleted.id);
                  controller.total.value = (controller.total.value - 1).clamp(
                    0,
                    1 << 30,
                  );
                },
              );
            }, childCount: controller.items.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
          );
        },
      );
    });
  }
}

class VideoListFooter extends StatelessWidget {
  final VideoListController controller;
  const VideoListFooter({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loadingMore.value) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        );
      }

      if (!controller.hasMore.value) {
        return Center(
          child: Text(
            'video_list_no_more'.tr,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }

      if (!controller.autoLoadFailed.value) {
        return const SizedBox.shrink();
      }

      return Center(
        child: OutlinedButton(
          onPressed: () =>
              controller.loadMore(fromAuto: false).catchError((_) {}),
          child: Text('video_list_load_more'.tr),
        ),
      );
    });
  }
}
