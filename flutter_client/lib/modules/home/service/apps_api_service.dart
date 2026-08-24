import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';
import '../../../core/user/current_user_controller.dart';

class AppsApiService extends BaseApiService {
  static AppsApiService get instance => Get.find<AppsApiService>();

  Future<ApiResponse<Map<String, dynamic>>> getHomeConfig({
    bool showLoading = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/home/config',
      showLoading: showLoading,
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getApps() {
    return apiGet<Map<String, dynamic>>(
      '/api/apps/getApps',
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setHideApps(List<String> hideApps) {
    final uid = CurrentUserController.instance.current?.id ?? 0;
    return apiPost<Map<String, dynamic>>(
      '/api/apps/setHideApps',
      body: {'uid': uid, 'hide_app': hideApps},
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> unhideApp(String app) {
    final uid = CurrentUserController.instance.current?.id ?? 0;
    return apiPost<Map<String, dynamic>>(
      '/api/apps/unhideApp',
      body: {'uid': uid, 'app': app},
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> hideApp(String app) {
    final uid = CurrentUserController.instance.current?.id ?? 0;
    return apiPost<Map<String, dynamic>>(
      '/api/apps/hideApp',
      body: {'uid': uid, 'app': app},
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAppsOrder(List<String> allApps) {
    final uid = CurrentUserController.instance.current?.id ?? 0;
    return apiPost<Map<String, dynamic>>(
      '/api/apps/setAppsOrder',
      body: {'uid': uid, 'order_app': allApps},
      dataParser: (json, code) => json,
    );
  }
}
