import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import '../../../base/components/custom_extended_image.dart';
import '../../../../core/api/api_controller.dart';
import '../beans/video_item_bean.dart';
import '../../../../core/user/current_user_controller.dart';
import '../../../../utils/context_menu_util.dart';
import '../../../base/components/custom_context_menu_item.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../utils/device_utils.dart';
import '../../scrape/service/video_scrape_api_service.dart';
import '../../source_setting/service/video_source_api_service.dart';
import '../../tmdb/view/video_search_media_dialog.dart';
import '../../../files/service/file_api_service.dart';
import '../../../home/views/pc_home_controller.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../video_utils/video_item_utils.dart';
import '../../album/service/video_album_api_service.dart';
import '../../album/view/dialogs/video_album_select_dialog.dart';

class VideoItemCoverImage extends StatelessWidget {
  final String imageUrl;
  final double borderRadius;
  final double rating;
  final String typeText;
  final bool hovered;

  const VideoItemCoverImage({
    super.key,
    required this.imageUrl,
    required this.borderRadius,
    required this.rating,
    required this.typeText,
    required this.hovered,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final scale = hovered ? 1.06 : 1.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              AnimatedScale(
                scale: scale,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: CustomExtendedImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  showLoading: false,
                  borderRadius: borderRadius,
                ),
              )
            else
              Container(color: theme.colorScheme.surfaceContainerHighest),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.78),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: _BadgeRow(rating: rating, typeText: typeText),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoItemContextMenuRegion extends StatelessWidget {
  final VideoHomeItemBean item;
  final Widget child;
  final VoidCallback onOpen;
  final ValueChanged<VideoHomeItemBean>? onDeleted;
  final int? currentAlbumId;
  final VoidCallback? onRemovedFromCurrentAlbum;

  const VideoItemContextMenuRegion({
    super.key,
    required this.item,
    required this.child,
    required this.onOpen,
    this.onDeleted,
    this.currentAlbumId,
    this.onRemovedFromCurrentAlbum,
  });

  @override
  Widget build(BuildContext context) {
    if (!DeviceUtils.isDesktopOrWeb) return child;

    Future<void> startAutoScrape() async {
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

    Future<void> cleanupScrapeInfo() async {
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

    Future<void> scanChanges() async {
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

    Future<void> openInFileBrowser() async {
      final target = resolveVideoBrowsePath(item);
      if (target.isEmpty) return;
      PcHomeController.instance.openFolderAt(target);
    }

    Future<void> deleteItem() async {
      final target = resolveVideoDeletePath(item);
      if (target.isEmpty) return;

      final isMovie = [
        'movie',
        'bdmv',
        'video_ts',
      ].contains(item.mediaType.toLowerCase().trim());
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

      final res = await FileApiService.instance.deleteEntries(
        [target],
        deleteScrapeFiles: isMovie && deleteScrapeFiles,
        recycle: recycle,
      );
      if (!res.success) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }
      ToastUtil.show('operation_success'.tr);
      onDeleted?.call(item);
    }

    void downloadItem() {
      final target = resolveVideoDownloadPath(item);
      if (target.isEmpty) return;
      if (!Get.isRegistered<DownloadController>()) {
        Get.put(DownloadController(), permanent: true);
      }
      Get.find<DownloadController>().handleDownload([target]);
    }

    Future<void> addToAlbum() async {
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

    Future<void> removeFromAlbum() async {
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

    final entries = <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.open_in_new, size: 18),
        value: 'open',
        onSelected: (_) => onOpen(),
      ),
      CustomContextMenuItem.create(
        label: Text('file_browse'.tr),
        icon: const Icon(Icons.folder_open, size: 18),
        value: 'file_browse',
        onSelected: (_) => openInFileBrowser(),
      ),
      CustomContextMenuItem.create(
        label: Text('download'.tr),
        icon: const Icon(Icons.download_outlined, size: 18),
        value: 'download',
        onSelected: (_) => downloadItem(),
      ),
      CustomContextMenuItem.create(
        label: Text('video_add_to_album'.tr),
        icon: const Icon(Icons.playlist_add, size: 18),
        value: 'add_to_album',
        onSelected: (_) => addToAlbum(),
      ),
    ];

    // 本机文件系统操作（仅桌面/Web端且客户端与服务端同机时显示）
    if (ApiController.instance.isSameMachine) {
      entries.add(const MenuDivider());
      entries.add(
        CustomContextMenuItem.create(
          label: Text('file_show_in_folder'.tr),
          icon: const Icon(Icons.folder_open, size: 18),
          value: 'show_in_system',
          onSelected: (_) async {
            if (!ApiController.instance.isServerVersionAtLeast(8)) {
              DialogUtil.showInfoDialog(
                title: 'tip'.tr,
                content: 'server_version_too_low'.tr,
              );
              return;
            }
            final path = item.fullPath.trim().isNotEmpty
                ? item.fullPath.trim()
                : resolveVideoBrowsePath(item);
            if (path.isEmpty) return;
            final res = await FileApiService.instance.showInSystem(path);
            if (!res.success) {
              ToastUtil.show(res.message ?? 'operation_failed'.tr);
            }
          },
        ),
      );
      entries.add(
        CustomContextMenuItem.create(
          label: Text('file_open_in_system'.tr),
          icon: const Icon(Icons.launch, size: 18),
          value: 'open_in_system',
          onSelected: (_) async {
            if (!ApiController.instance.isServerVersionAtLeast(8)) {
              DialogUtil.showInfoDialog(
                title: 'tip'.tr,
                content: 'server_version_too_low'.tr,
              );
              return;
            }
            final path = item.fullPath.trim().isNotEmpty
                ? item.fullPath.trim()
                : resolveVideoBrowsePath(item);
            if (path.isEmpty) return;
            final res = await FileApiService.instance.openInSystem(path);
            if (!res.success) {
              ToastUtil.show(res.message ?? 'operation_failed'.tr);
            }
          },
        ),
      );
    }

    final albumId = currentAlbumId ?? 0;
    if (albumId > 0) {
      entries.add(
        CustomContextMenuItem.create(
          label: Text('video_remove_from_album'.tr),
          icon: const Icon(Icons.playlist_remove, size: 18),
          value: 'remove_from_album',
          onSelected: (_) => removeFromAlbum(),
        ),
      );
    }

    final isAdmin = CurrentUserController.instance.isAdmin;
    if (isAdmin) {
      entries.add(const MenuDivider());
      entries.addAll([
        CustomContextMenuItem.create(
          label: Text('video_search_media_info'.tr),
          icon: const Icon(Icons.search, size: 18),
          value: 'search_media',
          onSelected: (_) => VideoSearchMediaDialog.show(context, item: item),
        ),
        CustomContextMenuItem.create(
          label: Text('video_scrape_auto'.tr),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          value: 'scrape_auto',
          onSelected: (_) => startAutoScrape(),
        ),
        CustomContextMenuItem.create(
          label: Text('video_scrape_cleanup'.tr),
          icon: const Icon(Icons.delete_outline, size: 18),
          value: 'scrape_cleanup',
          onSelected: (_) => cleanupScrapeInfo(),
        ),
        CustomContextMenuItem.create(
          label: Text('video_item_scan_changes'.tr),
          icon: const Icon(Icons.sync, size: 18),
          value: 'scan_changes',
          onSelected: (_) => scanChanges(),
        ),
      ]);
    }

    entries.add(const MenuDivider());
    entries.addAll([
      CustomContextMenuItem.create(
        label: Text('delete'.tr, style: TextStyle(color: Colors.red)),
        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
        value: 'delete',
        onSelected: (_) => deleteItem(),
      ),
    ]);

    return ContextMenuUtil.region(child: child, entries: entries);
  }
}

class _BadgeRow extends StatelessWidget {
  final double rating;
  final String typeText;

  const _BadgeRow({required this.rating, required this.typeText});

  static const _shortLabelMap = {'电视剧': '剧', '电影': '影'};

  @override
  Widget build(BuildContext context) {
    final hasRating = rating > 0;
    final hasType = typeText.trim().isNotEmpty;
    final ratingInt = rating.truncateToDouble() == rating;
    final ratingText = ratingInt
        ? rating.toInt().toString()
        : rating.toStringAsFixed(1);
    final displayTypeText = _shortLabelMap[typeText] ?? typeText;

    MainAxisAlignment alignment;
    if (hasRating && hasType) {
      alignment = MainAxisAlignment.spaceBetween;
    } else if (hasRating) {
      alignment = MainAxisAlignment.start;
    } else {
      alignment = MainAxisAlignment.end;
    }

    return Row(
      mainAxisAlignment: alignment,
      children: [
        if (hasRating)
          Flexible(
            child: _Pill(
              text: ratingText,
              bg: Colors.black.withValues(alpha: 0.55),
              fg: const Color.fromARGB(
                255,
                229,
                181,
                39,
              ).withValues(alpha: 0.92),
            ),
          ),
        if (hasType)
          Flexible(
            child: _Pill(
              text: displayTypeText,
              bg: Colors.black.withValues(alpha: 0.55),
              fg: Colors.white,
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;

  const _Pill({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.32)),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
