part of '../photo_trash_controller.dart';

// 基础状态和生命周期管理
extension PhotoTrashBase on PhotoTrashController {
  // 初始化
  void _initBase() {
    fetchTrashPhotos();
    scrollController.addListener(_onScroll);
  }

  // 清理
  void _disposeBase() {
    scrollController.dispose();
    searchController.dispose();
    _searchDebounce?.cancel();
  }

  // 滚动监听，用于分页加载
  void _onScroll() {
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200 &&
        hasMore.value &&
        !isLoading.value) {
      fetchTrashPhotos(loadMore: true);
    }
  }
}
