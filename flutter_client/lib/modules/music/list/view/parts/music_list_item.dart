import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:get/get.dart';
import '../../../../../utils/browse_path_utils.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_album.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../base/components/app_item_action_sheet.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../files/service/file_api_service.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../../../../modules/home/views/pc_home_controller.dart';
import '../../controller/music_list_controller.dart';
import '../../models/music_list_models.dart';
import '../../../playlist/service/play_list_api_service.dart';
import '../../../playlist/view/play_list_list_view.dart';
import '../../../favorite/service/music_favorite_api_service.dart';
import '../../../play_service/controller/music_play_service_controller.dart';
import '../../../sub_list/controller/music_sub_list_controller.dart';
import 'music_item_context_menu.dart';

class MusicItemCard extends StatefulWidget {
  final MusicListController controller;
  final MusicListItem item;
  final double width;
  final double coverSize;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelected;
  const MusicItemCard({
    super.key,
    required this.controller,
    required this.item,
    required this.width,
    required this.coverSize,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
  });

  @override
  State<MusicItemCard> createState() => _MusicItemCardState();
}

class _MusicItemCardState extends State<MusicItemCard> {
  bool _hovered = false;
  bool _favoriteLoading = false;
  bool? _isFavorite;

  bool get _effectiveFavorite => _isFavorite ?? widget.item.isFavorite;

  List<AppItemActionSheetEntry> _buildMobileActionSheetEntries(
    BuildContext context,
  ) {
    if (widget.selectionMode) return const <AppItemActionSheetEntry>[];
    final inPlayList = (widget.controller.listId ?? 0) > 0;
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
        title: (_effectiveFavorite ? 'unfavorite'.tr : 'favorites'.tr),
        icon: Icon(
          _effectiveFavorite ? Icons.favorite : Icons.favorite_border,
          color: _effectiveFavorite ? Colors.red : null,
        ),
        onTap: _toggleFavorite,
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
        onTap: () => _addToPlayList(context),
      ),
      if (inPlayList)
        AppItemActionSheetAction(
          title: 'remove_from_play_list'.tr,
          icon: const Icon(Icons.playlist_remove),
          onTap: _removeFromPlayList,
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

  Future<void> _showMobileActionSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final leading = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 52, height: 52, child: _buildCover(theme)),
    );
    await AppItemActionSheet.show(
      context,
      headerLeading: leading,
      headerTitle: widget.item.displayTitle,
      entries: _buildMobileActionSheetEntries(context),
    );
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
    final playableItems = widget.controller.items
        .where((e) => !e.isSeries)
        .toList(growable: false);
    if (playableItems.isEmpty) return;
    playCtrl.playFromList(
      items: playableItems,
      startItem: widget.item,
      paging: MusicPlaylistPaging.fromQuery(
        widget.controller.buildPagingQuery(),
      ),
    );
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

  @override
  void didUpdateWidget(covariant MusicItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _hovered = false;
      _favoriteLoading = false;
      _isFavorite = null;
      return;
    }
    if (oldWidget.item.isFavorite != widget.item.isFavorite) {
      if (_isFavorite == null) return;
      _isFavorite = null;
    }
  }

  List<ContextMenuEntry> _buildContextMenuEntries(BuildContext context) {
    final item = widget.item;
    final isSameMachine = DeviceUtils.isDesktopOrWeb &&
        ApiController.instance.isSameMachine;

    String resolvePath() {
      final full = item.fullPath.trim();
      if (full.isNotEmpty) return full;
      final dir = item.path.trim();
      final name = item.filename.trim();
      if (dir.isNotEmpty && name.isNotEmpty) return '$dir/$name';
      return '';
    }

    return MusicItemContextMenu.buildEntries(
      selectionMode: widget.selectionMode,
      isFavorite: _effectiveFavorite,
      inPlayList: (widget.controller.listId ?? 0) > 0,
      isSameMachine: isSameMachine,
      onOpen: _openItem,
      onFileBrowse: () => _openInFileBrowser(context),
      onToggleFavorite: _toggleFavorite,
      onDownload: () => widget.controller.downloadItem(widget.item),
      onAddToPlayList: () => _addToPlayList(context),
      onRemoveFromPlayList: _removeFromPlayList,
      onDelete: () => widget.controller.deleteItem(widget.item),
      onShowInSystem: () async {
        final path = resolvePath();
        if (path.isEmpty) return;
        final res = await FileApiService.instance.showInSystem(path);
        if (!res.success) {
          ToastUtil.show(res.message ?? 'operation_failed'.tr);
        }
      },
      onOpenInSystem: () async {
        final path = resolvePath();
        if (path.isEmpty) return;
        final res = await FileApiService.instance.openInSystem(path);
        if (!res.success) {
          ToastUtil.show(res.message ?? 'operation_failed'.tr);
        }
      },
    );
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) return;
    final id = widget.item.id;
    if (id <= 0) return;

    final prev = _effectiveFavorite;
    final next = !prev;

    setState(() {
      _favoriteLoading = true;
      _isFavorite = next;
    });

    try {
      final ok = next
          ? await MusicFavoriteApiService.instance.addFavorite(id)
          : await MusicFavoriteApiService.instance.removeFavorite(id);
      if (!ok) {
        if (mounted) {
          setState(() {
            _isFavorite = prev;
          });
        }
        return;
      }
      widget.controller.updateFavoriteState(id, next);
    } finally {
      if (mounted) {
        setState(() {
          _favoriteLoading = false;
        });
      }
    }
  }

  Future<void> _addToPlayList(BuildContext context) async {
    final indexId = widget.item.id;
    if (indexId <= 0) return;
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

  Future<void> _removeFromPlayList() async {
    await widget.controller.removeFromPlayListItem(widget.item);
  }

  String _buildSubtitleText() {
    if (widget.item.isSeries) {
      final cnt = widget.item.musicCount;
      return '${cnt < 0 ? 0 : cnt}首';
    }
    final al = widget.item.album.trim();
    final a = widget.item.artist.trim();
    if (al.isNotEmpty && a.isNotEmpty) return '$a · $al';
    if (al.isNotEmpty) return al;
    if (a.isNotEmpty) return a;
    return '';
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

  String _badgeLabel() {
    if (widget.item.isSeries) return 'series'.tr;
    var ext = widget.item.ext.trim();
    if (ext.isEmpty) {
      final name = widget.item.filename.trim();
      final i = name.lastIndexOf('.');
      ext = (i >= 0 && i < name.length - 1) ? name.substring(i + 1) : '';
    }
    ext = ext.replaceAll('.', '').trim();
    return ext.isEmpty ? '' : ext.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodySmall;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final subtitle = _buildSubtitleText();
    final entries = _buildContextMenuEntries(context);
    final badgeLabel = _badgeLabel();
    final showMoreButton = _hovered && entries.isNotEmpty;
    final showFavoriteButton =
        (_hovered || _effectiveFavorite) && !widget.selectionMode;
    final showSelectBox = widget.selectionMode || _hovered || widget.selected;

    final child = Column(
      children: [
        SizedBox(
          width: widget.coverSize,
          height: widget.coverSize,
          child: CustomAlbum(
            preview: Stack(
              fit: StackFit.expand,
              children: [
                _buildCover(theme),
                if (_hovered)
                  Container(color: Colors.black.withValues(alpha: 0.2)),
                if (!widget.selectionMode)
                  Obx(() {
                    final playCtrl = MusicPlayServiceController.instance;
                    final currentItem = _currentPlayingItem(playCtrl);
                    final currentPath = currentItem == null
                        ? ''
                        : _resolvePlayablePath(currentItem);
                    final itemPath = _resolvePlayablePath(widget.item);
                    final isCurrent =
                        currentPath.isNotEmpty && currentPath == itemPath;
                    final isPlaying = isCurrent && playCtrl.isPlaying.value;
                    final showHoverControl = _hovered;
                    if (!showHoverControl && !isPlaying) {
                      return const SizedBox.shrink();
                    }
                    if (showHoverControl) {
                      return Positioned.fill(
                        child: Center(
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                _openItem();
                              },
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  widget.item.isSeries
                                      ? Icons.folder_open
                                      : (isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow),
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return Positioned.fill(
                      child: Center(child: _buildWaveIndicator(26)),
                    );
                  }),
                if (showFavoriteButton)
                  Positioned(
                    top: 4,
                    left: 6,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _toggleFavorite,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.75,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: Icon(
                            _effectiveFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: _effectiveFavorite
                                ? Colors.red
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showMoreButton)
                  Positioned(
                    top: 4,
                    right: 6,
                    child: Builder(
                      builder: (context) {
                        final key = GlobalKey();
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              final box =
                                  key.currentContext?.findRenderObject()
                                      as RenderBox?;
                              final overlay =
                                  Overlay.of(context).context.findRenderObject()
                                      as RenderBox?;
                              if (box == null || overlay == null) return;
                              final pos = box.localToGlobal(
                                Offset.zero,
                                ancestor: overlay,
                              );
                              ContextMenuUtil.showAtPosition(
                                context,
                                entries: entries,
                                position: pos + const Offset(0, 30),
                              );
                            },
                            child: Container(
                              key: key,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.75,
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
                        );
                      },
                    ),
                  ),
                if (!showMoreButton && badgeLabel.isNotEmpty)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (DeviceUtils.isMobile && entries.isNotEmpty)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Builder(
                      builder: (context) {
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              _showMobileActionSheet(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.75,
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
                        );
                      },
                    ),
                  ),
                if (showSelectBox)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CustomCheckbox(
                      value: widget.selected,
                      onChanged: (_) => widget.onToggleSelected?.call(),
                      isCircle: true,
                      side: const BorderSide(color: Colors.white, width: 2.0),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 46,
          child: Column(
            children: [
              Obx(() {
                final playCtrl = MusicPlayServiceController.instance;
                final currentItem = _currentPlayingItem(playCtrl);
                final currentPath = currentItem == null
                    ? ''
                    : _resolvePlayablePath(currentItem);
                final itemPath = _resolvePlayablePath(widget.item);
                final isCurrent =
                    currentPath.isNotEmpty && currentPath == itemPath;
                final effectiveTitleStyle = isCurrent
                    ? (titleStyle?.copyWith(color: theme.colorScheme.primary) ??
                          TextStyle(color: theme.colorScheme.primary))
                    : titleStyle;
                return Tooltip(
                  message: widget.item.displayTitle,
                  child: Text(
                    widget.item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: effectiveTitleStyle,
                  ),
                );
              }),
              const SizedBox(height: 4),
              if (subtitle.isNotEmpty)
                Tooltip(
                  message: widget.item.isSeries ? "" : subtitle,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: subtitleStyle,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final tappableChild =
        widget.selectionMode && widget.onToggleSelected != null
        ? GestureDetector(onTap: widget.onToggleSelected, child: child)
        : GestureDetector(onTap: _openItem, child: child);

    if (!DeviceUtils.isDesktop && !DeviceUtils.isWeb) return tappableChild;

    final hoverChild = MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        if (widget.controller.isScrolling.value) return;
        if (_hovered) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!_hovered) return;
        setState(() => _hovered = false);
      },
      child: tappableChild,
    );

    if (entries.isEmpty) return hoverChild;
    return ContextMenuUtil.region(child: hoverChild, entries: entries);
  }

  Widget _buildCover(ThemeData theme) {
    String coverFilePath = '';
    if (widget.item.isSeries) {
      coverFilePath = widget.item.firstFilePath.trim();
    } else {
      coverFilePath = widget.item.fullPath.trim();
      if (coverFilePath.isEmpty) {
        final base = widget.item.path.trim();
        final name = widget.item.filename.trim();
        coverFilePath = base.isNotEmpty && name.isNotEmpty
            ? '$base/$name'
            : base;
      }
    }

    if (widget.item.hasInnerCover != 1) return _fallbackCover(theme);

    if (coverFilePath.isNotEmpty) {
      final url = ApiController.instance.getMusicCoverUrl(
        filePath: coverFilePath,
        size: 200,
      );
      if (url.isNotEmpty) {
        return CustomExtendedImage(
          imageUrl: url,
          fit: BoxFit.cover,
          showLoading: false,
          borderRadius: 0,
          errorBuilder: (context, error, stackTrace) => _fallbackCover(theme),
        );
      }
    }

    return _fallbackCover(theme);
  }

  Widget _fallbackCover(ThemeData theme) {
    final assetPath = _pickFallbackCoverAsset();
    return Container(
      color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
      child: Image.asset(
        assetPath,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  String _pickFallbackCoverAsset() {
    final raw = widget.item.genre.trim().toLowerCase();
    final parts = raw.split(RegExp(r'[\/,;|]')).map((e) => e.trim()).toList();
    final head = parts.isNotEmpty ? parts.first : '';
    final normalized = head.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final rng = Random(widget.item.id);
    const genreKeys = {
      'blues',
      'classical',
      'country',
      'gospel',
      'hiphop',
      'pop',
      'rock',
    };
    if (normalized.isNotEmpty && genreKeys.contains(normalized)) {
      final idx = rng.nextInt(6) + 1;
      return 'assets/music/musicCover/$normalized$idx.jpg';
    }
    final idx = rng.nextInt(20) + 1;
    return 'assets/music/musicCover/other$idx.jpg';
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
