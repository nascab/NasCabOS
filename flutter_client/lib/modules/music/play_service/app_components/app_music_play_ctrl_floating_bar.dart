import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/modules/music/list/models/music_list_models.dart';
import 'package:NasCabOS/modules/music/play_service/controller/music_play_service_controller.dart';
import 'package:NasCabOS/modules/music/play_service/play_ctrl_fullscreen/parts/music_play_ctrl_fullscreen_playlist_drawer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'music_play_disc_cover.dart';

class AppMusicPlayCtrlFloatingBar extends StatelessWidget {
  final VoidCallback onOpenFullscreen;

  const AppMusicPlayCtrlFloatingBar({
    super.key,
    required this.onOpenFullscreen,
  });

  MusicListItem? _currentItem(MusicPlayServiceController controller) {
    final idx = controller.currentIndex.value;
    if (idx < 0 || idx >= controller.playlist.length) return null;
    return controller.playlist[idx];
  }

  String _resolvePlayablePath(MusicListItem item) {
    if (item.isSeries) {
      final p = item.firstFilePath.trim();
      if (p.isNotEmpty) return p;
    }
    final full = item.fullPath.trim();
    if (full.isNotEmpty) return full;
    final base = item.path.trim();
    final name = item.filename.trim();
    if (base.isNotEmpty && name.isNotEmpty) return '$base/$name';
    return base;
  }

  String _resolveCoverUrl(MusicListItem item, {int size = 240}) {
    if (item.hasInnerCover != 1) return '';
    final coverPath = item.isSeries
        ? item.firstFilePath.trim()
        : (item.fullPath.trim().isNotEmpty
              ? item.fullPath.trim()
              : _resolvePlayablePath(item));
    if (coverPath.isEmpty) return '';
    return ApiController.instance.getMusicCoverUrl(
      filePath: coverPath,
      size: size,
    );
  }

  Future<void> _openPlaylistDrawer(
    BuildContext context, {
    required bool useBottomSheet,
  }) async {
    final controller = MusicPlayServiceController.instance;
    if (!controller.isReady.value) return;
    if (controller.playlist.isEmpty) return;
    if (useBottomSheet) {
      await MusicPlayCtrlFullScreenPlaylistDrawer.showBottomSheet(
        context: context,
        controller: controller,
        coverUrlResolver: _resolveCoverUrl,
      );
      return;
    }
    await MusicPlayCtrlFullScreenPlaylistDrawer.show(
      context: context,
      controller: controller,
      coverUrlResolver: _resolveCoverUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customColors = theme.extension<CustomColors>();
    final bg = (customColors?.oprationBarBgColor ?? theme.colorScheme.surface)
        .withValues(alpha: 0.92);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 750;
        final controller = MusicPlayServiceController.instance;
        return Obx(() {
          if (!controller.isReady.value) return const SizedBox.shrink();
          if (controller.playlist.isEmpty) return const SizedBox.shrink();
          final item = _currentItem(controller);
          if (item == null) return const SizedBox.shrink();
          final coverUrl = _resolveCoverUrl(item, size: isCompact ? 220 : 320);
          final discAsset = controller.discAsset;
          final isPlaying = controller.isPlaying.value;
          final downloading =
              !kIsWeb &&
              controller.isDownloading.value &&
              controller.downloadingFileHash.value.trim().isNotEmpty &&
              controller.downloadingFileHash.value.trim() ==
                  item.fileHash.trim();
          final progressText = downloading
              ? '${(controller.downloadProgress.value.clamp(0, 1) * 100).toStringAsFixed(0)}%'
              : '';
          final titleText = progressText.isNotEmpty
              ? '$progressText ${item.displayTitle}'
              : item.displayTitle;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenFullscreen,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: isCompact ? 60 : 68,
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    MusicPlayDiscCover(
                      coverUrl: coverUrl,
                      isPlaying: isPlaying,
                      discAsset: discAsset,
                      outerSize: isCompact ? 44 : 52,
                      innerSize: isCompact ? 30 : 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!isCompact)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item.artist.trim().isEmpty
                                    ? '-'
                                    : item.artist.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!isCompact)
                      IconButton(
                        tooltip: 'music_prev_track'.tr,
                        onPressed: controller.playPrevious,
                        icon: const Icon(Icons.skip_previous),
                      ),
                    IconButton(
                      tooltip: isPlaying ? 'pause'.tr : 'play'.tr,
                      onPressed: () {
                        if (isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      },
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                      ),
                    ),
                    if (!isCompact)
                      IconButton(
                        tooltip: 'music_next_track'.tr,
                        onPressed: controller.playNext,
                        icon: const Icon(Icons.skip_next),
                      ),
                    IconButton(
                      tooltip: 'player_playlist'.tr,
                      onPressed: () => _openPlaylistDrawer(
                        context,
                        useBottomSheet: isCompact,
                      ),
                      icon: const Icon(Icons.queue_music_outlined),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
