import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/api/api_controller.dart';
import '../../../../utils/device_utils.dart';
import '../../../../utils/toast_util.dart';
import '../../favorite/service/music_favorite_api_service.dart';
import '../../list/models/music_list_models.dart';
import '../../playlist/service/play_list_api_service.dart';
import '../../playlist/view/play_list_list_view.dart';
import '../controller/music_play_service_controller.dart';
import '../play_ctrl_fullscreen/parts/music_play_ctrl_fullscreen_playlist_drawer.dart';
import 'parts/music_play_ctrl_bottom_center_area.dart';
import 'parts/music_play_ctrl_bottom_left_area.dart';
import 'parts/music_play_ctrl_bottom_volume_control.dart';

class MusicPlayCtrlBottomBar extends StatefulWidget {
  final VoidCallback? onOpenFullscreen;

  const MusicPlayCtrlBottomBar({super.key, this.onOpenFullscreen});

  @override
  State<MusicPlayCtrlBottomBar> createState() => _MusicPlayCtrlBottomBarState();
}

class _MusicPlayCtrlBottomBarState extends State<MusicPlayCtrlBottomBar> {
  bool _dragging = false;
  double _dragValueMs = 0;
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

  String _resolveCoverUrl(MusicListItem item, {int size = 500}) {
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

  Future<void> _addToPlayList(MusicListItem item) async {
    final indexId = item.id;
    if (indexId <= 0) return;
    final context = Get.context;
    if (context == null) return;
    try {
      final list = await showDialog<PlayListItem>(
        context: context,
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

  Future<void> _showNowPlayingDrawer(
    MusicPlayServiceController controller,
  ) async {
    final ctx = Get.overlayContext ?? Get.context ?? context;
    final useBottomSheet = DeviceUtils.isPhone(ctx);
    if (useBottomSheet) {
      await MusicPlayCtrlFullScreenPlaylistDrawer.showBottomSheet(
        context: ctx,
        controller: controller,
        coverUrlResolver: _resolveCoverUrl,
      );
      return;
    }
    await MusicPlayCtrlFullScreenPlaylistDrawer.show(
      context: ctx,
      controller: controller,
      coverUrlResolver: _resolveCoverUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = MusicPlayServiceController.instance;

    return Obx(() {
      if (!controller.isReady.value) return const SizedBox.shrink();
      if (controller.playlist.isEmpty) return const SizedBox.shrink();
      final item = _currentItem(controller);
      if (item == null) return const SizedBox.shrink();

      final isPlaying = controller.isPlaying.value;
      final position = controller.position.value;
      final duration = controller.duration.value;
      final buffered = controller.buffered.value;
      final loopMode = controller.loopMode.value;
      final volume = controller.volume.value;
      final discAsset = controller.discAsset;
      final loopTip = switch (loopMode) {
        MusicLoopMode.sequence => 'music_loop_sequence'.tr,
        MusicLoopMode.listLoop => 'music_loop_list_loop'.tr,
        MusicLoopMode.singleLoop => 'music_loop_single_loop'.tr,
        MusicLoopMode.shuffle => 'music_loop_shuffle'.tr,
      };
      final downloading =
          controller.isDownloading.value &&
          controller.downloadingFileHash.value.trim().isNotEmpty &&
          controller.downloadingFileHash.value.trim() == item.fileHash.trim();
      final downloadProgress = downloading
          ? controller.downloadProgress.value
          : 0.0;
      final canIndexActions =
          item.id > 0 &&
          !item.isFromFile &&
          item.showType.trim().toLowerCase() != 'file_browser';

      final customColors = Theme.of(context).extension<CustomColors>();
      final bg = customColors!.leftTreeBgColor;
      return SafeArea(
        top: false,
        child: ClipRRect(
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MusicPlayCtrlBottomLeftArea(
                        item: item,
                        isPlaying: isPlaying,
                        favoriteLoading: _favoriteLoading,
                        downloading: downloading,
                        downloadProgress: downloadProgress,
                        coverUrl: _resolveCoverUrl(item, size: 500),
                        discAsset: discAsset,
                        onToggleFavorite: canIndexActions
                            ? () => _toggleFavorite(controller, item)
                            : null,
                        onOpenFullscreen: widget.onOpenFullscreen,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: MusicPlayCtrlBottomCenterArea(
                      isPlaying: isPlaying,
                      loopMode: loopMode,
                      loopIcon: _loopModeIcon(loopMode),
                      onToggleLoopMode: () =>
                          controller.setLoopMode(_nextLoopMode(loopMode)),
                      showLoopButton: false,
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
                      showAddToPlayListButton: false,
                      position: position,
                      duration: duration,
                      buffered: buffered,
                      dragging: _dragging,
                      dragValueMs: _dragValueMs,
                      onDragStart: (v) {
                        setState(() {
                          _dragging = true;
                          _dragValueMs = v;
                        });
                      },
                      onDragUpdate: (v) {
                        setState(() {
                          _dragging = true;
                          _dragValueMs = v;
                        });
                      },
                      onDragEnd: (v) async {
                        setState(() {
                          _dragging = false;
                          _dragValueMs = v;
                        });
                        await controller.seekTo(
                          Duration(milliseconds: v.round()),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: MusicPlayCtrlBottomVolumeControl(
                        volume: volume,
                        onChanged: controller.setVolume,
                        onToggleMute: controller.toggleMute,
                        showInlineSlider: false,
                        showLoopButton: true,
                        loopIcon: _loopModeIcon(loopMode),
                        loopTooltip: loopTip,
                        onToggleLoopMode: () =>
                            controller.setLoopMode(_nextLoopMode(loopMode)),
                        showPlayListButton: true,
                        playListTooltip: 'add_to_play_list'.tr,
                        onAddToPlayList: canIndexActions
                            ? () => _addToPlayList(item)
                            : null,
                        showNowPlayingButton: true,
                        nowPlayingTooltip: 'player_playlist'.tr,
                        onShowNowPlaying: () =>
                            _showNowPlayingDrawer(controller),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
