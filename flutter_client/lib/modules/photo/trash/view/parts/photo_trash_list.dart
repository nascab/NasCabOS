import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../../../../utils/device_utils.dart';
import '../../controller/photo_trash_controller.dart';
import 'photo_trash_item.dart';

class _PhotoRectEntry {
  final int photoId;
  final Rect rect;

  const _PhotoRectEntry({required this.photoId, required this.rect});
}

class PhotoTrashList extends StatefulWidget {
  final PhotoTrashController controller;
  const PhotoTrashList({super.key, required this.controller});

  @override
  State<PhotoTrashList> createState() => _PhotoTrashListState();
}

class _PhotoTrashListState extends State<PhotoTrashList> {
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

  String _rectCacheKey = '';
  List<_PhotoRectEntry> _photoRectCache = const [];
  List<double> _photoRectBottoms = const [];

  PhotoTrashController get _controller => widget.controller;

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

  double _currentGridScrollOffset() {
    return _scrollOffsetSafe > 0 ? _scrollOffsetSafe : 0.0;
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
    required int itemCount,
    required int crossAxisCount,
    required double cellExtent,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required double leftPadding,
    required double topPadding,
  }) {
    final entries = <_PhotoRectEntry>[];
    final bottoms = <double>[];

    double mainAxisOffset = topPadding;
    var col = 0;

    for (var i = 0; i < itemCount; i++) {
      final photo = _controller.photoItems[i];
      final crossAxisOffset = col * (cellExtent + crossAxisSpacing);
      final r = Rect.fromLTWH(
        leftPadding + crossAxisOffset,
        mainAxisOffset,
        cellExtent,
        cellExtent,
      );
      entries.add(_PhotoRectEntry(photoId: photo.id, rect: r));
      bottoms.add(r.bottom);
      col++;
      if (col >= crossAxisCount) {
        col = 0;
        mainAxisOffset += cellExtent + mainAxisSpacing;
      }
    }

    _photoRectCache = entries;
    _photoRectBottoms = bottoms;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final itemSize = _controller.itemSize.value;
      final isMultiSelectMode = _controller.isMultiSelectMode.value;
      final hasMore = _controller.hasMore.value;
      // Get reference to items to trigger dependency
      final itemsCount = _controller.photoItems.length;

      return LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            0.0,
            constraints.maxWidth -
                PhotoTrashController.leftPadding -
                PhotoTrashController.rightPadding,
          );

          final crossAxisCount = math.max(
            1,
            ((contentWidth + PhotoTrashController.crossAxisSpacing) /
                    (itemSize + PhotoTrashController.crossAxisSpacing))
                .floor(),
          );

          final usableCrossAxisExtent = math.max(
            0.0,
            contentWidth - (crossAxisCount - 1) * PhotoTrashController.crossAxisSpacing,
          );
          final cellExtent = usableCrossAxisExtent / crossAxisCount;

          final double topPadding = 8.0;
          final bottomPadding = isMultiSelectMode ? 76.0 : 8.0;
          final gridPadding = EdgeInsets.only(
            left: PhotoTrashController.leftPadding,
            right: PhotoTrashController.rightPadding,
            top: topPadding,
            bottom: bottomPadding,
          );

          _gridViewportHeight = constraints.maxHeight;

          final items = _controller.photoItems;
          final rectKey = [
            itemsCount,
            crossAxisCount,
            cellExtent.toStringAsFixed(2),
            topPadding.toStringAsFixed(2),
          ].join('|');

          if (_rectCacheKey != rectKey) {
            _rectCacheKey = rectKey;
            _rebuildPhotoRectCache(
              itemCount: items.length,
              crossAxisCount: crossAxisCount,
              cellExtent: cellExtent,
              crossAxisSpacing: PhotoTrashController.crossAxisSpacing,
              mainAxisSpacing: PhotoTrashController.mainAxisSpacing,
              leftPadding: PhotoTrashController.leftPadding,
              topPadding: topPadding,
            );
          }

          final enableMarquee = DeviceUtils.isDesktop ||
              (DeviceUtils.isWeb && DeviceUtils.isDesktopLayout(context));

          final gridView = GridView.builder(
            controller: _controller.scrollController,
            padding: gridPadding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: PhotoTrashController.crossAxisSpacing,
              mainAxisSpacing: PhotoTrashController.mainAxisSpacing,
              childAspectRatio: 1.0,
            ),
            itemCount: itemsCount + (hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == itemsCount) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }
              final photo = items[index];
              return PhotoTrashItem(
                key: ValueKey(photo.id),
                controller: _controller,
                photo: photo,
              );
            },
          );

          if (!enableMarquee) return gridView;

          return Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (e.buttons != kPrimaryButton) return;
                  final local = e.localPosition;
                  final gridLocal = local;
                  _pointerDownGridPos = gridLocal;
                  _multiModeAtStart = isMultiSelectMode;
                  _pointerDownHitPhotoId = _hitTestPhotoIdAtContentPoint(
                    Offset(gridLocal.dx, gridLocal.dy + _currentGridScrollOffset()),
                  );
                  _marqueeActive = false;
                },
                onPointerMove: (e) {
                  if (e.buttons != kPrimaryButton) return;
                  if (_pointerDownGridPos == null) return;
                  final local = e.localPosition;
                  final gridLocal = local;
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
                    final gridLocal = local;
                    final dist = (gridLocal - _pointerDownGridPos!).distance;
                    if (dist < _kMarqueeThreshold && _pointerDownHitPhotoId == null) {
                      _controller.exitMultiSelectMode();
                    }
                  }
                  _pointerDownGridPos = null;
                  _pointerDownHitPhotoId = null;
                  _marqueeActive = false;
                },
                onPointerCancel: (e) {
                  if (_marqueeActive) {
                    _dragging = false;
                    _controller.finishDragSelection();
                  }
                  _pointerDownGridPos = null;
                  _pointerDownHitPhotoId = null;
                  _marqueeActive = false;
                },
                child: gridView,
              ),
              Obx(() {
                final r = _controller.selectionRect.value;
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
            ],
          );
        },
      );
    });
  }
}
