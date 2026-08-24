import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class AppearanceApiService extends BaseApiService {
  static AppearanceApiService get instance => Get.find<AppearanceApiService>();

  Future<ApiResponse<List<dynamic>>> getWallpapers() {
    return apiGet<List<dynamic>>('/api/appearance/wallpapers');
  }

  Future<ApiResponse<Map<String, dynamic>>> setWallpaper({
    required String mode,
    String? name,
  }) {
    final body = {'mode': mode, if (name != null) 'name': name};
    return apiPost<Map<String, dynamic>>(
      '/api/appearance/setWallpaper',
      body: body,
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteWallpaper({
    required String name,
  }) {
    final body = {'name': name};
    return apiPost<Map<String, dynamic>>(
      '/api/appearance/deleteWallpaper',
      body: body,
      showLoading: true,
      loadingMsg: 'loading'.tr,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setCustomHostname({
    required String customHostname,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/appearance/setCustomHostname',
      body: {'customHostname': customHostname},
      showLoading: false,
    );
  }
}
