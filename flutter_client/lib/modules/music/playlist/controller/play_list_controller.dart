import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';
import '../service/play_list_api_service.dart';

class PlayListOverlayPayload {
  final int listId;
  final String name;

  const PlayListOverlayPayload({required this.listId, required this.name});
}

class PlayListOverlayController extends GetxController {
  final Rxn<PlayListOverlayPayload> active = Rxn<PlayListOverlayPayload>();

  void open({required int listId, required String name}) {
    if (listId <= 0) return;
    active.value = PlayListOverlayPayload(listId: listId, name: name);
  }

  void openFromItem(PlayListItem item) {
    open(listId: item.id, name: item.name);
  }

  void close() {
    active.value = null;
  }
}

class PlayListController extends GetxController {
  static const String keySortField = 'music_playlist_sort_field';
  static const String keySortOrder = 'music_playlist_sort_order';

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxList<PlayListItem> items = <PlayListItem>[].obs;
  final RxInt page = 1.obs;
  final RxInt pageSize = 30.obs;
  final RxInt total = 0.obs;

  final RxString keyword = ''.obs;
  final RxString sortBy = 'create_time'.obs;
  final RxString sortOrder = 'desc'.obs;

  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

  final PlayListApiService _api = PlayListApiService.instance;

  @override
  void onInit() {
    super.onInit();
    _loadSortSettings();
    refreshLists();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.onClose();
  }

  void onSearchChanged(String v) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      keyword.value = v.trim();
      refreshLists();
    });
  }

  void clearSearch() {
    keyword.value = '';
    searchController.clear();
    refreshLists();
  }

  void setSort({required String field, required String order}) {
    final nextField = field == 'name' || field == 'create_time'
        ? field
        : 'create_time';
    final nextOrder = order == 'asc' ? 'asc' : 'desc';
    if (sortBy.value == nextField && sortOrder.value == nextOrder) return;
    sortBy.value = nextField;
    sortOrder.value = nextOrder;
    _saveSortSettings();
    refreshLists();
  }

  void _loadSortSettings() {
    final cachedField = CacheManager().getString(keySortField);
    final cachedOrder = CacheManager().getString(keySortOrder);
    if (cachedField == 'name' || cachedField == 'create_time') {
      sortBy.value = cachedField!;
    }
    if (cachedOrder == 'asc' || cachedOrder == 'desc') {
      sortOrder.value = cachedOrder!;
    }
  }

  void _saveSortSettings() {
    CacheManager().setString(keySortField, sortBy.value);
    CacheManager().setString(keySortOrder, sortOrder.value);
  }

  Future<void> refreshLists() async {
    hasMore.value = true;
    await loadLists(pageNumber: 1, append: false);
  }

  Future<void> loadLists({
    required int pageNumber,
    required bool append,
  }) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listLists(
        page: pageNumber,
        pageSize: pageSize.value,
        search: keyword.value,
        sortBy: sortBy.value,
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
      total.value = data.pagination.total;
      page.value = data.pagination.page;
      pageSize.value = data.pagination.pageSize;
      hasMore.value = data.pagination.hasNextPage;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoading.value) return;
    if (!hasMore.value) return;
    await loadLists(pageNumber: page.value + 1, append: true);
  }

  void openList(PlayListItem list) {
    final overlay = Get.isRegistered<PlayListOverlayController>()
        ? Get.find<PlayListOverlayController>()
        : Get.put(PlayListOverlayController());
    overlay.openFromItem(list);
  }

  void closeList() {
    if (!Get.isRegistered<PlayListOverlayController>()) return;
    Get.find<PlayListOverlayController>().close();
  }

  Future<bool> createList(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.createList(name: trimmed);
    if (!res.success) return false;
    await refreshLists();
    return true;
  }

  /// 创建歌单并返回新建项（用于选择模式空列表时创建后直接选用）。
  Future<PlayListItem?> createListReturnItem(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final res = await _api.createList(name: trimmed);
    if (!res.success || res.data == null) return null;
    final item = res.data!;
    if (item.id <= 0) return null;
    await refreshLists();
    return item;
  }

  Future<bool> updateList({required int id, required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.updateList(id: id, name: trimmed);
    if (!res.success) return false;
    await refreshLists();
    return true;
  }

  Future<bool> deleteList(int id) async {
    final res = await _api.deleteList(id);
    if (!res.success) return false;
    if (Get.isRegistered<PlayListOverlayController>()) {
      final overlay = Get.find<PlayListOverlayController>();
      if (overlay.active.value?.listId == id) overlay.close();
    }
    await refreshLists();
    return true;
  }
}
