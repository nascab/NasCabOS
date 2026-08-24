import '../../../../core/api/base_api_service.dart';

class VideoTransApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> list({int page = 1}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/videoTrans/list',
      body: {'page': page},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required String sourcePath,
    required String targetPath,
    required Map<String, dynamic> transConfig,
    required String nonVideoPolicy,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/videoTrans/upsert',
      body: {
        if (id != null) 'id': id,
        'source_path': sourcePath,
        'target_path': targetPath,
        'trans_config': transConfig,
        'non_video_policy': nonVideoPolicy,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/videoTrans/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/videoTrans/start',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/videoTrans/stop',
      body: {'id': id},
    );
  }
}
