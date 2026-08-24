import '../../../../core/api/base_api_service.dart';

class ImgBatchCompressApiService extends BaseApiService {
  Future<ApiResponse<Map<String, dynamic>>> list({int page = 1}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/imgBatchCompress/list',
      body: {'page': page},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> upsert({
    int? id,
    required String sourcePath,
    required String targetPath,
    required String outFormat,
    required int quality,
    int? outSize,
    required String nonImagePolicy,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/imgBatchCompress/upsert',
      body: {
        if (id != null) 'id': id,
        'source_path': sourcePath,
        'target_path': targetPath,
        'out_format': outFormat,
        'quality': quality,
        if (outSize != null) 'out_size': outSize,
        'non_image_policy': nonImagePolicy,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/imgBatchCompress/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> start({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/imgBatchCompress/start',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stop({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/mediaTool/imgBatchCompress/stop',
      body: {'id': id},
    );
  }
}
