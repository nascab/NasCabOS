import '../../../../core/api/base_api_service.dart';

class MediaArrangeApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> list({int page = 1}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/mediaArrange/list',
      body: {'page': page},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required String sourcePath,
    required String targetPath,
    required String arrangeType,
    required String sameNamePolicy,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/mediaArrange/upsert',
      body: {
        if (id != null) 'id': id,
        'source_path': sourcePath,
        'target_path': targetPath,
        'arrange_type': arrangeType,
        'same_name_policy': sameNamePolicy,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/mediaArrange/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/mediaArrange/start',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/mediaArrange/stop',
      body: {'id': id},
    );
  }
}
