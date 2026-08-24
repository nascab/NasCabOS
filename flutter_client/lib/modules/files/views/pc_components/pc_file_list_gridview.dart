import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import 'pc_file_list_gridview_item.dart';
import '../../controllers/pc_file_explorer_controller.dart';
import 'pc_file_context_menu_handler.dart';
import 'pc_internal_drag_item.dart';

class PcFileListGridView extends StatefulWidget {
  PcFileListGridView({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;
  @override
  State<PcFileListGridView> createState() => _PcFileListGridViewState();
}

class _PcFileListGridViewState extends State<PcFileListGridView> {
  final ScrollController _gridScrollCtrl = ScrollController();
  Timer? _autoTimer;
  Timer? _throttleTimer;
  bool _dragging = false;
  double _viewportHeight = 0;
  Offset _lastLocal = const Offset(0, 0);

  Offset? _pointerDownPos;
  /// 按下时落在哪一个网格单元（用于空白处点击清除选中）；为 null 表示未点在任一单元格上
  int? _pointerDownCellIndex;
  /// 仅为 true 时表示按在「图标拖动区域」上，此时让给 [Draggable]，不启动圈选
  bool _suppressMarqueeFromIcon = false;
  bool _marqueeActive = false;
  static const double _kMarqueeThreshold = 8;

  // Layout cache for hit testing
  int _crossCount = 1;
  double _cellW = 100;
  double _cellH = 100;
  double _padding = 1.0;
  double _spacing = 1.0;

  @override
  void initState() {
    super.initState();
    _gridScrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _throttleTimer?.cancel();
    _gridScrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_dragging) {
      widget.ctrl.updateDragSelection(
        _lastLocal,
        scrollOffset: _gridScrollCtrl.offset,
      );
      _scheduleHitTest();
    }
  }

  void _scheduleHitTest() {
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 60), _performHitTest);
  }

  int? _hitTestGridIndex(
    Offset local,
    int dataLength,
    int crossCount,
    double padding,
    double cellW,
    double cellH,
    double spacing,
  ) {
    for (int i = 0; i < dataLength; i++) {
      final row = i ~/ crossCount;
      final col = i % crossCount;
      final x = padding + col * (cellW + spacing);
      final y =
          padding - _gridScrollCtrl.offset + row * (cellH + spacing);
      final r = Rect.fromLTWH(x, y, cellW, cellH);
      if (r.contains(local)) return i;
    }
    return null;
  }

  bool _gridPointInIconDragArea(
    Offset local,
    int cellIndex,
    int dataLength,
    int crossCount,
    double padding,
    double cellW,
    double cellH,
    double spacing,
    bool isLargeGrid,
  ) {
    if (cellIndex < 0 || cellIndex >= dataLength) return false;
    final row = cellIndex ~/ crossCount;
    final col = cellIndex % crossCount;
    final x = padding + col * (cellW + spacing);
    final y =
        padding - _gridScrollCtrl.offset + row * (cellH + spacing);
    final cx = local.dx - x;
    final cy = local.dy - y;
    if (cx < 0 || cy < 0 || cx > cellW || cy > cellH) return false;

    const itemPadding = 2.0;
    final iconSize = isLargeGrid ? 130.0 : 60.0;
    const textHeight = 35.0;
    const gap = 6.0;
    final innerH = cellH - itemPadding * 2;
    final iconH = iconSize;
    final contentH = iconH + gap + textHeight;

    double iconTop;
    double iconBottom;
    if (innerH < contentH || innerH <= 0) {
      final band = (innerH * (iconH / contentH)).clamp(4.0, innerH);
      iconTop = itemPadding;
      iconBottom = itemPadding + band;
    } else {
      final yContentTop = itemPadding + (innerH - contentH) / 2;
      iconTop = yContentTop;
      iconBottom = yContentTop + iconH;
    }

    final maxIconW = iconSize * 1.5;
    final maxInnerW = cellW - itemPadding * 2;
    final iconDisplayW =
        maxIconW < maxInnerW ? maxIconW : maxInnerW;
    final iconLeft = (cellW - iconDisplayW) / 2;
    final iconRect = Rect.fromLTRB(
      iconLeft,
      iconTop,
      iconLeft + iconDisplayW,
      iconBottom,
    );
    return iconRect.contains(Offset(cx, cy));
  }

  void _onNonMarqueePointerUp(PointerEvent e) {
    if (_marqueeActive) {
      _performHitTest();
      _dragging = false;
      widget.ctrl.finishDragSelection();
    } else if (_pointerDownPos != null) {
      final dist = (e.localPosition - _pointerDownPos!).distance;
      if (dist < _kMarqueeThreshold &&
          _pointerDownCellIndex == null &&
          !widget.ctrl.isAdditiveSelectionActive) {
        widget.ctrl.clearSelect();
      }
    }
    _pointerDownPos = null;
    _pointerDownCellIndex = null;
    _suppressMarqueeFromIcon = false;
    _marqueeActive = false;
  }

  void _performHitTest() {
    if (!_dragging) return;
    final rect = widget.ctrl.selectionRectContent.value;
    final hits = <int>{};
    final data = widget.ctrl.displayItems;
    if (rect != null) {
      // Optimization: only check items that could possibly overlap
      // Grid layout: y = padding + row * (cellH + spacing)
      // row = (y - padding) / (cellH + spacing)

      final rowHeight = _cellH + _spacing;
      final minRow = ((rect.top - _padding) / rowHeight).floor();
      final maxRow = ((rect.bottom - _padding) / rowHeight).ceil();

      final minI = (minRow * _crossCount).clamp(0, data.length);
      final maxI = ((maxRow + 1) * _crossCount).clamp(0, data.length);

      for (int i = minI; i < maxI; i++) {
        final row = i ~/ _crossCount;
        final col = i % _crossCount;
        final x = _padding + col * (_cellW + _spacing);
        final y = _padding + row * (_cellH + _spacing);
        final r = Rect.fromLTWH(x, y, _cellW, _cellH);
        if (r.overlaps(rect)) hits.add(i);
      }
    }
    widget.ctrl.updateDragPreview(hits);
  }

  void _ensureAutoTimer() {
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_dragging) return;
      final pos = _gridScrollCtrl.position;
      if (!pos.hasPixels) return;
      const edge = 30.0;
      double delta = 0.0;
      if (_lastLocal.dy < edge) {
        final t = (edge - _lastLocal.dy).clamp(0.0, edge) / edge;
        delta = -12.0 * t;
      } else {
        final distBottom = (_viewportHeight - _lastLocal.dy);
        if (distBottom < edge) {
          final t = (edge - distBottom).clamp(0.0, edge) / edge;
          delta = 12.0 * t;
        }
      }
      if (delta != 0.0) {
        double target = (pos.pixels + delta).clamp(0.0, pos.maxScrollExtent);
        _gridScrollCtrl.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        _viewportHeight = cons.maxHeight;
        double itemWidth = 94.0;
        double itemHeight = 100.0;
        if (widget.ctrl.viewMode.value == 'large_grid') {
          itemWidth = 158.0;
          itemHeight = 165.0;
        }
        final columns = cons.maxWidth ~/ (itemWidth + 12);
        final crossCount = columns.clamp(1, 12);
        const double padding = 1.0;
        const double spacing = 1.0;
        final availableW =
            cons.maxWidth - padding * 2 - spacing * (crossCount - 1);
        final cellW = availableW / crossCount;
        final ratio = itemWidth / itemHeight;
        final cellH = cellW / ratio;

        // Update layout cache
        _crossCount = crossCount;
        _cellW = cellW;
        _cellH = cellH;
        _padding = padding;
        _spacing = spacing;

        return MouseRegion(
          onEnter: (_) => widget.ctrl.setPointerInView(true),
          onExit: (_) => widget.ctrl.setPointerInView(false),
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) async {
                  final local = details.localPosition;
                  final global = details.globalPosition;
                  final data = widget.ctrl.displayItems;
                  final hitIndex = _hitTestGridIndex(
                    local,
                    data.length,
                    crossCount,
                    padding,
                    cellW,
                    cellH,
                    spacing,
                  );
                  if (hitIndex != null) {
                    final it = data[hitIndex];
                    await PcFileContextMenuHandler.show(
                      context: context,
                      ctrl: widget.ctrl,
                      globalPosition: global,
                      hitItem: it,
                    );
                  } else {
                    await PcFileContextMenuHandler.show(
                      context: context,
                      ctrl: widget.ctrl,
                      globalPosition: global,
                      hitItem: null,
                    );
                  }
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    if (e.buttons != kPrimaryButton) return;
                    final data = widget.ctrl.displayItems;
                    _pointerDownPos = e.localPosition;
                    _pointerDownCellIndex = _hitTestGridIndex(
                      e.localPosition,
                      data.length,
                      crossCount,
                      padding,
                      cellW,
                      cellH,
                      spacing,
                    );
                    final large =
                        widget.ctrl.viewMode.value == 'large_grid';
                    _suppressMarqueeFromIcon = _pointerDownCellIndex !=
                            null &&
                        _gridPointInIconDragArea(
                          e.localPosition,
                          _pointerDownCellIndex!,
                          data.length,
                          crossCount,
                          padding,
                          cellW,
                          cellH,
                          spacing,
                          large,
                        );
                    _marqueeActive = false;
                  },
                  onPointerMove: (e) {
                    if (e.buttons != kPrimaryButton) return;
                    if (_suppressMarqueeFromIcon) return;
                    final origin = _pointerDownPos;
                    if (origin == null) return;
                    if (!_marqueeActive) {
                      if ((e.localPosition - origin).distance >
                          _kMarqueeThreshold) {
                        _marqueeActive = true;
                        _dragging = true;
                        _lastLocal = e.localPosition;
                        _ensureAutoTimer();
                        widget.ctrl.startDragSelection(
                          origin,
                          scrollOffset: _gridScrollCtrl.offset,
                        );
                      }
                    }
                    if (_marqueeActive) {
                      _lastLocal = e.localPosition;
                      widget.ctrl.updateDragSelection(
                        e.localPosition,
                        scrollOffset: _gridScrollCtrl.offset,
                      );
                      _scheduleHitTest();
                    }
                  },
                  onPointerUp: _onNonMarqueePointerUp,
                  onPointerCancel: _onNonMarqueePointerUp,
                  child: Obx(() {
                    final data = widget.ctrl.displayItems;
                    // Remove selected dependency here to avoid rebuilding GridView on selection change
                    return GridView.builder(
                      padding: const EdgeInsets.all(1),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        mainAxisSpacing: 1,
                        crossAxisSpacing: 1,
                        childAspectRatio: itemWidth / itemHeight,
                      ),
                      controller: _gridScrollCtrl,
                      itemCount: data.length,
                      itemBuilder: (_, i) {
                        final it = data[i];
                        return PcInternalFolderDropTarget(
                          ctrl: widget.ctrl,
                          item: it,
                          overlayBorderRadius: BorderRadius.circular(8),
                          child: PcFileListGridViewItem(
                            item: it,
                            onTap: () {
                              widget.ctrl.handleItemTap(it, data);
                            },
                            onIconTap: () {
                              widget.ctrl.handleAudioIconTap(it);
                            },
                            ctrl: widget.ctrl,
                          ),
                        );
                      },
                    );
                  }),
                ),
              ),
              Obx(() {
                final r = widget.ctrl.selectionRect.value;
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
          ),
        );
      },
    );
  }
}
