import 'dart:async';

import 'package:NasCabOS/utils/dialog_util.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../utils/cache_manager.dart';
import '../models/photo_smart_album_model.dart';
import '../service/photo_smart_album_api_service.dart';

class PhotoSmartAlbumController extends GetxController {
  static const String keySortField = 'photo_smart_album_sort_field';
  static const String keySortOrder = 'photo_smart_album_sort_order';

  final PhotoSmartAlbumApiService _api = PhotoSmartAlbumApiService();

  final RxBool isLoading = false.obs;
  final RxBool hasMore = true.obs;
  final RxList<PhotoSmartAlbumItem> items = <PhotoSmartAlbumItem>[].obs;
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

  final Rxn<PhotoSmartAlbumItem> activeAlbum = Rxn<PhotoSmartAlbumItem>();

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
      final res = await _api.listSmartAlbums(
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

  void openAlbum(PhotoSmartAlbumItem album) {
    activeAlbum.value = album;
  }

  void closeAlbum() {
    activeAlbum.value = null;
  }

  Future<bool> createSmartAlbum({
    required String name,
    required String type,
    required Map<String, dynamic> filterContent,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.createSmartAlbum(
      name: trimmed,
      type: type,
      filterContent: filterContent,
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

  Future<bool> updateSmartAlbum({
    required int id,
    required String name,
    required String type,
    required Map<String, dynamic> filterContent,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final res = await _api.updateSmartAlbum(
      id: id,
      name: trimmed,
      type: type,
      filterContent: filterContent,
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
      DialogUtil.showInfoDialog(title: "tip".tr, content: res.message!);
    }
    return false;
  }

  Future<PhotoSmartAlbumDetail?> getSmartAlbumDetail(int id) async {
    final res = await _api.getSmartAlbum(id);
    if (!res.success) return null;
    return res.data;
  }

  static String? buildAlbumTooltipText(PhotoSmartAlbumItem album) {
    final type = album.type.trim();
    final filter = album.filterContent;
    if (filter.isEmpty) return null;

    if (type == 'smart_date') {
      final mode = (filter['mode'] ?? '').toString();
      if (mode == 'anniversary') {
        final repeat = (filter['repeat'] ?? 'year').toString();
        final day = (filter['day'] as num?)?.toInt();
        final month = (filter['month'] as num?)?.toInt();
        if (repeat == 'month') {
          if (day == null) return null;
          return 'smart_album_tooltip_every_month_day'.trParams({
            'day': day.toString(),
          });
        }
        if (day == null || month == null) return null;
        return 'smart_album_tooltip_every_year_month_day'.trParams({
          'month': month.toString(),
          'day': day.toString(),
        });
      }
      if (mode == 'fixed') {
        final op = (filter['operator'] ?? 'on').toString();
        final date = _formatDateText(filter['date']);
        if (date == null) return null;
        if (op == 'before') {
          return 'smart_album_tooltip_before_date'.trParams({'date': date});
        }
        if (op == 'after') {
          return 'smart_album_tooltip_after_date'.trParams({'date': date});
        }
        return 'smart_album_tooltip_on_date'.trParams({'date': date});
      }
      if (mode == 'range') {
        final start = _formatDateText(filter['start']);
        final end = _formatDateText(filter['end']);
        if (start == null || end == null) return null;
        return 'smart_album_tooltip_between_dates'.trParams({
          'start': start,
          'end': end,
        });
      }
      return null;
    }

    final logic = (filter['logic'] ?? 'and').toString().toLowerCase();
    final joiner = logic == 'or'
        ? 'smart_album_join_or'.tr
        : 'smart_album_join_and'.tr;
    final raw = filter['conditions'];
    if (raw is! List) return null;
    final parts = <String>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final field = (m['field'] ?? '').toString();
      final op = (m['operator'] ?? '').toString();
      final value = m['value'];
      final text = _formatConditionItem(
        field: field,
        operator: op,
        value: value,
      );
      if (text != null && text.trim().isNotEmpty) parts.add(text);
    }
    if (parts.isEmpty) return null;
    return parts.join(joiner);
  }

  String? buildAlbumTooltip(PhotoSmartAlbumItem album) =>
      PhotoSmartAlbumController.buildAlbumTooltipText(album);

  static String? _formatDateText(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return s;
    final y = int.tryParse(m.group(1)!);
    final mm = int.tryParse(m.group(2)!);
    final dd = int.tryParse(m.group(3)!);
    if (y == null || mm == null || dd == null) return s;
    String two(int n) => n.toString().padLeft(2, '0');
    return 'smart_album_date_format_ymd'.trParams({
      'year': y.toString(),
      'month': mm.toString(),
      'day': dd.toString(),
      'month2': two(mm),
      'day2': two(dd),
    });
  }

  static String _fieldLabel(String field) {
    switch (field.trim()) {
      case 'filename':
        return 'filename'.tr;
      case 'path':
        return 'path'.tr;
      case 'camera':
        return 'smart_album_field_camera'.tr;
      case 'size_mb':
        return 'size'.tr;
      case 'duration_min':
        return 'smart_album_field_duration'.tr;
      case 'width':
        return 'smart_album_field_width'.tr;
      case 'height':
        return 'smart_album_field_height'.tr;
      default:
        return field.trim();
    }
  }

  static String? _formatConditionItem({
    required String field,
    required String operator,
    required dynamic value,
  }) {
    final f = field.trim();
    if (f.isEmpty) return null;
    final op = operator.trim();
    if (op.isEmpty) return null;

    if (op == 'contains') {
      final s = value?.toString() ?? '';
      if (s.trim().isEmpty) return null;
      return 'smart_album_tooltip_contains'.trParams({
        'field': _fieldLabel(f),
        'value': s,
      });
    }

    if (op != 'gt' && op != 'eq' && op != 'lt') return null;
    final n = num.tryParse(value?.toString() ?? '');
    if (n == null) return null;

    final opText = switch (op) {
      'gt' => 'smart_album_cmp_gt'.tr,
      'lt' => 'smart_album_cmp_lt'.tr,
      _ => 'smart_album_cmp_eq'.tr,
    };

    final v = n % 1 == 0 ? n.toInt().toString() : n.toString();

    if (f == 'size_mb') {
      return 'smart_album_tooltip_compare'.trParams({
        'field': _fieldLabel(f),
        'op': opText,
        'value': v,
        'unit': 'smart_album_unit_mb'.tr,
      });
    }
    if (f == 'duration_min') {
      return 'smart_album_tooltip_compare'.trParams({
        'field': _fieldLabel(f),
        'op': opText,
        'value': v,
        'unit': 'smart_album_unit_min'.tr,
      });
    }

    return 'smart_album_tooltip_compare_no_unit'.trParams({
      'field': _fieldLabel(f),
      'op': opText,
      'value': v,
    });
  }
}
