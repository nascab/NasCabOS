import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../list/models/music_list_models.dart';

class PlayListApiService extends BaseApiService {
  static PlayListApiService get instance =>
      Get.isRegistered<PlayListApiService>()
      ? Get.find<PlayListApiService>()
      : PlayListApiService();

  Future<ApiResponse<PlayListPagedResult>> listLists({
    int page = 1,
    int pageSize = 30,
    String? search,
    String sortBy = 'create_time',
    String sortOrder = 'desc',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/playlist/list',
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
      PlayListPagedResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<PlayListItem>> createList({required String name}) {
    return apiPost<Map<String, dynamic>>(
      '/api/music/playlist/create',
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
        PlayListItem.fromJson(res.data ?? const <String, dynamic>{}),
        message: res.message,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    });
  }

  Future<ApiResponse<PlayListItem>> updateList({
    required int id,
    required String name,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/music/playlist/update',
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
        PlayListItem.fromJson(res.data ?? const <String, dynamic>{}),
        message: res.message,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    });
  }

  Future<ApiResponse<bool>> deleteList(int id) async {
    final res = await apiPost<dynamic>(
      '/api/music/playlist/delete',
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
      '/api/music/playlist/index/add',
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
      '/api/music/playlist/index/remove',
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

class PlayListItem {
  final int id;
  final int uid;
  final String name;
  final String createTime;
  final List<MusicListItem> previews;

  const PlayListItem({
    required this.id,
    required this.uid,
    required this.name,
    required this.createTime,
    required this.previews,
  });

  factory PlayListItem.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    String parseString(dynamic v) => (v?.toString() ?? '').trim();

    final previewsRaw = json['previews'] is List
        ? (json['previews'] as List)
        : const <dynamic>[];
    final previews = previewsRaw
        .whereType<Map>()
        .map((e) => MusicListItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    return PlayListItem(
      id: parseInt(json['id']),
      uid: parseInt(json['uid']),
      name: parseString(json['name']),
      createTime: parseString(json['create_time'] ?? json['createTime']),
      previews: previews,
    );
  }
}

class PlayListPagedResult {
  final List<PlayListItem> items;
  final PlayListPagination pagination;

  const PlayListPagedResult({required this.items, required this.pagination});

  const PlayListPagedResult.empty()
    : items = const <PlayListItem>[],
      pagination = const PlayListPagination.empty();

  factory PlayListPagedResult.fromJson(Map<String, dynamic> json) {
    final listRaw = json['items'] is List
        ? (json['items'] as List)
        : const <dynamic>[];
    final items = listRaw
        .whereType<Map>()
        .map((e) => PlayListItem.fromJson(e.cast<String, dynamic>()))
        .toList();

    final paginationRaw = json['pagination'] is Map
        ? (json['pagination'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return PlayListPagedResult(
      items: items,
      pagination: PlayListPagination.fromJson(paginationRaw),
    );
  }
}

class PlayListPagination {
  final int total;
  final int page;
  final int pageSize;

  const PlayListPagination({
    required this.total,
    required this.page,
    required this.pageSize,
  });

  const PlayListPagination.empty() : total = 0, page = 1, pageSize = 30;

  factory PlayListPagination.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

    return PlayListPagination(
      total: parseInt(json['total']),
      page: parseInt(json['page']),
      pageSize: parseInt(json['pageSize'] ?? json['page_size']),
    );
  }

  bool get hasNextPage {
    final size = pageSize <= 0 ? 30 : pageSize;
    final maxPage = total <= 0 ? 1 : ((total + size - 1) / size).floor();
    return page < maxPage;
  }
}
