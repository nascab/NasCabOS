import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import 'dart:math' as math;
import 'pc_file_list_header.dart';
import 'pc_file_list_listview_item.dart';
import '../../controllers/pc_file_explorer_controller.dart';

import 'pc_file_context_menu_handler.dart';
import 'pc_internal_drag_item.dart';

class PcFileListListView extends StatefulWidget {
  const PcFileListListView({super.key, required this.ctrl});
  final PcFileExplorerController ctrl;
  @override
  State<PcFileListListView> createState() => _PcFileListListViewState();
}

class _PcFileListListViewState extends State<PcFileListListView> {
  final ScrollController _listScrollCtrl = ScrollController();
  final ScrollController _hScrollCtrl = ScrollController();
  Timer? _autoTimer;
  Timer? _throttleTimer;
  bool _dragging = false;
  double _viewportHeight = 0;
  double _contentWidth = 0;
  Offset _lastLocal = const Offset(0, 0);

  Offset? _pointerDownPos;
  int? _pointerDownRowIndex;
  bool _suppressMarqueeFromIcon = false;
  bool _marqueeActive = false;
  static const double _kMarqueeThreshold = 8;

  @override
  void initState() {
    super.initState();
    _listScrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _throttleTimer?.cancel();
    _listScrollCtrl.dispose();
    _hScrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_dragging) {
      widget.ctrl.updateDragSelection(
        _lastLocal,
        scrollOffset: _listScrollCtrl.offset,
      );
      _scheduleHitTest();
    }
  }

  void _scheduleHitTest() {
    if (_throttleTimer?.isActive ?? false) return;
    _throttleTimer = Timer(const Duration(milliseconds: 60), _performHitTest);
  }

  int? _hitTestListIndex(Offset local, int dataLength, double rowHeight) {
    final idx = ((local.dy + _listScrollCtrl.offset) / rowHeight).floor();
    if (idx >= 0 && idx < dataLength) return idx;
    return null;
  }

  bool _listPointInIconDragArea(
    Offset local,
    int rowIndex,
    int dataLength,
    double rowHeight,
  ) {
    if (rowIndex < 0 || rowIndex >= dataLength) return false;
    final withinRowY = local.dy + _listScrollCtrl.offset - rowIndex * rowHeight;
    const iconSize = 50.0;
    const leftPad = 12.0;
    final iconTop = (rowHeight - iconSize) / 2;
    final iconRect = Rect.fromLTWH(leftPad, iconTop, iconSize, iconSize);
    return iconRect.contains(Offset(local.dx, withinRowY));
  }

  void _onNonMarqueePointerUp(PointerEvent e) {
    if (_marqueeActive) {
      _performHitTest();
      _dragging = false;
      widget.ctrl.finishDragSelection();
    } else if (_pointerDownPos != null) {
      final dist = (e.localPosition - _pointerDownPos!).distance;
      if (dist < _kMarqueeThreshold &&
          _pointerDownRowIndex == null &&
          !widget.ctrl.isAdditiveSelectionActive) {
        final data = widget.ctrl.displayItems;
        const rowHeight = PcFileExplorerController.kListViewRowHeight;
        final yBottom = -_listScrollCtrl.offset + data.length * rowHeight;
        if (e.localPosition.dy > yBottom) {
          widget.ctrl.clearSelect();
        }
      }
    }
    _pointerDownPos = null;
    _pointerDownRowIndex = null;
    _suppressMarqueeFromIcon = false;
    _marqueeActive = false;
  }

  void _performHitTest() {
    if (!_dragging) return;
    final rect = widget.ctrl.selectionRectContent.value;
    final hits = <int>{};
    final data = widget.ctrl.displayItems;
    if (rect != null) {
      final rowHeight = PcFileExplorerController.kListViewRowHeight;
      final minI = (rect.top / rowHeight).floor().clamp(0, data.length);
      final maxI = (rect.bottom / rowHeight).ceil().clamp(0, data.length);

      for (int i = minI; i < maxI; i++) {
        final y = i * rowHeight;
        final r = Rect.fromLTWH(0, y, _contentWidth, rowHeight);
        if (r.overlaps(rect)) hits.add(i);
      }
    }
    widget.ctrl.updateDragPreview(hits);
  }

  double _calcTableWidth(double minWidth) {
    final w = widget.ctrl.columnWidths;
    final total =
        (w['name'] ?? 300) +
        (w['mtime'] ?? 160) +
        (w['size'] ?? 120) +
        (w['type'] ?? 100);
    return math.max(minWidth, total);
  }

  void _ensureAutoTimer() {
    _autoTimer ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_dragging) return;
      final pos = _listScrollCtrl.position;
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
        _listScrollCtrl.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        return Obx(() {
          final tableWidth = _calcTableWidth(cons.maxWidth);
          _contentWidth = tableWidth;
          return Scrollbar(
            controller: _hScrollCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _hScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                height: cons.maxHeight,
                child: Column(
                  children: [
                    PcFileListHeader(ctrl: widget.ctrl),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, cons) {
                          _viewportHeight = cons.maxHeight;
                          const rowHeight = PcFileExplorerController.kListViewRowHeight;
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
                                    final hitIndex = _hitTestListIndex(
                                      local,
                                      data.length,
                                      rowHeight,
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
                                      _pointerDownRowIndex = _hitTestListIndex(
                                        e.localPosition,
                                        data.length,
                                        rowHeight,
                                      );
                                      _suppressMarqueeFromIcon =
                                          _pointerDownRowIndex != null &&
                                          _listPointInIconDragArea(
                                            e.localPosition,
                                            _pointerDownRowIndex!,
                                            data.length,
                                            rowHeight,
                                          );
                                      _marqueeActive = false;
                                    },
                                    onPointerMove: (e) {
                                      if (e.buttons != kPrimaryButton) return;
                                      if (_suppressMarqueeFromIcon) {
                                        return;
                                      }
                                      final origin = _pointerDownPos;
                                      if (origin == null) return;
                                      if (!_marqueeActive) {
                                        if ((e.localPosition - origin)
                                                .distance >
                                            _kMarqueeThreshold) {
                                          _marqueeActive = true;
                                          _dragging = true;
                                          _lastLocal = e.localPosition;
                                          _ensureAutoTimer();
                                          widget.ctrl.startDragSelection(
                                            origin,
                                            scrollOffset:
                                                _listScrollCtrl.offset,
                                          );
                                        }
                                      }
                                      if (_marqueeActive) {
                                        _lastLocal = e.localPosition;
                                        widget.ctrl.updateDragSelection(
                                          e.localPosition,
                                          scrollOffset: _listScrollCtrl.offset,
                                        );
                                        _scheduleHitTest();
                                      }
                                    },
                                    onPointerUp: _onNonMarqueePointerUp,
                                    onPointerCancel: _onNonMarqueePointerUp,
                                    child: Obx(() {
                                      final data = widget.ctrl.displayItems;
                                      return ListView.builder(
                                        itemCount: data.length,
                                        controller: _listScrollCtrl,
                                        itemBuilder: (_, i) {
                                          final it = data[i];
                                          final path =
                                              it['path']?.toString() ?? '';
                                          return PcInternalFolderDropTarget(
                                            ctrl: widget.ctrl,
                                            item: it,
                                            alignDropHintToListIconLeading:
                                                true,
                                            overlayBorderRadius:
                                                BorderRadius.circular(4),
                                            child: PcFileListListViewItem(
                                              key: ValueKey(path),
                                              item: it,
                                              onTap: () {
                                                widget.ctrl.handleItemTap(
                                                  it,
                                                  data,
                                                );
                                              },
                                              onIconTap: () {
                                                widget.ctrl.handleAudioIconTap(
                                                  it,
                                                );
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
                                  if (r == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Positioned(
                                    left: r.left,
                                    top: r.top,
                                    width: r.width,
                                    height: r.height,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.15,
                                          ),
                                          border: Border.all(
                                            color: Colors.blue,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
