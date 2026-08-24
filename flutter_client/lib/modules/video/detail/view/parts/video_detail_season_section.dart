import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../base/beans/video_item_bean.dart';
import '../../../base/views/video_item_poster.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../utils/device_utils.dart';
import '../../../home/view/parts/video_horizontal_scroller.dart';
import '../../controller/video_detail_controller.dart';

/// 季列表（仅 TV 相关资源显示）。
class VideoDetailSeasonSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailSeasonSection({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seasons = ctrl.seasonList;

    void openSeason(int indexId) {
      if (indexId <= 0) return;
      if (DeviceUtils.isMobile) {
        Get.toNamed(
          AppRoutes.videoDetail,
          arguments: {'index_id': indexId},
          preventDuplicates: false,
        );
        return;
      }
      AppRoutes.toVideoSubDetail(indexId);
    }

    VideoHomeItemBean toBean(Map<String, dynamic> s) {
      final rawFav = s['is_favorite'];
      final isFav = rawFav == true || rawFav == 1 || rawFav == '1';

      int parseId(dynamic v) {
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v.trim()) ?? 0;
        return 0;
      }

      final id = parseId(
        s['id'] ??
            s['index_id'] ??
            s['indexId'] ??
            s['season_id'] ??
            s['seasonId'],
      );
      return VideoHomeItemBean(
        id: id,
        mediaType: (s['media_type']?.toString() ?? 'season'),
        path: (s['path']?.toString() ?? ''),
        filename: (s['filename']?.toString() ?? ''),
        firstFilePath: (s['first_file_path']?.toString() ?? ''),
        nfoName: (s['nfo_name']?.toString() ?? ''),
        nfoYear: (s['nfo_year'] as num?)?.toInt() ?? 0,
        nfoScore: (s['nfo_score'] as num?)?.toDouble() ?? 0,
        nfoRegions: (s['nfo_regions']?.toString() ?? ''),
        nfoGenres: (s['nfo_genres']?.toString() ?? ''),
        posterPath: (s['poster_path']?.toString() ?? ''),
        fanartPath: (s['fanart_path']?.toString() ?? ''),
        fullPath: (s['full_path']?.toString() ?? ''),
        logoPath: (s['logo_path']?.toString() ?? ''),
        progress: 0,
        isFavorite: isFav,
        viewTime: s['view_time']?.toString(),
        createTime: s['create_time']?.toString(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'video_detail_season_list_title'.trParams({
            'count': seasons.length.toString(),
          }),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.clamp(0, 99999);
            final itemWidth = w < 420
                ? 120.0
                : w < 720
                ? 140.0
                : 168.0;
            const spacing = 12.0;
            final itemHeight = itemWidth * (3 / 2) + 64;

            final children = <Widget>[
              for (final s in seasons) ...[
                Padding(
                  padding: const EdgeInsets.only(right: spacing),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Builder(
                      builder: (context) {
                        final bean = toBean(s);
                        return VideoItemPoster(
                          item: bean,
                          width: itemWidth,
                          contentPadding: EdgeInsets.zero,
                          onTap: () => openSeason(bean.id),
                          onTitleTap: () => openSeason(bean.id),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
            ];

            if (DeviceUtils.isDesktopOrWeb) {
              return VideoHorizontalScroller(
                height: itemHeight,
                children: children,
              );
            }

            return SizedBox(
              height: itemHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                children: children,
              ),
            );
          },
        ),
      ],
    );
  }
}
