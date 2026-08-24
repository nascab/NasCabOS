import '../../../core/api/base_api_service.dart';

class OpenlistMountApiService extends BaseApiService {
  Future<ApiResponse<List<dynamic>>> list({String? uid, String? status}) {
    return apiPost<List<dynamic>>(
      '/api/openlistMount/list',
      body: {if (uid != null) 'uid': uid, if (status != null) 'status': status},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required String name,
    required String mountPath,
    required String driver,
    Map<String, dynamic>? config,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/openlistMount/upsert',
      body: {
        if (id != null) 'id': id,
        'name': name,
        'mount_path': mountPath,
        'driver': driver,
        if (config != null) 'config': config,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/openlistMount/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/openlistMount/start',
      body: {'id': id},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/openlistMount/stop',
      body: {'id': id},
    );
  }

  Future<ApiResponse<List<dynamic>>> drivers() {
    return apiGet<List<dynamic>>(
      '/api/openlistMount/drivers',
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> oauthHelpUrl() {
    return apiGet<Map<String, dynamic>>(
      '/api/openlistMount/oauthHelpUrl',
      showLoading: false,
    );
  }
}
