import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:NasCabOS/core/theme/custom_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../../utils/device_utils.dart';
import '../controller/book_list_controller.dart';
import 'parts/book_list_grid.dart';
import 'parts/book_list_multi_select_bottom_bar.dart';
import 'parts/book_list_top_bar.dart';
import '../../../base/components/custom_no_data.dart';
import '../../../base/components/custom_letter_filter.dart';

class BookListPage extends StatefulWidget {
  final String type;
  final bool isFavorite;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;

  /// 见 [BookListController.alertWhenNoSourcePath]。
  final bool alertWhenNoSourcePath;

  const BookListPage({
    super.key,
    required this.type,
    this.isFavorite = false,
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.alertWhenNoSourcePath = false,
  });

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
  late final String _controllerTag;
  late final ScrollController _scrollController;
  Timer? _autoTimer;
  Timer? _throttleTimer;
  bool _dragging = false;
  bool _marqueeActive = false;
  bool _multiModeAtStart = false;
  bool _additiveAtStart = false;
  Offset _lastLocal = const Offset(0, 0);
  Offset? _pointerDownPos;
  static const double _kMarqueeThreshold = 8;

  String _rectCacheKey = '';
  List<_GridRectEntry> _gridRectCache = const [];
  List<double> _gridRectBottoms = const [];

  double _gridViewportHeight = 0;

  @override
  void initState() {
    super.initState();
    _controllerTag =
        'book_list_${widget.type}_${widget.isFavorite ? 'fav' : 'all'}_${widget.listId ?? 0}_${widget.seriesIndexId ?? 0}_${widget.collectionId ?? 0}_${DateTime.now().microsecondsSinceEpoch}';
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _throttleTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (Get.isRegistered<BookListController>(tag: _controllerTag)) {
      Get.delete<BookListController>(tag: _controllerTag, force: true);
    }
    super.dispose();
  }

  void _onScroll() {
    final ctrl = Get.isRegistered<BookListController>(tag: _controllerTag)
        ? Get.find<BookListController>(tag: _controllerTag)
        : null;
    if (ctrl == null) return;
    if (!_scrollController.hasClients) return;
    if (_dragging) {
      ctrl.updateDragSelection(_lastLocal, scrollOffset: _scrollOffsetSafe);
      _scheduleHitTest();
    }
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      ctrl.loadMore(fromAuto: true).catchError((_) {});
    }
  }

  double get _scrollOffsetSafe =>
      _scrollController.hasClients ? _scrollController.offset : 0.0;

  double get _headerExtent => 50.0;

  double get _gridTopPadding => 12.0;

  bool get _isAdditiveSelectionActive {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  void _scheduleHitTest() {
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 60), _performHitTest);
  }

  int _lowerBoundBottom(List<double> bottoms, double value) {
    var lo = 0;
    var hi = bottoms.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (bottoms[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Set<int> _performHitTest() {
    if (!_dragging) return const {};
    final ctrl = Get.isRegistered<BookListController>(tag: _controllerTag)
        ? Get.find<BookListController>(tag: _controllerTag)
        : null;
    if (ctrl == null) return const {};
    final rect = ctrl.selectionRectContent.value;
    if (rect == null) return const {};
    final hits = <int>{};
    final start = _lowerBoundBottom(_gridRectBottoms, rect.top);
    for (var i = start; i < _gridRectCache.length; i++) {
      final r = _gridRectCache[i].rect;
      if (r.top > rect.bottom) break;
      if (r.overlaps(rect)) hits.add(_gridRectCache[i].id);
    }
    ctrl.updateDragPreview(hits, additive: _additiveAtStart);
    return hits;
  }

  void _ensureAutoTimer() {
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_dragging) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (!pos.hasPixels) return;
      const edge = 30.0;
      double delta = 0.0;
      if (_lastLocal.dy < edge) {
        final t = (edge - _lastLocal.dy).clamp(0.0, edge) / edge;
        delta = -12.0 * t;
      } else {
        final distBottom = (_gridViewportHeight - _lastLocal.dy);
        if (distBottom < edge) {
          final t = (edge - distBottom).clamp(0.0, edge) / edge;
          delta = 12.0 * t;
        }
      }
      if (delta != 0.0) {
        final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        _scrollController.jumpTo(target);
      }
    });
  }

  void _rebuildGridRectCache({
    required List items,
    required double maxWidth,
    required double coverScale,
  }) {
    const leftPadding = 16.0;
    const rightPadding = 38.0;
    final contentWidth = math.max(0.0, maxWidth - leftPadding - rightPadding);
    const itemScale = 1.7;
    const coverAspectRatio = 3 / 4;
    const titleHeight = 58.0;
    const titleSpacing = 2.0;
    final baseWidth = (contentWidth < 520 ? 72.0 : 84.0) * itemScale;
    final desiredWidth = baseWidth * coverScale;
    final crossAxisCount = (contentWidth / desiredWidth).floor().clamp(2, 12);
    final spacing = contentWidth < 520 ? 10.0 : 12.0;
    final totalSpacing = spacing * (crossAxisCount - 1);
    final cellW = ((contentWidth - totalSpacing) / crossAxisCount)
        .floorToDouble();
    final coverH = cellW / coverAspectRatio;
    final cellH = coverH + titleSpacing + titleHeight;
    final baseY = _headerExtent + _gridTopPadding;

    final entries = <_GridRectEntry>[];
    final bottoms = <double>[];
    for (var i = 0; i < items.length; i++) {
      final row = i ~/ crossAxisCount;
      final col = i % crossAxisCount;
      final x = leftPadding + col * (cellW + spacing);
      final y = baseY + row * (cellH + spacing);
      final r = Rect.fromLTWH(x, y, cellW, cellH);
      final id = (items[i].id as int?) ?? 0;
      if (id > 0) {
        entries.add(_GridRectEntry(id: id, rect: r));
        bottoms.add(r.bottom);
      }
    }
    _gridRectCache = entries;
    _gridRectBottoms = bottoms;
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<BookListController>(
      tag: _controllerTag,
      init: BookListController(
        type: widget.type,
        isFavorite: widget.isFavorite,
        listId: widget.listId,
        seriesIndexId: widget.seriesIndexId,
        collectionId: widget.collectionId,
        alertWhenNoSourcePath: widget.alertWhenNoSourcePath,
      ),
      builder: (ctrl) {
        return Obx(() {
          if (!ctrl.firstLoaded.value &&
              ctrl.loading.value &&
              ctrl.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final isEmpty =
              ctrl.firstLoaded.value &&
              !ctrl.loading.value &&
              ctrl.items.isEmpty;
          final showMultiBar = ctrl.isMultiSelectMode.value;
          final bottomSpace = showMultiBar ? 86.0 : 30.0;

          final rawSearch = ctrl.searchText.value.trim();
          final selectedLetter =
              rawSearch.length == 1 &&
                  (rawSearch == '#' ||
                      RegExp(r'^[a-zA-Z]$').hasMatch(rawSearch))
              ? rawSearch.toUpperCase()
              : null;

          final letterFilter = CustomLetterFilter(
            value: selectedLetter,
            onChanged: (v) => ctrl.setSearchImmediate(v ?? ''),
          );

          return LayoutBuilder(
            builder: (context, constraints) {
              final enableMarquee =
                  DeviceUtils.isDesktop ||
                  (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));
              _gridViewportHeight = constraints.maxHeight;

              final rectKey = [
                ctrl.items.length,
                constraints.maxWidth.toStringAsFixed(2),
                ctrl.coverScale.value.toStringAsFixed(2),
              ].join('|');
              if (_rectCacheKey != rectKey) {
                _rectCacheKey = rectKey;
                _rebuildGridRectCache(
                  items: ctrl.items,
                  maxWidth: constraints.maxWidth,
                  coverScale: ctrl.coverScale.value,
                );
              }

              final scrollView = CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _BookListTopBarHeaderDelegate(controller: ctrl),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(top: 12)),
                  if (isEmpty) ...[
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: CustomNoData(text: 'no_data'.tr),
                    ),
                  ] else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 38, 0),
                      sliver: BookListGrid(controller: ctrl),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    SliverToBoxAdapter(child: BookListFooter(controller: ctrl)),
                    SliverToBoxAdapter(child: SizedBox(height: bottomSpace)),
                  ],
                ],
              );

              final scrollLayer = enableMarquee
                  ? Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (e.buttons != kPrimaryButton) return;
                        _pointerDownPos = e.localPosition;
                        _multiModeAtStart = ctrl.isMultiSelectMode.value;
                        _additiveAtStart = _isAdditiveSelectionActive;
                        _marqueeActive = false;
                      },
                      onPointerMove: (e) {
                        if (e.buttons != kPrimaryButton) return;
                        final origin = _pointerDownPos;
                        if (origin == null) return;
                        final local = e.localPosition;
                        if (!_marqueeActive) {
                          if ((local - origin).distance > _kMarqueeThreshold) {
                            _marqueeActive = true;
                            _dragging = true;
                            _lastLocal = local;
                            _ensureAutoTimer();
                            _additiveAtStart = _isAdditiveSelectionActive;
                            ctrl.startDragSelection(
                              origin,
                              scrollOffset: _scrollOffsetSafe,
                            );
                          }
                        }
                        if (_marqueeActive) {
                          _lastLocal = local;
                          ctrl.updateDragSelection(
                            local,
                            scrollOffset: _scrollOffsetSafe,
                          );
                          _scheduleHitTest();
                        }
                      },
                      onPointerUp: (e) {
                        if (_marqueeActive) {
                          final hits = _performHitTest();
                          _dragging = false;
                          ctrl.finishDragSelection();
                          ctrl.applyDragSelection(
                            hits,
                            multiModeAtStart: _multiModeAtStart,
                            additive: _additiveAtStart,
                          );
                        } else {
                          ctrl.finishDragSelection();
                        }
                        _pointerDownPos = null;
                        _marqueeActive = false;
                      },
                      onPointerCancel: (e) {
                        _dragging = false;
                        ctrl.finishDragSelection();
                        _pointerDownPos = null;
                        _marqueeActive = false;
                      },
                      child: scrollView,
                    )
                  : scrollView;

              return Stack(
                children: [
                  scrollLayer,
                  if (enableMarquee)
                    Obx(() {
                      final r = ctrl.selectionRect.value;
                      if (r == null) return const SizedBox.shrink();
                      return Positioned(
                        left: r.left,
                        top: r.top,
                        width: r.width,
                        height: r.height,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              border: Border.all(color: Colors.blue, width: 1),
                            ),
                          ),
                        ),
                      );
                    }),
                  Positioned.fill(
                    top: 50 + 12,
                    bottom: showMultiBar ? 66 : 10,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: letterFilter,
                      ),
                    ),
                  ),
                  if (showMultiBar)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: BookListMultiSelectBottomBar(controller: ctrl),
                    ),
                ],
              );
            },
          );
        });
      },
    );
  }
}

class _GridRectEntry {
  final int id;
  final Rect rect;

  const _GridRectEntry({required this.id, required this.rect});
}

class _BookListTopBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final BookListController controller;

  _BookListTopBarHeaderDelegate({required this.controller});

  @override
  double get minExtent => 50;

  @override
  double get maxExtent => 50;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return ColoredBox(
      color: customColors!.mainContentBgColor,
      child: Column(children: [BookListTopBar(controller: controller)]),
    );
  }

  @override
  bool shouldRebuild(covariant _BookListTopBarHeaderDelegate oldDelegate) {
    return oldDelegate.controller != controller;
  }
}

class BookSeriesOverlay extends StatelessWidget {
  final int seriesIndexId;
  final String title;
  final VoidCallback onClose;

  const BookSeriesOverlay({
    super.key,
    required this.seriesIndexId,
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final customColors = Theme.of(context).extension<CustomColors>();
    return Positioned.fill(
      child: Material(
        color: customColors?.mainContentBgColor,
        child: SafeArea(
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
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back_ios_outlined),
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
      ),
    );
  }
}
