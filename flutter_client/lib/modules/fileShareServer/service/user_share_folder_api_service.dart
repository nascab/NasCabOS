import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class UserShareFolderApiService extends BaseApiService {
  static UserShareFolderApiService get instance =>
      Get.isRegistered<UserShareFolderApiService>()
      ? Get.find<UserShareFolderApiService>()
      : UserShareFolderApiService();

  Future<ApiResponse<Map<String, dynamic>>> list() {
    return apiGet<Map<String, dynamic>>(
      '/api/file/userShareFolder/list',
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> add({
    required String path,
    String? name,
    bool? allowDownload,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/file/userShareFolder/add',
      body: {
        'path': path,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (allowDownload != null) 'allowDownload': allowDownload,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> remove({required String path}) {
    return apiPost<Map<String, dynamic>>(
      '/api/file/userShareFolder/remove',
      body: {'path': path},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setAllowDownload({
    required String path,
    required bool allowDownload,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/file/userShareFolder/allowDownload',
      body: {'path': path, 'allowDownload': allowDownload},
    );
  }
}
