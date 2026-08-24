import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/music_list_models.dart';

class MusicListApiService extends BaseApiService {
  static MusicListApiService get instance =>
      Get.isRegistered<MusicListApiService>()
      ? Get.find<MusicListApiService>()
      : MusicListApiService();

  Future<ApiResponse<MusicLibraryCountResult>> getLibraryCounts({
    List<String>? sourceList,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/list/count',
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
    return ApiResponse.success(
      MusicLibraryCountResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteEntries(
    List<String> paths, {
    bool recycle = false,
    bool showLoading = true,
  }) {
    final targets =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()..sort();
    if (targets.isEmpty) {
      return Future.value(ApiResponse.failure('network_failure'));
    }
    return apiPost<Map<String, dynamic>>(
      '/api/music/delete',
      body: {'paths': targets, 'recycle': recycle},
      showLoading: showLoading,
    );
  }

  Future<MusicListPagedResult> listPaged({
    required int page,
    required int pageSize,
    String? listType,
    int? listId,
    int? seriesIndexId,
    int? collectionId,
    bool isFavorite = false,
    bool isHistory = false,
    String? search,
    List<String>? artists,
    List<String>? albums,
    List<String>? genres,
    List<String>? sourceList,
    String? sortBy,
    String? sortOrder,
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/music/list',
      body: {
        'page': page,
        'page_size': pageSize,
        if (listType != null && listType.trim().isNotEmpty)
          'listType': listType.trim(),
        if (listId != null && listId > 0) 'list_id': listId,
        if (seriesIndexId != null && seriesIndexId > 0)
          'series_index_id': seriesIndexId,
        if (collectionId != null && collectionId > 0)
          'collection_id': collectionId,
        if (isFavorite) 'is_favorite': 1,
        if (isHistory) 'isHistory': 1,
        if (search != null) 'search': search,
        if (artists != null) 'artists': artists,
        if (albums != null) 'albums': albums,
        if (genres != null) 'genres': genres,
        if (sourceList != null) 'sourceList': sourceList,
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
      showLoading: showLoading,
    );

    if (!res.success) return const MusicListPagedResult.empty();
    final data = res.data ?? <String, dynamic>{};
    return MusicListPagedResult.fromJson(data);
  }

  Future<ApiResponse<Map<String, dynamic>>> getDetailByPath(
    String filePath, {
    bool showLoading = false,
  }) {
    final p = filePath.trim();
    if (p.isEmpty) {
      return Future.value(ApiResponse.failure('network_failure'));
    }
    return apiPost<Map<String, dynamic>>(
      '/api/music/detail/get',
      body: {'file_path': p},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> refreshHistory({
    int? indexId,
    String? filePath,
    bool showLoading = false,
  }) {
    final id = indexId ?? 0;
    final p = filePath?.trim() ?? '';
    if (id <= 0 && p.isEmpty) {
      return Future.value(ApiResponse.failure('network_failure'));
    }
    return apiPost<Map<String, dynamic>>(
      '/api/music/history/refresh',
      body: {if (id > 0) 'index_id': id, if (p.isNotEmpty) 'file_path': p},
      showLoading: showLoading,
    );
  }
}

class MusicLibraryCountResult {
  final int songs;

  const MusicLibraryCountResult({required this.songs});

  factory MusicLibraryCountResult.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return MusicLibraryCountResult(songs: toInt(json['songs']));
  }
}
