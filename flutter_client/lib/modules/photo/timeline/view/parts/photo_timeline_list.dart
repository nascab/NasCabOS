import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../controller/photo_timeline_controller.dart';
import '../../../../../utils/device_utils.dart';
import '../../../../base/components/custom_loading_indicator.dart';
import '../../../../base/components/custom_no_data.dart';
import 'photo_timeline_item.dart';
import 'photo_timeline_item_date.dart';

class PhotoTimelineList extends StatefulWidget {
  final String? controllerTag;
  const PhotoTimelineList({super.key, this.controllerTag});

  @override
  State<PhotoTimelineList> createState() => _PhotoTimelineListState();
}

class _PhotoTimelineListState extends State<PhotoTimelineList> {
  static const double _kMarqueeThreshold = 8;
  Timer? _autoTimer;
  Timer? _throttleTimer;
  bool _dragging = false;
  bool _marqueeActive = false;
  bool _multiModeAtStart = false;

  double _gridViewportHeight = 0;
  Offset _lastGridLocal = const Offset(0, 0);
  Offset? _pointerDownGridPos;
  int? _pointerDownHitPhotoId;
  bool _pointerDownHitTimelineItem = false;

  String _rectCacheKey = '';
  List<_PhotoRectEntry> _photoRectCache = const [];
  List<double> _photoRectBottoms = const [];
  List<Rect> _headerRectCache = const [];
  List<double> _headerRectBottoms = const [];

  PhotoTimelineController get _controller => Get.find<PhotoTimelineController>(
        tag: widget.controllerTag,
      );

  double get _scrollOffsetSafe =>
      _controller.scrollController.hasClients ? _controller.scrollController.offset : 0.0;

  @override
  void initState() {
    super.initState();
    _controller.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _throttleTimer?.cancel();
    _controller.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_dragging) {
      _controller.updateDragSelection(
        _lastGridLocal,
        scrollOffset: _currentGridScrollOffset(),
      );
      _scheduleHitTest();
    }
  }

  double _currentTopLoadingExtent() {
    return _controller.isLoadingUp.value ? _controller.layoutTopLoadingExtent : 0.0;
  }

  double _currentGridViewportTop() {
    final top = _currentTopLoadingExtent() - _scrollOffsetSafe;
    return top > 0 ? top : 0.0;
  }

  double _currentGridScrollOffset() {
    final topExtent = _currentTopLoadingExtent();
    final v = _scrollOffsetSafe - topExtent;
    return v > 0 ? v : 0.0;
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

  int? _hitTestPhotoIdAtContentPoint(Offset contentPoint) {
    final dy = contentPoint.dy;
    final idx = _lowerBoundBottom(_photoRectBottoms, dy);
    if (idx < 0 || idx >= _photoRectCache.length) return null;
    for (var i = idx; i < _photoRectCache.length; i++) {
      final r = _photoRectCache[i].rect;
      if (r.top > dy) break;
      if (r.contains(contentPoint)) return _photoRectCache[i].photoId;
    }
    return null;
  }

  bool _hitTestHeaderAtContentPoint(Offset contentPoint) {
    final dy = contentPoint.dy;
    final idx = _lowerBoundBottom(_headerRectBottoms, dy);
    if (idx < 0 || idx >= _headerRectCache.length) return false;
    for (var i = idx; i < _headerRectCache.length; i++) {
      final r = _headerRectCache[i];
      if (r.top > dy) break;
      if (r.contains(contentPoint)) return true;
    }
    return false;
  }

  bool get _isAdditiveSelectionActive {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  Set<int> _performHitTest() {
    if (!_dragging) return const {};
    final rect = _controller.selectionRectContent.value;
    if (rect == null) return const {};
    final hits = <int>{};

    final start = _lowerBoundBottom(_photoRectBottoms, rect.top);
    for (var i = start; i < _photoRectCache.length; i++) {
      final r = _photoRectCache[i].rect;
      if (r.top > rect.bottom) break;
      if (r.overlaps(rect)) hits.add(_photoRectCache[i].photoId);
    }
    _controller.updateDragPreview(hits, additive: _isAdditiveSelectionActive);
    return hits;
  }

  void _ensureAutoTimer() {
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_dragging) return;
      if (!_controller.scrollController.hasClients) return;
      final pos = _controller.scrollController.position;
      if (!pos.hasPixels) return;
      const edge = 30.0;
      double delta = 0.0;
      if (_lastGridLocal.dy < edge) {
        final t = (edge - _lastGridLocal.dy).clamp(0.0, edge) / edge;
        delta = -12.0 * t;
      } else {
        final distBottom = (_gridViewportHeight - _lastGridLocal.dy);
        if (distBottom < edge) {
          final t = (edge - distBottom).clamp(0.0, edge) / edge;
          delta = 12.0 * t;
        }
      }
      if (delta != 0.0) {
        final target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        _controller.scrollController.jumpTo(target);
      }
    });
  }

  void _rebuildPhotoRectCache({
    required List<TimelineListItem> items,
    required int crossAxisCount,
    required double totalCrossAxisExtent,
    required double cellExtent,
    required double headerExtent,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required double leftPadding,
  }) {
    final entries = <_PhotoRectEntry>[];
    final bottoms = <double>[];
    final headerRects = <Rect>[];
    final headerBottoms = <double>[];

    double mainAxisOffset = 0;
    var col = 0;

    void startNewRowIfNeeded() {
      if (col == 0) return;
      mainAxisOffset += cellExtent + mainAxisSpacing;
      col = 0;
    }

    for (var i = 0; i < items.length; i++) {
      final n = items[i];
      if (n is TimelineListDateHeader) {
        startNewRowIfNeeded();
        final r = Rect.fromLTWH(
          leftPadding,
          mainAxisOffset,
          totalCrossAxisExtent,
          headerExtent,
        );
        headerRects.add(r);
        headerBottoms.add(r.bottom);
        mainAxisOffset += headerExtent + mainAxisSpacing;
        continue;
      }
      if (n is TimelineListPhoto) {
        final crossAxisOffset = col * (cellExtent + crossAxisSpacing);
        final r = Rect.fromLTWH(
          leftPadding + crossAxisOffset,
          mainAxisOffset,
          cellExtent,
          cellExtent,
        );
        entries.add(_PhotoRectEntry(photoId: n.photo.id, rect: r));
        bottoms.add(r.bottom);
        col++;
        if (col >= crossAxisCount) {
          col = 0;
          mainAxisOffset += cellExtent + mainAxisSpacing;
        }
      }
    }

    _photoRectCache = entries;
    _photoRectBottoms = bottoms;
    _headerRectCache = headerRects;
    _headerRectBottoms = headerBottoms;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isLoadingUp = _controller.isLoadingUp.value;
      // 显式依赖 itemSize 和 isMultiSelectMode
      // 这样当这些值变化时，Obx 会触发重建
      final itemSize = _controller.itemSize.value;
      final isMultiSelectMode = _controller.isMultiSelectMode.value;

      if (_controller.isLoadingDates.value && _controller.dateList.isEmpty) {
        return const Center(child: CustomLoadingIndicator());
      }

      if (_controller.photoItems.isEmpty &&
          !_controller.isLoadingDates.value &&
          !_controller.isLoadingDown.value) {
        return CustomNoData(
          text: 'no_photo'.tr,
        );
      }

      final double currentItemSize = itemSize;
      final bool currentIsMultiSelectMode = isMultiSelectMode;

      return LayoutBuilder(
        builder: (context, constraints) {
          final double crossAxisSpacing = _controller.layoutCrossAxisSpacing;
          final double mainAxisSpacing = _controller.layoutMainAxisSpacing;
          final double leftPadding = _controller.layoutLeftPadding;
          final double rightPadding = _controller.layoutRightPadding;
          final bottomPadding = currentIsMultiSelectMode ? 76.0 : 25.0;
          final gridPadding = EdgeInsets.only(
            left: leftPadding,
            right: rightPadding,
            bottom: bottomPadding,
          );

          final contentWidth = math.max(
            0.0,
            constraints.maxWidth - leftPadding - rightPadding,
          );

          final crossAxisCount = math.max(
            1,
            ((contentWidth + crossAxisSpacing) /
                    (currentItemSize + crossAxisSpacing))
                .floor(),
          );

          final usableCrossAxisExtent = math.max(
            0.0,
            contentWidth - (crossAxisCount - 1) * crossAxisSpacing,
          );
          final cellMainAxisExtent = usableCrossAxisExtent / crossAxisCount;

          // Update controller with exact layout info for precise scroll offset calculations
          // 延迟执行，避免在 build 过程中更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _controller.updateLayoutInfo(
              contentWidth,
              crossAxisCount,
              cellMainAxisExtent,
            );
          });

          final items = _controller.photoItems;
          final topLoadingExtent = isLoadingUp ? _controller.layoutTopLoadingExtent : 0.0;
          final gridViewportTop = math.max(
            0.0,
            topLoadingExtent - _scrollOffsetSafe,
          );
          _gridViewportHeight = (constraints.maxHeight - gridViewportTop).clamp(0.0, constraints.maxHeight);

          final rectKey = [
            items.length,
            crossAxisCount,
            contentWidth.toStringAsFixed(2),
            cellMainAxisExtent.toStringAsFixed(2),
            crossAxisSpacing.toStringAsFixed(2),
            mainAxisSpacing.toStringAsFixed(2),
            leftPadding.toStringAsFixed(2),
            _controller.layoutHeaderExtent.toStringAsFixed(2),
          ].join('|');
          if (_rectCacheKey != rectKey) {
            _rectCacheKey = rectKey;
            _rebuildPhotoRectCache(
              items: items,
              crossAxisCount: crossAxisCount,
              totalCrossAxisExtent: contentWidth,
              cellExtent: cellMainAxisExtent,
              headerExtent: _controller.layoutHeaderExtent,
              crossAxisSpacing: crossAxisSpacing,
              mainAxisSpacing: mainAxisSpacing,
              leftPadding: leftPadding,
            );
          }

          final indexByPhotoId = <int, int>{};
          for (var i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is TimelineListPhoto) {
              indexByPhotoId[item.photo.id] = i;
            }
          }

          final enableMarquee = DeviceUtils.isDesktop ||
              (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));

          final scrollView = ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: CustomScrollView(
              key: _controller.listViewKey,
              controller: _controller.scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Obx(() {
                  if (_controller.isLoadingUp.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CustomLoadingIndicator()),
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ),
              SliverPadding(
                padding: gridPadding,
                sliver: SliverGrid(
                  gridDelegate: _TimelineGridDelegate(
                    items: items,
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: crossAxisSpacing,
                    mainAxisSpacing: mainAxisSpacing,
                    childAspectRatio: 1.0,
                    headerExtent: _controller.layoutHeaderExtent,
                    loadingExtent: 0,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildGridChild(items[index]),
                    childCount: items.length,
                    findChildIndexCallback: (key) {
                      if (key is ValueKey<int>) {
                        return indexByPhotoId[key.value];
                      }
                      return null;
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Obx(() {
                  if (_controller.isLoadingDown.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CustomLoadingIndicator()),
                    );
                  }
                  if (!_controller.hasMoreDown.value) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('no_more'.tr),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ),
            ],
            ),
          );

          if (!enableMarquee) return scrollView;

          return Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (e.buttons != kPrimaryButton) return;
                  final local = e.localPosition;
                  final gridLocal = Offset(local.dx, local.dy - gridViewportTop);
                  if (gridLocal.dy < 0) return;
                  _pointerDownGridPos = gridLocal;
                  _multiModeAtStart = _controller.isMultiSelectMode.value;
                  _pointerDownHitPhotoId = _hitTestPhotoIdAtContentPoint(
                    Offset(gridLocal.dx, gridLocal.dy + _currentGridScrollOffset()),
                  );
                  _pointerDownHitTimelineItem =
                      _pointerDownHitPhotoId != null ||
                      _hitTestHeaderAtContentPoint(
                        Offset(
                          gridLocal.dx,
                          gridLocal.dy + _currentGridScrollOffset(),
                        ),
                      );
                  _marqueeActive = false;
                },
                onPointerMove: (e) {
                  if (e.buttons != kPrimaryButton) return;
                  if (_pointerDownGridPos == null) return;
                  final local = e.localPosition;
                  final gridLocal = Offset(local.dx, local.dy - gridViewportTop);
                  final origin = _pointerDownGridPos!;
                  if (!_marqueeActive) {
                    if ((gridLocal - origin).distance > _kMarqueeThreshold) {
                      _marqueeActive = true;
                      _dragging = true;
                      _lastGridLocal = gridLocal;
                      _ensureAutoTimer();
                      _controller.startDragSelection(
                        origin,
                        scrollOffset: _currentGridScrollOffset(),
                      );
                    }
                  }
                  if (_marqueeActive) {
                    _lastGridLocal = gridLocal;
                    _controller.updateDragSelection(
                      gridLocal,
                      scrollOffset: _currentGridScrollOffset(),
                    );
                    _scheduleHitTest();
                  }
                },
                onPointerUp: (e) {
                  if (_marqueeActive) {
                    final hits = _performHitTest();
                    _dragging = false;
                    _controller.finishDragSelection();
                    _controller.applyDragSelection(
                      hits,
                      multiModeAtStart: _multiModeAtStart,
                      additive: _isAdditiveSelectionActive,
                    );
                  } else if (_pointerDownGridPos != null) {
                    final local = e.localPosition;
                    final gridLocal = Offset(local.dx, local.dy - gridViewportTop);
                    final dist = (gridLocal - _pointerDownGridPos!).distance;
                    if (dist < _kMarqueeThreshold &&
                        !_pointerDownHitTimelineItem) {
                      _controller.exitMultiSelectMode();
                    }
                  }
                  _pointerDownGridPos = null;
                  _pointerDownHitPhotoId = null;
                  _pointerDownHitTimelineItem = false;
                  _marqueeActive = false;
                },
                onPointerCancel: (e) {
                  if (_marqueeActive) {
                    _dragging = false;
                    _controller.finishDragSelection();
                  }
                  _pointerDownGridPos = null;
                  _pointerDownHitTimelineItem = false;
                  _pointerDownHitPhotoId = null;
                  _marqueeActive = false;
                },
                child: scrollView,
              ),
              Obx(() {
                final r = _controller.selectionRect.value;
                if (r == null) return const SizedBox.shrink();
                return Positioned(
                  left: r.left,
                  top: r.top + gridViewportTop,
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
            ],
          );
        },
      );
    });
  }

  Widget _buildGridChild(TimelineListItem item) {
    if (item is TimelineListPhoto) {
      // 照片项组件
      return PhotoTimelineItem(
        key: ValueKey(item.photo.id),
        item: item.photo,
        controllerTag: widget.controllerTag,
      );
    }
    if (item is TimelineListDateHeader) {
      // 日期头组件
      return PhotoTimelineItemDate(item: item, controllerTag: widget.controllerTag);
    }
    return const SizedBox.shrink();
  }
}

class _PhotoRectEntry {
  final int photoId;
  final Rect rect;

  const _PhotoRectEntry({required this.photoId, required this.rect});
}

class _TimelineGridDelegate extends SliverGridDelegate {
  final List<TimelineListItem> items;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double childAspectRatio;
  final double headerExtent;
  final double loadingExtent;

  const _TimelineGridDelegate({
    required this.items,
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.childAspectRatio,
    required this.headerExtent,
    required this.loadingExtent,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final totalCrossAxisExtent = constraints.crossAxisExtent;
    final usableCrossAxisExtent = math.max(
      0.0,
      totalCrossAxisExtent - (crossAxisCount - 1) * crossAxisSpacing,
    );
    final cellCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    final cellMainAxisExtent = childAspectRatio == 0
        ? cellCrossAxisExtent
        : cellCrossAxisExtent / childAspectRatio;

    final geometries = List<SliverGridGeometry>.filled(
      items.length,
      const SliverGridGeometry(
        scrollOffset: 0,
        crossAxisOffset: 0,
        mainAxisExtent: 0,
        crossAxisExtent: 0,
      ),
      growable: false,
    );
    final trailingOffsets = List<double>.filled(
      items.length,
      0,
      growable: false,
    );
    final leadingOffsets = List<double>.filled(
      items.length,
      0,
      growable: false,
    );

    double mainAxisOffset = 0;
    var col = 0;

    void startNewRowIfNeeded() {
      if (col == 0) return;
      mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
      col = 0;
    }

    for (var i = 0; i < items.length; i++) {
      final n = items[i];

      if (n is TimelineListDateHeader) {
        startNewRowIfNeeded();

        final mainAxisExtent = headerExtent;

        geometries[i] = SliverGridGeometry(
          scrollOffset: mainAxisOffset,
          crossAxisOffset: 0,
          mainAxisExtent: mainAxisExtent,
          crossAxisExtent: totalCrossAxisExtent,
        );
        leadingOffsets[i] = mainAxisOffset;
        trailingOffsets[i] = mainAxisOffset + mainAxisExtent;
        mainAxisOffset += mainAxisExtent + mainAxisSpacing;
        continue;
      }

      final crossAxisOffset = col * (cellCrossAxisExtent + crossAxisSpacing);
      geometries[i] = SliverGridGeometry(
        scrollOffset: mainAxisOffset,
        crossAxisOffset: crossAxisOffset,
        mainAxisExtent: cellMainAxisExtent,
        crossAxisExtent: cellCrossAxisExtent,
      );
      leadingOffsets[i] = mainAxisOffset;
      trailingOffsets[i] = mainAxisOffset + cellMainAxisExtent;

      col++;
      if (col >= crossAxisCount) {
        col = 0;
        mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
      }
    }

    final maxScrollOffset = items.isEmpty
        ? 0.0
        : math.max(0.0, trailingOffsets.reduce(math.max));

    return _TimelineGridLayout(
      geometries: geometries,
      leadingOffsets: leadingOffsets,
      trailingOffsets: trailingOffsets,
      maxScrollOffset: maxScrollOffset,
    );
  }

  @override
  bool shouldRelayout(covariant _TimelineGridDelegate oldDelegate) {
    return crossAxisCount != oldDelegate.crossAxisCount ||
        crossAxisSpacing != oldDelegate.crossAxisSpacing ||
        mainAxisSpacing != oldDelegate.mainAxisSpacing ||
        childAspectRatio != oldDelegate.childAspectRatio ||
        headerExtent != oldDelegate.headerExtent ||
        loadingExtent != oldDelegate.loadingExtent ||
        items.length != oldDelegate.items.length;
  }
}

class _TimelineGridLayout extends SliverGridLayout {
  final List<SliverGridGeometry> geometries;
  final List<double> leadingOffsets;
  final List<double> trailingOffsets;
  final double maxScrollOffset;

  const _TimelineGridLayout({
    required this.geometries,
    required this.leadingOffsets,
    required this.trailingOffsets,
    required this.maxScrollOffset,
  });

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index < 0 || index >= geometries.length) {
      return const SliverGridGeometry(
        scrollOffset: 0,
        crossAxisOffset: 0,
        mainAxisExtent: 0,
        crossAxisExtent: 0,
      );
    }
    return geometries[index];
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    return maxScrollOffset;
  }

  int _lowerBoundTrailing(double scrollOffset) {
    var lo = 0;
    var hi = trailingOffsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (trailingOffsets[mid] <= scrollOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _upperBoundLeading(double scrollOffset) {
    var lo = 0;
    var hi = leadingOffsets.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (leadingOffsets[mid] <= scrollOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    if (geometries.isEmpty) return 0;
    return _lowerBoundTrailing(scrollOffset).clamp(0, geometries.length - 1);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (geometries.isEmpty) return 0;
    final idx = _upperBoundLeading(scrollOffset) - 1;
    return idx.clamp(0, geometries.length - 1);
  }
}
