part of '../photo_trash_controller.dart';

// 数据获取和管理
extension PhotoTrashData on PhotoTrashController {
  /// 获取回收站照片列表
  Future<void> fetchTrashPhotos({bool loadMore = false}) async {
    if (isLoading.value) return;

    if (loadMore) {
      currentPage.value++;
    } else {
      currentPage.value = 1;
      photoItems.clear();
      hasMore.value = true;
    }

    isLoading.value = true;

    try {
      final res = await _apiService.getTrashPhotoList(
        page: currentPage.value,
        pageSize: pageSize.value,
        fileType: fileType.value == 'all' ? null : fileType.value,
        search: searchKeyword.value.trim().isNotEmpty
            ? searchKeyword.value
            : null,
        sortField: sortField.value,
        sortOrder: sortOrder.value,
      );

      if (res.success) {
        final data = res.data ?? {};
        final rawItems = data['list'] as List<dynamic>? ?? [];
        final items = rawItems
            .whereType<Map>()
            .map((e) => TimelinePhotoItem.fromJson(e.cast<String, dynamic>()))
            .toList();

        total.value = data['total'] as int? ?? 0;

        if (loadMore) {
          photoItems.addAll(items);
        } else {
          photoItems.assignAll(items);
        }

        hasMore.value = photoItems.length < total.value;
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        if (loadMore) {
          currentPage.value--;
        }
      }
    } catch (e) {
      ToastUtil.show('operation_failed'.tr);
      if (loadMore) {
        currentPage.value--;
      }
    } finally {
      isLoading.value = false;
    }
  }

  /// 刷新列表
  Future<void> refreshList() async {
    fetchTrashPhotos();
  }

  /// 切换排序字段
  void toggleSortField(String field) {
    if (sortField.value == field) {
      // 切换排序顺序
      sortOrder.value = sortOrder.value == 'asc' ? 'desc' : 'asc';
    } else {
      // 切换排序字段，默认倒序
      sortField.value = field;
      sortOrder.value = 'desc';
    }
    fetchTrashPhotos();
  }

  /// 切换文件类型过滤
  void changeFileType(String type) {
    fileType.value = type;
    fetchTrashPhotos();
  }

  /// 执行搜索
  void onSearch(String keyword) {
    searchKeyword.value = keyword;
    fetchTrashPhotos();
  }

  /// 清空搜索
  void clearSearch() {
    searchKeyword.value = '';
    searchController.clear();
    fetchTrashPhotos();
  }

  /// 搜索输入变化（带防抖）
  void onSearchChanged(String val) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      searchKeyword.value = val;
      fetchTrashPhotos();
    });
  }

  /// 切换排序顺序
  void toggleSortOrder() {
    sortOrder.value = sortOrder.value == 'asc' ? 'desc' : 'asc';
    fetchTrashPhotos();
  }
}
