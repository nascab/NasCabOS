import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class VideoFavoriteApiService extends BaseApiService {
  static VideoFavoriteApiService get instance =>
      Get.isRegistered<VideoFavoriteApiService>()
      ? Get.find<VideoFavoriteApiService>()
      : VideoFavoriteApiService();

  Future<bool> addFavorite(int indexId) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/favorite/add',
      body: {'index_id': indexId},
      showLoading: false,
    );
    return res.success;
  }

  Future<bool> removeFavorite(int indexId) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/video/favorite/remove',
      body: {'index_id': indexId},
      showLoading: false,
    );
    return res.success;
  }
}
