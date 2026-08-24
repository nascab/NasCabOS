import 'dart:math' as math;

import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../core/api/api_controller.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../base/video_utils/video_utils.dart';
import '../../../video_main/controller/video_main_controller.dart';
import '../../controller/video_detail_controller.dart';

class AppVideoDetailTopSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const AppVideoDetailTopSection({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ctrl.item!;
    final title = (m['nfo_name']?.toString().trim().isNotEmpty ?? false)
        ? m['nfo_name'].toString()
        : (m['filename']?.toString() ?? '');
    final score = (m['nfo_score'] as num?)?.toDouble() ?? 0;
    final year = (m['nfo_year'] as num?)?.toInt() ?? 0;
    final regions = (m['nfo_regions']?.toString() ?? '').trim();
    final genres = (m['nfo_genres']?.toString() ?? '').trim();
    final rawMediaType = (m['media_type']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final resolvedMediaType = rawMediaType == 'season' ? 'tv' : rawMediaType;
    final logo = (m['logo_path']?.toString() ?? '').trim();
    final seasonCount = (m['season_count'] as num?)?.toInt() ?? 0;
    final episodeCount =
        (m['episode_count'] as num?)?.toInt() ??
        (m['episod_count'] as num?)?.toInt() ??
        0;
    final fanartUrl = VideoUtils.getFanartUrl(
      VideoHomeItemBean.fromJson(Map<String, dynamic>.from(m as Map)),
      size: 1000,
    );

    final metaParts = <String>[];
    if (ctrl.mediaType == 'season' && episodeCount > 0) {
      metaParts.add(
        'video_detail_episode_count'.trParams({
          'count': episodeCount.toString(),
        }),
      );
    }
    if (ctrl.mediaType == 'tv' && seasonCount > 0) {
      metaParts.add(
        'video_detail_season_count'.trParams({'count': seasonCount.toString()}),
      );
    }
    if (year > 0) metaParts.add(year.toString());

    List<String> splitComma(String input) {
      return input
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final regionList = splitComma(regions);
    final genreList = splitComma(genres);

    final bg = CustomExtendedImage(
      imageUrl: fanartUrl,
      alignment: Alignment.topCenter,
      fit: BoxFit.cover,
      showLoading: false,
      borderRadius: 0,
    );

    final scrimTop = MediaQuery.of(context).padding.top + 64;

    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 180,
          child: IgnorePointer(
            ignoring: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.black.withValues(alpha: 0.46),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: scrimTop,
          child: IgnorePointer(
            ignoring: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (logo.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        220,
                        MediaQuery.of(context).size.width * 0.55,
                      ),
                      maxHeight: 60,
                    ),
                    child: CustomExtendedImage(
                      imageUrl: ApiController.instance.getRawFileUrl(logo),
                      fit: BoxFit.contain,
                      showLoading: false,
                      borderRadius: 0,
                    ),
                  ),
                if (logo.isNotEmpty) const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (score > 0)
                      Text(
                        score.toStringAsFixed(1),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFD8A100),
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    if (score > 0) const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                if (metaParts.isNotEmpty ||
                    regionList.isNotEmpty ||
                    genreList.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AppMetaLine(
                    theme: theme,
                    metaParts: metaParts,
                    regions: regionList,
                    genres: genreList,
                    mediaType: resolvedMediaType,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppMetaLine extends StatelessWidget {
  final ThemeData theme;
  final List<String> metaParts;
  final List<String> regions;
  final List<String> genres;
  final String mediaType;

  const _AppMetaLine({
    required this.theme,
    required this.metaParts,
    required this.regions,
    required this.genres,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
      height: 1.35,
    );

    void openFilter(VideoFilterOverlayKind kind, String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (!Get.isRegistered<VideoMainController>()) return;
      Get.find<VideoMainController>().openFilterOverlay(
        kind: kind,
        value: v,
        mediaType: mediaType,
      );
    }

    final parts = <Widget>[
      ...metaParts.map((t) => Text(t, style: baseStyle)),
      ...regions.map(
        (r) => InkWell(
          onTap: () => openFilter(VideoFilterOverlayKind.region, r),
          child: Text(
            r,
            style: baseStyle?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
      ...genres.map(
        (g) => InkWell(
          onTap: () => openFilter(VideoFilterOverlayKind.genre, g),
          child: Text(
            g,
            style: baseStyle?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    ];

    if (parts.isEmpty) return const SizedBox.shrink();

    final spaced = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spaced.add(Text(' · ', style: baseStyle));
      }
      spaced.add(parts[i]);
    }

    return DefaultTextStyle(
      style: baseStyle ?? const TextStyle(),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: spaced,
      ),
    );
  }
}
