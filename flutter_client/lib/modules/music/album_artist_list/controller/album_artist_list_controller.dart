import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/toast_util.dart';
import '../models/album_artist_list_models.dart';
import '../service/album_artist_list_api_service.dart';
import '../../list/models/music_list_models.dart';
import '../../list/service/music_list_api_service.dart';
import '../../playlist/service/play_list_api_service.dart';
import '../../playlist/view/play_list_list_view.dart';

enum AlbumArtistListSortBy { count, name }

enum AlbumArtistListSortOrder { asc, desc }

class AlbumArtistListController extends GetxController {
  final String keyType;
  final AlbumArtistListSortBy initialSortBy;
  final AlbumArtistListSortOrder initialSortOrder;

  AlbumArtistListController({
    required this.keyType,
    this.initialSortBy = AlbumArtistListSortBy.count,
    this.initialSortOrder = AlbumArtistListSortOrder.desc,
  });

  final RxList<AlbumArtistGroupItem> items = <AlbumArtistGroupItem>[].obs;
  final RxBool loading = false.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxBool autoLoadFailed = false.obs;

  final RxInt total = 0.obs;
  final RxString searchText = ''.obs;

  final RxList<MusicListPathItem> availablePaths = <MusicListPathItem>[].obs;
  final RxList<String> selectedPaths = <String>[].obs;

  final Rx<AlbumArtistListSortBy> sortBy = AlbumArtistListSortBy.count.obs;
  final Rx<AlbumArtistListSortOrder> sortOrder =
      AlbumArtistListSortOrder.desc.obs;

  int _page = 1;
  final int _pageSize = 30;
  Timer? _searchDebounce;

  Future<void> addToPlayList(AlbumArtistGroupItem group) async {
    final context = Get.context;
    if (context == null) return;
    final name = group.name.trim();
    if (name.isEmpty) return;
    try {
      final list = await showDialog<PlayListItem>(
        context: context,
        barrierDismissible: true,
        builder: (_) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
              child: const PlayListListView(selectionMode: true),
            ),
          );
        },
      );
      if (list == null) return;

      final ids = await _fetchAllIndexIds(group);
      if (ids.isEmpty) return;
      final res = await PlayListApiService.instance.addIndexes(
        listId: list.id,
        indexIds: ids,
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<List<int>> _fetchAllIndexIds(AlbumArtistGroupItem group) async {
    final name = group.name.trim();
    if (name.isEmpty) return const <int>[];
    final pageSize = 200;
    var page = 1;
    final ids = <int>{};

    while (true) {
      final res = await MusicListApiService.instance.listPaged(
        page: page,
        pageSize: pageSize,
        artists: group.isArtist ? [name] : null,
        albums: group.isAlbum ? [name] : null,
        sourceList: selectedPaths.isEmpty ? null : selectedPaths.toList(),
        showLoading: page == 1,
      );
      for (final item in res.items) {
        final id = item.id;
        if (id > 0) ids.add(id);
      }
      if (!res.pagination.hasNextPage) break;
      if (group.indexCount > 0 && ids.length >= group.indexCount) break;
      page += 1;
      if (page > 200) break;
    }

    final list = ids.toList()..sort();
    return list;
  }

  @override
  void onInit() {
    super.onInit();
    sortBy.value = initialSortBy;
    sortOrder.value = initialSortOrder;
    refreshList(showLoading: true);
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    super.onClose();
  }

  String get badgeLabel {
    final t = keyType.trim().toLowerCase();
    return t == 'artist'
        ? 'music_menu_library_artists'.tr
        : 'music_menu_library_albums'.tr;
  }

  void setSort(AlbumArtistListSortBy by, AlbumArtistListSortOrder order) {
    if (sortBy.value == by && sortOrder.value == order) return;
    sortBy.value = by;
    sortOrder.value = order;
    refreshList(showLoading: false);
  }

  void onSearchChanged(String v) {
    searchText.value = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      refreshList(showLoading: false);
    });
  }

  void setSearchImmediate(String v) {
    searchText.value = v;
    _searchDebounce?.cancel();
    refreshList(showLoading: false);
  }

  void clearSearch() {
    if (searchText.value.isEmpty) return;
    searchText.value = '';
    refreshList(showLoading: false);
  }

  Future<void> refreshList({bool showLoading = false}) async {
    loading.value = true;
    autoLoadFailed.value = false;
    try {
      _page = 1;
      final res = await AlbumArtistListApiService.instance.listPaged(
        keyType: keyType,
        page: _page,
        pageSize: _pageSize,
        search: searchText.value,
        sourceList: selectedPaths.isEmpty ? null : selectedPaths.toList(),
        sortBy: _toSortByParam(sortBy.value),
        sortOrder: _toSortOrderParam(sortOrder.value),
        showLoading: showLoading,
      );
      items.assignAll(res.items);
      total.value = res.pagination.total;
      hasMore.value = res.pagination.hasNextPage;
      availablePaths.assignAll(res.validPaths);
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadMore({required bool fromAuto}) async {
    if (loadingMore.value || loading.value) return;
    if (!hasMore.value) return;
    loadingMore.value = true;
    try {
      final nextPage = _page + 1;
      final res = await AlbumArtistListApiService.instance.listPaged(
        keyType: keyType,
        page: nextPage,
        pageSize: _pageSize,
        search: searchText.value,
        sourceList: selectedPaths.isEmpty ? null : selectedPaths.toList(),
        sortBy: _toSortByParam(sortBy.value),
        sortOrder: _toSortOrderParam(sortOrder.value),
        showLoading: false,
      );
      _page = nextPage;
      items.addAll(res.items);
      total.value = res.pagination.total;
      hasMore.value = res.pagination.hasNextPage;
      availablePaths.assignAll(res.validPaths);
      autoLoadFailed.value = false;
    } catch (_) {
      if (fromAuto) autoLoadFailed.value = true;
      rethrow;
    } finally {
      loadingMore.value = false;
    }
  }

  String _toSortByParam(AlbumArtistListSortBy by) {
    return by == AlbumArtistListSortBy.count ? 'count' : 'name';
  }

  String _toSortOrderParam(AlbumArtistListSortOrder order) {
    return order == AlbumArtistListSortOrder.asc ? 'asc' : 'desc';
  }
}
