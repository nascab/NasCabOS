import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:get/get.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../utils/browse_path_utils.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/format_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../base/components/app_item_action_sheet.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../base/components/custom_no_data.dart';
import '../../../../../modules/home/views/pc_home_controller.dart';
import '../../../../files/service/file_api_service.dart';
import '../../controller/music_sub_list_controller.dart';
import '../../../list/models/music_list_models.dart';
import '../../../list/view/parts/music_item_context_menu.dart';
import '../../../play_service/controller/music_play_service_controller.dart';

class MusicSubListTable extends StatelessWidget {
  final MusicSubListController controller;
  final ScrollController scrollController;

  const MusicSubListTable({
    super.key,
    required this.controller,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.items.isEmpty) {
        return CustomNoData(text: 'no_data'.tr);
      }

      final playCtrl = Get.isRegistered<MusicPlayServiceController>()
          ? Get.find<MusicPlayServiceController>()
          : null;
      final showPlayerBar =
          playCtrl != null &&
          playCtrl.isReady.value &&
          playCtrl.playlist.isNotEmpty;
      final playerExtraSpace = showPlayerBar
          ? (112.0 + MediaQuery.of(context).padding.bottom)
          : 0.0;

      final showMultiBar = controller.isMultiSelectMode.value;
      final bottomSpace = (showMultiBar ? 66.0 : 20.0) + playerExtraSpace;
      final isApp = DeviceUtils.isMobile || DeviceUtils.isPhone(context);
      return Scrollbar(
        thumbVisibility: true,
        controller: scrollController,
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverFixedExtentList(
              itemExtent: 62,
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = controller.items[index];
                if (isApp) {
                  return _MobileDataRow(
                    key: ValueKey('music_sub_row_mobile_${item.id}'),
                    controller: controller,
                    item: item,
                    index: index,
                  );
                }
                return _DataRow(
                  key: ValueKey('music_sub_row_${item.id}'),
                  controller: controller,
                  item: item,
                  index: index,
                );
              }, childCount: controller.items.length),
            ),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: ValueKey('music_sub_list_footer'),
                child: _Footer(controller: controller),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomSpace)),
          ],
        ),
      );
    });
  }
}

class _DataRow extends StatefulWidget {
  final MusicSubListController controller;
  final MusicListItem item;
  final int index;

  const _DataRow({
    super.key,
    required this.controller,
    required this.item,
    required this.index,
  });

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hovered = false;

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

  MusicListItem? _currentPlayingItem(MusicPlayServiceController controller) {
    final idx = controller.currentIndex.value;
    if (idx < 0 || idx >= controller.playlist.length) return null;
    return controller.playlist[idx];
  }

  Widget _buildWaveIndicator(double size, {Color? color}) {
    return SpinKitWave(
      color: (color ?? Colors.white).withValues(alpha: 0.9),
      size: size,
      itemCount: 6,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final selectionMode = widget.controller.isMultiSelectMode.value;
      final selected = widget.controller.selectedItems.contains(widget.item.id);
      final playCtrl = MusicPlayServiceController.instance;
      final currentItem = _currentPlayingItem(playCtrl);
      final currentPath = currentItem == null
          ? ''
          : _resolvePlayablePath(currentItem);
      final itemPath = _resolvePlayablePath(widget.item);
      final isCurrent = currentPath.isNotEmpty && currentPath == itemPath;
      final isPlaying = isCurrent && playCtrl.isPlaying.value;
      final titleStyle = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      );
      final effectiveTitleStyle = isCurrent
          ? (titleStyle?.copyWith(color: theme.colorScheme.primary) ??
                TextStyle(color: theme.colorScheme.primary))
          : titleStyle;
      final subStyle = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
      );
      final tagStyle = theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
      );
      final subtitle = [
        widget.item.artist.trim(),
        widget.item.album.trim(),
      ].where((v) => v.isNotEmpty).join(' · ');
      final tagText = _buildAudioTagText(widget.item);
      final entries = MusicItemContextMenu.buildEntries(
        selectionMode: selectionMode,
        isFavorite: widget.item.isFavorite,
        inPlayList: widget.controller.isInPlayList,
        isSameMachine: DeviceUtils.isDesktopOrWeb &&
            ApiController.instance.isSameMachine,
        onFileBrowse: () => _openInFileBrowser(context),
        onToggleFavorite: () => widget.controller.toggleFavorite(widget.item),
        onDownload: () => widget.controller.downloadItem(widget.item),
        onAddToPlayList: () => widget.controller.addToPlayListItem(widget.item),
        onRemoveFromPlayList: () =>
            widget.controller.removeFromPlayListItem(widget.item),
        onDelete: () => widget.controller.deleteItem(widget.item),
        onShowInSystem: () async {
          final item = widget.item;
          final full = item.fullPath.trim();
          final path = full.isNotEmpty
              ? full
              : (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty)
                  ? '${item.path.trim()}/${item.filename.trim()}'
                  : '';
          if (path.isEmpty) return;
          final res = await FileApiService.instance.showInSystem(path);
          if (!res.success) {
            ToastUtil.show(res.message ?? 'operation_failed'.tr);
          }
        },
        onOpenInSystem: () async {
          final item = widget.item;
          final full = item.fullPath.trim();
          final path = full.isNotEmpty
              ? full
              : (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty)
                  ? '${item.path.trim()}/${item.filename.trim()}'
                  : '';
          if (path.isEmpty) return;
          final res = await FileApiService.instance.openInSystem(path);
          if (!res.success) {
            ToastUtil.show(res.message ?? 'operation_failed'.tr);
          }
        },
      );
      final overlayColor = selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : theme.colorScheme.onSurface.withValues(alpha: 0.03);

      final row = InkWell(
        onTap: () {
          if (selectionMode) {
            widget.controller.toggleSelection(widget.item.id);
            return;
          }
          if (isCurrent) {
            if (playCtrl.isPlaying.value) {
              playCtrl.pause();
            } else {
              playCtrl.play();
            }
            return;
          }
          widget.controller.playAt(widget.index);
        },
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Stack(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Center(
                      child: selectionMode
                          ? CustomCheckbox(
                              value: selected,
                              onChanged: (_) => widget.controller
                                  .toggleSelection(widget.item.id),
                              isCircle: false,
                            )
                          : (_hovered
                                ? Icon(
                                    isPlaying ? Icons.pause : Icons.play_arrow,
                                    size: 18,
                                  )
                                : isPlaying
                                ? _buildWaveIndicator(
                                    14,
                                    color: theme.colorScheme.primary,
                                  )
                                : Text('${widget.index + 1}', style: subStyle)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CoverThumb(
                    filePath: _resolvePathForCover(widget.item),
                    hasInnerCover: widget.item.hasInnerCover,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: effectiveTitleStyle,
                        ),
                        if (tagText.isNotEmpty || subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (tagText.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: theme.colorScheme.secondary
                                          .withValues(alpha: 0.4),
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tagText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tagStyle,
                                  ),
                                ),
                              if (tagText.isNotEmpty && subtitle.isNotEmpty)
                                const SizedBox(width: 6),
                              if (subtitle.isNotEmpty)
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: subStyle,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: widget.item.isFavorite
                        ? 'unfavorite'.tr
                        : 'favorites'.tr,
                    onPressed: () =>
                        widget.controller.toggleFavorite(widget.item),
                    icon: Icon(
                      widget.item.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 20,
                      color: widget.item.isFavorite ? Colors.red : null,
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        FormatUtil.formatDurationSeconds(
                          widget.item.duration,
                          autoPadZero: true,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subStyle,
                      ),
                    ),
                  ),
                ],
              ),
              if (selectionMode)
                Positioned.fill(
                  child: IgnorePointer(child: Container(color: overlayColor)),
                ),
            ],
          ),
        ),
      );

      if (!DeviceUtils.isDesktop && !DeviceUtils.isWeb) return row;

      final hoverChild = MouseRegion(
        onEnter: (_) {
          if (widget.controller.isScrolling.value) return;
          if (_hovered) return;
          setState(() => _hovered = true);
        },
        onExit: (_) {
          if (!_hovered) return;
          setState(() => _hovered = false);
        },
        child: row,
      );

      if (entries.isEmpty) return hoverChild;
      return ContextMenuUtil.region(child: hoverChild, entries: entries);
    });
  }

  static String _resolvePathForCover(MusicListItem item) {
    final full = item.fullPath.trim();
    final base = item.path.trim();
    final name = item.filename.trim();
    return full.isNotEmpty
        ? full
        : (base.isNotEmpty && name.isNotEmpty ? '$base/$name' : '');
  }

  static String _buildAudioTagText(MusicListItem item) {
    final parts = <String>[];
    final sampleRate = item.sampleRate ?? 0;
    final bitrate = item.bitrate ?? 0;
    final bitDepth = item.bitDepth ?? 0;
    if (bitDepth > 0) {
      parts.add('${bitDepth}bit');
    }
    if (sampleRate > 0) {
      parts.add(_formatSampleRate(sampleRate));
    } else if (bitrate > 0) {
      parts.add(_formatBitrate(bitrate));
    }
    if (parts.isEmpty) return '';
    return parts.join('|');
  }

  static String _formatBitrate(int bitrate) {
    final kbps = (bitrate / 1000).round();
    return '${kbps}kbps';
  }

  static String _formatSampleRate(int sampleRate) {
    final khz = sampleRate / 1000;
    final text = khz % 1 == 0 ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1);
    return '${text}khz';
  }

  void _openInFileBrowser(BuildContext context) {
    final item = widget.item;
    final full = item.fullPath.trim();
    final base = item.path.trim();
    final String target;
    if (item.isSeries) {
      final raw = full.isNotEmpty ? full : base;
      target = browseFolderPathMusic(raw);
    } else if (full.isNotEmpty) {
      target = browseFolderPathMusic(full);
    } else {
      target = browseFolderPathMusic(base);
    }
    if (target.isEmpty) return;
    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      PcHomeController.instance.openFolderAt(target);
      return;
    }
    AppRoutes.toFiles(initialPath: target);
  }
}

class _MobileDataRow extends StatefulWidget {
  final MusicSubListController controller;
  final MusicListItem item;
  final int index;

  const _MobileDataRow({
    super.key,
    required this.controller,
    required this.item,
    required this.index,
  });

  @override
  State<_MobileDataRow> createState() => _MobileDataRowState();
}

class _MobileDataRowState extends State<_MobileDataRow> {
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

  MusicListItem? _currentPlayingItem(MusicPlayServiceController controller) {
    final idx = controller.currentIndex.value;
    if (idx < 0 || idx >= controller.playlist.length) return null;
    return controller.playlist[idx];
  }

  void _openItem() {
    if (widget.item.isSeries) {
      _openSeries();
      return;
    }
    final playCtrl = MusicPlayServiceController.instance;
    final currentItem = _currentPlayingItem(playCtrl);
    final currentPath = currentItem == null
        ? ''
        : _resolvePlayablePath(currentItem);
    final itemPath = _resolvePlayablePath(widget.item);
    final isCurrent = currentPath.isNotEmpty && currentPath == itemPath;
    if (isCurrent) {
      if (playCtrl.isPlaying.value) {
        playCtrl.pause();
      } else {
        playCtrl.play();
      }
      return;
    }
    widget.controller.playAt(widget.index);
  }

  void _openSeries() {
    final seriesIndexId = widget.item.id;
    if (seriesIndexId <= 0) return;
    final overlayCtrl = Get.isRegistered<MusicSubListOverlayController>()
        ? Get.find<MusicSubListOverlayController>()
        : Get.put(MusicSubListOverlayController());
    overlayCtrl.open(
      keyType: 'series',
      name: widget.item.displayTitle,
      seriesIndexId: seriesIndexId,
    );
  }

  static String _resolvePathForCover(MusicListItem item) {
    final full = item.fullPath.trim();
    final base = item.path.trim();
    final name = item.filename.trim();
    return full.isNotEmpty
        ? full
        : (base.isNotEmpty && name.isNotEmpty ? '$base/$name' : '');
  }

  List<AppItemActionSheetEntry> _buildMobileActionSheetEntries(
    BuildContext context,
  ) {
    final selectionMode = widget.controller.isMultiSelectMode.value;
    if (selectionMode) return const <AppItemActionSheetEntry>[];
    final inPlayList = widget.controller.isInPlayList;
    return <AppItemActionSheetEntry>[
      AppItemActionSheetAction(
        title: 'open'.tr,
        icon: const Icon(Icons.open_in_new),
        onTap: _openItem,
      ),
      AppItemActionSheetAction(
        title: 'file_browse'.tr,
        icon: const Icon(Icons.folder_open_outlined),
        onTap: () => _openInFileBrowser(context),
      ),
      const AppItemActionSheetDivider(),
      AppItemActionSheetAction(
        title: (widget.item.isFavorite ? 'unfavorite'.tr : 'favorites'.tr),
        icon: Icon(
          widget.item.isFavorite ? Icons.favorite : Icons.favorite_border,
          color: widget.item.isFavorite ? Colors.red : null,
        ),
        onTap: () => widget.controller.toggleFavorite(widget.item),
      ),
      AppItemActionSheetAction(
        title: 'download'.tr,
        icon: const Icon(Icons.download_outlined),
        onTap: () => widget.controller.downloadItem(widget.item),
      ),
      const AppItemActionSheetDivider(),
      AppItemActionSheetAction(
        title: 'add_to_play_list'.tr,
        icon: const Icon(Icons.playlist_add),
        onTap: () => widget.controller.addToPlayListItem(widget.item),
      ),
      if (inPlayList)
        AppItemActionSheetAction(
          title: 'remove_from_play_list'.tr,
          icon: const Icon(Icons.playlist_remove),
          onTap: () => widget.controller.removeFromPlayListItem(widget.item),
        ),
      const AppItemActionSheetDivider(),
      AppItemActionSheetAction(
        title: 'delete'.tr,
        titleColor: Colors.red,
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onTap: () => widget.controller.deleteItem(widget.item),
      ),
    ];
  }

  Widget _buildActionSheetLeading(BuildContext context) {
    final theme = Theme.of(context);
    final filePath = _resolvePathForCover(widget.item);
    final url = filePath.trim().isEmpty || widget.item.hasInnerCover != 1
        ? ''
        : ApiController.instance.getMusicCoverUrl(
            filePath: filePath,
            size: 180,
          );
    final border = BorderRadius.circular(10);

    Widget fallback() {
      final seed = filePath.hashCode;
      final idx = Random(seed).nextInt(20) + 1;
      return ClipRRect(
        borderRadius: border,
        child: Container(
          width: 52,
          height: 52,
          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
          child: Image.asset(
            'assets/music/musicCover/other$idx.jpg',
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (url.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: border,
      child: CustomExtendedImage(
        imageUrl: url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }

  Future<void> _showMobileActionSheet(BuildContext context) async {
    await AppItemActionSheet.show(
      context,
      headerLeading: _buildActionSheetLeading(context),
      headerTitle: widget.item.displayTitle,
      headerSubtitle: widget.item.displaySubtitle,
      entries: _buildMobileActionSheetEntries(context),
    );
  }

  void _openInFileBrowser(BuildContext context) {
    final item = widget.item;
    final full = item.fullPath.trim();
    final base = item.path.trim();
    final String target;
    if (item.isSeries) {
      final raw = full.isNotEmpty ? full : base;
      target = browseFolderPathMusic(raw);
    } else if (full.isNotEmpty) {
      target = browseFolderPathMusic(full);
    } else {
      target = browseFolderPathMusic(base);
    }
    if (target.isEmpty) return;
    if (DeviceUtils.isDesktop && Get.isRegistered<PcHomeController>()) {
      PcHomeController.instance.openFolderAt(target);
      return;
    }
    AppRoutes.toFiles(initialPath: target);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final theme = Theme.of(context);
      final selectionMode = widget.controller.isMultiSelectMode.value;
      final selected = widget.controller.selectedItems.contains(widget.item.id);

      final playCtrl = MusicPlayServiceController.instance;
      final currentItem = _currentPlayingItem(playCtrl);
      final currentPath = currentItem == null
          ? ''
          : _resolvePlayablePath(currentItem);
      final itemPath = _resolvePlayablePath(widget.item);
      final isCurrent = currentPath.isNotEmpty && currentPath == itemPath;
      final isPlaying = isCurrent && playCtrl.isPlaying.value;

      final titleStyle = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      );
      final effectiveTitleStyle = isCurrent
          ? (titleStyle?.copyWith(color: theme.colorScheme.primary) ??
                TextStyle(color: theme.colorScheme.primary))
          : titleStyle;
      final subStyle = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
      );

      Widget cover() {
        final base = _CoverThumb(
          filePath: _resolvePathForCover(widget.item),
          hasInnerCover: widget.item.hasInnerCover,
        );
        if (!isPlaying) return base;
        return Stack(
          children: [
            base,
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: Center(
                    child: SpinKitWave(
                      color: theme.colorScheme.primary.withValues(alpha: 0.9),
                      size: 16,
                      itemCount: 6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }

      final row = InkWell(
        onTap: () {
          if (selectionMode) {
            widget.controller.toggleSelection(widget.item.id);
            return;
          }
          _openItem();
        },
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              if (selectionMode) ...[
                CustomCheckbox(
                  value: selected,
                  onChanged: (_) =>
                      widget.controller.toggleSelection(widget.item.id),
                  isCircle: false,
                ),
                const SizedBox(width: 10),
              ],
              cover(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: effectiveTitleStyle,
                    ),
                    if (widget.item.displaySubtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.item.displaySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: subStyle,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: selectionMode
                    ? null
                    : () => _showMobileActionSheet(context),
                icon: const Icon(Icons.more_vert, size: 20),
              ),
            ],
          ),
        ),
      );

      if (!selectionMode) return row;

      final overlayColor = selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : theme.colorScheme.onSurface.withValues(alpha: 0.03);
      return Stack(
        children: [
          row,
          Positioned.fill(
            child: IgnorePointer(child: Container(color: overlayColor)),
          ),
        ],
      );
    });
  }
}

class _CoverThumb extends StatelessWidget {
  final String filePath;
  final int hasInnerCover;
  const _CoverThumb({required this.filePath, this.hasInnerCover = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = filePath.trim().isEmpty || hasInnerCover != 1
        ? ''
        : ApiController.instance.getMusicCoverUrl(
            filePath: filePath,
            size: 120,
          );
    final border = BorderRadius.circular(8);

    Widget fallback() {
      final seed = filePath.hashCode;
      final idx = Random(seed).nextInt(20) + 1;
      return ClipRRect(
        borderRadius: border,
        child: Container(
          width: 46,
          height: 46,
          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
          child: Image.asset(
            'assets/music/musicCover/other$idx.jpg',
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (url.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: border,
      child: CustomExtendedImage(
        imageUrl: url,
        width: 46,
        height: 46,
        fit: BoxFit.cover,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => fallback(),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final MusicSubListController controller;
  const _Footer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loadingMore.value) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      if (!controller.hasMore.value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Center(child: Text('music_list_no_more'.tr)),
        );
      }

      if (!controller.autoLoadFailed.value) {
        return const SizedBox(height: 20);
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: OutlinedButton(
            onPressed: () =>
                controller.loadMore(fromAuto: false).catchError((_) {}),
            child: Text('music_list_load_more'.tr),
          ),
        ),
      );
    });
  }
}
