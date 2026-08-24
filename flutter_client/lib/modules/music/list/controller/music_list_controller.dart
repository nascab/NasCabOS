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
import '../../playlist/service/play_list_api_service.dart';
import '../../playlist/view/play_list_list_view.dart';
import '../models/music_list_models.dart';
import '../service/music_list_api_service.dart';
import 'music_multi_select_controller.dart';

enum MusicListSortBy {
  title,
  artist,
  album,
  year,
  duration,
  ctime,
  mtime,
  favoriteTime,
}

enum MusicListSortOrder { asc, desc }

class MusicListController extends GetxController
    implements MusicMultiSelectController {
  final String listType;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;
  final bool isFavorite;
  final MusicListSortBy initialSortBy;
  final MusicListSortOrder initialSortOrder;
  MusicListController({
    this.listType = '',
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.isFavorite = false,
    this.initialSortBy = MusicListSortBy.mtime,
    this.initialSortOrder = MusicListSortOrder.desc,
  });

  bool get isFavoriteList => isFavorite;

  final RxList<MusicListItem> items = <MusicListItem>[].obs;
  final RxBool loading = false.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxBool autoLoadFailed = false.obs;

  final RxInt total = 0.obs;

  final RxString searchText = ''.obs;

  final RxBool isMultiSelectMode = false.obs;
  @override
  final RxSet<int> selectedItems = <int>{}.obs;
  final selectionRect = Rxn<Rect>();
  final selectionRectContent = Rxn<Rect>();
  Offset? _dragStartViewport;
  double _dragStartScrollOffset = 0;
  Set<int>? _dragSelectionBaseline;

  final RxList<String> artists = <String>[].obs;
  final RxList<String> albums = <String>[].obs;
  final RxList<String> genres = <String>[].obs;

  final RxList<String> availableArtists = <String>[].obs;
  final RxList<String> availableAlbums = <String>[].obs;
  final RxList<String> availableGenres = <String>[].obs;

  final RxList<MusicListPathItem> availablePaths = <MusicListPathItem>[].obs;
  final RxList<String> selectedPaths = <String>[].obs;
  List<MusicListPathItem> _allAvailablePathsCache = <MusicListPathItem>[];

  final Rx<MusicListSortBy> sortBy = MusicListSortBy.mtime.obs;
  final Rx<MusicListSortOrder> sortOrder = MusicListSortOrder.desc.obs;

  int get activeFilterCount => artists.length + albums.length + genres.length;

  int _page = 1;
  final int _pageSize = 300;
  Timer? _searchDebounce;
  final RxBool isScrolling = false.obs;
  Timer? _scrollEndDebounce;

  String get _sortCacheScope {
    if (seriesIndexId != null && seriesIndexId! > 0) {
      final t = listType.isNotEmpty ? listType : 'all';
      return 'series_$t';
    }
    if (isFavoriteList) return 'favorite';
    if ((listId ?? 0) > 0) return 'list_$listId';
    if ((collectionId ?? 0) > 0) return 'collection_$collectionId';
    if (listType.isNotEmpty) return 'lib_$listType';
    return 'lib_all';
  }

  String get _cacheKeySortBy =>
      '${CacheKeys.musicListSortByPrefix}$_sortCacheScope';
  String get _cacheKeySortOrder =>
      '${CacheKeys.musicListSortOrderPrefix}$_sortCacheScope';
  bool get _shouldUseSelectedPathsCache {
    if ((listId ?? 0) > 0) return false;
    if ((collectionId ?? 0) > 0) return false;
    if ((seriesIndexId ?? 0) > 0) return false;
    return true;
  }

  String get _cacheKeySelectedPaths => CacheKeys.musicListSelectedPaths;

  MusicListSortBy? _parseSortBy(String? s) {
    switch (s) {
      case 'title':
        return MusicListSortBy.title;
      case 'artist':
        return MusicListSortBy.artist;
      case 'album':
        return MusicListSortBy.album;
      case 'year':
        return MusicListSortBy.year;
      case 'duration':
        return MusicListSortBy.duration;
      case 'ctime':
        return MusicListSortBy.ctime;
      case 'mtime':
        return MusicListSortBy.mtime;
      case 'favorite_time':
        return MusicListSortBy.favoriteTime;
      default:
        return null;
    }
  }

  MusicListSortOrder? _parseSortOrder(String? s) {
    if (s == 'asc') return MusicListSortOrder.asc;
    if (s == 'desc') return MusicListSortOrder.desc;
    return null;
  }

  void _applyInitialSortFromCache() {
    final cachedBy = CacheManager().getString(_cacheKeySortBy);
    final cachedOrder = CacheManager().getString(_cacheKeySortOrder);
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
    CacheManager().setString(_cacheKeySortBy, _toSortByParam(sortBy.value));
    CacheManager().setString(
      _cacheKeySortOrder,
      _toSortOrderParam(sortOrder.value),
    );
  }

  Worker? _selectedPathsWorker;
  bool _restoringSelectedPathsFromCache = false;

  void _loadSelectedPathsFromCache() {
    if (!_shouldUseSelectedPathsCache) return;
    _restoringSelectedPathsFromCache = true;
    try {
      final cached = CacheManager().getStringList(_cacheKeySelectedPaths);
      if (cached == null || cached.isEmpty) return;
      final cleaned =
          cached
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (cleaned.isEmpty) return;
      selectedPaths.assignAll(cleaned);
    } finally {
      _restoringSelectedPathsFromCache = false;
    }
  }

  void _saveSelectedPathsToCache() {
    if (!_shouldUseSelectedPathsCache) return;
    final cleaned =
        selectedPaths
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (cleaned.isEmpty) {
      CacheManager().remove(_cacheKeySelectedPaths);
      return;
    }
    CacheManager().setStringList(_cacheKeySelectedPaths, cleaned);
  }

  bool _reconcileSelectedPathsWithAvailablePaths() {
    if (!_shouldUseSelectedPathsCache) return false;
    if (selectedPaths.isEmpty) return false;
    if (availablePaths.isEmpty) return false;
    final availableSet =
        availablePaths
            .map((e) => e.path.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
    if (availableSet.isEmpty) return false;

    final currentSet =
        selectedPaths
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet();
    final next =
        currentSet.where(availableSet.contains).toSet().toList(growable: false)
          ..sort();
    if (currentSet.length == next.length && currentSet.containsAll(next)) {
      return false;
    }
    if (next.isEmpty) {
      selectedPaths.clear();
    } else {
      selectedPaths.assignAll(next);
    }
    return true;
  }

  @override
  void onInit() {
    super.onInit();
    _applyInitialSortFromCache();
    _loadSelectedPathsFromCache();
    if (_shouldUseSelectedPathsCache) {
      _selectedPathsWorker = ever<List<String>>(selectedPaths, (_) {
        if (_restoringSelectedPathsFromCache) return;
        _saveSelectedPathsToCache();
      });
    }
    refreshList(showLoading: true);
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    _scrollEndDebounce?.cancel();
    _selectedPathsWorker?.dispose();
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

  void startDragSelection(Offset start, {double scrollOffset = 0}) {
    _dragStartViewport = start;
    _dragStartScrollOffset = scrollOffset;
    _dragSelectionBaseline = selectedItems.toSet();
    selectionRect.value = Rect.fromLTWH(start.dx, start.dy, 0, 0);
    selectionRectContent.value = Rect.fromLTWH(
      start.dx,
      start.dy + scrollOffset,
      0,
      0,
    );
  }

  void updateDragSelection(Offset current, {double scrollOffset = 0}) {
    final s = _dragStartViewport;
    if (s == null) return;
    final left = s.dx < current.dx ? s.dx : current.dx;
    final top = s.dy < current.dy ? s.dy : current.dy;
    final width = (s.dx - current.dx).abs();
    final height = (s.dy - current.dy).abs();
    selectionRect.value = Rect.fromLTWH(left, top, width, height);

    final startContentY = s.dy + _dragStartScrollOffset;
    final currentContentY = current.dy + scrollOffset;
    final topContent = startContentY < currentContentY ? startContentY : currentContentY;
    final heightContent = (startContentY - currentContentY).abs();
    selectionRectContent.value = Rect.fromLTWH(
      left,
      topContent,
      width,
      heightContent,
    );
  }

  void updateDragPreview(Set<int> hitIds, {required bool additive}) {
    final baseline = _dragSelectionBaseline ?? selectedItems.toSet();
    final next = additive ? (baseline.toSet()..addAll(hitIds)) : hitIds;
    selectedItems
      ..clear()
      ..addAll(next);
    selectedItems.refresh();
  }

  void applyDragSelection(
    Set<int> hitIds, {
    required bool multiModeAtStart,
    required bool additive,
  }) {
    final baseline = _dragSelectionBaseline ?? selectedItems.toSet();
    final next = additive ? (baseline.toSet()..addAll(hitIds)) : hitIds;
    selectedItems
      ..clear()
      ..addAll(next);
    selectedItems.refresh();
    if (next.isNotEmpty) {
      if (!isMultiSelectMode.value) isMultiSelectMode.value = true;
    }
    if (next.isEmpty && !multiModeAtStart) {
      isMultiSelectMode.value = false;
    }
  }

  void finishDragSelection() {
    selectionRect.value = null;
    selectionRectContent.value = null;
    _dragStartViewport = null;
    _dragStartScrollOffset = 0;
    _dragSelectionBaseline = null;
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

  Future<void> favoriteSelected() async {
    if (isFavoriteList) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    final ok = await MusicFavoriteApiService.instance.batchFavorite(ids, true);
    if (!ok) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    for (final id in ids) {
      updateFavoriteState(id, true);
    }
    ToastUtil.show('operation_success'.tr);
    exitMultiSelectMode();
  }

  Future<void> unfavoriteSelected() async {
    if (!isFavoriteList) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    final ok = await MusicFavoriteApiService.instance.batchFavorite(ids, false);
    if (!ok) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    for (final id in ids) {
      updateFavoriteState(id, false);
    }
    ToastUtil.show('operation_success'.tr);
    exitMultiSelectMode();
  }

  @override
  bool get isInPlayList => (listId ?? 0) > 0;

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
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<void> removeFromPlayListItem(MusicListItem item) async {
    final currentListId = listId ?? 0;
    final indexId = item.id;
    if (currentListId <= 0 || indexId <= 0) return;
    try {
      final res = await PlayListApiService.instance.removeIndexes(
        listId: currentListId,
        indexIds: [indexId],
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
        final before = items.length;
        items.removeWhere((e) => e.id == indexId);
        if (before != items.length) {
          total.value = (total.value - 1).clamp(0, 1 << 30);
        }
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

  Future<void> downloadItem(MusicListItem item) async {
    final paths = _resolveDownloadTargets([item]);
    if (paths.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(paths);
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

  Future<void> refreshList({bool showLoading = false}) async {
    if (loading.value) return;
    loading.value = true;
    autoLoadFailed.value = false;
    try {
      var effectiveShowLoading = showLoading;
      var didReconcile = false;
      for (var pass = 0; pass < 2; pass++) {
        _page = 1;
        final res = await MusicListApiService.instance.listPaged(
          page: _page,
          pageSize: _pageSize,
          listType: listType,
          listId: listId,
          seriesIndexId: seriesIndexId,
          collectionId: collectionId,
          isFavorite: isFavoriteList,
          search: searchText.value,
          sourceList: selectedPaths.isEmpty ? null : selectedPaths.toList(),
          sortBy: _toSortByParam(sortBy.value),
          sortOrder: _toSortOrderParam(sortOrder.value),
          showLoading: effectiveShowLoading,
        );
        items.assignAll(res.items);
        total.value = res.pagination.total;
        hasMore.value = res.pagination.hasNextPage;
        if (selectedPaths.isEmpty) {
          _allAvailablePathsCache = res.validPaths;
          availablePaths.assignAll(res.validPaths);
        } else if (_allAvailablePathsCache.isNotEmpty) {
          availablePaths.assignAll(_allAvailablePathsCache);
        } else {
          availablePaths.assignAll(res.validPaths);
        }
        final changed = _reconcileSelectedPathsWithAvailablePaths();
        if (!changed || didReconcile) break;
        didReconcile = true;
        effectiveShowLoading = false;
      }
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
        isFavorite: isFavoriteList,
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
      autoLoadFailed.value = false;
    } catch (_) {
      autoLoadFailed.value = true;
      rethrow;
    } finally {
      loadingMore.value = false;
    }
  }

  MusicListPagingQuery buildPagingQuery() {
    final artistsParam = artists.isEmpty ? null : artists.toList();
    final albumsParam = albums.isEmpty ? null : albums.toList();
    final genresParam = genres.isEmpty ? null : genres.toList();
    final sourcesParam = selectedPaths.isEmpty
        ? null
        : selectedPaths.toList(growable: false);
    return MusicListPagingQuery(
      page: _page,
      pageSize: _pageSize,
      hasMore: hasMore.value,
      listType: listType,
      listId: listId,
      seriesIndexId: seriesIndexId,
      collectionId: collectionId,
      isFavorite: isFavoriteList,
      search: searchText.value,
      artists: artistsParam,
      albums: albumsParam,
      genres: genresParam,
      sourceList: sourcesParam,
      sortBy: _toSortByParam(sortBy.value),
      sortOrder: _toSortOrderParam(sortOrder.value),
    );
  }

  void setSort(MusicListSortBy by, MusicListSortOrder order) {
    if (sortBy.value == by && sortOrder.value == order) return;
    sortBy.value = by;
    sortOrder.value = order;
    _saveSortToCache();
    refreshList(showLoading: true);
  }

  void toggleArtist(String value) {
    if (artists.contains(value)) {
      artists.remove(value);
    } else {
      artists.add(value);
    }
    refreshList(showLoading: true);
  }

  void toggleAlbum(String value) {
    if (albums.contains(value)) {
      albums.remove(value);
    } else {
      albums.add(value);
    }
    refreshList(showLoading: true);
  }

  void toggleGenre(String value) {
    if (genres.contains(value)) {
      genres.remove(value);
    } else {
      genres.add(value);
    }
    refreshList(showLoading: true);
  }

  void resetFilter() {
    artists.clear();
    albums.clear();
    genres.clear();
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

  List<String> _resolveDownloadTargets(List<MusicListItem> list) {
    final out = <String>{};
    for (final item in list) {
      final full = item.fullPath.trim();
      final base = item.path.trim();
      final name = item.filename.trim();
      final resolved = full.isNotEmpty
          ? full
          : (base.isNotEmpty && name.isNotEmpty ? '$base/$name' : '');
      if (resolved.isNotEmpty) out.add(resolved);
    }
    final paths = out.toList()..sort();
    return paths;
  }

  _MusicDeleteTargets _resolveDeleteTargets(List<MusicListItem> list) {
    final ids = <int>{};
    final pathSet = <String>{};
    for (final item in list) {
      final full = item.fullPath.trim();
      final base = item.path.trim();
      final name = item.filename.trim();
      final resolved = full.isNotEmpty
          ? full
          : (base.isNotEmpty && name.isNotEmpty ? '$base/$name' : '');
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
    return true;
  }

  String _toSortByParam(MusicListSortBy by) {
    switch (by) {
      case MusicListSortBy.title:
        return 'title';
      case MusicListSortBy.artist:
        return 'artist';
      case MusicListSortBy.album:
        return 'album';
      case MusicListSortBy.year:
        return 'year';
      case MusicListSortBy.duration:
        return 'duration';
      case MusicListSortBy.ctime:
        return 'ctime';
      case MusicListSortBy.mtime:
        return 'mtime';
      case MusicListSortBy.favoriteTime:
        return 'favorite_time';
    }
  }

  String _toSortOrderParam(MusicListSortOrder order) {
    return order == MusicListSortOrder.asc ? 'asc' : 'desc';
  }

  void updateFavoriteState(int indexId, bool nextIsFavorite) {
    final id = indexId;
    if (id <= 0) return;

    if (isFavoriteList && !nextIsFavorite) {
      items.removeWhere((e) => e.id == id);
      total.value = (total.value - 1).clamp(0, 1 << 30);
      return;
    }

    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    items[i] = items[i].copyWith(isFavorite: nextIsFavorite);
  }
}

class _MusicDeleteTargets {
  final List<String> paths;
  final Set<int> ids;
  const _MusicDeleteTargets({required this.paths, required this.ids});

  bool get isEmpty => paths.isEmpty;
}
