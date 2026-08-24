import 'dart:async';

import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';
import '../models/video_collection_model.dart';
import '../service/video_collection_api_service.dart';

class VideoCollectionController extends GetxController {
  static const String keySortField = 'video_collection_sort_field';
  static const String keySortOrder = 'video_collection_sort_order';

  final VideoCollectionApiService _api = VideoCollectionApiService();

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxList<VideoCollectionItem> items = <VideoCollectionItem>[].obs;
  final RxInt page = 1.obs;
  final RxInt pageSize = 20.obs;
  final RxInt total = 0.obs;
  final RxString keyword = ''.obs;
  final RxString sortField = 'create_time'.obs;
  final RxString sortOrder = 'desc'.obs;

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Timer? _searchDebounce;

  final Rxn<VideoCollectionItem> activeCollection = Rxn<VideoCollectionItem>();

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    _loadSortSettings();
    refreshCollections();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.onClose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent - 200) {
      loadMore();
    }
  }

  void onSearchChanged(String val) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      keyword.value = val.trim();
      refreshCollections();
    });
  }

  void clearSearch() {
    keyword.value = '';
    searchController.clear();
    refreshCollections();
  }

  void setSort({required String field, required String order}) {
    if (sortField.value == field && sortOrder.value == order) return;
    sortField.value = field;
    sortOrder.value = order;
    _saveSortSettings();
    refreshCollections();
  }

  void _loadSortSettings() {
    final cachedField = CacheManager().getString(keySortField);
    final cachedOrder = CacheManager().getString(keySortOrder);

    if (cachedField == 'name' || cachedField == 'create_time') {
      sortField.value = cachedField!;
    }
    if (cachedOrder == 'asc' || cachedOrder == 'desc') {
      sortOrder.value = cachedOrder!;
    }
  }

  void _saveSortSettings() {
    CacheManager().setString(keySortField, sortField.value);
    CacheManager().setString(keySortOrder, sortOrder.value);
  }

  Future<void> refreshCollections() async {
    hasMore.value = true;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    await loadCollections(pageNumber: 1, append: false);
  }

  Future<void> loadCollections({
    required int pageNumber,
    required bool append,
  }) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listCollections(
        page: pageNumber,
        pageSize: pageSize.value,
        keyword: keyword.value,
        sortField: sortField.value,
        sortOrder: sortOrder.value,
      );
      if (!res.success || res.data == null) return;
      final data = res.data!;
      if (append) {
        final existingIds = items.map((e) => e.id).toSet();
        final next = data.items.where((e) => !existingIds.contains(e.id));
        items.addAll(next);
      } else {
        items.assignAll(data.items);
      }
      total.value = data.total;
      page.value = data.page;
      pageSize.value = data.pageSize;

      final size = pageSize.value <= 0 ? 20 : pageSize.value;
      final maxPage = total.value <= 0
          ? 1
          : ((total.value + size - 1) / size).floor();
      hasMore.value = page.value < maxPage;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value) return;
    if (!hasMore.value) return;
    await loadCollections(pageNumber: page.value + 1, append: true);
  }

  void openCollection(VideoCollectionItem collection) {
    activeCollection.value = collection;
  }

  void closeCollection() {
    activeCollection.value = null;
  }

  Future<bool> createCollection({
    required String name,
    required List<String> pathList,
  }) async {
    final trimmed = name.trim();
    final cleanedPaths = pathList
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (trimmed.isEmpty || cleanedPaths.isEmpty) return false;
    final res = await _api.createCollection(
      name: trimmed,
      pathList: cleanedPaths,
    );
    if (res.success) {
      await refreshCollections();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: 'tip'.tr, content: res.message!);
    }
    return false;
  }

  Future<bool> updateCollection({
    required int id,
    required String name,
    required List<String> pathList,
  }) async {
    final trimmed = name.trim();
    final cleanedPaths = pathList
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (trimmed.isEmpty || cleanedPaths.isEmpty) return false;
    final res = await _api.updateCollection(
      id: id,
      name: trimmed,
      pathList: cleanedPaths,
    );
    if (res.success) {
      await refreshCollections();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: 'tip'.tr, content: res.message!);
    }
    return false;
  }

  Future<bool> deleteCollection(int id) async {
    final res = await _api.deleteCollection(id);
    if (!res.success) return false;
    if (activeCollection.value?.id == id) {
      activeCollection.value = null;
    }
    if (res.success) {
      await refreshCollections();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: 'tip'.tr, content: res.message!);
    }
    return false;
  }
}
