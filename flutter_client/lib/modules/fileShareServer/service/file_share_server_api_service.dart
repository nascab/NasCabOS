import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class FileShareServerApiService extends BaseApiService {
  static FileShareServerApiService get instance =>
      Get.isRegistered<FileShareServerApiService>()
      ? Get.find<FileShareServerApiService>()
      : FileShareServerApiService();

  Future<ApiResponse<List<dynamic>>> list({required String serverType}) {
    return apiPost<List<dynamic>>(
      '/api/fileServer/list',
      body: {'server_type': serverType},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    required int uid,
    required String serverType,
    required List<dynamic> rootPath,
    required Map<String, dynamic> config,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileServer/upsert',
      body: {
        'uid': uid.toString(),
        'server_type': serverType,
        'root_path': rootPath,
        'config': config,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({
    required int uid,
    required String serverType,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileServer/delete',
      body: {'uid': uid.toString(), 'server_type': serverType},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({
    required String serverType,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileServer/start',
      body: {'server_type': serverType},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required String serverType}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileServer/stop',
      body: {'server_type': serverType},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getPorts({
    required String serverType,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileServer/ports/get',
      body: {'server_type': serverType},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setPorts({
    required String serverType,
    int? httpPort,
    int? httpsPort,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileServer/ports/set',
      body: {
        'server_type': serverType,
        if (httpPort != null) 'http_port': httpPort,
        if (httpsPort != null) 'https_port': httpsPort,
      },
    );
  }
}
