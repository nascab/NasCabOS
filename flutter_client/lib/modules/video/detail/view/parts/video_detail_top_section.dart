import 'dart:math' as math;

import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../../core/api/api_controller.dart';
import '../../controller/video_detail_controller.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../base/video_utils/video_utils.dart';
import '../../../video_main/controller/video_main_controller.dart';

/// 顶部大图区域：背景海报 + 渐变遮罩 + 标题/评分/元信息。
class VideoDetailTopSection extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailTopSection({super.key, required this.ctrl});

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
    final fanartUrl = VideoUtils.getFanartUrl(
      VideoHomeItemBean.fromJson(Map<String, dynamic>.from(m as Map)),
      size: 1000,
    );
    final seasonCount = (m['season_count'] as num?)?.toInt() ?? 0;
    final episodeCount =
        (m['episode_count'] as num?)?.toInt() ??
        (m['episod_count'] as num?)?.toInt() ??
        0;
    final width = (m['width'] as num?)?.toInt() ?? 0;
    final height = (m['height'] as num?)?.toInt() ?? 0;
    final itemResLabel = _resolutionLabel(width, height);
    final resLabel = ctrl.mediaType == 'tv'
        ? (ctrl.episodeList.isNotEmpty
              ? _resolutionLabel(
                  (ctrl.episodeList.first['width'] as num?)?.toInt() ?? 0,
                  (ctrl.episodeList.first['height'] as num?)?.toInt() ?? 0,
                )
              : '')
        : itemResLabel;

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

    // 顶部背景
    final bg = CustomExtendedImage(
      imageUrl: fanartUrl,
      alignment: Alignment.center,
      fit: BoxFit.fitWidth,
      showLoading: false,
      borderRadius: 0,
    );

    return Stack(
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
                  theme.colorScheme.surface.withValues(alpha: 0.98),
                  theme.colorScheme.surface.withValues(alpha: 0.32),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(60, 0, 60, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                return Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (logo.isNotEmpty)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: wide ? 420 : 320,
                                  maxHeight: 200,
                                ),
                                child: CustomExtendedImage(
                                  imageUrl: ApiController.instance
                                      .getRawFileUrl(logo),
                                  fit: BoxFit.contain,
                                  showLoading: false,
                                  borderRadius: 0,
                                ),
                              ),
                            if (logo.isNotEmpty) const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (score > 0)
                                    Text(
                                      score.toStringAsFixed(1),
                                      style: theme.textTheme.displaySmall
                                          ?.copyWith(
                                            color: const Color(0xFFD8A100),
                                            fontWeight: FontWeight.w900,
                                            height: 1.0,
                                          ),
                                    ),
                                  if (score > 0) const SizedBox(height: 8),
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (metaParts.isNotEmpty) const SizedBox(height: 10),
                        if (metaParts.isNotEmpty ||
                            regionList.isNotEmpty ||
                            genreList.isNotEmpty)
                          _MetaLine(
                            theme: theme,
                            metaParts: metaParts,
                            regions: regionList,
                            genres: genreList,
                            mediaType: resolvedMediaType,
                          ),
                      ],
                    ),
                    if (resLabel.isNotEmpty)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Text(
                            resLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  final ThemeData theme;
  final List<String> metaParts;
  final List<String> regions;
  final List<String> genres;
  final String mediaType;

  const _MetaLine({
    required this.theme,
    required this.metaParts,
    required this.regions,
    required this.genres,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
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
              decorationColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.45,
              ),
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
              decorationColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.45,
              ),
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

String _resolutionLabel(int width, int height) {
  final w = math.max(0, width);
  final h = math.max(0, height);
  if (w >= 3840 || h >= 2160) return '4K';
  if (w >= 1920 || h >= 1080) return '1080P';
  if (w >= 1280 || h >= 720) return '720P';
  return '';
}
