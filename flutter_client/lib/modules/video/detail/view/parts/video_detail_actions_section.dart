import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/api/api_controller.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../files/service/file_api_service.dart';
import '../../../../home/views/pc_home_controller.dart';
import '../../../../transfer/controllers/download_controller.dart';
import '../../../base/beans/video_item_bean.dart';
import '../../../base/services/video_item_sync_service.dart';
import '../../../favorite/service/video_favorite_api_service.dart';
import '../../../scrape/service/video_scrape_api_service.dart';
import '../../../source_setting/service/video_source_api_service.dart';
import '../../../tmdb/view/video_search_media_dialog.dart';
import '../../../video_main/controller/video_main_controller.dart';
import '../../service/video_detail_api_service.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../base/components/custom_button.dart';
import '../../controller/video_detail_controller.dart';
import 'video_open_skip_dialog.dart';

/// 操作区：播放/刷新/收藏/标记已看/更多。
/// 统一使用 [kActionButtonRadius] 作为按钮圆角，保持风格一致。
const double kActionButtonRadius = 10.0;

class VideoDetailActionsSection extends StatefulWidget {
  final VideoDetailController ctrl;

  const VideoDetailActionsSection({super.key, required this.ctrl});

  @override
  State<VideoDetailActionsSection> createState() =>
      _VideoDetailActionsSectionState();
}

class _VideoDetailActionsSectionState extends State<VideoDetailActionsSection> {
  bool? _isFavorite;
  bool _favoriteLoading = false;

  String _formatSeconds(int seconds) {
    final d = Duration(seconds: seconds < 0 ? 0 : seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get _effectiveFavorite {
    final raw = widget.ctrl.item?['is_favorite'];
    final fromCtrl = raw == true || raw == 1 || raw == '1';
    return _isFavorite ?? fromCtrl;
  }

  @override
  void didUpdateWidget(covariant VideoDetailActionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isFavorite == null) return;
    final oldRaw = oldWidget.ctrl.item?['is_favorite'];
    final newRaw = widget.ctrl.item?['is_favorite'];
    final oldFav = oldRaw == true || oldRaw == 1 || oldRaw == '1';
    final newFav = newRaw == true || newRaw == 1 || newRaw == '1';
    if (oldFav != newFav) {
      _isFavorite = null;
    }
  }

  void _patchCtrlFavorite(bool next) {
    final raw = widget.ctrl.raw.value;
    if (raw == null) return;
    final nextRaw = Map<String, dynamic>.from(raw);
    final item = nextRaw['item'];
    if (item is! Map) return;
    final nextItem = Map<String, dynamic>.from(item.cast<String, dynamic>());
    nextItem['is_favorite'] = next;
    nextRaw['item'] = nextItem;
    widget.ctrl.raw.value = nextRaw;
    widget.ctrl.update();
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) return;
    final id = widget.ctrl.indexId;
    if (id <= 0) return;

    final prev = _effectiveFavorite;
    final next = !prev;

    setState(() {
      _favoriteLoading = true;
      _isFavorite = next;
    });

    try {
      final ok = next
          ? await VideoFavoriteApiService.instance.addFavorite(id)
          : await VideoFavoriteApiService.instance.removeFavorite(id);
      if (!ok) {
        setState(() {
          _isFavorite = prev;
        });
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      _patchCtrlFavorite(next);
      ToastUtil.show('operation_success'.tr);
    } finally {
      if (mounted) {
        setState(() {
          _favoriteLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ctrl = widget.ctrl;
    final m = ctrl.item!;
    final isFile = (m['is_file'] as num?)?.toInt() == 1;
    final mediaType = ctrl.mediaType.trim().toLowerCase();
    final filePath = ((isFile ? m['full_path'] : m['play_file_path'])?.toString() ?? '').trim();
    final isMovieLike = mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts';
    final discPlaylist = ctrl.buildDiscPlaybackPlaylist();
    final hasDiscPlaylist = (mediaType == 'bdmv' || mediaType == 'video_ts') && discPlaylist.isNotEmpty;
    final canPlayTv =
        !isFile &&
        (mediaType == 'tv' || mediaType == 'season') &&
        ctrl.indexId > 0;

    final hasHistory = ctrl.hasHistory;
    final playText = hasHistory ? 'video_detail_continue_play'.tr : 'play'.tr;
    final showProgress =
        hasHistory && (mediaType == 'season' || isMovieLike);
    final watched = ctrl.historySeconds;
    final total = ctrl.historyDurationSeconds;
    final progress = total > 0 ? (watched / total).clamp(0.0, 1.0) : 0.0;
    final epNum = ctrl.historyEpisodeNum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CustomButton(
              width: 138,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kActionButtonRadius),
                ),
              ),
              text: playText,
              onPressed: (isFile || mediaType == 'bdmv' || mediaType == 'video_ts') && filePath.isNotEmpty
                  ? () {
                      if (hasDiscPlaylist) {
                        AppRoutes.toVideoPlayer(
                          playlist: discPlaylist,
                          initialIndex: 0,
                        ignoreFindSub: 0,
                        );
                        return;
                      }
                      AppRoutes.toVideoPlayer(
                        playlist: [
                          {
                            'path': filePath,
                            'name':
                                (m['nfo_name']?.toString() ?? '').trim().isNotEmpty
                                ? m['nfo_name']?.toString() ?? ''
                                : m['filename']?.toString() ?? '',
                          },
                        ],
                        initialIndex: 0,
                      ignoreFindSub: 0,
                      );
                    }
                  : canPlayTv
                  ? () async {
                      final res = await VideoDetailApiService.instance
                          .getTvPlayInfo(ctrl.indexId, showLoading: true);
                      if (!res.success || res.data == null) {
                        ToastUtil.show(
                          res.message ?? 'video_detail_load_failed'.tr,
                        );
                        return;
                      }

                      final data = res.data!;
                      final rawList = data['playlist'];
                      final list = rawList is List ? rawList : const [];
                      final playlist = list
                          .whereType<Map>()
                          .map((e) => e.cast<String, dynamic>())
                          .toList();
                      final initialIndex =
                          (data['initialIndex'] as num?)?.toInt() ?? 0;
                      if (playlist.isEmpty) {
                        ToastUtil.show(
                          res.message ?? 'video_detail_load_failed'.tr,
                        );
                        return;
                      }

                      AppRoutes.toVideoPlayer(
                        playlist: playlist,
                        initialIndex: initialIndex,
                        ignoreFindSub: 0,
                      );
                    }
                  : null,
              isPrimary: true,
              icon: const Icon(Icons.play_arrow),
              height: 44,
            ),
            CustomButton(
              text: 'refresh'.tr,
              onPressed: () => ctrl.refreshDetail(showLoading: true),
              isPrimary: false,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                foregroundColor: theme.colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kActionButtonRadius),
                ),
              ),
              icon: const Icon(Icons.refresh),
              height: 44,
            ),
            CustomButton(
              text: 'favorites'.tr,
              onPressed: _favoriteLoading ? null : _toggleFavorite,
              isPrimary: false,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                foregroundColor: theme.colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kActionButtonRadius),
                ),
              ),
              icon: Icon(
                _effectiveFavorite ? Icons.favorite : Icons.favorite_border,
              ),
              height: 44,
            ),
            _OperationMenu(ctrl: ctrl),
          ],
        ),
        if (showProgress) ...[
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 3),
              SizedBox(
                width: 170,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blue.shade400,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Text(
                ctrl.mediaType == 'season' && epNum > 0
                    ? 'video_detail_watched_episode'.trParams({
                        'time': _formatSeconds(watched),
                        'ep': epNum.toString(),
                      })
                    : 'video_detail_watched'.trParams({
                        'time': _formatSeconds(watched),
                      }),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _OperationMenu extends StatelessWidget {
  final VideoDetailController ctrl;

  const _OperationMenu({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = ctrl.item!;
    final mediaType = (m['media_type']?.toString() ?? '').trim().toLowerCase();
    final filePath = (m['full_path']?.toString() ?? '').trim();
    final basePath = (m['path']?.toString() ?? '').trim();
    final filename = (m['filename']?.toString() ?? '').trim();
    final isMovieLike = mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts';
    final isAdmin = CurrentUserController.instance.isAdmin;
    final canEditOpenSkip = isAdmin && ctrl.canEditOpenSkip;

    String resolveBrowsePath() {
      if (isMovieLike) {
        if (filePath.isNotEmpty) return p.dirname(filePath);
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.dirname(p.join(basePath, filename));
        }
      }
      if (mediaType == 'tv' || mediaType == 'season') {
        if (filePath.isNotEmpty) return filePath;
      }
      if (basePath.isNotEmpty) return basePath;
      if (filePath.isNotEmpty) return p.dirname(filePath);
      return '';
    }

    String resolveDeletePath() {
      if (mediaType == 'bdmv') {
        if (filePath.isNotEmpty) return p.join(filePath, 'BDMV');
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.join(basePath, filename, 'BDMV');
        }
        return '';
      }
      if (mediaType == 'video_ts') {
        if (filePath.isNotEmpty) return p.join(filePath, 'VIDEO_TS');
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.join(basePath, filename, 'VIDEO_TS');
        }
        return '';
      }
      if (isMovieLike) {
        if (filePath.isNotEmpty) return filePath;
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.join(basePath, filename);
        }
      }
      if (basePath.isNotEmpty) return basePath;
      return filePath;
    }

    String resolveDownloadPath() {
      if (isMovieLike) {
        if (filePath.isNotEmpty) return filePath;
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.join(basePath, filename);
        }
        return '';
      }

      if (mediaType == 'tv' || mediaType == 'season') {
        if (filePath.isNotEmpty) return filePath;
        if (basePath.isNotEmpty && filename.isNotEmpty) {
          return p.join(basePath, filename);
        }
        return basePath;
      }

      if (filePath.isNotEmpty) return filePath;
      if (basePath.isNotEmpty && filename.isNotEmpty) {
        return p.join(basePath, filename);
      }
      return basePath;
    }

    Future<void> openInFileBrowser() async {
      final target = resolveBrowsePath();
      if (target.isEmpty) return;
      if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
        PcHomeController.instance.openFolderAt(target);
        return;
      }
      AppRoutes.toFiles(initialPath: target);
    }

    Future<void> deleteItem() async {
      final target = resolveDeletePath();
      if (target.isEmpty) return;

      final isMovie = isMovieLike;
      final isShellSupported = ApiController.instance.state.shellSupported;
      var deleteScrapeFiles = true;
      var recycle = isShellSupported;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setState) {
              return DialogUtil.createAlertDialog(
                title: Text('need_confirm'.tr),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'video_delete_confirm_path'.trParams({'path': target}),
                    ),
                    if (isMovie) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: deleteScrapeFiles,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) => setState(() {
                          deleteScrapeFiles = v == true;
                        }),
                        title: Text('video_delete_with_scrape_files'.tr),
                      ),
                    ],
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: recycle,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: isShellSupported
                          ? (v) => setState(() {
                              recycle = v == true;
                            })
                          : null,
                      title: Text(
                        'put_in_recycle_bin'.tr,
                        style: TextStyle(
                          color: isShellSupported
                              ? null
                              : Theme.of(context).textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Get.back(result: false),
                    child: Text('cancel'.tr),
                  ),
                  TextButton(
                    onPressed: () => Get.back(result: true),
                    child: Text('ok'.tr),
                  ),
                ],
              );
            },
          );
        },
      );
      if (ok != true) return;

      void closeDetailAfterDelete() {
        if (Get.isRegistered<VideoMainController>()) {
          final mainCtrl = Get.find<VideoMainController>();
          if (mainCtrl.activeSubDetailIndexId.value == ctrl.indexId) {
            mainCtrl.closeSubDetail();
            return;
          }
          mainCtrl.closeDetail();
          return;
        }
        AppRoutes.back();
      }

      final res = await FileApiService.instance.deleteEntries([
        target,
      ], deleteScrapeFiles: isMovie && deleteScrapeFiles, recycle: recycle);
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      VideoItemSyncService.notifyDeleted(ctrl.indexId);
      closeDetailAfterDelete();
      ToastUtil.show('operation_success'.tr);
    }

    Future<void> startAutoScrape() async {
      if (ctrl.indexId <= 0) return;
      final res = await VideoScrapeApiService.instance.startScrape(
        indexId: ctrl.indexId,
        mode: 'auto',
        showLoading: false,
      );
      if (!res.success) {
        ToastUtil.show('video_scrape_start_failed'.tr);
        return;
      }
      final data = res.data ?? const <String, dynamic>{};
      final started = data['started'] == true;
      final skipped = data['skipped'] == true;
      if (!started && skipped) {
        ToastUtil.show('video_scrape_skipped_existing_nfo'.tr);
        return;
      }
      if (!started) {
        ToastUtil.show('video_scrape_start_failed'.tr);
        return;
      }
      ToastUtil.show('video_scrape_started'.tr);
    }

    Future<void> cleanupScrapeInfo() async {
      if (ctrl.indexId <= 0) return;
      final ok = await DialogUtil.showConfirmDialog(
        title: 'need_confirm'.tr,
        content: 'video_scrape_cleanup_confirm'.tr,
        confirmText: 'ok'.tr,
        cancelText: 'cancel'.tr,
      );
      if (ok != true) return;

      final res = await VideoScrapeApiService.instance.cleanupScrape(
        indexId: ctrl.indexId,
        showLoading: true,
      );
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
    }

    Future<void> scanChanges() async {
      if (ctrl.indexId <= 0) return;
      final res = await VideoSourceApiService.instance.scanIndex(
        ctrl.indexId,
        showLoading: false,
      );
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
    }

    void searchMedia() {
      final bean = VideoHomeItemBean.fromJson(Map<String, dynamic>.from(m));
      VideoSearchMediaDialog.show(context, item: bean);
    }

    Future<void> editOpenSkip() async {
      if (!canEditOpenSkip || ctrl.indexId <= 0) return;
      final form = await showVideoOpenSkipDialog(
        context,
        initialStartSeconds: ctrl.openSkipStartSeconds,
        initialEndSeconds: ctrl.openSkipEndSeconds,
      );
      if (form == null) return;
      final res = await VideoDetailApiService.instance.setOpenSkip(
        ctrl.indexId,
        openSkipStartSec: form.startSeconds,
        openSkipEndSec: form.endSeconds,
        showLoading: true,
      );
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      await ctrl.refreshDetail(showLoading: false);
      ToastUtil.show('operation_success'.tr);
    }

    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: (v) async {
        if (v == 'download') {
          final target = resolveDownloadPath();
          if (target.isEmpty) return;
          if (!Get.isRegistered<DownloadController>()) {
            Get.put(DownloadController(), permanent: true);
          }
          await Get.find<DownloadController>().handleDownload([target]);
          return;
        }
        if (v == 'file_browse') {
          await openInFileBrowser();
          return;
        }
        if (v == 'delete') {
          await deleteItem();
          return;
        }
        if (v == 'search_media') {
          searchMedia();
          return;
        }
        if (v == 'open_skip') {
          await editOpenSkip();
          return;
        }
        if (v == 'scrape_auto') {
          await startAutoScrape();
          return;
        }
        if (v == 'scrape_cleanup') {
          await cleanupScrapeInfo();
          return;
        }
        if (v == 'scan_changes') {
          await scanChanges();
          return;
        }
      },
      itemBuilder: (_) {
        final downloadTarget = resolveDownloadPath();
        final items = <PopupMenuEntry<String>>[];
        items.add(
          PopupMenuItem(
            value: 'download',
            enabled: downloadTarget.isNotEmpty,
            child: Text('download'.tr),
          ),
        );

        if (isAdmin) {
          items.add(const PopupMenuDivider());
          items.addAll([
            PopupMenuItem(
              value: 'search_media',
              child: Text('video_search_media_info'.tr),
            ),
            if (canEditOpenSkip)
              PopupMenuItem(
                value: 'open_skip',
                child: Text('video_detail_open_skip'.tr),
              ),
            PopupMenuItem(
              value: 'scrape_auto',
              child: Text('video_scrape_auto'.tr),
            ),
            PopupMenuItem(
              value: 'scrape_cleanup',
              child: Text('video_scrape_cleanup'.tr),
            ),
            PopupMenuItem(
              value: 'scan_changes',
              child: Text('video_item_scan_changes'.tr),
            ),
          ]);
        }

        items.add(const PopupMenuDivider());
        items.addAll([
          PopupMenuItem(value: 'file_browse', child: Text('file_browse'.tr)),
          PopupMenuItem(
            value: 'delete',
            child: Text(
              'delete'.tr,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ]);
        return items;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.more_horiz),
            label: Text('video_detail_operation'.tr),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundColor: theme.colorScheme.onSurface,
              disabledBackgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
              disabledForegroundColor: theme.colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kActionButtonRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
