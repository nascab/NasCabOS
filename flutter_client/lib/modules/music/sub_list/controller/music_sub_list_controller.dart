import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../favorite/service/music_favorite_api_service.dart';
import '../../list/controller/music_multi_select_controller.dart';
import '../../list/models/music_list_models.dart';
import '../../list/service/music_list_api_service.dart';
import '../../play_service/controller/music_play_service_controller.dart';
import '../../playlist/service/play_list_api_service.dart';
import '../../playlist/view/play_list_list_view.dart';

enum MusicSubListSortBy {
  filename,
  title,
  artist,
  album,
  year,
  duration,
  ctime,
  mtime,
  favoriteTime,
}

enum MusicSubListSortOrder { asc, desc }

class MusicSubListPayload {
  final String keyType; // 'album' | 'artist'
  final String name;
  final int? seriesIndexId;
  const MusicSubListPayload({
    required this.keyType,
    required this.name,
    this.seriesIndexId,
  });
}

class MusicSubListOverlayController extends GetxController {
  final Rxn<MusicSubListPayload> active = Rxn<MusicSubListPayload>();
  void open({
    required String keyType,
    required String name,
    int? seriesIndexId,
  }) {
    if (name.trim().isEmpty) return;
    active.value = MusicSubListPayload(
      keyType: keyType.trim(),
      name: name.trim(),
      seriesIndexId: seriesIndexId,
    );
  }

  void openFromGroupItem(String keyType, String name) {
    open(keyType: keyType, name: name);
  }

  void close() {
    if (active.value == null) return;
    active.value = null;
  }
}

class MusicSubListController extends GetxController
    implements MusicMultiSelectController {
  final String keyType;
  final String name;
  final bool isFavorite;
  final bool isHistory;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;
  final String? listType;
  final MusicSubListSortBy initialSortBy;
  final MusicSubListSortOrder initialSortOrder;

  MusicSubListController({
    required this.keyType,
    required this.name,
    this.isFavorite = false,
    this.isHistory = false,
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.listType,
    this.initialSortBy = MusicSubListSortBy.filename,
    this.initialSortOrder = MusicSubListSortOrder.asc,
  });

  final RxList<MusicListItem> items = <MusicListItem>[].obs;
  final RxBool loading = false.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxBool autoLoadFailed = false.obs;
  final RxInt total = 0.obs;
  final RxBool isMultiSelectMode = false.obs;
  @override
  final RxSet<int> selectedItems = <int>{}.obs;

  final Rx<MusicSubListSortBy> sortBy = MusicSubListSortBy.filename.obs;
  final Rx<MusicSubListSortOrder> sortOrder = MusicSubListSortOrder.asc.obs;
  final RxString searchText = ''.obs;

  int _page = 1;
  final int _pageSize = 300;
  final RxBool isScrolling = false.obs;
  Timer? _scrollEndDebounce;
  Timer? _searchDebounce;

  MusicSubListSortBy? _parseSortBy(String? s) {
    switch (s) {
      case 'filename':
        return MusicSubListSortBy.filename;
      case 'title':
        return MusicSubListSortBy.title;
      case 'artist':
        return MusicSubListSortBy.artist;
      case 'album':
        return MusicSubListSortBy.album;
      case 'year':
        return MusicSubListSortBy.year;
      case 'duration':
        return MusicSubListSortBy.duration;
      case 'ctime':
        return MusicSubListSortBy.ctime;
      case 'mtime':
        return MusicSubListSortBy.mtime;
      case 'favorite_time':
        return MusicSubListSortBy.favoriteTime;
      default:
        return null;
    }
  }

  MusicSubListSortOrder? _parseSortOrder(String? s) {
    if (s == 'asc') return MusicSubListSortOrder.asc;
    if (s == 'desc') return MusicSubListSortOrder.desc;
    return null;
  }

  void _applyInitialSortFromCache() {
    final cachedBy = CacheManager().getString(CacheKeys.musicSubListSortBy);
    final cachedOrder = CacheManager().getString(CacheKeys.musicSubListSortOrder);
    final parsedBy = _parseSortBy(cachedBy);
    final parsedOrder = _parseSortOrder(cachedOrder);
    if (parsedBy != null && parsedOrder != null) {
      sortBy.value = parsedBy;
      sortOrder.value = parsedOrder;
    } else {
      sortBy.value = initialSortBy;
      sortOrder.value = initialSortOrder;
    }
  }

  void _saveSortToCache() {
    CacheManager().setString(
      CacheKeys.musicSubListSortBy,
      _toSortByParam(sortBy.value),
    );
    CacheManager().setString(
      CacheKeys.musicSubListSortOrder,
      _toSortOrderParam(sortOrder.value),
    );
  }

  @override
  void onInit() {
    super.onInit();
    _applyInitialSortFromCache();
    refreshList(showLoading: true);
  }

  @override
  void onClose() {
    _scrollEndDebounce?.cancel();
    _searchDebounce?.cancel();
    super.onClose();
  }

  void markScrolling() {
    if (!isScrolling.value) {
      isScrolling.value = true;
    }
    _scrollEndDebounce?.cancel();
    _scrollEndDebounce = Timer(const Duration(milliseconds: 120), () {
      isScrolling.value = false;
    });
  }

  String get headerCoverPath {
    if (items.isEmpty) return '';
    final first = items.first;
    final full = first.fullPath.trim();
    final base = first.path.trim();
    final name = first.filename.trim();
    final resolved = full.isNotEmpty
        ? full
        : (base.isNotEmpty && name.isNotEmpty ? '$base/$name' : '');
    return resolved;
  }

  String get headerCoverUrl {
    if (items.isEmpty) return '';
    if (items.first.hasInnerCover != 1) return '';
    final p = headerCoverPath;
    if (p.isEmpty) return '';
    return ApiController.instance.getMusicCoverUrl(filePath: p, size: 500);
  }

  void playAll({int initialIndex = 0}) {
    if (items.isEmpty) return;
    final idx = initialIndex.clamp(0, items.length - 1);
    final startItem = items[idx];
    final artistsParam = !isHistory && keyType.trim().toLowerCase() == 'artist'
        ? [name]
        : null;
    final albumsParam = !isHistory && keyType.trim().toLowerCase() == 'album'
        ? [name]
        : null;
    MusicPlayServiceController.instance.playFromList(
      items: items.toList(growable: false),
      startItem: startItem,
      paging: MusicPlaylistPaging.fromQuery(
        MusicListPagingQuery(
          page: _page,
          pageSize: _pageSize,
          hasMore: hasMore.value,
          listType: listType,
          listId: listId,
          seriesIndexId: seriesIndexId,
          collectionId: collectionId,
          isFavorite: isFavorite,
          isHistory: isHistory,
          search: searchText.value,
          artists: artistsParam,
          albums: albumsParam,
          sortBy: _toSortByParam(sortBy.value),
          sortOrder: _toSortOrderParam(sortOrder.value),
        ),
      ),
    );
  }

  void playAt(int index) {
    playAll(initialIndex: index);
  }

  void toggleMultiSelectMode() {
    isMultiSelectMode.value = !isMultiSelectMode.value;
    if (!isMultiSelectMode.value) {
      selectedItems.clear();
    }
  }

  void toggleSelection(int id) {
    if (id <= 0) return;
    if (selectedItems.contains(id)) {
      selectedItems.remove(id);
    } else {
      selectedItems.add(id);
    }
    if (selectedItems.isNotEmpty && !isMultiSelectMode.value) {
      isMultiSelectMode.value = true;
    }
    if (selectedItems.isEmpty) {
      exitMultiSelectMode();
    }
  }

  @override
  bool get isAllCurrentSelected {
    final ids = items.map((e) => e.id).where((e) => e > 0).toList();
    if (ids.isEmpty) return false;
    return ids.every(selectedItems.contains);
  }

  @override
  void toggleSelectAllCurrent() {
    final ids = items.map((e) => e.id).where((e) => e > 0).toList();
    if (ids.isEmpty) return;
    if (isAllCurrentSelected) {
      selectedItems.removeAll(ids);
      exitMultiSelectMode();
      return;
    }
    selectedItems.addAll(ids);
    if (!isMultiSelectMode.value && selectedItems.isNotEmpty) {
      isMultiSelectMode.value = true;
    }
  }

  @override
  void exitMultiSelectMode() {
    isMultiSelectMode.value = false;
    selectedItems.clear();
  }

  @override
  bool get isSelectedAllFavorited {
    final selected = items.where((e) => selectedItems.contains(e.id)).toList();
    if (selected.isEmpty) return false;
    return selected.every((e) => e.isFavorite);
  }

  void setSort(MusicSubListSortBy by, MusicSubListSortOrder order) {
    if (sortBy.value == by && sortOrder.value == order) return;
    sortBy.value = by;
    sortOrder.value = order;
    _saveSortToCache();
    refreshList(showLoading: true);
  }

  void onSearchChanged(String v) {
    searchText.value = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      refreshList(showLoading: false);
    });
  }

  void setSearchImmediate(String v) {
    searchText.value = v;
    _searchDebounce?.cancel();
    refreshList(showLoading: false);
  }

  void clearSearch() {
    searchText.value = '';
    refreshList(showLoading: false);
  }

  Future<void> refreshList({bool showLoading = false}) async {
    loading.value = true;
    autoLoadFailed.value = false;
    try {
      _page = 1;
      final res = await MusicListApiService.instance.listPaged(
        page: _page,
        pageSize: _pageSize,
        listType: listType,
        listId: listId,
        seriesIndexId: seriesIndexId,
        collectionId: collectionId,
        isFavorite: isFavorite,
        isHistory: isHistory,
        search: searchText.value,
        artists: !isHistory && keyType.trim().toLowerCase() == 'artist'
            ? [name]
            : null,
        albums: !isHistory && keyType.trim().toLowerCase() == 'album'
            ? [name]
            : null,
        sortBy: _toSortByParam(sortBy.value),
        sortOrder: _toSortOrderParam(sortOrder.value),
        showLoading: showLoading,
      );
      items.assignAll(res.items);
      total.value = res.pagination.total;
      hasMore.value = res.pagination.hasNextPage;
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadMore({bool fromAuto = false}) async {
    if (loadingMore.value || loading.value) return;
    if (!hasMore.value) return;
    if (fromAuto && autoLoadFailed.value) return;
    loadingMore.value = true;
    try {
      final nextPage = _page + 1;
      final res = await MusicListApiService.instance.listPaged(
        page: nextPage,
        pageSize: _pageSize,
        listType: listType,
        listId: listId,
        seriesIndexId: seriesIndexId,
        collectionId: collectionId,
        isFavorite: isFavorite,
        isHistory: isHistory,
        search: searchText.value,
        artists: !isHistory && keyType.trim().toLowerCase() == 'artist'
            ? [name]
            : null,
        albums: !isHistory && keyType.trim().toLowerCase() == 'album'
            ? [name]
            : null,
        sortBy: _toSortByParam(sortBy.value),
        sortOrder: _toSortOrderParam(sortOrder.value),
        showLoading: false,
      );
      _page = nextPage;
      items.addAll(res.items);
      total.value = res.pagination.total;
      hasMore.value = res.pagination.hasNextPage;
      autoLoadFailed.value = false;
    } catch (_) {
      autoLoadFailed.value = true;
      rethrow;
    } finally {
      loadingMore.value = false;
    }
  }

  Future<void> downloadAll() async {
    if (items.isEmpty) return;
    final paths = _resolveDownloadTargets(items);
    if (paths.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(paths);
  }

  Future<void> downloadItem(MusicListItem item) async {
    final paths = _resolveDownloadTargets([item]);
    if (paths.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(paths);
  }

  Future<void> toggleFavorite(MusicListItem item) async {
    final id = item.id;
    if (id <= 0) return;
    final next = !item.isFavorite;
    final ok = next
        ? await MusicFavoriteApiService.instance.addFavorite(id)
        : await MusicFavoriteApiService.instance.removeFavorite(id);
    if (!ok) return;
    updateFavoriteState(id, next);
  }

  @override
  Future<void> toggleFavoriteSelected() async {
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    final next = !isSelectedAllFavorited;
    final ok = await MusicFavoriteApiService.instance.batchFavorite(ids, next);
    if (!ok) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    for (final id in ids) {
      updateFavoriteState(id, next);
    }
    ToastUtil.show('operation_success'.tr);
    exitMultiSelectMode();
  }

  void updateFavoriteState(int indexId, bool nextIsFavorite) {
    final id = indexId;
    if (id <= 0) return;

    if (isFavorite && !nextIsFavorite) {
      items.removeWhere((e) => e.id == id);
      total.value = (total.value - 1).clamp(0, 1 << 30);
      return;
    }

    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    items[i] = items[i].copyWith(isFavorite: nextIsFavorite);
    items.refresh();
  }

  @override
  bool get isInPlayList => (listId ?? 0) > 0;

  void _autoLoadMoreIfNeeded() {
    if (!hasMore.value) return;
    if (loading.value || loadingMore.value) return;
    if (items.length >= _pageSize) return;
    Future.microtask(() {
      if (!hasMore.value) return;
      if (loading.value || loadingMore.value) return;
      if (items.length >= _pageSize) return;
      loadMore(fromAuto: false).catchError((_) {});
    });
  }

  Future<void> removeFromPlayListItem(MusicListItem item) async {
    final currentListId = listId ?? 0;
    if (currentListId <= 0) return;
    final indexId = item.id;
    if (indexId <= 0) return;
    try {
      final res = await PlayListApiService.instance.removeIndexes(
        listId: currentListId,
        indexIds: [indexId],
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
        final before = items.length;
        items.removeWhere((e) => e.id == indexId);
        final removed = before - items.length;
        if (removed > 0) {
          total.value = (total.value - removed).clamp(0, 1 << 30);
        }
        _autoLoadMoreIfNeeded();
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  @override
  Future<void> removeFromPlayListSelected() async {
    final currentListId = listId ?? 0;
    if (currentListId <= 0) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    try {
      final res = await PlayListApiService.instance.removeIndexes(
        listId: currentListId,
        indexIds: ids,
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
        final before = items.length;
        items.removeWhere((e) => ids.contains(e.id));
        final removed = before - items.length;
        if (removed > 0) {
          total.value = (total.value - removed).clamp(0, 1 << 30);
        }
        exitMultiSelectMode();
        _autoLoadMoreIfNeeded();
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  @override
  Future<void> addToPlayListSelected() async {
    final context = Get.context;
    if (context == null) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
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
      final res = await PlayListApiService.instance.addIndexes(
        listId: list.id,
        indexIds: ids,
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
        exitMultiSelectMode();
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<void> addToPlayListItem(MusicListItem item) async {
    final indexId = item.id;
    if (indexId <= 0) return;
    final context = Get.context;
    if (context == null) return;
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
      final res = await PlayListApiService.instance.addIndexes(
        listId: list.id,
        indexIds: [indexId],
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

  List<String> _resolveDownloadTargets(List<MusicListItem> list) {
    final out = <String>{};
    for (final item in list) {
      final resolved = _resolveFilePath(item);
      if (resolved.isNotEmpty) out.add(resolved);
    }
    final paths = out.toList()..sort();
    return paths;
  }

  String _resolveFilePath(MusicListItem item) {
    final full = item.fullPath.trim();
    final base = item.path.trim();
    final name = item.filename.trim();
    final resolved = full.isNotEmpty
        ? full
        : (base.isNotEmpty && name.isNotEmpty ? '$base/$name' : '');
    return resolved;
  }

  @override
  Future<void> downloadSelected() async {
    final paths = _resolveDownloadTargets(
      items.where((e) => selectedItems.contains(e.id)).toList(),
    );
    if (paths.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(paths);
    exitMultiSelectMode();
  }

  _MusicDeleteTargets _resolveDeleteTargets(List<MusicListItem> list) {
    final ids = <int>{};
    final pathSet = <String>{};
    for (final item in list) {
      final resolved = _resolveFilePath(item);
      if (resolved.isEmpty) continue;
      pathSet.add(resolved);
      final id = item.id;
      if (id > 0) ids.add(id);
    }
    final paths = pathSet.toList()..sort();
    return _MusicDeleteTargets(paths: paths, ids: ids);
  }

  Future<bool?> _showDeleteConfirmDialog(List<String> paths) async {
    final context = Get.context;
    if (context == null) return null;
    if (paths.isEmpty) return null;
    final count = paths.length;
    final content = count <= 5
        ? [
            'book_delete_confirm_list'.tr,
            ...paths.map(
              (p) => 'book_delete_confirm_path_line'.trParams({'path': p}),
            ),
          ].join('\n')
        : 'book_delete_confirm_count'.trParams({'count': '$count'});
    final isShellSupported = ApiController.instance.state.shellSupported;
    bool recycle = isShellSupported;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DialogUtil.createAlertDialog(
              title: Text('need_confirm'.tr),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(content),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CustomCheckbox(
                        value: recycle,
                        onChanged: isShellSupported
                            ? (v) => setState(() => recycle = v ?? false)
                            : null,
                        isCircle: false,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'put_in_recycle_bin'.tr,
                        style: TextStyle(
                          color: isShellSupported
                              ? null
                              : Theme.of(context).textTheme.bodyMedium?.color
                                    ?.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('cancel'.tr),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(recycle),
                  child: Text('ok'.tr),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _deletePathsAndRemoveItems({
    required List<String> paths,
    required Set<int> removeIds,
    required bool recycle,
  }) async {
    if (paths.isEmpty) return false;
    try {
      final res = await MusicListApiService.instance.deleteEntries(
        paths,
        recycle: recycle,
      );
      if (!res.success) {
        DialogUtil.showErrorDialog(
          title: 'error'.tr,
          message: res.message ?? 'operation_failed'.tr,
        );
        return false;
      }
    } catch (_) {
      DialogUtil.showErrorDialog(
        title: 'error'.tr,
        message: 'operation_failed'.tr,
      );
      return false;
    }
    if (removeIds.isNotEmpty) {
      items.removeWhere((e) => removeIds.contains(e.id));
      total.value = (total.value - removeIds.length).clamp(0, 1 << 30);
    }
    ToastUtil.show('delete_success'.tr);
    _autoLoadMoreIfNeeded();
    return true;
  }

  @override
  Future<void> deleteSelected() async {
    final selected = items.where((e) => selectedItems.contains(e.id)).toList();
    final targets = _resolveDeleteTargets(selected);
    if (targets.isEmpty) return;
    final recycle = await _showDeleteConfirmDialog(targets.paths);
    if (recycle == null) return;
    final ok = await _deletePathsAndRemoveItems(
      paths: targets.paths,
      removeIds: targets.ids,
      recycle: recycle,
    );
    if (ok) exitMultiSelectMode();
  }

  Future<void> deleteItem(MusicListItem item) async {
    final targets = _resolveDeleteTargets([item]);
    if (targets.isEmpty) return;
    final recycle = await _showDeleteConfirmDialog(targets.paths);
    if (recycle == null) return;
    await _deletePathsAndRemoveItems(
      paths: targets.paths,
      removeIds: targets.ids,
      recycle: recycle,
    );
  }

  String _toSortByParam(MusicSubListSortBy by) {
    switch (by) {
      case MusicSubListSortBy.filename:
        return 'filename';
      case MusicSubListSortBy.title:
        return 'title';
      case MusicSubListSortBy.artist:
        return 'artist';
      case MusicSubListSortBy.album:
        return 'album';
      case MusicSubListSortBy.year:
        return 'year';
      case MusicSubListSortBy.duration:
        return 'duration';
      case MusicSubListSortBy.ctime:
        return 'ctime';
      case MusicSubListSortBy.mtime:
        return 'mtime';
      case MusicSubListSortBy.favoriteTime:
        return 'favorite_time';
    }
  }

  String _toSortOrderParam(MusicSubListSortOrder order) {
    return order == MusicSubListSortOrder.asc ? 'asc' : 'desc';
  }
}

class _MusicDeleteTargets {
  final List<String> paths;
  final Set<int> ids;
  const _MusicDeleteTargets({required this.paths, required this.ids});

  bool get isEmpty => paths.isEmpty;
}
