import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import '../../../../../utils/browse_path_utils.dart';
import '../../../../../utils/context_menu_util.dart';
import '../../../../../utils/dialog_util.dart';
import '../../../../../utils/local_web_asset_server.dart';
import '../../../../../utils/pdf_viewer_util.dart';
import '../../../../../utils/toast_util.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_checkbox.dart';
import '../../../../base/components/custom_extended_image.dart';
import '../../../../base/components/custom_context_menu_item.dart';
import '../../../../base/components/app_item_action_sheet.dart';
import '../../../../../core/api/api_controller.dart';
import '../../../../../core/languages/language_service.dart';
import '../../../../../core/routes/app_routes.dart';
import '../../service/book_list_api_service.dart';
import '../../service/book_local_cache_service_stub.dart'
    if (dart.library.io) '../../service/book_local_cache_service_io.dart';
import '../book_list_page.dart';
import '../../../../home/views/pc_home_controller.dart';
import '../../../../files/service/file_api_service.dart';
import '../../../../transfer/controllers/download_controller.dart';
import '../../../../user/service/user_api_service.dart';
import '../../../favorite/service/book_favorite_api_service.dart';
import '../../../reader_comic/view/book_comic_reader_page.dart';
import '../../../reader/view/book_web_reader_page_stub.dart'
    if (dart.library.io) '../../../reader/view/book_web_reader_page_io.dart'
    if (dart.library.html) '../../../reader/view/book_web_reader_page_web.dart';
import '../../../reader/view/book_txt_reader_page.dart';

class BookItemCard extends StatefulWidget {
  final BookListItem item;
  final bool mobileLayout;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onOpenSeries;
  final Future<void> Function()? onAddToBookList;
  final Future<void> Function()? onRemoveFromBookList;
  final Future<void> Function()? onDelete;
  final ValueChanged<bool>? onFavoriteChanged;
  final bool showHoverMask;
  final bool showMoreButton;
  final bool showSelectionCheckbox;
  final bool showFavoriteButton;
  const BookItemCard({
    super.key,
    required this.item,
    this.mobileLayout = false,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelected,
    this.onOpenSeries,
    this.onAddToBookList,
    this.onRemoveFromBookList,
    this.onDelete,
    this.onFavoriteChanged,
    this.showHoverMask = true,
    this.showMoreButton = true,
    this.showSelectionCheckbox = true,
    this.showFavoriteButton = true,
  });

  @override
  State<BookItemCard> createState() => _BookItemCardState();
}

class _BookItemCardState extends State<BookItemCard> {
  bool _hovered = false;
  bool? _isFavorite;
  bool _favoriteLoading = false;

  bool get _effectiveFavorite => _isFavorite ?? widget.item.isFavorite;

  bool _isPdfCover() {
    final item = widget.item;
    final ext = item.ext.trim().toLowerCase();
    if (ext == 'pdf' || ext == '.pdf') return true;
    final fullPath = item.fullPath.trim();
    if (p.extension(fullPath).toLowerCase() == '.pdf') return true;
    final filename = item.filename.trim();
    if (p.extension(filename).toLowerCase() == '.pdf') return true;
    final firstFilePath = item.firstFilePath.trim();
    if (p.extension(firstFilePath).toLowerCase() == '.pdf') return true;
    return false;
  }

  Widget _coverForActionSheet(ThemeData theme) {
    final item = widget.item;
    final isSeries = item.showType == 'series';
    if (isSeries) return _folderCover(theme);
    if (_isPdfCover()) return _pdfCover(theme);
    final shouldFallback =
        item.coverState == 2 ||
        (isSeries
            ? item.firstFilePath.trim().isEmpty
            : (item.fileHash.trim().isEmpty && item.fullPath.trim().isEmpty));
    return shouldFallback ? _fallbackCover(theme) : _networkCover(theme);
  }

  List<AppItemActionSheetEntry> _buildMobileActionSheetEntries(
    BuildContext context,
  ) {
    if (widget.selectionMode) return const <AppItemActionSheetEntry>[];

    final item = widget.item;
    final fileHash = item.fileHash.trim();
    final canDeleteLocalCache =
        !DeviceUtils.isWeb &&
        item.type == 'book' &&
        item.showType != 'series' &&
        fileHash.isNotEmpty &&
        BookLocalCacheService.instance.isCached(fileHash);

    String resolveBrowsePath() {
      final fullPath = item.fullPath.trim();
      if (item.showType == 'series') return fullPath;
      if (fullPath.isNotEmpty) return browsePathDirname(fullPath);
      final base = item.path.trim();
      if (base.isNotEmpty) return browseFolderPathBook(base);
      return '';
    }

    String resolveDownloadPath() {
      final fullPath = item.fullPath.trim();
      if (fullPath.isNotEmpty) return fullPath;
      final base = item.path.trim();
      final name = item.filename.trim();
      if (base.isNotEmpty && name.isNotEmpty) return p.join(base, name);
      return '';
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

    void downloadItem() {
      final target = resolveDownloadPath();
      if (target.isEmpty) return;
      if (!Get.isRegistered<DownloadController>()) {
        Get.put(DownloadController(), permanent: true);
      }
      Get.find<DownloadController>().handleDownload([target]);
    }

    Future<void> deleteLocalCache() async {
      if (fileHash.isEmpty) return;
      final ok = await BookLocalCacheService.instance.deleteCache(
        fileHash: fileHash,
      );
      if (!mounted) return;
      ToastUtil.show(ok ? 'delete_success'.tr : 'delete_failed'.tr);
    }

    final entries = <AppItemActionSheetEntry>[
      AppItemActionSheetAction(
        title: 'open'.tr,
        icon: const Icon(Icons.open_in_new),
        onTap: () {
          _handleOpen(context);
        },
      ),
      AppItemActionSheetAction(
        title: 'file_browse'.tr,
        icon: const Icon(Icons.folder_open),
        onTap: () {
          openInFileBrowser();
        },
      ),
      AppItemActionSheetAction(
        title: 'download'.tr,
        icon: const Icon(Icons.download_outlined),
        onTap: downloadItem,
      ),
      if (canDeleteLocalCache)
        AppItemActionSheetAction(
          title: 'book_item_delete_local_cache'.tr,
          titleColor: Colors.red,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onTap: () {
            deleteLocalCache();
          },
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
      if (widget.onAddToBookList != null)
        AppItemActionSheetAction(
          title: 'add_to_book_list'.tr,
          icon: const Icon(Icons.playlist_add),
          onTap: () {
            widget.onAddToBookList?.call();
          },
        ),
      if (widget.onRemoveFromBookList != null)
        AppItemActionSheetAction(
          title: 'remove_from_book_list'.tr,
          icon: const Icon(Icons.playlist_remove),
          onTap: () {
            widget.onRemoveFromBookList?.call();
          },
        ),
      if (widget.onDelete != null) ...[
        const AppItemActionSheetDivider(),
        AppItemActionSheetAction(
          title: 'delete'.tr,
          titleColor: Colors.red,
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onTap: () {
            widget.onDelete?.call();
          },
        ),
      ],
    ];

    return entries;
  }

  Future<void> _showMobileActionSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final leading = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: _coverForActionSheet(theme),
      ),
    );
    await AppItemActionSheet.show(
      context,
      headerLeading: leading,
      headerTitle: widget.item.displayTitle,
      entries: _buildMobileActionSheetEntries(context),
    );
  }

  List<ContextMenuEntry> _buildContextMenuEntries(BuildContext context) {
    if (widget.selectionMode) return const <ContextMenuEntry>[];

    final item = widget.item;
    final fileHash = item.fileHash.trim();
    final canDeleteLocalCache =
        !DeviceUtils.isWeb &&
        item.type == 'book' &&
        item.showType != 'series' &&
        fileHash.isNotEmpty &&
        BookLocalCacheService.instance.isCached(fileHash);

    String resolveBrowsePath() {
      final fullPath = item.fullPath.trim();
      if (item.showType == 'series') return fullPath;
      if (fullPath.isNotEmpty) return browsePathDirname(fullPath);
      final base = item.path.trim();
      if (base.isNotEmpty) return browseFolderPathBook(base);
      return '';
    }

    String resolveDownloadPath() {
      final fullPath = item.fullPath.trim();
      if (fullPath.isNotEmpty) return fullPath;
      final base = item.path.trim();
      final name = item.filename.trim();
      if (base.isNotEmpty && name.isNotEmpty) return p.join(base, name);
      return '';
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

    void downloadItem() {
      final target = resolveDownloadPath();
      if (target.isEmpty) return;
      if (!Get.isRegistered<DownloadController>()) {
        Get.put(DownloadController(), permanent: true);
      }
      Get.find<DownloadController>().handleDownload([target]);
    }

    Future<void> deleteLocalCache() async {
      if (fileHash.isEmpty) return;
      final ok = await BookLocalCacheService.instance.deleteCache(
        fileHash: fileHash,
      );
      if (!mounted) return;
      ToastUtil.show(ok ? 'delete_success'.tr : 'delete_failed'.tr);
    }

    return <ContextMenuEntry>[
      CustomContextMenuItem.create(
        label: Text('open'.tr),
        icon: const Icon(Icons.open_in_new, size: 18),
        value: 'open',
        onSelected: (_) => _handleOpen(context),
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
      if (canDeleteLocalCache)
        CustomContextMenuItem.create(
          label: Text(
            'book_item_delete_local_cache'.tr,
            style: const TextStyle(color: Colors.red),
          ),
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          value: 'delete_local_cache',
          onSelected: (_) => deleteLocalCache(),
        ),
      // 本机文件系统操作（仅桌面/Web端且客户端与服务端同机时显示）
      if (DeviceUtils.isDesktopOrWeb &&
          ApiController.instance.isSameMachine) ...[
        const MenuDivider(),
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
                : resolveBrowsePath();
            if (path.isEmpty) return;
            final res = await FileApiService.instance.showInSystem(path);
            if (!res.success) {
              ToastUtil.show(res.message ?? 'operation_failed'.tr);
            }
          },
        ),
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
                : resolveBrowsePath();
            if (path.isEmpty) return;
            final res = await FileApiService.instance.openInSystem(path);
            if (!res.success) {
              ToastUtil.show(res.message ?? 'operation_failed'.tr);
            }
          },
        ),
      ],
      const MenuDivider(),
      CustomContextMenuItem.create(
        label: Text(_effectiveFavorite ? 'unfavorite'.tr : 'favorites'.tr),
        icon: Icon(
          _effectiveFavorite ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: _effectiveFavorite ? Colors.red : null,
        ),
        value: 'favorite',
        onSelected: (_) => _toggleFavorite(),
      ),
      if (widget.onAddToBookList != null)
        CustomContextMenuItem.create(
          label: Text('add_to_book_list'.tr),
          icon: const Icon(Icons.playlist_add, size: 18),
          value: 'add_to_book_list',
          onSelected: (_) => widget.onAddToBookList?.call(),
        ),
      if (widget.onRemoveFromBookList != null)
        CustomContextMenuItem.create(
          label: Text('remove_from_book_list'.tr),
          icon: const Icon(Icons.playlist_remove, size: 18),
          value: 'remove_from_book_list',
          onSelected: (_) => widget.onRemoveFromBookList?.call(),
        ),
      if (widget.onDelete != null) ...[
        const MenuDivider(),
        CustomContextMenuItem.create(
          label: Text('delete'.tr, style: TextStyle(color: Colors.red)),
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          value: 'delete',
          onSelected: (_) => widget.onDelete?.call(),
        ),
      ],
    ];
  }

  @override
  void didUpdateWidget(covariant BookItemCard oldWidget) {
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
          ? await BookFavoriteApiService.instance.addFavorite(id)
          : await BookFavoriteApiService.instance.removeFavorite(id);
      if (!ok) {
        if (mounted) {
          setState(() {
            _isFavorite = prev;
          });
        }
        return;
      }
      widget.onFavoriteChanged?.call(next);
    } finally {
      if (mounted) {
        setState(() {
          _favoriteLoading = false;
        });
      }
    }
  }

  static const double _coverAspectRatio = 3 / 4;
  static const double _titleHeight = 42;
  static const double _metaHeight = 16;

  static const _fallbackAssets = <String>[
    'assets/icons/book/book_blue.jpg',
    'assets/icons/book/book_brown.jpg',
    'assets/icons/book/book_red.jpg',
    'assets/icons/book/book_green.jpg',
  ];

  int _stableIndex(String seed) {
    if (seed.isEmpty) return 0;
    final h = seed.codeUnits.fold<int>(0, (p, e) => (p * 31 + e) & 0x7fffffff);
    return h % _fallbackAssets.length;
  }

  @override
  Widget build(BuildContext context) {
    if (DeviceUtils.isWeb) return _buildContent(context);
    final item = widget.item;
    final shouldObserve =
        item.type == 'book' &&
        item.showType != 'series' &&
        item.fileHash.trim().isNotEmpty;
    if (!shouldObserve) {
      return GetBuilder<ApiController>(builder: (_) => _buildContent(context));
    }
    return GetBuilder<ApiController>(
      builder: (_) => Obx(() => _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final extLabel = item.extLabel;
    final isSeries = item.showType == 'series';
    final isComic = item.type == 'comic';
    final isBook = item.type == 'book';
    final showMeta = isSeries || isComic;
    final badgeLabel = isSeries ? 'series'.tr : extLabel;
    final entries = _buildContextMenuEntries(context);
    final showMoreButton =
        widget.showMoreButton &&
        entries.isNotEmpty &&
        (widget.mobileLayout ? true : _hovered);
    final fileHash = item.fileHash.trim();
    final isCached =
        !DeviceUtils.isWeb &&
        isBook &&
        !isSeries &&
        fileHash.isNotEmpty &&
        BookLocalCacheService.instance.isCached(fileHash);
    final double? p = !DeviceUtils.isWeb && fileHash.isNotEmpty
        ? BookLocalCacheService.instance.progressOf(fileHash)
        : null;
    final downloadProgressValue = (p ?? 0).clamp(0.0, 1.0);
    final showDownloadProgress =
        p != null && downloadProgressValue >= 0 && downloadProgressValue <= 1;

    String resolveProgressText() {
      if (item.lastReadAt.trim().isEmpty) return '';
      if (isSeries) return '';
      if (item.type == 'comic') {
        final total = item.totalPage;
        if (total <= 0) return '';
        final safeIdx = item.currentPage.clamp(0, total - 1);
        return '${safeIdx + 1}/$total';
      }
      if (item.type == 'book') {
        final f = item.fraction;
        if (f <= 0) return '';
        final pct = (f.clamp(0.0, 1.0) * 100).round();
        return '$pct%';
      }
      return '';
    }

    final progressText = resolveProgressText();
    final metaBaseText = showMeta
        ? (isSeries
              ? 'book_item_books'.trParams({'count': '${item.bookCount}'})
              : 'book_item_pages'.trParams({'count': '${item.totalPage}'}))
        : '';
    final metaTextRaw = metaBaseText.isNotEmpty && progressText.isNotEmpty
        ? '$metaBaseText · $progressText'
        : (progressText.isNotEmpty ? progressText : metaBaseText);
    final metaText = isCached
        ? (metaTextRaw.isEmpty
              ? 'book_item_downloaded'.tr
              : '(${'book_item_downloaded'.tr}) $metaTextRaw')
        : metaTextRaw;
    final showMetaLine = metaText.isNotEmpty;
    final shouldFallback =
        item.coverState == 2 ||
        (isSeries
            ? item.firstFilePath.trim().isEmpty
            : (item.fileHash.trim().isEmpty && item.fullPath.trim().isEmpty));
    final cover = isSeries
        ? _folderCover(theme)
        : (_isPdfCover()
              ? _pdfCover(theme)
              : (shouldFallback
                    ? _fallbackCover(theme)
                    : _networkCover(theme)));
    final titleStyle = theme.textTheme.titleSmall?.copyWith();
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      height: 1.0,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
    );
    final showSelectBox =
        widget.showSelectionCheckbox &&
        (widget.selectionMode || _hovered || widget.selected);
    final showTypeBadge = widget.mobileLayout && !widget.selectionMode;

    String resolveTypeLabel() {
      if (isSeries) return 'series'.tr;
      if (isComic) return 'book_menu_library_comic'.tr;
      return 'book_menu_library_book'.tr;
    }

    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: _coverAspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                cover,
                if (widget.showHoverMask && _hovered)
                  Container(color: Colors.black.withValues(alpha: 0.2)),
                if (showDownloadProgress && !isSeries && isBook)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 160,
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: downloadProgressValue,
                                    minHeight: 6,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.25,
                                    ),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(downloadProgressValue * 100).round()}%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.showFavoriteButton &&
                    (_hovered || _effectiveFavorite) &&
                    !widget.selectionMode)
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
                        if (widget.mobileLayout) {
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => _showMobileActionSheet(context),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface.withValues(
                                    alpha: 0.75,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.12),
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
                        }
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
                if (!widget.mobileLayout &&
                    !showMoreButton &&
                    badgeLabel.isNotEmpty)
                  Positioned(
                    top: 8,
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
                if (showTypeBadge)
                  Positioned(
                    right: 6,
                    bottom: 6,
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
                        resolveTypeLabel(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
        const SizedBox(height: 2),
        SizedBox(
          height: _titleHeight + _metaHeight,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                SizedBox(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Tooltip(
                      message: item.displayTitle,
                      child: Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: titleStyle,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 6),
                SizedBox(
                  height: _metaHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: showMetaLine
                        ? Text(
                            metaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: metaStyle,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final tappableChild =
        widget.selectionMode && widget.onToggleSelected != null
        ? GestureDetector(onTap: widget.onToggleSelected, child: child)
        : GestureDetector(
            onTap: () => _handleOpen(context),
            onLongPress: widget.onToggleSelected,
            child: child,
          );

    if (!DeviceUtils.isDesktop && !DeviceUtils.isWeb) return tappableChild;

    final hoverChild = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: tappableChild,
    );

    if (entries.isEmpty) return hoverChild;
    return ContextMenuUtil.region(child: hoverChild, entries: entries);
  }

  Future<void> _handleOpen(BuildContext context) async {
    final item = widget.item;
    final isSeries = item.showType == 'series';
    final isComic = item.type == 'comic';
    final isBook = item.type == 'book';
    final fileHash = item.fileHash.trim();

    if (isComic && !isSeries && fileHash.isNotEmpty) {
      Get.to(
        () => BookComicReaderPage(fileHash: fileHash, title: item.displayTitle),
        preventDuplicates: false,
      );
      return;
    }

    if (isBook && !isSeries) {
      String filePath = item.fullPath.trim();
      if (filePath.isEmpty) {
        final base = item.path.trim();
        final name = item.filename.trim();
        if (base.isNotEmpty && name.isNotEmpty) {
          filePath = p.join(base, name);
        }
      }
      if (filePath.isEmpty) {
        final alt = item.firstFilePath.trim();
        if (alt.isNotEmpty) filePath = alt;
      }
      if (filePath.isEmpty) {
        ToastUtil.show('not_implemented_yet'.tr);
        return;
      }

      // PDF：与文件浏览器一致，使用 pdfrx；P2P 下经 LocalWebAssetServer 环回代理
      if (_isPdfCover()) {
        await PdfViewerUtil.openPdfInViewer(
          filePath: filePath,
          title: item.displayTitle,
          fileHash: fileHash.isNotEmpty ? fileHash : null,
          expectedSize: item.size,
        );
        return;
      }

      final extLower = item.ext.trim().toLowerCase();
      final isTxt =
          extLower == 'txt' || p.extension(filePath).toLowerCase() == '.txt';

      final scopedRes = await UserApiService.instance.createScopedToken(
        allowApi: const <String>[
          '/api/book/history',
          '/api/book/preference',
          '/api/file/rawFile',
        ],
        allowPath: <String>[filePath],
      );
      if (!context.mounted) return;
      if (!scopedRes.success) {
        ToastUtil.show(scopedRes.message ?? 'network_failure'.tr);
        return;
      }
      final scopedToken =
          scopedRes.data?['accessToken']?.toString().trim() ?? '';
      if (scopedToken.isEmpty) {
        ToastUtil.show('network_failure'.tr);
        return;
      }

      final fileUrl = ApiController.instance.getRawFileUrl(
        filePath,
        withAccessToken: true,
        accessTokenOverride: scopedToken,
        isRawFile: true,
        p2pChannel: 'download',
      );

      if (isTxt) {
        if (DeviceUtils.isWeb) {
          Get.to(
            () => BookTxtReaderPage(
              fileHash: fileHash,
              title: item.displayTitle,
              url: fileUrl,
              expectedSize: item.size,
            ),
            preventDuplicates: false,
          );
          return;
        }

        final ok = await BookLocalCacheService.instance.ensureCached(
          fileHash: fileHash,
          fileName: item.filename.trim().isNotEmpty
              ? item.filename
              : item.displayTitle,
          ext: item.ext,
          remoteUrl: fileUrl,
          expectedSize: item.size,
        );
        if (!context.mounted) return;
        if (!ok) {
          ToastUtil.show('operation_failed'.tr);
          return;
        }

        final cachedPath = BookLocalCacheService.instance.cachedFilePathOf(
          fileHash,
        );
        if (cachedPath != null && cachedPath.trim().isNotEmpty) {
          Get.to(
            () => BookTxtReaderPage(
              fileHash: fileHash,
              title: item.displayTitle,
              localFilePath: cachedPath,
              expectedSize: item.size,
            ),
            preventDuplicates: false,
          );
          return;
        }

        final session = await BookLocalCacheService.instance
            .openLocalServeSession(fileHash: fileHash);
        if (!context.mounted) return;
        if (session == null) {
          ToastUtil.show('operation_failed'.tr);
          return;
        }

        Get.to(
          () => BookTxtReaderPage(
            fileHash: fileHash,
            title: item.displayTitle,
            url: session.url,
            expectedSize: item.size,
            onDispose: () async {
              await session.close().catchError((_) {});
            },
          ),
          preventDuplicates: false,
        );
        return;
      }

      final lang = LanguageService.to.currentLocale.replaceAll('_', '-');
      final readerFileName = item.filename.trim().isNotEmpty
          ? item.filename.trim()
          : p.basename(filePath);
      if (DeviceUtils.isWeb) {
        final apiBase = ApiController.instance.baseUrl.trim();
        // Web：开发时为 assets/web/...，打包后为 assets/assets/web/...
        final path = kReleaseMode
            ? 'assets/assets/web/reader/reader.html'
            : 'assets/web/reader/reader.html';
        final pageUrl = Uri.base.resolve(path).toString();
        final readerUrl = Uri.parse(pageUrl)
            .replace(
              queryParameters: <String, String>{
                'url': fileUrl,
                'lang': lang,
                'file_hash': fileHash,
                'filename': readerFileName,
                'accessToken': scopedToken,
                if (apiBase.isNotEmpty) 'apiBase': apiBase,
              },
            )
            .toString();
        Get.to(
          () => BookWebReaderPage(url: readerUrl, title: item.displayTitle),
          preventDuplicates: false,
        );
        return;
      }

      final ok = await BookLocalCacheService.instance.ensureCached(
        fileHash: fileHash,
        fileName: item.filename.trim().isNotEmpty
            ? item.filename
            : item.displayTitle,
        ext: item.ext,
        remoteUrl: fileUrl,
        expectedSize: item.size,
      );
      if (!context.mounted) return;
      if (!ok) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }

      final session = await BookLocalCacheService.instance
          .openLocalServeSession(fileHash: fileHash);
      if (!context.mounted) return;
      if (session == null) {
        ToastUtil.show('operation_failed'.tr);
        return;
      }

      final localBase = await LocalWebAssetServer.instance.acquire();
      final localReaderUrl = localBase
          .replace(
            path: '/reader/reader.html',
            queryParameters: <String, String>{
              'url': session.url,
              'lang': lang,
              'file_hash': fileHash,
              'filename': readerFileName,
              'accessToken': scopedToken,
              'apiBase': localBase.toString(),
            },
          )
          .toString();
      Get.to(
        () => BookWebReaderPage(
          url: localReaderUrl,
          title: item.displayTitle,
          onDispose: () async {
            await session.close().catchError((_) {});
            await LocalWebAssetServer.instance.release();
          },
        ),
        preventDuplicates: false,
      );
      return;
    }

    if (isSeries) {
      if (widget.onOpenSeries != null) {
        widget.onOpenSeries?.call();
        return;
      }
      Get.to(
        () => _SeriesIndexOverlay(
          seriesIndexId: item.id,
          title: item.displayTitle,
        ),
        preventDuplicates: false,
      );
      return;
    }
    ToastUtil.show('not_implemented_yet'.tr);
  }

  Widget _fallbackCover(ThemeData theme) {
    final item = widget.item;
    final idx = _stableIndex(
      item.fileHash.isNotEmpty ? item.fileHash : item.fullPath,
    );
    final bg = _fallbackAssets[idx];
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(bg, fit: BoxFit.cover),
        Container(
          color: Colors.black.withValues(alpha: 0.35),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10),
          child: Text(
            item.displayTitle,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _folderCover(ThemeData theme) {
    final item = widget.item;
    final seed = item.fullPath.trim().isNotEmpty
        ? item.fullPath.trim()
        : (item.firstFilePath.trim().isNotEmpty
              ? item.firstFilePath.trim()
              : item.id.toString());
    final bg = _fallbackAssets[_stableIndex(seed)];
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(bg, fit: BoxFit.cover),
        Center(
          child: Image.asset(
            'assets/icons/file/books.png',
            width: 72,
            height: 72,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }

  Widget _pdfCover(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/icons/book/pdf.jpg', fit: BoxFit.cover),
        // Container(
        //   color: Colors.black.withValues(alpha: 0.35),
        //   alignment: Alignment.center,
        //   padding: const EdgeInsets.all(10),
        //   child: Text(
        //     item.displayTitle,
        //     textAlign: TextAlign.center,
        //     maxLines: 4,
        //     overflow: TextOverflow.ellipsis,
        //     style: theme.textTheme.titleSmall?.copyWith(
        //       color: Colors.white,
        //       fontWeight: FontWeight.w600,
        //     ),
        //   ),
        // ),
      ],
    );
  }

  Widget _networkCover(ThemeData theme) {
    if (_isPdfCover()) return _pdfCover(theme);
    final item = widget.item;
    final isSeries = item.showType == 'series';
    if (isSeries) return _folderCover(theme);
    final fullPath = item.fullPath.trim();
    final fileHash = item.fileHash.trim();
    final firstFilePath = item.firstFilePath.trim();

    final primaryUrl = isSeries
        ? (firstFilePath.isNotEmpty
              ? ApiController.instance.getTinyUrl(firstFilePath)
              : '')
        : fileHash.isNotEmpty
        ? ApiController.instance.getBookTinyUrl(fileHash: fileHash, size: 500)
        : (fullPath.isNotEmpty
              ? ApiController.instance.getTinyUrl(fullPath)
              : (firstFilePath.isNotEmpty
                    ? ApiController.instance.getTinyUrl(firstFilePath)
                    : ''));

    final secondaryUrl = isSeries
        ? ''
        : (fullPath.isNotEmpty
              ? ApiController.instance.getTinyUrl(fullPath)
              : (firstFilePath.isNotEmpty
                    ? ApiController.instance.getTinyUrl(firstFilePath)
                    : ''));

    return _NetworkCoverWithFallback(
      primaryUrl: primaryUrl,
      secondaryUrl: secondaryUrl,
      fallback: _fallbackCover(theme),
    );
  }
}

class _NetworkCoverWithFallback extends StatefulWidget {
  final String primaryUrl;
  final String secondaryUrl;
  final Widget fallback;
  const _NetworkCoverWithFallback({
    required this.primaryUrl,
    required this.secondaryUrl,
    required this.fallback,
  });

  @override
  State<_NetworkCoverWithFallback> createState() =>
      _NetworkCoverWithFallbackState();
}

class _NetworkCoverWithFallbackState extends State<_NetworkCoverWithFallback> {
  bool _useSecondary = false;

  @override
  void didUpdateWidget(covariant _NetworkCoverWithFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryUrl != widget.primaryUrl ||
        oldWidget.secondaryUrl != widget.secondaryUrl) {
      _useSecondary = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryUrl.trim();
    final secondary = widget.secondaryUrl.trim();

    if (primary.isEmpty) {
      if (secondary.isEmpty) return widget.fallback;
      return CustomExtendedImage(
        imageUrl: secondary,
        fit: BoxFit.cover,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => widget.fallback,
      );
    }

    if (_useSecondary && secondary.isNotEmpty) {
      return CustomExtendedImage(
        imageUrl: secondary,
        fit: BoxFit.cover,
        showLoading: false,
        borderRadius: 0,
        errorBuilder: (context, error, stackTrace) => widget.fallback,
      );
    }

    return CustomExtendedImage(
      imageUrl: primary,
      fit: BoxFit.cover,
      showLoading: false,
      borderRadius: 0,
      errorBuilder: (context, error, stackTrace) {
        if (!_useSecondary && secondary.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _useSecondary = true;
            });
          });
        }
        return widget.fallback;
      },
    );
  }
}

class _SeriesIndexOverlay extends StatelessWidget {
  final int seriesIndexId;
  final String title;
  const _SeriesIndexOverlay({required this.seriesIndexId, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Get.theme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'back'.tr,
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Get.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: BookListPage(
                key: ValueKey('book_series_$seriesIndexId'),
                type: '',
                seriesIndexId: seriesIndexId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
