part of '../photo_timeline_controller.dart';

/// 控制器设置项（排序、文件类型、缩略图尺寸）的读写与变更入口。
extension PhotoTimelineControllerSettings on PhotoTimelineController {
  /// 从本地缓存恢复用户上一次设置。
  ///
  /// 这里不做网络请求，仅用于初始化 UI 状态与后续请求参数。
  void _loadSettings() {
    sortOrder.value =
        CacheManager().getString(PhotoTimelineController.keySortOrder) ??
        'desc';
    // fileType.value =
    //     CacheManager().getString(PhotoTimelineController.keyFileType) ?? 'all';
    itemSize.value =
        CacheManager().getDouble(PhotoTimelineController.keyItemSize) ?? 140.0;
    isCoverMode.value =
        CacheManager().getBool(PhotoTimelineController.keyIsCoverMode) ?? true;
  }

  /// 将当前设置写回本地缓存。
  void _saveSettings() {
    CacheManager().setString(
      PhotoTimelineController.keySortOrder,
      sortOrder.value,
    );
    // CacheManager().setString(
    //   PhotoTimelineController.keyFileType,
    //   fileType.value,
    // );
    CacheManager().setDouble(
      PhotoTimelineController.keyItemSize,
      itemSize.value,
    );
    CacheManager().setBool(
      PhotoTimelineController.keyIsCoverMode,
      isCoverMode.value,
    );
  }

  /// 切换时间轴排序。
  ///
  /// - `desc`：日期/时间倒序（较新的在前）
  /// - `asc`：日期/时间正序（较旧的在前）
  ///
  /// 切换后会触发整条时间轴重新加载，清理已加载数据与选择状态。
  void toggleSortOrder() {
    sortOrder.value = sortOrder.value == 'desc' ? 'asc' : 'desc';
    _saveSettings();
    _loadDateList();
  }

  /// 设置文件类型筛选（例如全部/图片/视频等）。
  ///
  /// 切换后同样会触发整条时间轴重新加载。
  void setFileType(String type) {
    fileType.value = type;
    _saveSettings();
    _loadDateList();
  }

  void setTimelineMode({
    required String nextListType,
    required bool nextLoadTheDay,
  }) {
    if (listType.value == nextListType && loadTheDay.value == nextLoadTheDay) {
      return;
    }
    listType.value = nextListType;
    loadTheDay.value = nextLoadTheDay;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    _loadDateList();
  }

  /// 改变缩略图尺寸（影响网格列数与排布）。
  ///
  /// `delta` 为增量，最终尺寸会被限制在 [80, 400] 区间内。
  void changeItemSize(double delta) {
    double newSize = itemSize.value + delta;
    if (newSize < minItemSize) newSize = minItemSize.toDouble();
    if (newSize > maxItemSize) newSize = maxItemSize.toDouble();
    itemSize.value = newSize;
    print("newSize: $newSize");
    _saveSettings();
  }

  void setItemSize(double newSize, {bool save = true}) {
    if (newSize < minItemSize) newSize = minItemSize.toDouble();
    if (newSize > maxItemSize) newSize = maxItemSize.toDouble();
    itemSize.value = newSize;
    if (save) _saveSettings();
  }

  /// 切换图片显示模式（Cover/Contain）。
  void toggleCoverMode() {
    isCoverMode.toggle();
    _saveSettings();
  }

  Future<bool> _restoreSelectedPaths(
    List<TimelinePathItem> availablePathItems,
  ) async {
    final restoredPaths = await _sourceFilterStorage.restoreSelection(
      availablePaths: availablePathItems.map((item) => item.path),
    );
    if (_sameSelectedPaths(selectedPaths, restoredPaths)) {
      return false;
    }
    selectedPaths.assignAll(restoredPaths);
    return true;
  }

  Future<void> setSourcePathSelected(String path, bool isSelected) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    final nextSelectedPaths = selectedPaths.toList(growable: true);
    final hasSelected = nextSelectedPaths.contains(normalizedPath);
    if (isSelected) {
      if (hasSelected) {
        return;
      }
      nextSelectedPaths.add(normalizedPath);
    } else {
      if (!hasSelected) {
        return;
      }
      nextSelectedPaths.remove(normalizedPath);
    }
    selectedPaths.assignAll(nextSelectedPaths);
    await _sourceFilterStorage.saveSelection(selectedPaths);
    await refreshTimeline();
  }

  Future<void> clearSourcePathSelection({bool refresh = true}) async {
    if (selectedPaths.isEmpty) {
      await _sourceFilterStorage.saveSelection(const <String>[]);
      if (refresh) {
        await refreshTimeline();
      }
      return;
    }
    selectedPaths.clear();
    await _sourceFilterStorage.saveSelection(const <String>[]);
    if (refresh) {
      await refreshTimeline();
    }
  }
}
