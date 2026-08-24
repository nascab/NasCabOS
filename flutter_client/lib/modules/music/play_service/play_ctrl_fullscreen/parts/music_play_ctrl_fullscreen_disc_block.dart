import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'music_play_ctrl_fullscreen_disc_with_needle.dart';

class MusicPlayCtrlFullScreenDiscBlock extends StatelessWidget {
  final bool isPlaying;
  final String coverUrl;
  final String discAsset;
  final VoidCallback? onToggleFavorite;
  final bool favoriteLoading;
  final bool isFavorite;
  final VoidCallback onNextDiscStyle;
  final VoidCallback onShowProperties;
  final VoidCallback onShowPlaylist;
  final VoidCallback? onTapDisc;

  const MusicPlayCtrlFullScreenDiscBlock({
    super.key,
    required this.isPlaying,
    required this.coverUrl,
    required this.discAsset,
    required this.onToggleFavorite,
    required this.favoriteLoading,
    required this.isFavorite,
    required this.onNextDiscStyle,
    required this.onShowProperties,
    required this.onShowPlaylist,
    this.onTapDisc,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.85);

    Widget icon(IconData data, {Color? color}) {
      return Icon(data, color: color ?? iconColor);
    }

    final disc = onTapDisc == null
        ? MusicPlayCtrlFullScreenDiscWithNeedle(
            isPlaying: isPlaying,
            coverUrl: coverUrl,
            discAsset: discAsset,
          )
        : GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTapDisc,
            child: MusicPlayCtrlFullScreenDiscWithNeedle(
              isPlaying: isPlaying,
              coverUrl: coverUrl,
              discAsset: discAsset,
            ),
          );

    final actions = Wrap(
      spacing: 10,
      children: [
        if (onToggleFavorite != null)
          IconButton(
            tooltip: isFavorite ? 'unfavorite'.tr : 'favorites'.tr,
            onPressed: onToggleFavorite,
            icon: favoriteLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1),
                  )
                : icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red : iconColor,
                  ),
          ),
        IconButton(
          tooltip: 'change_disc_style'.tr,
          onPressed: onNextDiscStyle,
          icon: icon(Icons.rotate_left),
        ),
        IconButton(
          tooltip: 'property'.tr,
          onPressed: onShowProperties,
          icon: icon(Icons.info_outline),
        ),
        IconButton(
          tooltip: 'player_playlist'.tr,
          onPressed: onShowPlaylist,
          icon: icon(Icons.queue_music),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (ctx, c) {
        final boundedHeight = c.hasBoundedHeight && c.maxHeight.isFinite;
        if (!boundedHeight) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AspectRatio(aspectRatio: 1, child: disc),
                ),
              ),
              const SizedBox(height: 10),
              Center(child: actions),
            ],
          );
        }

        const actionsHeight = 48.0;
        const gap = 10.0;
        final maxDiscByHeight = (c.maxHeight - actionsHeight - gap).clamp(
          0.0,
          double.infinity,
        );
        final discSize = [
          520.0,
          c.maxWidth,
          maxDiscByHeight,
        ].reduce((a, b) => a < b ? a : b);

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: discSize, height: discSize, child: disc),
              const SizedBox(height: gap),
              Center(child: actions),
            ],
          ),
        );
      },
    );
  }
}
