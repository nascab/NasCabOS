import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../models/video_smart_album_model.dart';
import '../service/video_smart_album_api_service.dart';
import '../utils/video_smart_album_tooltip_util.dart';

class VideoSmartAlbumController extends GetxController {
  static const String keySortField = 'video_smart_album_sort_field';
  static const String keySortOrder = 'video_smart_album_sort_order';

  final VideoSmartAlbumApiService _api = VideoSmartAlbumApiService.instance;

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxList<VideoSmartAlbumItem> items = <VideoSmartAlbumItem>[].obs;
  final RxInt page = 1.obs;
  final RxInt pageSize = 20.obs;
  final RxInt total = 0.obs;
  final RxString keyword = ''.obs;
  final RxString sortField = 'create_time'.obs;
  final RxString sortOrder = 'desc'.obs;

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Timer? _searchDebounce;

  final Rxn<VideoSmartAlbumItem> activeAlbum = Rxn<VideoSmartAlbumItem>();

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(_onScroll);
    _loadSortSettings();
    refreshAlbums();
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
      refreshAlbums();
    });
  }

  void clearSearch() {
    keyword.value = '';
    searchController.clear();
    refreshAlbums();
  }

  void setSort({required String field, required String order}) {
    if (sortField.value == field && sortOrder.value == order) return;
    sortField.value = field;
    sortOrder.value = order;
    _saveSortSettings();
    refreshAlbums();
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

  Future<void> refreshAlbums() async {
    await loadAlbums(pageNumber: 1, append: false);
  }

  Future<void> loadAlbums({
    required int pageNumber,
    required bool append,
  }) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listSmartAlbums(
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
    await loadAlbums(pageNumber: page.value + 1, append: true);
  }

  void openAlbum(VideoSmartAlbumItem album) {
    activeAlbum.value = album;
  }

  void closeAlbum() {
    activeAlbum.value = null;
  }

  Future<bool> createSmartAlbum({
    required String name,
    required Map<String, dynamic> filterContent,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.createSmartAlbum(
      name: trimmed,
      filterContent: filterContent,
    );
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: 'tip'.tr, content: res.message!);
    }
    return false;
  }

  Future<bool> updateSmartAlbum({
    required int id,
    required String name,
    required Map<String, dynamic> filterContent,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.updateSmartAlbum(
      id: id,
      name: trimmed,
      filterContent: filterContent,
    );
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: 'tip'.tr, content: res.message!);
    }
    return false;
  }

  Future<bool> deleteSmartAlbum(int id) async {
    final res = await _api.deleteSmartAlbum(id);
    if (!res.success) return false;
    if (activeAlbum.value?.id == id) {
      activeAlbum.value = null;
    }
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: 'tip'.tr, content: res.message!);
    }
    return false;
  }

  String? buildAlbumTooltip(VideoSmartAlbumItem album) {
    return VideoSmartAlbumTooltipUtil.buildTooltip(album.filterContent);
  }
}
