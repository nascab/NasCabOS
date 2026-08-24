import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/album_artist_list_models.dart';

class AlbumArtistListApiService extends BaseApiService {
  static AlbumArtistListApiService get instance =>
      Get.isRegistered<AlbumArtistListApiService>()
      ? Get.find<AlbumArtistListApiService>()
      : AlbumArtistListApiService();

  Future<AlbumArtistListPagedResult> listPaged({
    required String keyType,
    required int page,
    required int pageSize,
    String? search,
    List<String>? sourceList,
    String? sortBy,
    String? sortOrder,
    bool showLoading = false,
  }) async {
    final type = keyType.trim().toLowerCase();
    final endpoint = type == 'artist'
        ? '/api/music/artist/list'
        : '/api/music/album/list';
    final res = await apiPost<Map<String, dynamic>>(
      endpoint,
      body: {
        'page': page,
        'page_size': pageSize,
        if (search != null) 'search': search,
        if (sourceList != null) 'sourceList': sourceList,
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
      showLoading: showLoading,
    );

    if (!res.success) return const AlbumArtistListPagedResult.empty();
    final data = res.data ?? <String, dynamic>{};
    return AlbumArtistListPagedResult.fromJson(data);
  }
}
