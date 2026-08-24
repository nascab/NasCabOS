import '../../../core/api/base_api_service.dart';

class EncryptedSpaceApiService extends BaseApiService {
  Future<ApiResponse<List<dynamic>>> list() {
    return apiPost<List<dynamic>>(
      '/api/encryptedSpace/list',
      body: const {},
      showLoading: false,
    );
  }

  Future<ApiResponse<List<dynamic>>> exportTaskList() {
    return apiPost<List<dynamic>>(
      '/api/encryptedSpace/export/list',
      body: const {},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> addSpace({
    required String folderPath,
    required String spaceName,
    required String spacePwd,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/addSpace',
      body: {
        'folderPath': folderPath,
        'spaceName': spaceName,
        'spacePwd': spacePwd,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> importSpace({
    required String folderPath,
    required String spaceName,
    required String spacePwd,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/importSpace',
      body: {
        'folderPath': folderPath,
        'spaceName': spaceName,
        'spacePwd': spacePwd,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> checkPwd({
    required int spaceId,
    required String spacePwd,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/checkPwd',
      body: {'spaceId': spaceId, 'spacePwd': spacePwd},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteToken({
    required int spaceId,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/deleteToken',
      body: {'spaceId': spaceId},
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSpace({
    required int spaceId,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/deleteSpace',
      body: {'spaceId': spaceId},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateSpaceName({
    required int spaceId,
    required String spaceName,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/updateSpaceName',
      body: {'spaceId': spaceId, 'spaceName': spaceName},
    );
  }

  Future<ApiResponse<List<dynamic>>> getFileList({
    required int spaceId,
    required String token,
    int count = 200,
    int offsetCount = 0,
    String orderField = 'create_time',
    String orderType = 'desc',
    String fileType = 'all',
    String keyword = '',
  }) {
    return apiPost<List<dynamic>>(
      '/api/encryptedSpace/getFileList',
      body: {
        'spaceId': spaceId,
        'token': token,
        'count': count,
        'offsetCount': offsetCount,
        'orderField': orderField,
        'orderType': orderType,
        'fileType': fileType,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSpaceFiles({
    required int spaceId,
    required List<int> ids,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/deleteSpaceFiles',
      body: {'spaceId': spaceId, 'ids': ids},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> addExportTask({
    required int spaceId,
    required String spacePwd,
    required String targetPath,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/export/add',
      body: {
        'spaceId': spaceId,
        'spacePwd': spacePwd,
        'targetPath': targetPath,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteExportTask({
    required int id,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/export/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> clearFinishedExportTasks() {
    return apiPost<Map<String, dynamic>>(
      '/api/encryptedSpace/export/clearFinished',
      body: const {},
    );
  }
}
