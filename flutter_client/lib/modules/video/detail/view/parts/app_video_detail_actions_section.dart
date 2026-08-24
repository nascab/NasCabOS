import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../../../../core/api/api_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../core/user/current_user_controller.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../base/components/custom_icon_button.dart';
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
import '../../controller/video_detail_controller.dart';
import '../../service/video_detail_api_service.dart';
import 'video_open_skip_dialog.dart';

class AppVideoDetailActionsSection extends StatefulWidget {
  final VideoDetailController ctrl;

  const AppVideoDetailActionsSection({super.key, required this.ctrl});

  @override
  State<AppVideoDetailActionsSection> createState() =>
      _AppVideoDetailActionsSectionState();
}

class _AppVideoDetailActionsSectionState
    extends State<AppVideoDetailActionsSection> {
  bool? _isFavorite;
  bool _favoriteLoading = false;

  void _closeDetailAfterDelete() {
    if (Get.isRegistered<VideoMainController>()) {
      final mainCtrl = Get.find<VideoMainController>();
      if (mainCtrl.activeSubDetailIndexId.value == widget.ctrl.indexId) {
        mainCtrl.closeSubDetail();
        return;
      }
      mainCtrl.closeDetail();
      return;
    }
    AppRoutes.back();
  }

  bool get _effectiveFavorite {
    final raw = widget.ctrl.item?['is_favorite'];
    final fromCtrl = raw == true || raw == 1 || raw == '1';
    return _isFavorite ?? fromCtrl;
  }

  @override
  void didUpdateWidget(covariant AppVideoDetailActionsSection oldWidget) {
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

  String _resolveBrowsePath(Map<String, dynamic> m) {
    final mediaType = (m['media_type']?.toString() ?? '').trim().toLowerCase();
    final filePath = (m['full_path']?.toString() ?? '').trim();
    final basePath = (m['path']?.toString() ?? '').trim();
    final filename = (m['filename']?.toString() ?? '').trim();
    final isMovieLike = mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts';

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

  String _resolveDeletePath(Map<String, dynamic> m) {
    final mediaType = (m['media_type']?.toString() ?? '').trim().toLowerCase();
    final filePath = (m['full_path']?.toString() ?? '').trim();
    final basePath = (m['path']?.toString() ?? '').trim();
    final filename = (m['filename']?.toString() ?? '').trim();
    final isMovieLike = mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts';

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

  String _resolveDownloadPath(Map<String, dynamic> m) {
    final mediaType = (m['media_type']?.toString() ?? '').trim().toLowerCase();
    final filePath = (m['full_path']?.toString() ?? '').trim();
    final basePath = (m['path']?.toString() ?? '').trim();
    final filename = (m['filename']?.toString() ?? '').trim();
    final isMovieLike = mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts';

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

  Future<void> _openInFileBrowser(Map<String, dynamic> m) async {
    final target = _resolveBrowsePath(m);
    if (target.isEmpty) return;
    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      PcHomeController.instance.openFolderAt(target);
      return;
    }
    AppRoutes.toFiles(initialPath: target);
  }

  Future<void> _deleteItem(BuildContext context, Map<String, dynamic> m) async {
    final mediaType = (m['media_type']?.toString() ?? '').trim().toLowerCase();
    final target = _resolveDeletePath(m);
    if (target.isEmpty) return;

    final isMovie = mediaType == 'movie' || mediaType == 'bdmv' || mediaType == 'video_ts';
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
                  Text('video_delete_confirm_path'.trParams({'path': target})),
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

    final res = await FileApiService.instance.deleteEntries([
      target,
    ], deleteScrapeFiles: isMovie && deleteScrapeFiles, recycle: recycle);
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    VideoItemSyncService.notifyDeleted(widget.ctrl.indexId);
    _closeDetailAfterDelete();
    ToastUtil.show('operation_success'.tr);
  }

  void _downloadItem(Map<String, dynamic> m) {
    final target = _resolveDownloadPath(m);
    if (target.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    Get.find<DownloadController>().handleDownload([target]);
  }

  Future<void> _startAutoScrape() async {
    if (widget.ctrl.indexId <= 0) return;
    final res = await VideoScrapeApiService.instance.startScrape(
      indexId: widget.ctrl.indexId,
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

  Future<void> _cleanupScrapeInfo() async {
    if (widget.ctrl.indexId <= 0) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'video_scrape_cleanup_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    final res = await VideoScrapeApiService.instance.cleanupScrape(
      indexId: widget.ctrl.indexId,
      showLoading: true,
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> _scanChanges() async {
    if (widget.ctrl.indexId <= 0) return;
    final res = await VideoSourceApiService.instance.scanIndex(
      widget.ctrl.indexId,
      showLoading: false,
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
  }

  void _searchMedia() {
    final m = widget.ctrl.item;
    if (m == null) return;
    final bean = VideoHomeItemBean.fromJson(Map<String, dynamic>.from(m));
    VideoSearchMediaDialog.show(context, item: bean);
  }

  Future<void> _editOpenSkip(BuildContext context) async {
    if (!CurrentUserController.instance.isAdmin || !widget.ctrl.canEditOpenSkip) {
      return;
    }
    if (widget.ctrl.indexId <= 0) return;
    final form = await showVideoOpenSkipDialog(
      context,
      initialStartSeconds: widget.ctrl.openSkipStartSeconds,
      initialEndSeconds: widget.ctrl.openSkipEndSeconds,
    );
    if (form == null) return;
    final res = await VideoDetailApiService.instance.setOpenSkip(
      widget.ctrl.indexId,
      openSkipStartSec: form.startSeconds,
      openSkipEndSec: form.endSeconds,
      showLoading: true,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await widget.ctrl.refreshDetail(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> _showMoreSheet(
    BuildContext context,
    Map<String, dynamic> m,
  ) async {
    final theme = Theme.of(context);
    final isAdmin = CurrentUserController.instance.isAdmin;
    final canEditOpenSkip = isAdmin && widget.ctrl.canEditOpenSkip;
    final downloadTarget = _resolveDownloadPath(m);
    final browseTarget = _resolveBrowsePath(m);
    final deleteTarget = _resolveDeletePath(m);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined, size: 22),
              title: Text('download'.tr),
              enabled: downloadTarget.isNotEmpty,
              onTap: downloadTarget.isNotEmpty
                  ? () {
                      Navigator.of(ctx).pop();
                      _downloadItem(m);
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, size: 22),
              title: Text('file_browse'.tr),
              enabled: browseTarget.isNotEmpty,
              onTap: browseTarget.isNotEmpty
                  ? () async {
                      Navigator.of(ctx).pop();
                      await _openInFileBrowser(m);
                    }
                  : null,
            ),
            if (isAdmin) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.search, size: 22),
                title: Text('video_search_media_info'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _searchMedia();
                },
              ),
              if (canEditOpenSkip)
                ListTile(
                  leading: const Icon(Icons.skip_next_outlined, size: 22),
                  title: Text('video_detail_open_skip'.tr),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _editOpenSkip(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.auto_fix_high_outlined, size: 22),
                title: Text('video_scrape_auto'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _startAutoScrape();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, size: 22),
                title: Text('video_scrape_cleanup'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _cleanupScrapeInfo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync_outlined, size: 22),
                title: Text('video_item_scan_changes'.tr),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _scanChanges();
                },
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, size: 22),
              title: Text(
                'delete'.tr,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              enabled: deleteTarget.isNotEmpty,
              onTap: deleteTarget.isNotEmpty
                  ? () async {
                      Navigator.of(ctx).pop();
                      await _deleteItem(context, m);
                    }
                  : null,
            ),
          ],
        );
      },
    );
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

    final buttonBg = theme.colorScheme.surfaceContainerHighest;
    final onButton = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CustomIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: playText,
              iconColor: Colors.white,
              backgroundColor: Colors.blue.shade800,
              buttonSize: 42,
              iconSize: 22,
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
              borderRadius: 12,
            ),
            CustomIconButton(
              icon: Icons.refresh,
              tooltip: 'refresh'.tr,
              iconColor: onButton,
              backgroundColor: buttonBg,
              buttonSize: 42,
              iconSize: 21,
              onPressed: () => ctrl.refreshDetail(showLoading: true),
              borderRadius: 12,
            ),
            CustomIconButton(
              icon: _effectiveFavorite ? Icons.favorite : Icons.favorite_border,
              tooltip: _effectiveFavorite
                  ? 'unfavorite'.tr
                  : 'folder_add_favorite'.tr,
              iconColor: _effectiveFavorite ? Colors.redAccent : onButton,
              backgroundColor: buttonBg,
              buttonSize: 42,
              iconSize: 21,
              onPressed: _favoriteLoading ? null : _toggleFavorite,
              borderRadius: 12,
            ),
            CustomIconButton(
              icon: Icons.more_horiz,
              tooltip: 'video_detail_operation'.tr,
              iconColor: onButton,
              backgroundColor: buttonBg,
              buttonSize: 42,
              iconSize: 22,
              onPressed: () => _showMoreSheet(context, m),
              borderRadius: 12,
            ),
          ],
        ),
        if (showProgress) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            ctrl.mediaType == 'season' && epNum > 0
                ? 'video_detail_watched_episode'.trParams({
                    'time': _formatSeconds(watched),
                    'ep': epNum.toString(),
                  })
                : 'video_detail_watched'.trParams({
                    'time': _formatSeconds(watched),
                  }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}
