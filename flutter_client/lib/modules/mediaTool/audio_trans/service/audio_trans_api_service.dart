import '../../../../core/api/base_api_service.dart';

class AudioTransApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> list({int page = 1}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/audioTrans/list',
      body: {'page': page},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required String sourcePath,
    required String targetPath,
    required Map<String, dynamic> transConfig,
    required String nonAudioPolicy,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/audioTrans/upsert',
      body: {
        if (id != null) 'id': id,
        'source_path': sourcePath,
        'target_path': targetPath,
        'trans_config': transConfig,
        'non_audio_policy': nonAudioPolicy,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/audioTrans/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/audioTrans/start',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/audioTrans/stop',
      body: {'id': id},
    );
  }
}
