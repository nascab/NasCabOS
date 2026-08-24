import 'dart:ui';

import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/api/api_controller.dart';
import '../../../../utils/toast_util.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../favorite/service/music_favorite_api_service.dart';
import '../../list/models/music_list_models.dart';
import '../../playlist/service/play_list_api_service.dart';
import '../../playlist/view/play_list_list_view.dart';
import '../controller/music_play_service_controller.dart';
import 'parts/music_play_ctrl_fullscreen_body.dart';
import 'parts/music_play_ctrl_fullscreen_bottom_bar.dart';
import 'parts/music_play_ctrl_fullscreen_file_properties_dialog.dart';
import 'parts/music_play_ctrl_fullscreen_header.dart';
import 'parts/music_play_ctrl_fullscreen_playlist_drawer.dart';

class MusicPlayCtrlFullScreenSheet extends StatefulWidget {
  final VoidCallback onClose;

  const MusicPlayCtrlFullScreenSheet({super.key, required this.onClose});

  @override
  State<MusicPlayCtrlFullScreenSheet> createState() =>
      _MusicPlayCtrlFullScreenSheetState();
}

class _MusicPlayCtrlFullScreenSheetState
    extends State<MusicPlayCtrlFullScreenSheet> {
  bool _favoriteLoading = false;

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

  String _resolveCoverUrl(MusicListItem item, {int size = 800}) {
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

  MusicLoopMode _nextLoopMode(MusicLoopMode mode) {
    return switch (mode) {
      MusicLoopMode.sequence => MusicLoopMode.listLoop,
      MusicLoopMode.listLoop => MusicLoopMode.singleLoop,
      MusicLoopMode.singleLoop => MusicLoopMode.shuffle,
      MusicLoopMode.shuffle => MusicLoopMode.sequence,
    };
  }

  IconData _loopModeIcon(MusicLoopMode mode) {
    return switch (mode) {
      MusicLoopMode.sequence => Icons.format_list_numbered,
      MusicLoopMode.listLoop => Icons.repeat,
      MusicLoopMode.singleLoop => Icons.repeat_one,
      MusicLoopMode.shuffle => Icons.shuffle,
    };
  }

  Future<void> _addToPlayList(MusicListItem item) async {
    final indexId = item.id;
    if (indexId <= 0) return;
    final ctx = Get.context ?? context;
    try {
      final list = await showDialog<PlayListItem>(
        context: ctx,
        barrierDismissible: true,
        builder: (_) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
              child: const PlayListListView(selectionMode: true),
            ),
          );
        },
      );
      if (list == null) return;
      final res = await PlayListApiService.instance.addIndexes(
        listId: list.id,
        indexIds: [indexId],
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<void> _toggleFavorite(
    MusicPlayServiceController controller,
    MusicListItem item,
  ) async {
    if (_favoriteLoading) return;
    final id = item.id;
    if (id <= 0) return;
    final prev = item.isFavorite;
    final next = !prev;

    setState(() {
      _favoriteLoading = true;
    });

    try {
      final ok = next
          ? await MusicFavoriteApiService.instance.addFavorite(id)
          : await MusicFavoriteApiService.instance.removeFavorite(id);
      if (!ok) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      final idx = controller.playlist.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        controller.playlist[idx] = controller.playlist[idx].copyWith(
          isFavorite: next,
        );
        controller.playlist.refresh();
      }
    } finally {
      if (mounted) {
        setState(() {
          _favoriteLoading = false;
        });
      }
    }
  }

  Future<void> _showFileProperties(MusicListItem item) async {
    final filePath = _resolvePlayablePath(item);
    await MusicPlayCtrlFullScreenFilePropertiesDialog.show(
      context: Get.overlayContext ?? context,
      filePath: filePath,
    );
  }

  Future<void> _showPlaylistDrawer(
    MusicPlayServiceController controller,
  ) async {
    final useBottomSheet = DeviceUtils.isPhone(context);
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

  void _nextDiscStyle(MusicPlayServiceController controller) {
    controller.nextDiscStyle();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayServiceController.instance;
    final isNarrow = DeviceUtils.isMobile;

    return Obx(() {
      final item = _currentItem(controller);
      if (!controller.isReady.value || item == null) {
        return const SizedBox.shrink();
      }

      final coverUrl = _resolveCoverUrl(item, size: 1200);
      final discAsset = controller.discAsset;
      final isPlaying = controller.isPlaying.value;
      final position = controller.position.value;
      final duration = controller.duration.value;
      final buffered = controller.buffered.value;
      final loopMode = controller.loopMode.value;
      final volume = controller.volume.value;
      final lyrics = controller.currentLyrics.value;
      final musicPath = _resolvePlayablePath(item);

      final bottomCoverUrl = _resolveCoverUrl(item, size: 500);
      final canIndexActions =
          item.id > 0 &&
          !item.isFromFile &&
          item.showType.trim().toLowerCase() != 'file_browser';
      final bgImage = coverUrl.trim().isEmpty
          ? Image.asset(
              'assets/music/icons/default_cover.jpg',
              fit: BoxFit.cover,
            )
          : CustomExtendedImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              showLoading: false,
              borderRadius: 0,
              errorBuilder: (context, error, stackTrace) => Image.asset(
                'assets/music/icons/default_cover.jpg',
                fit: BoxFit.cover,
              ),
            );
      final customColors = Theme.of(context).extension<CustomColors>();
      return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          widget.onClose();
        },
        child: Material(
          color: customColors?.leftTreeBgColor,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.2,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                    child: bgImage,
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
              Column(
                children: [
                  MusicPlayCtrlFullScreenHeader(
                    onClose: widget.onClose,
                    height: isNarrow ? 60 : 96,
                    topPadding: isNarrow ? 12 : 40,
                  ),
                  Expanded(
                    child: MusicPlayCtrlFullScreenBody(
                      isPlaying: isPlaying,
                      coverUrl: coverUrl,
                      discAsset: discAsset,
                      musicPath: musicPath,
                      trackDuration: duration,
                      onToggleFavorite: canIndexActions && !_favoriteLoading
                          ? () => _toggleFavorite(controller, item)
                          : null,
                      favoriteLoading: _favoriteLoading,
                      isFavorite: item.isFavorite,
                      onNextDiscStyle: () => _nextDiscStyle(controller),
                      onShowProperties: () => _showFileProperties(item),
                      onShowPlaylist: () => _showPlaylistDrawer(controller),
                      title: item.displayTitle,
                      album: item.album.trim(),
                      artist: item.artist.trim(),
                      lyrics: lyrics,
                      position: position,
                      onSeekTo: controller.seekTo,
                    ),
                  ),
                  MusicPlayCtrlFullScreenBottomBar(
                    controller: controller,
                    item: item,
                    isPlaying: isPlaying,
                    discAsset: discAsset,
                    position: position,
                    duration: duration,
                    buffered: buffered,
                    loopIcon: _loopModeIcon(loopMode),
                    loopMode: loopMode,
                    volume: volume,
                    favoriteLoading: _favoriteLoading,
                    coverUrl: bottomCoverUrl,
                    onToggleFavorite: canIndexActions
                        ? () => _toggleFavorite(controller, item)
                        : null,
                    onToggleLoopMode: () =>
                        controller.setLoopMode(_nextLoopMode(loopMode)),
                    onPrev: controller.playPrevious,
                    onNext: controller.playNext,
                    onPlayPause: () {
                      if (isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    },
                    onAddToPlayList: canIndexActions
                        ? () => _addToPlayList(item)
                        : null,
                    onVolumeChanged: controller.setVolume,
                    onSeekTo: controller.seekTo,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}
