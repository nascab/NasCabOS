import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../../base/beans/video_item_bean.dart';

class VideoListApiService extends BaseApiService {
  static VideoListApiService get instance =>
      Get.isRegistered<VideoListApiService>()
      ? Get.find<VideoListApiService>()
      : VideoListApiService();

  Future<ApiResponse<VideoIndexCountResult>> getIndexCounts({
    List<String>? sourceList,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/list/count',
      body: {if (sourceList != null) 'sourceList': sourceList},
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
    final parsed = VideoIndexCountResult.fromJson(data);

    return ApiResponse.success(
      parsed,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<VideoListPagedResult> listPaged({
    required int page,
    required int pageSize,
    String? listType,
    String? mediaType,
    int? albumId,
    int? collectionId,
    int? smartAlbumId,
    String? search,
    List<String>? genres,
    List<String>? regions,
    List<String>? actors,
    List<String>? directors,
    List<int>? years,
    List<String>? sourceList,
    String? sortBy,
    String? sortOrder,
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/list',
      body: {
        'page': page,
        'page_size': pageSize,
        if (listType != null && listType.trim().isNotEmpty)
          'listType': listType.trim(),
        if (mediaType != null && mediaType.trim().isNotEmpty)
          'media_type': mediaType.trim(),
        if (albumId != null && albumId > 0) 'album_id': albumId,
        if (collectionId != null && collectionId > 0)
          'collection_id': collectionId,
        if (smartAlbumId != null && smartAlbumId > 0)
          'smart_album_id': smartAlbumId,
        if (search != null) 'search': search,
        if (genres != null) 'genres': genres,
        if (regions != null) 'regions': regions,
        if (actors != null) 'actors': actors,
        if (directors != null) 'directors': directors,
        if (years != null) 'years': years,
        if (sourceList != null) 'sourceList': sourceList,
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
      showLoading: showLoading,
    );

    if (!res.success) return const VideoListPagedResult.empty();
    final data = res.data ?? <String, dynamic>{};
    return VideoListPagedResult.fromJson(data);
  }
}

class VideoIndexCountResult {
  final int movie;
  final int tv;

  const VideoIndexCountResult({required this.movie, required this.tv});

  int get total => movie + tv;

  factory VideoIndexCountResult.fromJson(Map<String, dynamic> json) {
    final rawMovie = json['movie'];
    final rawTv = json['tv'];
    final movie = rawMovie is num
        ? rawMovie.toInt()
        : int.tryParse(rawMovie?.toString() ?? '') ?? 0;
    final tv = rawTv is num
        ? rawTv.toInt()
        : int.tryParse(rawTv?.toString() ?? '') ?? 0;
    return VideoIndexCountResult(movie: movie, tv: tv);
  }
}

class VideoListPagination {
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPrevPage;

  const VideoListPagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPrevPage,
  });

  const VideoListPagination.empty()
    : total = 0,
      page = 1,
      limit = 30,
      totalPages = 0,
      hasNextPage = false,
      hasPrevPage = false;

  factory VideoListPagination.fromJson(Map<String, dynamic> json) {
    return VideoListPagination(
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 30,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      hasNextPage: (json['hasNextPage'] as bool?) ?? false,
      hasPrevPage: (json['hasPrevPage'] as bool?) ?? false,
    );
  }
}

class VideoListFilterOptions {
  final List<String> genres;
  final List<String> regions;
  final List<int> years;

  const VideoListFilterOptions({
    required this.genres,
    required this.regions,
    required this.years,
  });

  factory VideoListFilterOptions.fromJson(Map<String, dynamic> json) {
    List<String> parseStringList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .map((e) => e.toString())
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<int> parseIntList(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
          .where((e) => e > 0)
          .toList();
    }

    return VideoListFilterOptions(
      genres: parseStringList(json['genres']),
      regions: parseStringList(json['regions']),
      years: parseIntList(json['years']),
    );
  }
}

class VideoListPathItem {
  final String path;
  final bool valid;

  const VideoListPathItem({required this.path, required this.valid});

  factory VideoListPathItem.fromJson(Map<String, dynamic> json) {
    return VideoListPathItem(
      path: (json['path']?.toString() ?? '').trim(),
      valid: (json['valid'] as bool?) ?? false,
    );
  }
}

class VideoListPagedResult {
  final List<VideoHomeItemBean> items;
  final VideoListPagination pagination;
  final VideoListFilterOptions? filters;
  final List<VideoListPathItem> validPaths;

  const VideoListPagedResult({
    required this.items,
    required this.pagination,
    required this.filters,
    required this.validPaths,
  });

  const VideoListPagedResult.empty()
    : items = const <VideoHomeItemBean>[],
      pagination = const VideoListPagination.empty(),
      filters = null,
      validPaths = const <VideoListPathItem>[];

  factory VideoListPagedResult.fromJson(Map<String, dynamic> json) {
    List<VideoHomeItemBean> parseItems(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => VideoHomeItemBean.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id > 0)
          .toList();
    }

    List<VideoListPathItem> parseValidPaths(dynamic v) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .map((e) {
            if (e is String) {
              final p = e.trim();
              return VideoListPathItem(path: p, valid: true);
            }
            if (e is Map) {
              return VideoListPathItem.fromJson(e.cast<String, dynamic>());
            }
            return const VideoListPathItem(path: '', valid: false);
          })
          .where((e) => e.path.isNotEmpty)
          .toList();
    }

    final paginationRaw = json['pagination'];
    final paginationMap = paginationRaw is Map
        ? paginationRaw.cast<String, dynamic>()
        : <String, dynamic>{};
    final filtersRaw = json['filters'] ?? json['filterOptions'];
    final filtersMap = filtersRaw is Map
        ? filtersRaw.cast<String, dynamic>()
        : null;
    final validPathsRaw = json['validPaths'] ?? json['valid_paths'];
    return VideoListPagedResult(
      items: parseItems(json['items']),
      pagination: VideoListPagination.fromJson(paginationMap),
      filters: filtersMap == null
          ? null
          : VideoListFilterOptions.fromJson(filtersMap),
      validPaths: parseValidPaths(validPathsRaw),
    );
  }
}
