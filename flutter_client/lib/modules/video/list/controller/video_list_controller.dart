import 'dart:async';
import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';
import '../../base/beans/video_item_bean.dart';
import '../../base/services/video_item_sync_service.dart';
import '../service/video_list_api_service.dart';
import '../view/parts/video_list_sort_menu.dart';
import '../../../../utils/device_utils.dart';

enum VideoListSortBy { favoriteTime, viewTime, year, score, createTime, name }

enum VideoListSortOrder { asc, desc }

class VideoListYearGroup {
  final String label;
  final List<int> years;
  final bool single;
  const VideoListYearGroup({
    required this.label,
    required this.years,
    required this.single,
  });
}

class VideoListSourceFilterStorage {
  static const String _cacheKeyPrefix = 'video_list_selected_source_paths';
  final CacheManager _cacheManager = CacheManager();

  String _buildCacheKey({
    required String listType,
    required String mediaType,
  }) {
    final lt = listType.trim().isEmpty ? 'default' : listType.trim();
    final mt = mediaType.trim().isEmpty ? 'all' : mediaType.trim();
    return '${_cacheKeyPrefix}_${lt}_$mt';
  }

  Future<List<String>> restoreSelection({
    required String listType,
    required String mediaType,
    required Iterable<String> availablePaths,
  }) async {
    final cacheKey = _buildCacheKey(listType: listType, mediaType: mediaType);
    List<String> savedPaths;
    try {
      savedPaths = _normalizePaths(_cacheManager.getStringList(cacheKey));
    } catch (_) {
      return const <String>[];
    }
    if (savedPaths.isEmpty) {
      return const <String>[];
    }
    final availablePathSet = _normalizePaths(availablePaths).toSet();
    final restoredPaths = savedPaths
        .where(availablePathSet.contains)
        .toList(growable: false);
    if (_samePaths(savedPaths, restoredPaths)) {
      return restoredPaths;
    }
    await saveSelection(
      listType: listType,
      mediaType: mediaType,
      paths: restoredPaths,
    );
    return restoredPaths;
  }

  Future<void> saveSelection({
    required String listType,
    required String mediaType,
    required Iterable<String> paths,
  }) async {
    final cacheKey = _buildCacheKey(listType: listType, mediaType: mediaType);
    final normalizedPaths = _normalizePaths(paths);
    if (normalizedPaths.isEmpty) {
      try {
        await _cacheManager.remove(cacheKey);
      } catch (_) {}
      return;
    }
    try {
      await _cacheManager.setStringList(cacheKey, normalizedPaths);
    } catch (_) {}
  }

  List<String> _normalizePaths(Iterable<String>? paths) {
    if (paths == null) {
      return const <String>[];
    }
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawPath in paths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(path)) {
        continue;
      }
      normalized.add(path);
    }
    return normalized;
  }

  bool _samePaths(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

class VideoListController extends GetxController {
  static const String _keySortBy = 'video_list_sort_by';
  static const String _keySortOrder = 'video_list_sort_order';
  static const String _keyPosterScale = 'video_list_poster_scale';
  static double posterScaleMin = DeviceUtils.isMobile ? 0.9 : 0.7;
  static double posterScaleMax = DeviceUtils.isMobile ? 1.6 : 1.4;
  static const double posterScaleStep = 0.1;
  static final RxDouble sharedPosterScale = 1.0.obs;
  static bool _posterScaleLoaded = false;

  final String initialMediaType;
  final String listType;
  final int? albumId;
  final int? collectionId;
  final int? smartAlbumId;
  final List<String> initialGenres;
  final List<String> initialRegions;
  final List<String> initialActors;
  final List<String> initialDirectors;
  VideoListController({
    required this.initialMediaType,
    this.listType = '',
    this.albumId,
    this.collectionId,
    this.smartAlbumId,
    this.initialGenres = const <String>[],
    this.initialRegions = const <String>[],
    this.initialActors = const <String>[],
    this.initialDirectors = const <String>[],
  });

  bool get isFavoriteList => listType.trim().toLowerCase() == 'favorite';
  bool get isAlbumList => (albumId ?? 0) > 0;

  // 当前列表数据
  final RxList<VideoHomeItemBean> items = <VideoHomeItemBean>[].obs;
  // 首屏加载状态
  final RxBool loading = false.obs;
  // 分页加载状态
  final RxBool loadingMore = false.obs;
  // 是否还有更多页
  final RxBool hasMore = true.obs;
  // 自动加载失败时，显示“加载更多”按钮兜底
  final RxBool autoLoadFailed = false.obs;

  // 后端返回的总数（用于UI展示可选）
  final RxInt total = 0.obs;

  // 当前媒体类型：movie / tv
  final RxString mediaType = ''.obs;
  // 搜索关键字（nfo_name / filename）
  final RxString searchText = ''.obs;
  // 筛选：genres / region（后端使用索引表 video_index2key 精确匹配）
  final RxList<String> genres = <String>[].obs;
  final RxList<String> regions = <String>[].obs;
  final RxList<String> actors = <String>[].obs;
  final RxList<String> directors = <String>[].obs;
  final RxList<int> selectedYears = <int>[].obs;

  final RxList<String> availableGenres = <String>[].obs;
  final RxList<String> availableRegions = <String>[].obs;
  final RxList<int> availableYears = <int>[].obs;
  final RxList<int> baseAvailableYears = <int>[].obs;

  final RxList<VideoListPathItem> availablePaths = <VideoListPathItem>[].obs;
  final RxList<String> selectedPaths = <String>[].obs;
  final VideoListSourceFilterStorage _sourceFilterStorage =
      VideoListSourceFilterStorage();

  final Rx<VideoListSortBy> sortBy = VideoListSortBy.viewTime.obs;
  final Rx<VideoListSortOrder> sortOrder = VideoListSortOrder.desc.obs;
  final RxDouble posterScale = sharedPosterScale;

  bool get hasActiveFilters =>
      genres.isNotEmpty ||
      regions.isNotEmpty ||
      actors.isNotEmpty ||
      directors.isNotEmpty ||
      selectedYears.isNotEmpty;

  int get selectedYearGroupCount {
    if (selectedYears.isEmpty) return 0;
    final groups = getYearGroups();
    if (groups.isEmpty) return 1;
    final selected = selectedYears.toSet();
    final selectedGroupCount = groups.where((g) {
      if (g.single) {
        return selected.length == 1 && selected.contains(g.years.first);
      }
      return g.years.every(selected.contains);
    }).length;
    return selectedGroupCount > 0 ? selectedGroupCount : 1;
  }

  int get activeFilterCount =>
      genres.length +
      regions.length +
      actors.length +
      directors.length +
      selectedYearGroupCount;

  bool get hasCustomSort {
    final defaultBy = isFavoriteList
        ? VideoListSortBy.favoriteTime
        : VideoListSortBy.createTime;
    return sortBy.value != defaultBy ||
        sortOrder.value != VideoListSortOrder.desc;
  }

  int _page = 1;
  final int _pageSize = 30;
  Timer? _searchDebounce;
  StreamSubscription<int>? _deletedSubscription;

  /// 排序持久化仅按 [listType] 区分；空字符串与多种入口共用 `default` 键。
  String _sortStorageSuffix() {
    final t = listType.trim();
    return t.isEmpty ? 'default' : t;
  }

  static double normalizePosterScale(double value) {
    final clamped = value.clamp(posterScaleMin, posterScaleMax);
    return (clamped * 100).roundToDouble() / 100;
  }

  static void ensureSharedPosterScaleLoaded() {
    if (_posterScaleLoaded) return;
    sharedPosterScale.value = loadStoredPosterScale();
    _posterScaleLoaded = true;
  }

  static double loadStoredPosterScale() {
    try {
      final cached = CacheManager().getDouble(_keyPosterScale);
      if (cached == null || !cached.isFinite) return 1.0;
      return normalizePosterScale(cached);
    } catch (_) {
      return 1.0;
    }
  }

  VideoListSortBy? _parseSortBy(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    switch (t) {
      case 'favorite_time':
        return VideoListSortBy.favoriteTime;
      case 'view_time':
        return VideoListSortBy.viewTime;
      case 'year':
        return VideoListSortBy.year;
      case 'score':
        return VideoListSortBy.score;
      case 'create_time':
        return VideoListSortBy.createTime;
      case 'name':
        return VideoListSortBy.name;
      default:
        return null;
    }
  }

  VideoListSortOrder? _parseSortOrder(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    switch (t) {
      case 'asc':
        return VideoListSortOrder.asc;
      case 'desc':
        return VideoListSortOrder.desc;
      default:
        return null;
    }
  }

  void _loadSortSettings() {
    try {
      final suf = _sortStorageSuffix();
      final byStr = CacheManager().getString('${_keySortBy}_$suf');
      final orderStr = CacheManager().getString('${_keySortOrder}_$suf');
      // 缺一半、空串、脏数据：一律不应用，保持 onInit 已设的默认排序
      if (byStr == null ||
          orderStr == null ||
          byStr.trim().isEmpty ||
          orderStr.trim().isEmpty) {
        return;
      }
      final by = _parseSortBy(byStr);
      final order = _parseSortOrder(orderStr);
      if (by == null || order == null) return;
      if (!videoListSortPairMatchesMenu(this, by, order)) return;
      sortBy.value = by;
      sortOrder.value = order;
    } catch (_) {}
  }

  void _saveSortSettings() {
    try {
      final suf = _sortStorageSuffix();
      CacheManager().setString(
        '${_keySortBy}_$suf',
        _toSortByParam(sortBy.value),
      );
      CacheManager().setString(
        '${_keySortOrder}_$suf',
        _toSortOrderParam(sortOrder.value),
      );
    } catch (_) {}
  }

  void _loadPosterScale() {
    ensureSharedPosterScaleLoaded();
  }

  void _savePosterScale() {
    try {
      final normalized = normalizePosterScale(posterScale.value);
      posterScale.value = normalized;
      CacheManager().setDouble(_keyPosterScale, normalized);
    } catch (_) {}
  }

  @override
  void onInit() {
    super.onInit();
    _deletedSubscription = VideoItemSyncService.deletedStream.listen(
      _handleExternalDelete,
    );
    mediaType.value = initialMediaType;
    if (isFavoriteList) {
      sortBy.value = VideoListSortBy.favoriteTime;
      sortOrder.value = VideoListSortOrder.desc;
    }
    _loadSortSettings();
    _loadPosterScale();
    genres.assignAll(
      initialGenres.map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
    regions.assignAll(
      initialRegions.map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
    actors.assignAll(
      initialActors.map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
    directors.assignAll(
      initialDirectors.map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
    refreshList(showLoading: true);
  }

  @override
  void onClose() {
    _deletedSubscription?.cancel();
    _searchDebounce?.cancel();
    super.onClose();
  }

  void _handleExternalDelete(int indexId) {
    if (indexId <= 0) return;
    final before = items.length;
    items.removeWhere((e) => e.id == indexId);
    final removed = before - items.length;
    if (removed > 0) {
      total.value = (total.value - removed).clamp(0, 1 << 30);
    }
  }

  Future<void> refreshList({bool showLoading = false}) async {
    final requestedSelectedPaths = selectedPaths.toList(growable: false);
    loading.value = true;
    autoLoadFailed.value = false;
    try {
      _page = 1;
      final effectiveMediaType = initialMediaType.trim().isNotEmpty
          ? initialMediaType.trim()
          : mediaType.value.trim();
      final res = await VideoListApiService.instance.listPaged(
        page: _page,
        pageSize: _pageSize,
        listType: listType,
        mediaType: effectiveMediaType,
        albumId: albumId,
        collectionId: collectionId,
        smartAlbumId: smartAlbumId,
        search: searchText.value,
        genres: genres.toList(),
        regions: regions.toList(),
        actors: actors.toList(),
        directors: directors.toList(),
        years: selectedYears.toList(),
        sourceList:
            requestedSelectedPaths.isEmpty ? null : requestedSelectedPaths,
        sortBy: _toSortByParam(sortBy.value),
        sortOrder: _toSortOrderParam(sortOrder.value),
        showLoading: showLoading,
      );
      items.assignAll(res.items);
      total.value = res.pagination.total;
      hasMore.value = res.pagination.hasNextPage;
      availablePaths.assignAll(res.validPaths);
      final didRestoreSelectedPaths = await _restoreSelectedPaths(
        effectiveMediaType: effectiveMediaType,
        availablePathItems: res.validPaths,
      );
      if (
        didRestoreSelectedPaths &&
        !_sameSelectedPaths(requestedSelectedPaths, selectedPaths)
      ) {
        await refreshList(showLoading: false);
        return;
      }
      final filters = res.filters;
      if (filters != null) {
        availableGenres.assignAll(filters.genres);
        availableRegions.assignAll(filters.regions);
        availableYears.assignAll(filters.years);
        if (selectedYears.isEmpty) {
          baseAvailableYears.assignAll(filters.years);
        }
      }
    } finally {
      loading.value = false;
    }
  }

  bool _sameSelectedPaths(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  Future<bool> _restoreSelectedPaths({
    required String effectiveMediaType,
    required List<VideoListPathItem> availablePathItems,
  }) async {
    final restoredPaths = await _sourceFilterStorage.restoreSelection(
      listType: listType,
      mediaType: effectiveMediaType,
      availablePaths: availablePathItems.map((e) => e.path),
    );
    if (_sameSelectedPaths(selectedPaths, restoredPaths)) {
      return false;
    }
    selectedPaths.assignAll(restoredPaths);
    return true;
  }

  Future<void> setSourcePathSelected(
    String path,
    bool isSelected, {
    bool showLoading = false,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }
    final nextSelectedPaths = selectedPaths.toList(growable: true);
    final hasSelected = nextSelectedPaths.contains(normalizedPath);
    if (isSelected) {
      if (hasSelected) {
        return;
      }
      nextSelectedPaths.add(normalizedPath);
    } else {
      if (!hasSelected) {
        return;
      }
      nextSelectedPaths.remove(normalizedPath);
    }
    selectedPaths.assignAll(nextSelectedPaths);
    final effectiveMediaType = initialMediaType.trim().isNotEmpty
        ? initialMediaType.trim()
        : mediaType.value.trim();
    await _sourceFilterStorage.saveSelection(
      listType: listType,
      mediaType: effectiveMediaType,
      paths: selectedPaths,
    );
    await refreshList(showLoading: showLoading);
  }

  Future<void> clearSourcePathSelection({
    bool refresh = true,
    bool showLoading = false,
  }) async {
    selectedPaths.clear();
    final effectiveMediaType = initialMediaType.trim().isNotEmpty
        ? initialMediaType.trim()
        : mediaType.value.trim();
    await _sourceFilterStorage.saveSelection(
      listType: listType,
      mediaType: effectiveMediaType,
      paths: const <String>[],
    );
    if (refresh) {
      await refreshList(showLoading: showLoading);
    }
  }

  Future<void> loadMore({bool fromAuto = false}) async {
    if (loadingMore.value || loading.value) return;
    if (!hasMore.value) return;
    if (fromAuto && autoLoadFailed.value) return;

    loadingMore.value = true;
    try {
      final nextPage = _page + 1;
      final effectiveMediaType = initialMediaType.trim().isNotEmpty
          ? initialMediaType.trim()
          : mediaType.value.trim();
      final res = await VideoListApiService.instance.listPaged(
        page: nextPage,
        pageSize: _pageSize,
        listType: listType,
        mediaType: effectiveMediaType,
        albumId: albumId,
        collectionId: collectionId,
        smartAlbumId: smartAlbumId,
        search: searchText.value,
        genres: genres.toList(),
        regions: regions.toList(),
        actors: actors.toList(),
        directors: directors.toList(),
        years: selectedYears.toList(),
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

  void setMediaType(String type) {
    if (mediaType.value == type) return;
    mediaType.value = type;
    refreshList(showLoading: true);
  }

  void updateFavoriteState(int indexId, bool isFavorite) {
    final id = indexId;
    if (id <= 0) return;

    if (listType.trim().toLowerCase() == 'favorite' && !isFavorite) {
      items.removeWhere((e) => e.id == id);
      total.value = (total.value - 1).clamp(0, 1 << 30);
      return;
    }

    final i = items.indexWhere((e) => e.id == id);
    if (i == -1) return;
    items[i] = items[i].copyWith(isFavorite: isFavorite);
  }

  void removeFromCurrentAlbumState(int indexId) {
    if (!isAlbumList) return;
    final id = indexId;
    if (id <= 0) return;
    items.removeWhere((e) => e.id == id);
    total.value = (total.value - 1).clamp(0, 1 << 30);
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
    refreshList(showLoading: false);
  }

  void toggleGenre(String g) {
    final v = g.trim();
    if (v.isEmpty) return;
    if (genres.contains(v)) {
      genres.remove(v);
    } else {
      genres.add(v);
    }
    refreshList(showLoading: true);
  }

  void toggleRegion(String r) {
    final v = r.trim();
    if (v.isEmpty) return;
    if (regions.contains(v)) {
      regions.remove(v);
    } else {
      regions.add(v);
    }
    refreshList(showLoading: true);
  }

  void toggleYear(int year) {
    final y = year;
    if (y <= 0) return;
    if (selectedYears.length == 1 && selectedYears.first == y) {
      selectedYears.clear();
    } else {
      selectedYears.assignAll(<int>[y]);
    }
    refreshList(showLoading: true);
  }

  void toggleYearGroup(List<int> years) {
    final ys = years.where((e) => e > 0).toSet().toList(growable: false)
      ..sort((a, b) => b.compareTo(a));
    if (ys.isEmpty) return;
    final selected = selectedYears.toSet();
    final isSameSelection =
        selectedYears.length == ys.length && ys.every(selected.contains);
    if (isSameSelection) {
      selectedYears.clear();
    } else {
      selectedYears.assignAll(ys);
    }
    refreshList(showLoading: true);
  }

  void setYears(List<int> years) {
    selectedYears.assignAll(
      years.where((e) => e > 0).toSet().toList()
        ..sort((a, b) => b.compareTo(a)),
    );
    refreshList(showLoading: true);
  }

  List<VideoListYearGroup> getYearGroups() {
    final sourceYears = baseAvailableYears.isNotEmpty
        ? baseAvailableYears
        : availableYears;
    final years = sourceYears.where((e) => e > 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (years.isEmpty) return const <VideoListYearGroup>[];

    final latest = years.first;
    final groups = <VideoListYearGroup>[
      VideoListYearGroup(
        label: latest.toString(),
        years: <int>[latest],
        single: true,
      ),
    ];

    final latestDecade = (latest ~/ 10) * 10;
    final decadeWindowCount = 5;
    final minDecade = latestDecade - (decadeWindowCount - 1) * 10;

    for (var d = latestDecade; d >= minDecade; d -= 10) {
      final decadeYears = years
          .where((y) => y >= d && y < d + 10)
          .toList(growable: false);
      if (decadeYears.isEmpty) continue;
      if (d == latestDecade &&
          decadeYears.length == 1 &&
          decadeYears.first == latest) {
        continue;
      }
      groups.add(
        VideoListYearGroup(label: '${d}s', years: decadeYears, single: false),
      );
    }

    final olderYears = years
        .where((y) => y < minDecade)
        .toList(growable: false);
    if (olderYears.isNotEmpty) {
      groups.add(
        VideoListYearGroup(label: '更早', years: olderYears, single: false),
      );
    }
    return groups;
  }

  void resetFilter() {
    genres.clear();
    regions.clear();
    selectedYears.clear();
    refreshList(showLoading: true);
  }

  void setSort(VideoListSortBy by, VideoListSortOrder order) {
    sortBy.value = by;
    sortOrder.value = order;
    _saveSortSettings();
    refreshList(showLoading: true);
  }

  void increasePosterScale() {
    posterScale.value = normalizePosterScale(
      posterScale.value + posterScaleStep,
    );
    _savePosterScale();
  }

  void decreasePosterScale() {
    posterScale.value = normalizePosterScale(
      posterScale.value - posterScaleStep,
    );
    _savePosterScale();
  }

  String _toSortByParam(VideoListSortBy v) {
    switch (v) {
      case VideoListSortBy.favoriteTime:
        return 'favorite_time';
      case VideoListSortBy.viewTime:
        return 'view_time';
      case VideoListSortBy.year:
        return 'year';
      case VideoListSortBy.score:
        return 'score';
      case VideoListSortBy.createTime:
        return 'create_time';
      case VideoListSortBy.name:
        return 'name';
    }
  }

  String _toSortOrderParam(VideoListSortOrder v) {
    switch (v) {
      case VideoListSortOrder.asc:
        return 'asc';
      case VideoListSortOrder.desc:
        return 'desc';
    }
  }
}
