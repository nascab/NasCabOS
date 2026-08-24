import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/video_list_controller.dart';
import '../../../../base/components/custom_hover_menu_anchor.dart';

class VideoListSortEntry {
  final bool divider;
  final VideoListSortBy? by;
  final VideoListSortOrder? order;
  final String? labelKey;

  const VideoListSortEntry.divider()
    : divider = true,
      by = null,
      order = null,
      labelKey = null;

  const VideoListSortEntry.option({
    required this.by,
    required this.order,
    required this.labelKey,
  }) : divider = false;
}

List<VideoListSortEntry> getVideoListSortEntries(
  VideoListController controller,
) {
  final showFavoriteTime = controller.isFavoriteList;
  return <VideoListSortEntry>[
    if (showFavoriteTime) ...[
      const VideoListSortEntry.option(
        by: VideoListSortBy.favoriteTime,
        order: VideoListSortOrder.desc,
        labelKey: 'video_list_sort_favorite_time_desc',
      ),
      const VideoListSortEntry.option(
        by: VideoListSortBy.favoriteTime,
        order: VideoListSortOrder.asc,
        labelKey: 'video_list_sort_favorite_time_asc',
      ),
      const VideoListSortEntry.divider(),
    ],
    const VideoListSortEntry.option(
      by: VideoListSortBy.viewTime,
      order: VideoListSortOrder.desc,
      labelKey: 'video_list_sort_view_time_desc',
    ),
    const VideoListSortEntry.option(
      by: VideoListSortBy.viewTime,
      order: VideoListSortOrder.asc,
      labelKey: 'video_list_sort_view_time_asc',
    ),
    const VideoListSortEntry.divider(),
    const VideoListSortEntry.option(
      by: VideoListSortBy.createTime,
      order: VideoListSortOrder.desc,
      labelKey: 'create_time_desc',
    ),
    const VideoListSortEntry.option(
      by: VideoListSortBy.createTime,
      order: VideoListSortOrder.asc,
      labelKey: 'create_time_asc',
    ),
    const VideoListSortEntry.divider(),
    const VideoListSortEntry.option(
      by: VideoListSortBy.year,
      order: VideoListSortOrder.desc,
      labelKey: 'video_list_sort_year_desc',
    ),
    const VideoListSortEntry.option(
      by: VideoListSortBy.year,
      order: VideoListSortOrder.asc,
      labelKey: 'video_list_sort_year_asc',
    ),
    const VideoListSortEntry.divider(),
    const VideoListSortEntry.option(
      by: VideoListSortBy.score,
      order: VideoListSortOrder.desc,
      labelKey: 'video_list_sort_score_desc',
    ),
    const VideoListSortEntry.option(
      by: VideoListSortBy.score,
      order: VideoListSortOrder.asc,
      labelKey: 'video_list_sort_score_asc',
    ),
    const VideoListSortEntry.divider(),
    const VideoListSortEntry.option(
      by: VideoListSortBy.name,
      order: VideoListSortOrder.asc,
      labelKey: 'name_asc',
    ),
    const VideoListSortEntry.option(
      by: VideoListSortBy.name,
      order: VideoListSortOrder.desc,
      labelKey: 'name_desc',
    ),
  ];
}

/// 与 [getVideoListSortEntries] 一致，用于恢复缓存时校验；不匹配则不应应用缓存。
bool videoListSortPairMatchesMenu(
  VideoListController controller,
  VideoListSortBy by,
  VideoListSortOrder order,
) {
  for (final e in getVideoListSortEntries(controller)) {
    if (e.divider) continue;
    if (e.by == by && e.order == order) return true;
  }
  return false;
}

String? getCurrentVideoListSortLabelKey(VideoListController controller) {
  final by = controller.sortBy.value;
  final order = controller.sortOrder.value;
  final entries = getVideoListSortEntries(controller);
  for (final e in entries) {
    if (e.divider) continue;
    if (e.by == by && e.order == order) return e.labelKey;
  }
  return null;
}

class VideoListSortMenu extends StatelessWidget {
  final VideoListController controller;
  const VideoListSortMenu({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      bool isSelected(VideoListSortEntry e) =>
          !e.divider &&
          e.by == controller.sortBy.value &&
          e.order == controller.sortOrder.value;

      Widget leading(VideoListSortEntry e) => isSelected(e)
          ? const Icon(Icons.check, size: 18)
          : const SizedBox(width: 18);

      return CustomHoverMenuAnchor(
        menuChildren: [
          ...getVideoListSortEntries(controller).map((e) {
            if (e.divider) return const Divider(height: 1);
            return MenuItemButton(
              onPressed: () => controller.setSort(e.by!, e.order!),
              leadingIcon: leading(e),
              child: Text(e.labelKey!.tr),
            );
          }),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_by_alpha, size: 18),
            const SizedBox(width: 6),
            Text('sort'.tr),
          ],
        ),
      );
    });
  }
}
