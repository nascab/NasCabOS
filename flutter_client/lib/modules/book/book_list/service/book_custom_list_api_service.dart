import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../list/service/book_list_api_service.dart';

class BookCustomListApiService extends BaseApiService {
  static BookCustomListApiService get instance =>
      Get.isRegistered<BookCustomListApiService>()
      ? Get.find<BookCustomListApiService>()
      : BookCustomListApiService();

  Future<ApiResponse<BookCustomListPagedResult>> listLists({
    int page = 1,
    int pageSize = 30,
    String? search,
    String sortBy = 'create_time',
    String sortOrder = 'desc',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/book_list/list',
      body: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
      },
      showLoading: false,
    );

    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(
      BookCustomListPagedResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<BookCustomListItem>> createList({required String name}) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/book_list/create',
      body: {'name': name.trim()},
      showLoading: true,
    ).then((res) {
      if (!res.success) {
        return ApiResponse.failure(
          res.message ?? 'network_failure',
          code: res.code,
          rawResponse: res.rawResponse,
        );
      }
      return ApiResponse.success(
        BookCustomListItem.fromJson(res.data ?? const <String, dynamic>{}),
        message: res.message,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    });
  }

  Future<ApiResponse<BookCustomListItem>> updateList({
    required int id,
    required String name,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/book_list/update',
      body: {'id': id, 'name': name.trim()},
      showLoading: true,
    ).then((res) {
      if (!res.success) {
        return ApiResponse.failure(
          res.message ?? 'network_failure',
          code: res.code,
          rawResponse: res.rawResponse,
        );
      }
      return ApiResponse.success(
        BookCustomListItem.fromJson(res.data ?? const <String, dynamic>{}),
        message: res.message,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    });
  }

  Future<ApiResponse<bool>> deleteList(int id) async {
    final res = await apiPost<dynamic>(
      '/api/book/book_list/delete',
      body: {'id': id},
      showLoading: true,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> addIndexes({
    required int listId,
    required List<int> indexIds,
  }) async {
    final ids = indexIds.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) {
      return ApiResponse.failure('network_failure');
    }
    final res = await apiPost<dynamic>(
      '/api/book/book_list/index/add',
      body: {'list_id': listId, 'index_ids': ids},
      showLoading: true,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> removeIndexes({
    required int listId,
    required List<int> indexIds,
  }) async {
    final ids = indexIds.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) {
      return ApiResponse.failure('network_failure');
    }
    final res = await apiPost<dynamic>(
      '/api/book/book_list/index/remove',
      body: {'list_id': listId, 'index_ids': ids},
      showLoading: true,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}

class BookCustomListItem {
  final int id;
  final int uid;
  final String name;
  final String createTime;
  final List<BookListItem> previews;

  const BookCustomListItem({
    required this.id,
    required this.uid,
    required this.name,
    required this.createTime,
    required this.previews,
  });

  factory BookCustomListItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    String parseString(dynamic v) => (v?.toString() ?? '').trim();

    final previewsRaw = json['previews'] is List
        ? (json['previews'] as List)
        : const <dynamic>[];
    final previews = previewsRaw
        .whereType<Map>()
        .map((e) => BookListItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    return BookCustomListItem(
      id: parseInt(json['id']),
      uid: parseInt(json['uid']),
      name: parseString(json['name']),
      createTime: parseString(json['create_time'] ?? json['createTime']),
      previews: previews,
    );
  }
}

class BookCustomListPagedResult {
  final List<BookCustomListItem> items;
  final BookCustomListPagination pagination;

  const BookCustomListPagedResult({
    required this.items,
    required this.pagination,
  });

  const BookCustomListPagedResult.empty()
    : items = const <BookCustomListItem>[],
      pagination = const BookCustomListPagination.empty();

  factory BookCustomListPagedResult.fromJson(Map<String, dynamic> json) {
    final listRaw = json['items'] is List
        ? (json['items'] as List)
        : const <dynamic>[];
    final items = listRaw
        .whereType<Map>()
        .map((e) => BookCustomListItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    final paginationRaw = json['pagination'] is Map
        ? (json['pagination'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return BookCustomListPagedResult(
      items: items,
      pagination: BookCustomListPagination.fromJson(paginationRaw),
    );
  }
}

class BookCustomListPagination {
  final int total;
  final int page;
  final int pageSize;

  const BookCustomListPagination({
    required this.total,
    required this.page,
    required this.pageSize,
  });

  const BookCustomListPagination.empty() : total = 0, page = 1, pageSize = 30;

  bool get hasNextPage {
    final size = pageSize <= 0 ? 30 : pageSize;
    final maxPage = total <= 0 ? 1 : ((total + size - 1) / size).floor();
    return page < maxPage;
  }

  factory BookCustomListPagination.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return BookCustomListPagination(
      total: parseInt(json['total']),
      page: parseInt(json['page']),
      pageSize: parseInt(json['pageSize'] ?? json['page_size']),
    );
  }
}
