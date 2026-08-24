part of '../pc_file_explorer_controller.dart';

extension PcFileExplorerDragSelect on PcFileExplorerController {
  /// 开始拖拽框选
  void startDragSelection(Offset start, {double scrollOffset = 0}) {
    _dragStartViewport = start;
    _dragStartScrollOffset = scrollOffset;
    _dragSelectionBaseline = selected.toSet();
    selectionRect.value = Rect.fromLTWH(start.dx, start.dy, 0, 0);
    selectionRectContent.value = Rect.fromLTWH(
      start.dx,
      start.dy + scrollOffset,
      0,
      0,
    );
  }

  /// 更新拖拽框选（视口与内容坐标同时维护）
  void updateDragSelection(Offset current, {double scrollOffset = 0}) {
    final s = _dragStartViewport;
    if (s == null) return;
    final left = s.dx < current.dx ? s.dx : current.dx;
    final top = s.dy < current.dy ? s.dy : current.dy;
    final width = (s.dx - current.dx).abs();
    final height = (s.dy - current.dy).abs();
    selectionRect.value = Rect.fromLTWH(left, top, width, height);

    final startContentY = s.dy + _dragStartScrollOffset;
    final currentContentY = current.dy + scrollOffset;
    final topContent = startContentY < currentContentY
        ? startContentY
        : currentContentY;
    final heightContent = (startContentY - currentContentY).abs();
    selectionRectContent.value = Rect.fromLTWH(
      left,
      topContent,
      width,
      heightContent,
    );
  }

  /// 根据命中的索引集合实时预览选中状态
  void updateDragPreview(Set<int> hitIndexes) {
    final baseline = _dragSelectionBaseline ?? selected.toSet();
    final additive = isAdditiveSelectionActive;
    if (!additive) {
      final next = <String>{};
      for (final i in hitIndexes) {
        final it = displayItems[i];
        final virtualType = it['virtualType']?.toString() ?? '';
        if (virtualType.isNotEmpty) continue;
        final path = it['path']?.toString() ?? '';
        if (path.isEmpty) continue;
        next.add(path);
      }
      selected
        ..clear()
        ..addAll(next);
      selected.refresh();
    } else {
      final next = baseline.toSet();
      for (final i in hitIndexes) {
        final it = displayItems[i];
        final virtualType = it['virtualType']?.toString() ?? '';
        if (virtualType.isNotEmpty) continue;
        final path = it['path']?.toString() ?? '';
        if (path.isEmpty) continue;
        if (baseline.contains(path)) {
          next.remove(path);
        } else {
          next.add(path);
        }
      }
      selected
        ..clear()
        ..addAll(next);
      selected.refresh();
    }
  }

  /// 结束拖拽框选并根据传入的命中索引集合选中
  /// 结束拖拽（不再更改选中，仅清理拖拽状态）
  void finishDragSelection() {
    selectionRect.value = null;
    selectionRectContent.value = null;
    _dragStartViewport = null;
    _dragStartScrollOffset = 0;
    _dragSelectionBaseline = null;
  }

  void setPointerInView(bool v) {
    pointerInView.value = v;
  }

  void selectAllVisible() {
    selected.clear();
    for (final it in displayItems) {
      final virtualType = it['virtualType']?.toString() ?? '';
      if (virtualType.isNotEmpty) continue;
      final path = it['path']?.toString() ?? '';
      if (path.isEmpty) continue;
      selected.add(path);
    }
    selected.refresh();
  }
}
