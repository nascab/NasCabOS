import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';
import '../../auth/service/auth_api_service.dart';
import '../../transfer/models/file_operation_log.dart';

class UserApiService extends BaseApiService {
  static UserApiService get instance => Get.isRegistered<UserApiService>()
      ? Get.find<UserApiService>()
      : UserApiService();

  Future<List<dynamic>> fetchUsers({
    int page = 1,
    int limit = 20,
    String keyword = '',
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/list',
      body: {'page': page, 'limit': limit, 'keyword': keyword},
    );
    final data = res.data ?? {};
    return (data['items'] as List?) ?? [];
  }

  Future<ApiResponse> createUser({
    required String username,
    required String password,
    String? userRemark,
    String? phone,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/create',
      body: {
        'username': username,
        'password': AuthApiService.obfuscatePassword(password),
        if (userRemark != null && userRemark.trim().isNotEmpty)
          'user_remark': userRemark.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
    return res;
  }

  Future<ApiResponse> updateUser({
    required int id,
    String? username,
    String? password,
    bool? isActive,
    String? userRemark,
    String? phone,
  }) async {
    final body = {
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (isActive != null) 'is_active': isActive,
      if (userRemark != null) 'user_remark': userRemark,
      if (phone != null) 'phone': phone,
    };
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/update/$id',
      body: body,
    );
    return res;
  }

  Future<ApiResponse> deleteUsers(List<int> ids) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/delete',
      body: {'ids': ids},
    );
    return res;
  }

  Future<List<dynamic>> getUserPermissions(int uid) async {
    final res = await apiPost<List<dynamic>>(
      '/api/user/permissions/get',
      body: {'uid': uid},
    );
    return res.data ?? [];
  }

  Future<ApiResponse> setUserPermissions(
    int uid,
    List<Map<String, dynamic>> permissions,
  ) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/permissions/$uid',
      body: {'permissions': permissions},
    );
    return res;
  }

  Future<Map<String, dynamic>> listDirectory(
    String path, {
    bool onlyDir = true,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/list',
      body: {'path': path, 'onlyDir': onlyDir ? 'true' : 'false'},
    );
    return res.data ?? {};
  }

  Future<List<dynamic>> getLoginRecords({
    required int uid,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/login-records',
      body: {'uid': uid, 'page': page, 'limit': limit},
    );
    final data = res.data ?? {};
    return (data['items'] as List?) ?? [];
  }

  Future<ApiResponse<FileLogListResponse>> getUserFileLogs({
    required int uid,
    List<String>? types,
    int page = 1,
    int pageSize = 20,
    List<String>? stateList,
    String? keyword,
  }) {
    return apiPost<FileLogListResponse>(
      '/api/user/file-log/list',
      body: {
        'uid': uid,
        'page': page,
        'pageSize': pageSize,
        if (types != null) 'types': types,
        if (stateList != null) 'stateList': stateList,
        if (keyword != null) 'keyword': keyword,
      },
      dataParser: (data, _) => FileLogListResponse.fromJson(data),
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createScopedToken({
    required List<String> allowApi,
    required List<String> allowPath,
    String expiresIn = '1440m',
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/user/token/scoped',
      body: {
        'allow_api': allowApi,
        'allow_path': allowPath,
        'expiresIn': expiresIn,
      },
      showLoading: showLoading,
    );
  }

  Future<Map<String, dynamic>> getUser2faStatus({required int uid}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/2fa/status',
      body: {'uid': uid},
      showLoading: false,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'operation_failed'.tr);
    }
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> setupUser2fa({
    required int uid,
    String? issuer,
    String? accountName,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/user/2fa/setup',
      body: {
        'uid': uid,
        if (issuer != null) 'issuer': issuer,
        if (accountName != null) 'accountName': accountName,
      },
    );
    if (!res.success) {
      throw Exception(res.message ?? 'operation_failed'.tr);
    }
    return res.data ?? {};
  }

  Future<ApiResponse<Map<String, dynamic>>> enableUser2fa({
    required int uid,
    required String code,
    String? secret,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/user/2fa/enable',
      body: {'uid': uid, 'code': code, if (secret != null) 'secret': secret},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> resetUser2fa({required int uid}) {
    return apiPost<Map<String, dynamic>>(
      '/api/user/2fa/reset',
      body: {'uid': uid},
    );
  }
}
