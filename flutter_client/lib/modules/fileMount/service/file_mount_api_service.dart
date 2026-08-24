import '../../../core/api/base_api_service.dart';

class FileMountApiService extends BaseApiService {
  Future<ApiResponse<List<dynamic>>> list({String? uid, String? status}) {
    return apiPost<List<dynamic>>(
      '/api/fileMount/list',
      body: {if (uid != null) 'uid': uid, if (status != null) 'status': status},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required String name,
    required String mountPath,
    required String remote,
    Map<String, dynamic>? config,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileMount/upsert',
      body: {
        if (id != null) 'id': id,
        'name': name,
        'mount_path': mountPath,
        'remote': remote,
        if (config != null) 'config': config,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileMount/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileMount/start',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileMount/stop',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> checkWinfsp() {
    return apiPost<Map<String, dynamic>>(
      '/api/fileMount/checkWinfsp',
      body: const {},
      showLoading: false,
    );
  }
}
