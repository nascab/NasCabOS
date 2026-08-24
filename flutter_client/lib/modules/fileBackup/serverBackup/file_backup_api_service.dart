import '../../../core/api/base_api_service.dart';

class FileBackupApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> list({
    int page = 1,
    int? pageSize,
    String? status,
    String? type,
    String? keyword,
    String? sortBy,
    String? sortOrder,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileBackup/list',
      body: {
        'page': page,
        if (pageSize != null) 'pageSize': pageSize,
        if (status != null) 'status': status,
        if (type != null) 'type': type,
        if (keyword != null) 'keyword': keyword,
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required List<String> sourcePathList,
    required String type,
    required String targetPath,
    required int frenquence,
    required List<String> excludeList,
    Map<String, dynamic>? taskConfig,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileBackup/upsert',
      body: {
        if (id != null) 'id': id,
        'source_path': sourcePathList,
        'type': type,
        'target_path': targetPath,
        'frenquence': frenquence,
        'exclude_list': excludeList,
        if (taskConfig != null) 'task_config': taskConfig,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileBackup/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileBackup/start',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileBackup/stop',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> listRecords({
    required int taskId,
    int page = 1,
    int pageSize = 50,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/fileBackup/records/list',
      body: {
        'id': taskId,
        'page': page,
        'pageSize': pageSize,
      },
      showLoading: false,
    );
  }
}
