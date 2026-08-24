part of '../photo_timeline_controller.dart';

/// 时间轴“重置/跳转/初始化加载”相关逻辑。
extension PhotoTimelineControllerLoading on PhotoTimelineController {
  /// 手动刷新入口：重新拉取日期列表并重置页面数据。
  Future<void> refreshTimeline() async {
    await _loadDateList();
  }

  /// 加载日期列表，并在成功后加载首屏照片。
  ///
  /// 该方法会重置以下状态：
  /// - 加载标记、上下是否还有更多
  /// - 多选状态与选中集合
  /// - photoItems
  /// - 日期 header key 缓存
  Future<void> _loadDateList() async {
    final requestedSelectedPaths = selectedPaths.toList(growable: false);
    isLoadingDates.value = true;
    hasMoreUp.value = true;
    hasMoreDown.value = true;
    isMultiSelectMode.value = false;
    selectedItems.clear();
    photoItems.clear();
    dateInfoMap.clear();

    try {
      final type = fileType.value == 'all' ? null : fileType.value;
      // 拉取日期列表
      final res = await _apiService.getTimelineDateList(
        sort: sortOrder.value,
        fileType: type,
        search: searchKeyword.value,
        geohash: geohashForRequest,
        sourceList: requestedSelectedPaths.isEmpty ? null : requestedSelectedPaths,
        listType: listType.value == 'favorite' ? 'favorite' : null,
        albumId: albumId.value,
        collectionId: collectionId.value,
        smartAlbumId: smartAlbumId.value,
        faceId: faceId.value,
        placeName: placeName.value,
        loadTheDay: loadTheDay.value,
        year: year.value,
      );

      if (res.success && res.data != null) {
        dateList.assignAll(res.data!.items);
        availablePaths.assignAll(res.data!.validPaths);
        final didRestoreSelectedPaths = await _restoreSelectedPaths(
          res.data!.validPaths,
        );
        if (
          didRestoreSelectedPaths &&
          !_sameSelectedPaths(requestedSelectedPaths, selectedPaths)
        ) {
          await _loadDateList();
          return;
        }

        // 检查不可用路径
        final invalidPaths = res.data!.validPaths
            .where((p) => !p.valid)
            .toList();
        if (invalidPaths.isNotEmpty) {
          _checkAndAlertInvalidPaths(invalidPaths);
        }
        if (res.data!.validPaths.isEmpty) {
          //未设置来源路径 提示用户
          final isAdmin = CurrentUserController.instance.isAdmin;
          if (alertWhenNoSourcePath && isAdmin) {
            DialogUtil.showConfirmDialog(
              title: 'tip'.tr,
              content: 'path_no_set'.tr,
              confirmText: 'go_to'.tr,
              cancelText: 'i_know'.tr,
              onConfirm: () {
                // 跳转到来源设置
                if (Get.isRegistered<PhotoHomeController>()) {
                  Get.find<PhotoHomeController>().currentPageKey.value =
                      'settings.source';
                  return;
                }
                if (DeviceUtils.isMobile) {
                  Get.to(
                    () => const AppPhotoSettingsView(initialTabIndex: 0),
                    preventDuplicates: false,
                  );
                }
              },
            );
          }
        }

        if (dateList.isNotEmpty) {
          // 加载首屏照片
          await _loadInitialPhotos();
          // 刷新完成后，将列表滚动到顶部
          if (scrollController.hasClients) {
            scrollController.jumpTo(0);
          }
        }
      }
    } catch (e) {
      print('加载日期列表错误: $e');
    } finally {
      isLoadingDates.value = false;
    }
  }

  /// 加载首屏照片。
  ///
  /// 首屏的定位规则：
  /// - 排序为 `desc`：取日期列表的第一天，使用“当天结束”作为 `originalTime`，向“更旧”方向拉取
  /// - 排序为 `asc`：取日期列表的第一天，使用“当天开始”作为 `originalTime`，向“更新”方向拉取
  Future<void> _loadInitialPhotos() async {
    if (dateList.isEmpty) return;

    isLoadingDown.value = true;
    try {
      final firstDateStr = dateList.first.originalDate;

      final range = _buildFetchRangeByMinCount(
        anchorDate: firstDateStr,
        up: false,
        includeAnchor: true,
        minCount: PhotoTimelineController.minGetCount,
      );

      if (range == null) {
        hasMoreDown.value = false;
        hasMoreUp.value = false;
        return;
      }

      // 获取照片列表
      final result = await _fetchAndProcessPhotos(
        startTime: range.startTime,
        endTime: range.endTime,
        isUp: false,
        clear: true,
      );

      if (!result.hasData) {
        hasMoreDown.value = false;
        hasMoreUp.value = false;
      } else {
        hasMoreUp.value = range.startIndex > 0;
        hasMoreDown.value = range.endIndex < dateList.length - 1;
      }
    } catch (e) {
      print('加载初始照片错误: $e');
    } finally {
      isLoadingDown.value = false;
    }
  }

  /// 跳转到某个日期（侧边栏点击）。
  ///
  /// 流程分两步：
  /// 1) 以目标日期的起止时间为锚点拉取一页，确保目标日期附近的数据在内存中
  /// 2) 再向“上方”补一页（`up: true`），尽量保证目标日期在视口中间更容易找到 header
  /// 3) `Scrollable.ensureVisible` 对应日期的 header，实现“无动画”定位
  Future<void> jumpToDate(String date) async {
    // 记录首次加载时的第一个日期 用于加载上一页后回跳
    showTimeline();

    hasMoreUp.value = true;
    hasMoreDown.value = true;
    isMultiSelectMode.value = false;
    selectedItems.clear();
    photoItems.clear();
    isLoadingDown.value = true;

    try {
      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
      }

      final range = _buildFetchRangeByMinCount(
        anchorDate: date,
        up: false,
        includeAnchor: true,
        minCount: PhotoTimelineController.minGetCount,
      );

      if (range == null) {
        hasMoreDown.value = false;
        hasMoreUp.value = false;
        return;
      }

      final result = await _fetchAndProcessPhotos(
        startTime: range.startTime,
        endTime: range.endTime,
        isUp: false,
        clear: true,
      );

      if (!result.hasData) {
        hasMoreDown.value = false;
        hasMoreUp.value = false;
      } else {
        hasMoreUp.value = range.startIndex > 0;
        hasMoreDown.value = range.endIndex < dateList.length - 1;
      }

      if (photoItems.isNotEmpty) {
        await _loadMore(up: true);
      }
    } catch (e) {
      print('跳转日期错误: $e');
    } finally {
      isLoadingDown.value = false;
    }
  }

  void _checkAndAlertInvalidPaths(List<TimelinePathItem> invalidPaths) {
    // 避免重复弹窗（简单的防抖，或者只弹一次？这里暂时每次检测到都弹，因为用户可能修复了）
    // 为了防止频繁弹窗，可以加一个简单的标记，比如本次会话已弹过就不弹了，但用户要求“马上弹窗”
    // 考虑到这是在 loadDateList 调用的，通常是页面初始化或刷新时，频率不高。

    final pathStr = invalidPaths.map((e) => e.path).join('\n');
    final isAdmin = CurrentUserController.instance.isAdmin;

    if (isAdmin) {
      DialogUtil.showConfirmDialog(
        title: 'path_invalid_admin_title'.tr,
        content: 'path_invalid_admin_content'.trParams({'path': '\n$pathStr'}),
        confirmText: 'check_now'.tr,
        cancelText: 'i_know'.tr,
        onConfirm: () {
          // 跳转到来源设置
          if (Get.isRegistered<PhotoHomeController>()) {
            Get.find<PhotoHomeController>().currentPageKey.value =
                'settings.source';
            return;
          }
        },
      );
    } else {
      DialogUtil.showInfoDialog(
        title: 'path_invalid_user_title'.tr,
        content: 'path_invalid_user_content'.trParams({'path': '\n$pathStr'}),
        buttonText: 'i_know'.tr,
      );
    }
  }

  /// 获取文件属性
  Future<Map<String, dynamic>?> getFileProperties(String filePath) async {
    try {
      final baseUrl = ApiController.instance.baseUrl;
      final token = ApiController.instance.accessToken;
      final res = await HttpUtil.get(
        '$baseUrl/api/file/attributes?path=${Uri.encodeComponent(filePath)}',
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      if (res.isOk && res.json != null) {
        return res.json!['data'] as Map<String, dynamic>;
      }
    } catch (e) {
      return null;
    }
    return null;
  }
}
