import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class MusicFavoriteApiService extends BaseApiService {
  static MusicFavoriteApiService get instance =>
      Get.isRegistered<MusicFavoriteApiService>()
      ? Get.find<MusicFavoriteApiService>()
      : MusicFavoriteApiService();

  Future<bool> addFavorite(int indexId) async {
    return batchFavorite([indexId], true);
  }

  Future<bool> removeFavorite(int indexId) async {
    return batchFavorite([indexId], false);
  }

  Future<bool> batchFavorite(List<int> indexIds, bool isFavorite) async {
    final ids = indexIds.where((e) => e > 0).toSet().toList()..sort();
    if (ids.isEmpty) return false;
    final res = await apiPost<void>(
      '/api/music/favorite/batch',
      body: {'index_ids': ids, 'is_favorite': isFavorite},
      showLoading: false,
    );
    return res.success;
  }
}
