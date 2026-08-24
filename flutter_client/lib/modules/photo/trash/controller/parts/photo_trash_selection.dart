part of '../photo_trash_controller.dart';

// 多选操作管理
extension PhotoTrashSelection on PhotoTrashController {
  /// 切换多选模式
  void toggleMultiSelectMode() {
    isMultiSelectMode.value = !isMultiSelectMode.value;
    if (!isMultiSelectMode.value) {
      selectedItems.clear();
    }
  }

  /// 强制退出多选模式并清空选中
  void exitMultiSelectMode() {
    isMultiSelectMode.value = false;
    selectedItems.clear();
  }

  /// 切换单个照片的选中状态
  void toggleSelection(int id) {
    if (selectedItems.contains(id)) {
      selectedItems.remove(id);
    } else {
      selectedItems.add(id);
    }
    if (selectedItems.isNotEmpty && !isMultiSelectMode.value) {
      isMultiSelectMode.value = true;
    }
    if (selectedItems.isEmpty) {
      isMultiSelectMode.value = false;
    }
  }

  /// 全选/取消全选
  void toggleSelectAll() {
    if (selectedItems.length == photoItems.length) {
      // 取消全选
      selectedItems.clear();
      isMultiSelectMode.value = false;
    } else {
      // 全选
      selectedItems.assignAll(photoItems.map((item) => item.id));
      isMultiSelectMode.value = true;
    }
  }

  void startDragSelection(Offset start, {double scrollOffset = 0}) {
    dragStartViewport = start;
    dragStartScrollOffset = scrollOffset;
    dragSelectionBaseline = selectedItems.toSet();
    selectionRect.value = Rect.fromLTWH(start.dx, start.dy, 0, 0);
    selectionRectContent.value = Rect.fromLTWH(
      start.dx,
      start.dy + scrollOffset,
      0,
      0,
    );
  }

  void updateDragSelection(Offset current, {double scrollOffset = 0}) {
    final s = dragStartViewport;
    if (s == null) return;
    final left = s.dx < current.dx ? s.dx : current.dx;
    final top = s.dy < current.dy ? s.dy : current.dy;
    final width = (s.dx - current.dx).abs();
    final height = (s.dy - current.dy).abs();
    selectionRect.value = Rect.fromLTWH(left, top, width, height);

    final startContentY = s.dy + dragStartScrollOffset;
    final currentContentY = current.dy + scrollOffset;
    final topContent = startContentY < currentContentY ? startContentY : currentContentY;
    final heightContent = (startContentY - currentContentY).abs();
    selectionRectContent.value = Rect.fromLTWH(
      left,
      topContent,
      width,
      heightContent,
    );
  }

  void updateDragPreview(Set<int> hitIds, {required bool additive}) {
    final baseline = dragSelectionBaseline ?? selectedItems.toSet();
    final next = additive ? (baseline.toSet()..addAll(hitIds)) : hitIds;
    selectedItems
      ..clear()
      ..addAll(next);
    selectedItems.refresh();
  }

  void applyDragSelection(
    Set<int> hitIds, {
    required bool multiModeAtStart,
    required bool additive,
  }) {
    final baseline = dragSelectionBaseline ?? selectedItems.toSet();
    final next = additive ? (baseline.toSet()..addAll(hitIds)) : hitIds;
    selectedItems
      ..clear()
      ..addAll(next);
    selectedItems.refresh();
    if (next.isNotEmpty) {
      if (!isMultiSelectMode.value) isMultiSelectMode.value = true;
    }
    if (next.isEmpty && !multiModeAtStart) {
      isMultiSelectMode.value = false;
    }
  }

  void finishDragSelection() {
    selectionRect.value = null;
    selectionRectContent.value = null;
    dragStartViewport = null;
    dragStartScrollOffset = 0;
    dragSelectionBaseline = null;
  }
}
