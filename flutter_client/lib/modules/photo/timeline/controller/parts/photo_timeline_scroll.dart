part of '../photo_timeline_controller.dart';

/// 滚动监听、日期锚点、时间轴悬浮提示等与 UI 滚动相关的逻辑。
extension PhotoTimelineControllerScroll on PhotoTimelineController {
  String? currentTopDate() {
    if (!scrollController.hasClients) return null;
    final anchor = _findItemAtOffset(scrollController.offset);
    if (anchor == null) return null;
    final item = anchor.item;
    if (item is TimelineListDateHeader) return item.date;
    if (item is TimelineListPhoto) return item.photo.originalDate;
    return null;
  }

  /// 保存当前滚动位置的锚点 item
  void saveAnchorItem() {
    if (!scrollController.hasClients) return;
    final offset = scrollController.offset;

    final anchor = _findItemAtOffset(offset);
    if (anchor != null) {
      savedAnchorItemId = anchor.item.id;
      savedAnchorItemOffset = offset - anchor.startOffset;
      // print("Saved anchor: ${anchor.item.id}, relative: $savedAnchorItemOffset, scroll: $offset");
    } else {
      savedAnchorItemId = null;
      savedAnchorItemOffset = 0.0;
    }
    print("保存锚点: $savedAnchorItemId, 偏移量: $savedAnchorItemOffset");
  }

  /// 恢复滚动位置到锚点 item
  void restoreScrollPosition() {
    if (savedAnchorItemId == null) return;

    // 使用 addPostFrameCallback 确保在 UI 重建（Loading 移除、新数据插入）完成后再进行跳转
    // 避免因布局尚未更新导致的计算偏差或 RenderObject 状态不一致
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final index = photoItems.indexWhere(
        (item) => item.id == savedAnchorItemId,
      );
      if (index != -1) {
        final itemStart = _calculateScrollOffsetForIndex(index);
        if (itemStart >= 0) {
          final newOffset = itemStart + savedAnchorItemOffset;
          print(
            "Restoring to $savedAnchorItemId: $newOffset (Start: $itemStart, Relative: $savedAnchorItemOffset)",
          );
          if (scrollController.hasClients) {
            scrollController.jumpTo(newOffset);
          }
        }
      }
      savedAnchorItemId = null;
      savedAnchorItemOffset = 0.0;
    });
  }

  ({TimelineListItem item, double startOffset})? _findItemAtOffset(
    double scrollOffset,
  ) {
    if (_viewportContentWidth <= 0 ||
        _crossAxisCount <= 0 ||
        photoItems.isEmpty) {
      return null;
    }

    final mainAxisSpacing = layoutMainAxisSpacing;
    final headerExtent = layoutHeaderExtent;

    final crossAxisCount = _crossAxisCount;
    final cellMainAxisExtent = _cellMainAxisExtent;

    double mainAxisOffset = isLoadingUp.value ? layoutTopLoadingExtent : 0;
    var col = 0;

    TimelineListItem? lastCandidateItem;
    double lastCandidateOffset = 0;

    for (var i = 0; i < photoItems.length; i++) {
      final item = photoItems[i];

      if (item is TimelineListDateHeader) {
        if (col != 0) {
          mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
          col = 0;
        }

        // Check if this header starts after the scrollOffset?
        // If mainAxisOffset > scrollOffset, then the PREVIOUS candidate was the correct one.
        if (mainAxisOffset > scrollOffset) {
          if (lastCandidateItem == null) {
            return (item: photoItems.first, startOffset: mainAxisOffset);
          }
          return (item: lastCandidateItem, startOffset: lastCandidateOffset);
        }

        lastCandidateItem = item;
        lastCandidateOffset = mainAxisOffset;

        final height = headerExtent;
        mainAxisOffset += height + mainAxisSpacing;
        continue;
      }

      // Photo
      if (col == 0) {
        // Check if this row starts after the scrollOffset
        if (mainAxisOffset > scrollOffset) {
          if (lastCandidateItem == null) {
            return (item: photoItems.first, startOffset: mainAxisOffset);
          }
          return (item: lastCandidateItem, startOffset: lastCandidateOffset);
        }
        lastCandidateItem = item;
        lastCandidateOffset = mainAxisOffset;
      }

      col++;
      if (col >= crossAxisCount) {
        col = 0;
        mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
      }
    }

    // If we reached the end, return the last candidate
    return lastCandidateItem != null
        ? (item: lastCandidateItem, startOffset: lastCandidateOffset)
        : null;
  }

  double _calculateScrollOffsetForIndex(int targetIndex) {
    if (_viewportContentWidth <= 0 || _crossAxisCount <= 0) {
      // 如果尚未获取到布局信息
      return -1;
    }

    final mainAxisSpacing = layoutMainAxisSpacing;
    final headerExtent = layoutHeaderExtent;

    final crossAxisCount = _crossAxisCount;
    final cellMainAxisExtent = _cellMainAxisExtent;

    double mainAxisOffset = 0;
    var col = 0;

    for (var i = 0; i < photoItems.length; i++) {
      if (i >= targetIndex) {
        mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
        return mainAxisOffset;
      }
      final item = photoItems[i];
      if (item is TimelineListDateHeader) {
        if (col != 0) {
          // Start new row
          mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
          col = 0;
        }
        mainAxisOffset += headerExtent + mainAxisSpacing;
        continue;
      }

      // Photo
      col++;
      if (col >= crossAxisCount) {
        col = 0;
        mainAxisOffset += cellMainAxisExtent + mainAxisSpacing;
      }
    }
    return mainAxisOffset;
  }

  /// 滚动监听：在接近上下边界时触发分页加载。
  ///
  /// - 接近底部且仍在向下滚动：触发向下加载（`up: false`）
  /// - 接近顶部且仍在向上滚动：触发向上加载（`up: true`）
  ///
  /// `threshold` 用于提前触发，避免真正到顶/到底时再加载导致卡顿。
  void _onScroll() {
    showTimeline();

    if (!scrollController.hasClients) return;
    if (_scrollLoadLock) return;

    final position = scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final minScroll = position.minScrollExtent;
    final currentScroll = position.pixels;
    final dir = position.userScrollDirection;

    const threshold = 100.0;

    if (currentScroll >= maxScroll - threshold &&
        dir == ScrollDirection.reverse) {
      unawaited(_triggerLoadMore(up: false));
    }

    if (currentScroll <= minScroll + threshold &&
        dir == ScrollDirection.forward) {
      unawaited(_triggerLoadMore(up: true));
    }
  }

  /// 显示右侧时间轴悬浮 UI（并自动在 2 秒后隐藏）。
  void showTimeline() {
    isTimelineVisible.value = true;
    _timelineHideTimer?.cancel();
    _timelineHideTimer = Timer(const Duration(seconds: 2), () {
      isTimelineVisible.value = false;
    });
  }

  /// 在用户持续 hover/拖动时间轴时保持可见（不设置自动隐藏定时器）。
  void keepTimelineVisible() {
    isTimelineVisible.value = true;
    _timelineHideTimer?.cancel();
  }

  /// 设置当前时间轴 hover 的日期（用于 overlay 显示）。
  ///
  /// 传入 `null` 或空字符串表示取消 hover。
  void setTimelineHoverDate(String? date) {
    final d = date?.trim() ?? '';
    if (d.isEmpty) {
      timelineHoverDate.value = '';
      isTimelineHovering.value = false;
      return;
    }
    timelineHoverDate.value = d;
    isTimelineHovering.value = true;
  }

  /// 清空 hover 日期。
  void clearTimelineHoverDate() {
    timelineHoverDate.value = '';
    isTimelineHovering.value = false;
  }
}
