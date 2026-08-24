import 'package:NasCabOS/core/routes/app_routes.dart';
import 'package:NasCabOS/modules/base/components/custom_extended_image.dart';
import 'package:NasCabOS/modules/video/base/beans/video_item_bean.dart';
import 'package:NasCabOS/modules/video/base/video_utils/video_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../files/service/file_api_service.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../video_utils/video_item_utils.dart';
import '../../favorite/service/video_favorite_api_service.dart';
import '../../scrape/service/video_scrape_api_service.dart';
import '../../source_setting/service/video_source_api_service.dart';
import '../../tmdb/view/video_search_media_dialog.dart';
import '../../album/service/video_album_api_service.dart';
import '../../album/view/dialogs/video_album_select_dialog.dart';

class AppVideoItemPoster extends StatelessWidget {
  final VideoHomeItemBean item;
  final double width;
  final double borderRadius;
  final double imageRadius;
  final double? progress;
  final ValueChanged<VideoHomeItemBean>? onDeleted;
  final ValueChanged<bool>? onFavoriteChanged;
  final int? currentAlbumId;
  final VoidCallback? onRemovedFromCurrentAlbum;

  const AppVideoItemPoster({
    super.key,
    required this.item,
    required this.width,
    this.borderRadius = 14,
    this.imageRadius = 12,
    this.progress,
    this.onDeleted,
    this.onFavoriteChanged,
    this.currentAlbumId,
    this.onRemovedFromCurrentAlbum,
  });

  Future<void> _toggleFavorite(VideoHomeItemBean item) async {
    if (item.id <= 0) return;
    final next = !item.isFavorite;
    final ok = next
        ? await VideoFavoriteApiService.instance.addFavorite(item.id)
        : await VideoFavoriteApiService.instance.removeFavorite(item.id);
    if (!ok) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    onFavoriteChanged?.call(next);
  }

  Future<void> _startAutoScrape(VideoHomeItemBean item) async {
    if (item.id <= 0) return;
    final res = await VideoScrapeApiService.instance.startScrape(
      indexId: item.id,
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

  Future<void> _cleanupScrapeInfo(VideoHomeItemBean item) async {
    if (item.id <= 0) return;
    final ok = await DialogUtil.showConfirmDialog(
      title: 'need_confirm'.tr,
      content: 'video_scrape_cleanup_confirm'.tr,
      confirmText: 'ok'.tr,
      cancelText: 'cancel'.tr,
    );
    if (ok != true) return;

    final res = await VideoScrapeApiService.instance.cleanupScrape(
      indexId: item.id,
      showLoading: true,
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> _scanChanges(VideoHomeItemBean item) async {
    if (item.id <= 0) return;
    final res = await VideoSourceApiService.instance.scanIndex(
      item.id,
      showLoading: false,
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
  }

  void _downloadItem(VideoHomeItemBean item) {
    final target = resolveVideoDownloadPath(item);
    if (target.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    Get.find<DownloadController>().handleDownload([target]);
  }

  Future<void> _deleteItem(VideoHomeItemBean item) async {
    final target = resolveVideoDeletePath(item);
    if (target.isEmpty) return;

    final isMovie = ['movie', 'bdmv', 'video_ts'].contains(item.mediaType.toLowerCase().trim());
    final isShellSupported = ApiController.instance.state.shellSupported;
    final dialogContext = Get.context;
    if (dialogContext == null) return;
    var deleteScrapeFiles = true;
    var recycle = isShellSupported;
    final ok = await showDialog<bool>(
      context: dialogContext,
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
    ToastUtil.show('operation_success'.tr);
    onDeleted?.call(item);
  }

  Future<void> _addToAlbum(BuildContext context, VideoHomeItemBean item) async {
    if (item.id <= 0) return;
    final selected = await VideoAlbumSelectDialog.show(
      context,
      initialSelectedId: currentAlbumId,
    );
    if (selected == null || selected.id <= 0) return;
    final res = await VideoAlbumApiService.instance.addAlbumIndexes(
      albumId: selected.id,
      indexIds: [item.id],
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> _removeFromAlbum(VideoHomeItemBean item) async {
    final albumId = currentAlbumId ?? 0;
    if (albumId <= 0) return;
    if (item.id <= 0) return;
    final res = await VideoAlbumApiService.instance.removeAlbumIndexes(
      albumId: albumId,
      indexIds: [item.id],
    );
    if (!res.success) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
    onRemovedFromCurrentAlbum?.call();
  }

  Future<void> _showActionMenu(BuildContext context) async {
    final isAdmin = CurrentUserController.instance.isAdmin;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isFavorite = item.isFavorite;
        final albumId = currentAlbumId ?? 0;
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new, size: 22),
              title: Text('open'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                AppRoutes.toVideoDetail(item.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, size: 22),
              title: Text('file_browse'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                final path = resolveVideoBrowsePath(item);
                if (path.isEmpty) return;
                AppRoutes.toFiles(initialPath: path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined, size: 22),
              title: Text('download'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _downloadItem(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, size: 22),
              title: Text('video_add_to_album'.tr),
              onTap: () {
                Navigator.of(ctx).pop();
                _addToAlbum(context, item);
              },
            ),
            if (albumId > 0)
              ListTile(
                leading: const Icon(Icons.playlist_remove, size: 22),
                title: Text('video_remove_from_album'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _removeFromAlbum(item);
                },
              ),
            ListTile(
              leading: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                size: 22,
              ),
              title: Text(
                isFavorite ? 'unfavorite'.tr : 'folder_add_favorite'.tr,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _toggleFavorite(item);
              },
            ),
            if (isAdmin) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.search, size: 22),
                title: Text('video_search_media_info'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  VideoSearchMediaDialog.show(context, item: item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome_outlined, size: 22),
                title: Text('video_scrape_auto'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _startAutoScrape(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, size: 22),
                title: Text('video_scrape_cleanup'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _cleanupScrapeInfo(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.sync, size: 22),
                title: Text('video_item_scan_changes'.tr),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _scanChanges(item);
                },
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                size: 22,
                color: Colors.red,
              ),
              title: Text(
                'delete'.tr,
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.red),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteItem(item);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _pill({required String text, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.nfoName.isNotEmpty ? item.nfoName : item.filename;
    final posterUrl = VideoUtils.getPosterUrl(item, size: 500);
    final safeProgress = progress?.clamp(0, 1).toDouble();
    final rating = item.nfoScore;
    final typeText = videoMediaTypeText(item.mediaType);
    final year = item.nfoYear > 0 ? item.nfoYear.toString() : '';
    final meta = buildVideoHomeMeta(item);
    final subtitle = <String>[
      year,
      meta,
    ].where((e) => e.isNotEmpty).join(' · ');

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: () => AppRoutes.toVideoDetail(item.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(imageRadius),
                    child: posterUrl.isNotEmpty
                        ? CustomExtendedImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            borderRadius: imageRadius,
                            showLoading: false,
                          )
                        : ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(imageRadius),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.72),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _showActionMenu(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (item.isFavorite)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                        child: Icon(
                          Icons.favorite,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Row(
                      children: [
                        if (rating > 0)
                          _pill(
                            text: rating.toStringAsFixed(1),
                            bg: Colors.black.withValues(alpha: 0.5),
                            fg: const Color.fromARGB(
                              255,
                              229,
                              181,
                              39,
                            ).withValues(alpha: 0.92),
                          ),
                        if (typeText.trim().isNotEmpty)
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _pill(
                                text: typeText,
                                bg: Colors.black.withValues(alpha: 0.5),
                                fg: Colors.white.withValues(alpha: 0.95),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (safeProgress != null && safeProgress > 0)
                    Positioned(
                      left: 8,
                      right: 8,
                      top: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: safeProgress,
                          minHeight: 5,
                          backgroundColor: Colors.black.withValues(alpha: 0.35),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
