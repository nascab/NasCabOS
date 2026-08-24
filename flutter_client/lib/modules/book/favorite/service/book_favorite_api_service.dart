import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class BookFavoriteApiService extends BaseApiService {
  static BookFavoriteApiService get instance =>
      Get.isRegistered<BookFavoriteApiService>()
      ? Get.find<BookFavoriteApiService>()
      : BookFavoriteApiService();

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
      '/api/book/favorite/batch',
      body: {'index_ids': ids, 'is_favorite': isFavorite},
      showLoading: false,
    );
    return res.success;
  }
}
