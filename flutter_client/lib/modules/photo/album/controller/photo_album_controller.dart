import 'dart:async';

import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../../../utils/cache_manager.dart';
import '../models/photo_album_model.dart';
import '../service/photo_album_api_service.dart';

class PhotoAlbumController extends GetxController {
  PhotoAlbumController({String type = 'all'}) {
    typeFilter.value = type;
  }

  static const String keySortField = 'photo_album_sort_field';
  static const String keySortOrder = 'photo_album_sort_order';

  final PhotoAlbumApiService _api = PhotoAlbumApiService();

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxList<PhotoAlbumItem> items = <PhotoAlbumItem>[].obs;
  final RxInt page = 1.obs;
  final RxInt pageSize = 20.obs;
  final RxInt total = 0.obs;
  final RxString keyword = ''.obs;
  final RxString typeFilter = 'all'.obs;
  final RxString sortField = 'create_time'.obs;
  final RxString sortOrder = 'desc'.obs;

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Timer? _searchDebounce;

  final Rxn<PhotoAlbumItem> activeAlbum = Rxn<PhotoAlbumItem>();

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

  void setTypeFilter(String v) {
    if (typeFilter.value == v) return;
    typeFilter.value = v;
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
    hasMore.value = true;
    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    await loadAlbums(pageNumber: 1, append: false);
  }

  Future<void> loadAlbums({
    required int pageNumber,
    required bool append,
  }) async {
    if (isLoading.value) return;
    isLoading.value = true;
    try {
      final res = await _api.listAlbums(
        page: pageNumber,
        pageSize: pageSize.value,
        keyword: keyword.value,
        type: typeFilter.value,
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

  void openAlbum(PhotoAlbumItem album) {
    activeAlbum.value = album;
  }

  void closeAlbum() {
    activeAlbum.value = null;
  }

  Future<bool> createAlbum({
    required String name,
    required bool isPublic,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.createAlbum(name: trimmed, isPublic: isPublic);
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
    }
    return false;
  }

  Future<bool> updateAlbum({
    required int id,
    required String name,
    required bool isPublic,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.updateAlbum(
      id: id,
      name: trimmed,
      isPublic: isPublic,
    );
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
    }
    return false;
  }

  Future<bool> deleteAlbum(int id) async {
    final res = await _api.deleteAlbum(id);
    if (!res.success) return false;
    if (activeAlbum.value?.id == id) {
      activeAlbum.value = null;
    }
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
    }
    return false;
  }

  Future<PhotoAlbumDetail?> getAlbumDetail(int id) async {
    final res = await _api.getAlbum(id);
    if (!res.success) return null;
    return res.data;
  }

  Future<bool> updateAlbumShares({
    required int id,
    required List<Map<String, dynamic>> shares,
  }) async {
    final res = await _api.updateAlbum(id: id, shares: shares);
    if (res.success) {
      await refreshAlbums();
      return true;
    }
    if (res.message != null) {
      DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
    }
    return false;
  }

  Future<void> downloadAlbums(List<int> albumIds) async {
    final ids = albumIds.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handlePhotoDownload(
      albumType: 'album',
      ids: ids,
    );
  }
}
