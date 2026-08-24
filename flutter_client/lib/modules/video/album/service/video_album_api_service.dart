import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/video_album_model.dart';
import '../../collection/models/video_collection_model.dart';
import '../../smart_album/models/video_smart_album_model.dart';

class VideoAlbumOverviewResult {
  final List<VideoAlbumItem> albums;
  final int albumTotal;
  final List<VideoCollectionItem> collections;
  final int collectionTotal;
  final List<VideoSmartAlbumItem> smartAlbums;
  final int smartAlbumTotal;

  VideoAlbumOverviewResult({
    required this.albums,
    required this.albumTotal,
    required this.collections,
    required this.collectionTotal,
    required this.smartAlbums,
    required this.smartAlbumTotal,
  });

  factory VideoAlbumOverviewResult.fromJson(Map<String, dynamic> json) {
    List<T> parseItems<T>(
      dynamic v,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final list = v is List ? v : const <dynamic>[];
      return list
          .whereType<Map>()
          .map((e) => fromJson(e.cast<String, dynamic>()))
          .toList();
    }

    final albumsBlock = (json['albums'] as Map?)?.cast<String, dynamic>() ?? {};
    final collectionsBlock =
        (json['collections'] as Map?)?.cast<String, dynamic>() ?? {};
    final smartBlock =
        (json['smart_albums'] as Map?)?.cast<String, dynamic>() ?? {};

    return VideoAlbumOverviewResult(
      albums: parseItems<VideoAlbumItem>(
        albumsBlock['items'],
        VideoAlbumItem.fromJson,
      ).where((e) => e.id > 0).toList(),
      albumTotal: (albumsBlock['total'] as num?)?.toInt() ?? 0,
      collections: parseItems<VideoCollectionItem>(
        collectionsBlock['items'],
        VideoCollectionItem.fromJson,
      ).where((e) => e.id > 0).toList(),
      collectionTotal: (collectionsBlock['total'] as num?)?.toInt() ?? 0,
      smartAlbums: parseItems<VideoSmartAlbumItem>(
        smartBlock['items'],
        VideoSmartAlbumItem.fromJson,
      ).where((e) => e.id > 0).toList(),
      smartAlbumTotal: (smartBlock['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class VideoAlbumApiService extends BaseApiService {
  static VideoAlbumApiService get instance =>
      Get.isRegistered<VideoAlbumApiService>()
      ? Get.find<VideoAlbumApiService>()
      : VideoAlbumApiService();

  Future<ApiResponse<VideoAlbumListResult>> listAlbums({
    int page = 1,
    int pageSize = 50,
    String? keyword,
    String sortField = 'create_time',
    String sortOrder = 'desc',
    int? previewLimit,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/album/list',
      body: {
        'page': page,
        'pageSize': pageSize,
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword': keyword.trim(),
        'sortField': sortField,
        'sortOrder': sortOrder,
        if (previewLimit != null && previewLimit > 0)
          'previewLimit': previewLimit,
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
      VideoAlbumListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<VideoAlbumOverviewResult>> getAlbumOverview({
    int limit = 6,
  }) async {
    final safeLimit = limit.clamp(1, 12);
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/album/overview',
      body: {'limit': safeLimit},
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
      VideoAlbumOverviewResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<VideoAlbumDetail>> getAlbum(int id) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/album/get',
      body: {'id': id},
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
      VideoAlbumDetail.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createAlbum({
    required String name,
    bool isPublic = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/album/create',
      body: {'name': name, 'is_public': isPublic ? 1 : 0},
      showLoading: true,
    );
  }

  Future<ApiResponse<bool>> updateAlbum({
    required int id,
    String? name,
    bool? isPublic,
  }) {
    final body = <String, dynamic>{
      'id': id,
      if (name != null) 'name': name,
      if (isPublic != null) 'is_public': isPublic ? 1 : 0,
    };
    return apiPost<dynamic>(
      '/api/video/album/update',
      body: body,
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
        true,
        message: res.message,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    });
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteAlbum(int id) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/album/delete',
      body: {'id': id},
      showLoading: true,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> addAlbumIndexes({
    required int albumId,
    required List<int> indexIds,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/album/index/add',
      body: {'album_id': albumId, 'index_ids': indexIds},
      showLoading: true,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> removeAlbumIndexes({
    required int albumId,
    required List<int> indexIds,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/video/album/index/remove',
      body: {'album_id': albumId, 'index_ids': indexIds},
      showLoading: true,
    );
  }

  Future<ApiResponse<bool>> setAlbumCover({
    required int albumId,
    required int indexId,
  }) {
    return apiPost<bool>(
      '/api/video/album/cover/set',
      body: {'album_id': albumId, 'index_id': indexId},
      showLoading: true,
    );
  }
}
