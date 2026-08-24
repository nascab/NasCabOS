import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controller/video_detail_controller.dart';
import 'app_video_detail_actions_section.dart';
import 'video_detail_disc_content_section.dart';
import 'app_video_detail_top_section.dart';
import 'video_detail_episode_section.dart';
import 'video_detail_file_info.dart';
import 'video_detail_people_section.dart';
import 'video_detail_season_section.dart';
import 'video_detail_storyline_section.dart';

class AppVideoDetailBody extends StatelessWidget {
  final VideoDetailController ctrl;

  const AppVideoDetailBody({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final m = ctrl.item;
    if (m == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final orientation = MediaQuery.of(context).orientation;
        final topH = orientation == Orientation.portrait
            ? math.min(460.0, h * 0.62)
            : math.min(360.0, h * 0.78);

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: topH,
                child: AppVideoDetailTopSection(ctrl: ctrl),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VideoDetailStorylineSection(ctrl: ctrl),
                    const SizedBox(height: 12),
                    AppVideoDetailActionsSection(ctrl: ctrl),
                    const SizedBox(height: 14),
                    if (ctrl.seasonList.isNotEmpty) ...[
                      VideoDetailSeasonSection(ctrl: ctrl),
                      const SizedBox(height: 10),
                    ],
                    if (ctrl.showEpisodeSection) ...[
                      VideoDetailEpisodeSection(ctrl: ctrl),
                      const SizedBox(height: 10),
                    ],
                    if (ctrl.showDiscContentSection) ...[
                      VideoDetailDiscContentSection(ctrl: ctrl),
                      const SizedBox(height: 10),
                    ],
                    VideoDetailPeopleSection(ctrl: ctrl),
                    const SizedBox(height: 14),
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
