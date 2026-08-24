part of '../photo_timeline_controller.dart';

/// 上/下分页拉取与数据合并逻辑。
extension PhotoTimelineControllerPagination on PhotoTimelineController {
  /// 根据滚动方向加载更多。
  Future<void> _loadMore({required bool up}) async {
    if (up) {
      if (isLoadingUp.value || !hasMoreUp.value) return;
      saveAnchorItem();
    } else {
      if (isLoadingDown.value || !hasMoreDown.value) return;
    }

    // 从 photoItems 中查找边界照片
    TimelinePhotoItem? boundaryPhoto;
    if (up) {
      for (final item in photoItems) {
        if (item is TimelineListPhoto) {
          boundaryPhoto = item.photo;
          break;
        }
      }
    } else {
      for (final item in photoItems.reversed) {
        if (item is TimelineListPhoto) {
          boundaryPhoto = item.photo;
          break;
        }
      }
    }

    if (boundaryPhoto == null) return;

    try {
      if (up) {
        isLoadingUp.value = true;
      } else {
        isLoadingDown.value = true;
      }

      final boundaryDate = boundaryPhoto.originalDate;
      final range = _buildFetchRangeByMinCount(
        anchorDate: boundaryDate,
        up: up,
        includeAnchor: false,
        minCount: PhotoTimelineController.minGetCount,
      );

      if (range == null) {
        if (up) {
          hasMoreUp.value = false;
        } else {
          hasMoreDown.value = false;
        }
        return;
      }

      final result = await _fetchAndProcessPhotos(
        startTime: range.startTime,
        endTime: range.endTime,
        isUp: up,
        clear: false,
      );

      if (!result.hasData) {
        if (up) {
          hasMoreUp.value = false;
        } else {
          hasMoreDown.value = false;
        }
        return;
      }

      if (up) {
        hasMoreUp.value = range.startIndex > 0;
      } else {
        hasMoreDown.value = range.endIndex < dateList.length - 1;
      }
    } catch (e) {
      print('加载更多错误: $e');
    } finally {
      if (up) {
        isLoadingUp.value = false;
        // 如果是向上加载 则跳转回加载之前的第一个可见组件
        if (photoItems.isNotEmpty) {
          restoreScrollPosition();
        }
      } else {
        isLoadingDown.value = false;
      }
    }
  }

  /// 拉取照片列表并合并到 photoItems。
  Future<FetchResult> _fetchAndProcessPhotos({
    required int startTime,
    required int endTime,
    required bool isUp,
    bool clear = false,
  }) async {
    final type = fileType.value == 'all' ? null : fileType.value;
    final requestSort = sortOrder.value;

    final res = await _apiService.getTimelinePhotoList(
      sort: requestSort,
      fileType: type,
      startTime: startTime,
      endTime: endTime,
      search: searchKeyword.value,
      geohash: geohashForRequest,
      sourceList: selectedPaths.isEmpty ? null : selectedPaths,
      listType: listType.value == 'favorite' ? 'favorite' : null,
      albumId: albumId.value,
      collectionId: collectionId.value,
      smartAlbumId: smartAlbumId.value,
      faceId: faceId.value,
      placeName: placeName.value,
      loadTheDay: loadTheDay.value,
      year: year.value,
    );

    if (!res.success || res.data == null || res.data!.photoList.isEmpty) {
      _lastFetchResult = const FetchResult(
        hasData: false,
        incomingCount: 0,
        addedCount: 0,
      );
      return _lastFetchResult;
    }

    final payload = res.data!;

    if (clear) {
      dateInfoMap.clear();
    }
    for (final info in payload.dateInfoList) {
      final date = info.originalDate.trim();
      if (date.isEmpty) continue;
      dateInfoMap[date] = info;
    }

    var incoming = List<TimelinePhotoItem>.from(payload.photoList);

    if (incoming.isEmpty) {
      _lastFetchResult = FetchResult(
        hasData: false,
        incomingCount: incoming.length,
        addedCount: 0,
      );
      return _lastFetchResult;
    }

    if (clear) {
      // 全量重建
      final newItems = <TimelineListItem>[];
      String? currentDate;

      for (final p in incoming) {
        if (p.originalDate != currentDate) {
          currentDate = p.originalDate;
          newItems.add(TimelineListDateHeader(date: currentDate));
        }
        newItems.add(TimelineListPhoto(photo: p));
      }
      photoItems.assignAll(newItems);
    } else {
      _mergeIncomingPhotos(incoming, isUp: isUp);
    }

    _lastFetchResult = FetchResult(
      hasData: true,
      incomingCount: incoming.length,
      addedCount: incoming.length,
    );
    return _lastFetchResult;
  }

  /// 将“新拉取的数据”合并到 photoItems。
  void _mergeIncomingPhotos(
    List<TimelinePhotoItem> photos, {
    required bool isUp,
  }) {
    if (photos.isEmpty) return;

    // 构建新数据的 TimelineListItem 列表
    final newItems = <TimelineListItem>[];
    String? currentDate;
    // 预处理 newItems
    for (final p in photos) {
      if (p.originalDate != currentDate) {
        currentDate = p.originalDate;
        // 添加日期item
        newItems.add(TimelineListDateHeader(date: currentDate));
      }
      // 添加photo item
      newItems.add(TimelineListPhoto(photo: p));
    }

    // 确定插入位置和边界处理
    if (isUp) {
      // 向上加载：插入到头部
      int insertIndex = 0;

      // 检查边界：新数据的最后一天 vs 旧数据的第一天
      if (insertIndex < photoItems.length) {
        final firstExistingItem = photoItems[insertIndex]; // 应该是 Header
        if (firstExistingItem is TimelineListDateHeader) {
          final lastNewPhoto = photos.last;
          if (lastNewPhoto.originalDate == firstExistingItem.date) {
            // 日期重合，旧数据的这个 Header 是多余的，因为新数据里已经包含了这个日期的 Header（在中间或结尾）
            // 或者新数据结尾是该日期照片，旧数据开头是该日期 Header。
            // 应该移除旧数据的 Header，让新数据的照片与旧数据的照片连在一起。
            photoItems.removeAt(insertIndex);
          }
        }
      }

      photoItems.insertAll(insertIndex, newItems);
    } else {
      // 向下加载：追加到尾部
      int appendIndex = photoItems.length;

      // 检查边界：旧数据的最后一天 vs 新数据的第一天
      // 找到旧数据最后一个 Photo
      TimelinePhotoItem? lastExistingPhoto;
      for (int i = appendIndex - 1; i >= 0; i--) {
        final item = photoItems[i];
        if (item is TimelineListPhoto) {
          lastExistingPhoto = item.photo;
          break;
        }
      }

      if (lastExistingPhoto != null) {
        final firstNewPhoto = photos.first;
        if (lastExistingPhoto.originalDate == firstNewPhoto.originalDate) {
          // 日期重合，新数据的第一个 Header 是多余的
          if (newItems.isNotEmpty && newItems.first is TimelineListDateHeader) {
            newItems.removeAt(0);
          }
        }
      }

      photoItems.insertAll(appendIndex, newItems);
    }
  }

  /// 带节流的触发加载：防止滚动边界抖动时短时间内多次触发分页。
  Future<void> _triggerLoadMore({required bool up}) async {
    if (_scrollLoadLock) return;
    _scrollLoadLock = true;
    try {
      print("触发分页加载 ${up ? '上一页' : '下一页'}");
      await _loadMore(up: up);
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        _scrollLoadLock = false;
      });
    }
  }
}
