import '../../../../core/api/base_api_service.dart';
import '../models/ai_faces_models.dart';

class PhotoAiFacesApiService extends BaseApiService {
  Future<ApiResponse<AiFaceListResult>> listFaces({
    int page = 1,
    int pageSize = 50,
    String status = 'visiable',
    String keyword = '',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/face/list',
      body: {
        'page': page,
        'pageSize': pageSize,
        'status': status,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
      showLoading: false,
    );

    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    final data = res.data ?? <String, dynamic>{};
    return ApiResponse.success(
      AiFaceListResult.fromJson(data),
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> updateFaceName({
    required int faceId,
    required String name,
  }) async {
    final res = await apiPost<dynamic>(
      '/api/photo/face/name/update',
      body: {'face_id': faceId, 'name': name},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> setFaceStatus({
    required int faceId,
    required bool isHide,
  }) async {
    final res = await apiPost<dynamic>(
      '/api/photo/face/status/set',
      body: {'face_id': faceId, 'is_hide': isHide ? 1 : 0},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> mergeFaces({required List<int> faceIds}) async {
    final ids = faceIds.where((e) => e > 0).toList();
    final res = await apiPost<dynamic>(
      '/api/photo/face/merge',
      body: {'face_ids': ids},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> moveFaceToOther({
    required int fromFaceId,
    required int toFaceId,
  }) async {
    if (fromFaceId <= 0 || toFaceId <= 0 || fromFaceId == toFaceId) {
      return ApiResponse.failure('network_failure');
    }

    final res = await apiPost<dynamic>(
      '/api/photo/face/merge',
      body: {'from_face_id': fromFaceId, 'to_face_id': toFaceId},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<bool>> resetFaces() async {
    final res = await apiPost<dynamic>(
      '/api/photo/face/reset',
      body: {},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    return ApiResponse.success(
      true,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
