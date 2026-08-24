import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class DockerApiService extends BaseApiService {
  static DockerApiService get instance =>
      Get.isRegistered<DockerApiService>()
          ? Get.find<DockerApiService>()
          : DockerApiService();

  Future<ApiResponse<Map<String, dynamic>>> getStatus() {
    return apiGet<Map<String, dynamic>>(
      '/api/docker/status',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getConfig() {
    return apiGet<Map<String, dynamic>>(
      '/api/docker/config',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> saveConfig(String content) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/config/save',
      body: {
        'content': content,
      },
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> startDocker() {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/start',
      body: const <String, dynamic>{},
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stopDocker() {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/stop',
      body: const <String, dynamic>{},
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setProxyConfig({
    required String httpProxy,
    required String httpsProxy,
    required String noProxy,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/config/proxy',
      body: {
        'httpProxy': httpProxy,
        'httpsProxy': httpsProxy,
        'noProxy': noProxy,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<List<dynamic>>> listImages() async {
    final response = await apiGet<List<dynamic>>(
      '/api/docker/images/list',
      showLoading: false,
    );
    if (!response.success) return response;
    final raw = response.data;
    final list = raw is List ? raw : const <dynamic>[];
    return ApiResponse.success(
      list,
      message: response.message,
      code: response.code,
      rawResponse: response.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> pullImage({
    required String image,
    String registry = '',
    String tag = '',
    String username = '',
    String password = '',
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/images/pull',
      body: {
        'image': image,
        'registry': registry,
        'tag': tag,
        'username': username,
        'password': password,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> importImage({
    required String archivePath,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/images/import',
      body: {
        'archivePath': archivePath,
      },
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteImage(
    String imageId, {
    String reference = '',
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/images/delete',
      body: {
        'imageId': imageId,
        'reference': reference,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> tagImage({
    required String imageId,
    required String repository,
    required String tag,
    String sourceReference = '',
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/images/tag',
      body: {
        'imageId': imageId,
        'repository': repository,
        'tag': tag,
        'sourceReference': sourceReference,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<List<dynamic>>> listContainers({String status = ''}) async {
    final response = await apiGet<List<dynamic>>(
      '/api/docker/containers/list',
      queryParams: status.trim().isEmpty ? null : {'status': status.trim()},
      showLoading: false,
    );
    if (!response.success) return response;
    final raw = response.data;
    final list = raw is List ? raw : const <dynamic>[];
    return ApiResponse.success(
      list,
      message: response.message,
      code: response.code,
      rawResponse: response.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createContainer(
    Map<String, dynamic> body,
  ) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/containers/create',
      body: body,
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> startContainer(String id) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/containers/start',
      body: {'containerId': id},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stopContainer(
    String id, {
    int timeout = 10,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/containers/stop',
      body: {'containerId': id, 'timeout': timeout},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteContainer(
    String id, {
    bool force = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/containers/delete',
      body: {'containerId': id, 'force': force},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getContainerLogs({
    required String containerId,
    String since = '',
    String until = '',
    int tail = 200,
    bool streamOutput = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/docker/containers/logs',
      queryParams: {
        'containerId': containerId,
        'since': since,
        'until': until,
        'tail': '$tail',
        'streamOutput': '$streamOutput',
      },
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: streamOutput ? const Duration(seconds: 10) : const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> listTasks() {
    return apiGet<Map<String, dynamic>>(
      '/api/docker/tasks/list',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getTask(String taskId) {
    return apiGet<Map<String, dynamic>>(
      '/api/docker/tasks/detail',
      queryParams: {'taskId': taskId},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getTaskLogs(
    String taskId, {
    int offset = 0,
    int limit = 200,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/docker/tasks/logs',
      queryParams: {
        'taskId': taskId,
        'offset': '$offset',
        'limit': '$limit',
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> cancelTask(String taskId) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/tasks/cancel',
      body: {'taskId': taskId},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteTask(String taskId) {
    return apiPost<Map<String, dynamic>>(
      '/api/docker/tasks/delete',
      body: {'taskId': taskId},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }
}
