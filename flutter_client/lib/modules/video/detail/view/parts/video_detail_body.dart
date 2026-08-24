import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controller/video_detail_controller.dart';
import 'video_detail_actions_section.dart';
import 'video_detail_disc_content_section.dart';
import 'video_detail_episode_section.dart';
import 'video_detail_people_section.dart';
import 'video_detail_season_section.dart';
import 'video_detail_storyline_section.dart';
import 'video_detail_top_section.dart';
import 'video_detail_file_info.dart';

/// 视频详情页主体：顶部信息区 + 详情内容区。
class VideoDetailBody extends StatelessWidget {
  final VideoDetailController ctrl;

  const VideoDetailBody({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final m = ctrl.item;
    if (m == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final topH = math.min(520.0, h * 0.62);
        final horizontalPadding = 60.0;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: topH,
                child: VideoDetailTopSection(ctrl: ctrl),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VideoDetailStorylineSection(ctrl: ctrl),
                    const SizedBox(height: 14),
                    VideoDetailActionsSection(ctrl: ctrl),
                    const SizedBox(height: 18),
                    if (ctrl.seasonList.isNotEmpty) ...[
                      VideoDetailSeasonSection(ctrl: ctrl),
                      const SizedBox(height: 12),
                    ],
                    if (ctrl.showEpisodeSection) ...[
                      VideoDetailEpisodeSection(ctrl: ctrl),
                      const SizedBox(height: 20),
                    ],
                    if (ctrl.showDiscContentSection) ...[
                      VideoDetailDiscContentSection(ctrl: ctrl),
                      const SizedBox(height: 20),
                    ],
                    VideoDetailPeopleSection(ctrl: ctrl),
                    const SizedBox(height: 18),
                    VideoDetailFileInfoSection(ctrl: ctrl),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
