import 'dart:async';
import 'package:NasCabOS/utils/device_utils.dart';
import 'package:flutter/material.dart';
import 'package:NasCabOS/core/user/current_user_controller.dart';
import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../utils/cache_manager.dart';
import '../../../../utils/dialog_util.dart';
import '../../book_list/service/book_custom_list_api_service.dart';
import '../../book_list/view/book_custom_list_list_view.dart';
import '../../../../utils/toast_util.dart';
import '../../favorite/service/book_favorite_api_service.dart';
import '../../../base/components/custom_checkbox.dart';
import '../../../transfer/controllers/download_controller.dart';
import '../../book_main/controller/book_main_controller.dart';
import '../../source_setting/view/book_source_settings_view.dart';
import '../service/book_list_api_service.dart';

enum BookListSortBy { viewTime, createTime, favoriteTime, name }

enum BookListSortOrder { asc, desc }

class BookSeriesOverlayPayload {
  final int seriesIndexId;
  final String title;

  const BookSeriesOverlayPayload({
    required this.seriesIndexId,
    required this.title,
  });
}

class BookSeriesOverlayController extends GetxController {
  final Rxn<BookSeriesOverlayPayload> active = Rxn<BookSeriesOverlayPayload>();

  void open({required int seriesIndexId, required String title}) {
    if (seriesIndexId <= 0) return;
    active.value = BookSeriesOverlayPayload(
      seriesIndexId: seriesIndexId,
      title: title,
    );
  }

  void openFromItem(BookListItem item) {
    final id = item.id;
    if (id <= 0) return;
    open(seriesIndexId: id, title: item.displayTitle);
  }

  void close() {
    active.value = null;
  }
}

class BookListController extends GetxController {
  static bool _globalSourceEmptyDialogShown = false;
  static const String _keyCoverScale = 'book_list_cover_scale';
  static double coverScaleMin = DeviceUtils.isMobile ? 0.9 : 0.7;
  static double coverScaleMax = DeviceUtils.isMobile ? 1.6 : 1.4;
  static const double coverScaleStep = 0.1;
  static final RxDouble sharedCoverScale = 1.0.obs;
  static bool _coverScaleLoaded = false;

  final String type;
  final bool isFavorite;
  final int? listId;
  final int? seriesIndexId;
  final int? collectionId;

  /// 未配置来源路径时是否提示管理员（仅图书/漫画/收藏「首页」列表应开启）。
  final bool alertWhenNoSourcePath;

  BookListController({
    required this.type,
    this.isFavorite = false,
    this.listId,
    this.seriesIndexId,
    this.collectionId,
    this.alertWhenNoSourcePath = false,
  });

  bool get isFavoriteList => isFavorite;
  bool get isInCustomList => (listId ?? 0) > 0;

  final RxList<BookListItem> items = <BookListItem>[].obs;
  final RxBool loading = false.obs;
  final RxBool firstLoaded = false.obs;
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;
  final RxBool autoLoadFailed = false.obs;
  final RxInt total = 0.obs;

  final RxString searchText = ''.obs;

  final RxList<BookListPathItem> availablePaths = <BookListPathItem>[].obs;
  final RxList<String> selectedPaths = <String>[].obs;
  List<BookListPathItem> _allAvailablePathsCache = <BookListPathItem>[];

  final Rx<BookListSortBy> sortBy = BookListSortBy.createTime.obs;
  final Rx<BookListSortOrder> sortOrder = BookListSortOrder.desc.obs;
  final RxDouble coverScale = sharedCoverScale;

  final RxBool isMultiSelectMode = false.obs;
  final RxSet<int> selectedItems = <int>{}.obs;
  final selectionRect = Rxn<Rect>();
  final selectionRectContent = Rxn<Rect>();
  Offset? _dragStartViewport;
  double _dragStartScrollOffset = 0;
  Set<int>? _dragSelectionBaseline;

  bool _sourceEmptyDialogShown = false;

  int _page = 1;
  final int _pageSize = 60;
  Timer? _searchDebounce;
  Worker? _selectedPathsWorker;
  bool _restoringSelectedPathsFromCache = false;

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

  void _openSourceSettings() {
    if (Get.isRegistered<BookMainController>()) {
      Get.find<BookMainController>().selectPage('settings.source');
      return;
    }
    if (DeviceUtils.isMobile) {
      Get.to(() => const BookSourceSettingsView());
    }
  }

  String get _sortCacheScope {
    if (seriesIndexId != null && seriesIndexId! > 0) {
      final t = type.isNotEmpty ? type : 'book';
      return 'series_$t';
    }
    if (isFavoriteList) return 'favorite';
    if ((listId ?? 0) > 0) return 'list_$listId';
    if ((collectionId ?? 0) > 0) return 'collection_$collectionId';
    if (type.isNotEmpty) return 'lib_$type';
    return 'lib_default';
  }

  String get _cacheKeySortBy =>
      '${CacheKeys.bookListSortByPrefix}$_sortCacheScope';
  String get _cacheKeySortOrder =>
      '${CacheKeys.bookListSortOrderPrefix}$_sortCacheScope';
  bool get _shouldUseSelectedPathsCache {
    if ((listId ?? 0) > 0) return false;
    if ((collectionId ?? 0) > 0) return false;
    if ((seriesIndexId ?? 0) > 0) return false;
    return true;
  }

  String get _cacheKeySelectedPaths =>
      '${CacheKeys.bookListSelectedPaths}_$_sortCacheScope';

  BookListSortBy? _parseSortBy(String? s) {
    switch (s) {
      case 'view_time':
        return BookListSortBy.viewTime;
      case 'create_time':
        return BookListSortBy.createTime;
      case 'favorite_time':
        return BookListSortBy.favoriteTime;
      case 'name':
        return BookListSortBy.name;
      default:
        return null;
    }
  }

  BookListSortOrder? _parseSortOrder(String? s) {
    if (s == 'asc') return BookListSortOrder.asc;
    if (s == 'desc') return BookListSortOrder.desc;
    return null;
  }

  void _applyInitialSortFromCache() {
    late BookListSortBy defBy;
    late BookListSortOrder defOrder;
    if (seriesIndexId != null && seriesIndexId! > 0) {
      defBy = BookListSortBy.name;
      defOrder = BookListSortOrder.asc;
    } else if (isFavoriteList) {
      defBy = BookListSortBy.favoriteTime;
      defOrder = BookListSortOrder.desc;
    } else {
      defBy = BookListSortBy.createTime;
      defOrder = BookListSortOrder.desc;
    }

    final cachedBy = CacheManager().getString(_cacheKeySortBy);
    final cachedOrder = CacheManager().getString(_cacheKeySortOrder);
    final parsedBy = _parseSortBy(cachedBy);
    final parsedOrder = _parseSortOrder(cachedOrder);
    if (parsedBy != null && parsedOrder != null) {
      sortBy.value = parsedBy;
      sortOrder.value = parsedOrder;
    } else {
      sortBy.value = defBy;
      sortOrder.value = defOrder;
    }
  }

  void _saveSortToCache() {
    CacheManager().setString(_cacheKeySortBy, _toSortByParam(sortBy.value));
    CacheManager().setString(
      _cacheKeySortOrder,
      _toSortOrderParam(sortOrder.value),
    );
  }

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

  static double normalizeCoverScale(double value) {
    final clamped = value.clamp(coverScaleMin, coverScaleMax);
    return (clamped * 100).roundToDouble() / 100;
  }

  static double loadStoredCoverScale() {
    try {
      final cached = CacheManager().getDouble(_keyCoverScale);
      if (cached == null || !cached.isFinite) return 1.0;
      return normalizeCoverScale(cached);
    } catch (_) {
      return 1.0;
    }
  }

  static void ensureSharedCoverScaleLoaded() {
    if (_coverScaleLoaded) return;
    sharedCoverScale.value = loadStoredCoverScale();
    _coverScaleLoaded = true;
  }

  void _saveCoverScale() {
    try {
      final normalized = normalizeCoverScale(coverScale.value);
      coverScale.value = normalized;
      CacheManager().setDouble(_keyCoverScale, normalized);
    } catch (_) {}
  }

  @override
  void onInit() {
    super.onInit();
    ensureSharedCoverScaleLoaded();
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
    _selectedPathsWorker?.dispose();
    super.onClose();
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

  bool get isAllCurrentSelected {
    final ids = items.map((e) => e.id).where((e) => e > 0).toList();
    if (ids.isEmpty) return false;
    return ids.every(selectedItems.contains);
  }

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

  void exitMultiSelectMode() {
    isMultiSelectMode.value = false;
    selectedItems.clear();
  }

  bool get isSelectedAllFavorited {
    final selected = items.where((e) => selectedItems.contains(e.id)).toList();
    if (selected.isEmpty) return false;
    return selected.every((e) => e.isFavorite);
  }

  Future<void> toggleFavoriteSelected() async {
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    final next = !isSelectedAllFavorited;
    final ok = await BookFavoriteApiService.instance.batchFavorite(ids, next);
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

  void openSeries(BookListItem item) {
    final overlay = Get.isRegistered<BookSeriesOverlayController>()
        ? Get.find<BookSeriesOverlayController>()
        : Get.put(BookSeriesOverlayController());
    overlay.openFromItem(item);
  }

  void closeSeries() {
    if (!Get.isRegistered<BookSeriesOverlayController>()) return;
    Get.find<BookSeriesOverlayController>().close();
  }

  Future<void> deleteItem(BookListItem item) async {
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

  Future<void> addToBookListSelected() async {
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    try {
      final context = Get.context;
      if (context == null) return;
      final list = await showDialog<BookCustomListItem>(
        context: context,
        barrierDismissible: true,
        builder: (_) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
              child: const BookCustomListListView(selectionMode: true),
            ),
          );
        },
      );
      if (list == null) return;

      final res = await BookCustomListApiService.instance.addIndexes(
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

  Future<void> addToBookListItem(BookListItem item) async {
    selectedItems
      ..clear()
      ..add(item.id);
    await addToBookListSelected();
  }

  Future<void> removeFromBookListSelected() async {
    if (!isInCustomList) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    try {
      final res = await BookCustomListApiService.instance.removeIndexes(
        listId: listId!,
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

  Future<void> removeFromBookListItem(BookListItem item) async {
    if (!isInCustomList) return;
    final id = item.id;
    if (id <= 0) return;
    try {
      final res = await BookCustomListApiService.instance.removeIndexes(
        listId: listId!,
        indexIds: [id],
      );
      if (res.success) {
        ToastUtil.show('operation_success'.tr);
        final before = items.length;
        items.removeWhere((e) => e.id == id);
        if (before != items.length) {
          total.value = (total.value - 1).clamp(0, 1 << 30);
        }
        _autoLoadMoreIfNeeded();
      } else {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    }
  }

  Future<void> unfavoriteSelected() async {
    if (!isFavoriteList) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    final ok = await BookFavoriteApiService.instance.batchFavorite(ids, false);
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

  Future<void> unfavoriteItem(BookListItem item) async {
    if (!isFavoriteList) return;
    final id = item.id;
    if (id <= 0) return;
    final ok = await BookFavoriteApiService.instance.removeFavorite(id);
    if (!ok) {
      ToastUtil.show('operation_failed'.tr);
      return;
    }
    ToastUtil.show('operation_success'.tr);
    updateFavoriteState(id, false);
  }

  Future<void> favoriteSelected() async {
    if (isFavoriteList) return;
    final ids = selectedItems.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return;
    final ok = await BookFavoriteApiService.instance.batchFavorite(ids, true);
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

  Future<void> downloadSelected() async {
    final paths =
        items
            .where((e) => selectedItems.contains(e.id))
            .map((e) => e.fullPath.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (paths.isEmpty) return;
    if (!Get.isRegistered<DownloadController>()) {
      Get.put(DownloadController(), permanent: true);
    }
    await Get.find<DownloadController>().handleDownload(paths);
    exitMultiSelectMode();
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
        final response = await BookListApiService.instance.listPaged(
          page: _page,
          pageSize: _pageSize,
          type: type,
          listId: listId,
          seriesIndexId: seriesIndexId,
          collectionId: collectionId,
          isFavorite: isFavorite,
          search: searchText.value.trim(),
          sourceList: selectedPaths.isEmpty ? null : selectedPaths.toList(),
          sortBy: _toSortByParam(sortBy.value),
          sortOrder: _toSortOrderParam(sortOrder.value),
          showLoading: effectiveShowLoading,
        );
        if (!response.success) {
          autoLoadFailed.value = true;
          return;
        }
        final res = response.data!;
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

      if (selectedPaths.isEmpty &&
          availablePaths.isEmpty &&
          CurrentUserController.instance.isAdmin) {
        if (alertWhenNoSourcePath &&
            !_sourceEmptyDialogShown &&
            !_globalSourceEmptyDialogShown) {
          _sourceEmptyDialogShown = true;
          _globalSourceEmptyDialogShown = true;
          DialogUtil.showInfoDialog(
            title: 'tip'.tr,
            content: 'path_no_set'.tr,
            buttonText: 'ok'.tr,
            onPressed: _openSourceSettings,
          );
        }
      } else {
        _sourceEmptyDialogShown = false;
        _globalSourceEmptyDialogShown = false;
      }
    } finally {
      loading.value = false;
      firstLoaded.value = true;
    }
  }

  Future<void> loadMore({bool fromAuto = false}) async {
    if (loadingMore.value || loading.value) return;
    if (!hasMore.value) return;
    if (fromAuto && autoLoadFailed.value) return;

    loadingMore.value = true;
    try {
      final nextPage = _page + 1;
      final response = await BookListApiService.instance.listPaged(
        page: nextPage,
        pageSize: _pageSize,
        type: type,
        listId: listId,
        seriesIndexId: seriesIndexId,
        collectionId: collectionId,
        isFavorite: isFavorite,
        search: searchText.value,
        sourceList: selectedPaths.isEmpty ? null : selectedPaths.toList(),
        sortBy: _toSortByParam(sortBy.value),
        sortOrder: _toSortOrderParam(sortOrder.value),
        showLoading: false,
      );
      if (!response.success) {
        autoLoadFailed.value = true;
        return;
      }
      final res = response.data!;
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

  void setSearchText(String v) {
    searchText.value = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
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
    _searchDebounce?.cancel();
    refreshList(showLoading: true);
  }

  void setSort(BookListSortBy by, BookListSortOrder order) {
    if (sortBy.value == by && sortOrder.value == order) return;
    sortBy.value = by;
    sortOrder.value = order;
    _saveSortToCache();
    refreshList(showLoading: true);
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

  void toggleSortOrder() {
    sortOrder.value = sortOrder.value == BookListSortOrder.asc
        ? BookListSortOrder.desc
        : BookListSortOrder.asc;
    _saveSortToCache();
    refreshList(showLoading: true);
  }

  void increaseCoverScale() {
    coverScale.value = normalizeCoverScale(coverScale.value + coverScaleStep);
    _saveCoverScale();
  }

  void decreaseCoverScale() {
    coverScale.value = normalizeCoverScale(coverScale.value - coverScaleStep);
    _saveCoverScale();
  }

  String _toSortByParam(BookListSortBy v) {
    switch (v) {
      case BookListSortBy.viewTime:
        return 'view_time';
      case BookListSortBy.createTime:
        return 'create_time';
      case BookListSortBy.favoriteTime:
        return 'favorite_time';
      case BookListSortBy.name:
        return 'name';
    }
  }

  String _toSortOrderParam(BookListSortOrder v) =>
      v == BookListSortOrder.asc ? 'asc' : 'desc';

  _BookDeleteTargets _resolveDeleteTargets(List<BookListItem> items) {
    final ids = <int>{};
    final pathSet = <String>{};
    for (final item in items) {
      final p = item.fullPath.trim();
      if (p.isEmpty) continue;
      pathSet.add(p);
      final id = item.id;
      if (id > 0) ids.add(id);
    }
    final paths = pathSet.toList()..sort();
    return _BookDeleteTargets(paths: paths, ids: ids);
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
      final res = await BookListApiService.instance.deleteEntries(
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
}

class _BookDeleteTargets {
  final List<String> paths;
  final Set<int> ids;
  const _BookDeleteTargets({required this.paths, required this.ids});

  bool get isEmpty => paths.isEmpty;
}
