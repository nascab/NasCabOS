import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';
import '../beans/server_info_bean.dart';
import './response/login_response.dart';
import './response/server_status_response.dart';
import './response/recover_info_response.dart';
import '../../../core/user/current_user_controller.dart';
import '../../../utils/user_agent_util.dart';

/// 认证API服务类，基于BaseApiService实现
class AuthApiService extends BaseApiService {
  static AuthApiService get instance => Get.find<AuthApiService>();

  Future<ApiResponse<Map<String, dynamic>>> getLoginConfig() {
    return apiGet<Map<String, dynamic>>(
      '/api/apiSetting/loginConfig',
      showLoading: false,
      showNetworkIssueOnFailure: false,
      dataParser: (json, code) => json,
    );
  }

  /// 登录到服务器
  Future<LoginResponse> loginToServer(
    ServerInfoBean serverInfo, {
    bool showLoading = true,
  }) async {
    CurrentUserController.instance.clearWallpaper();
    // 构建登录URL
    final loginUrl = '/api/auth/login';

    // 准备请求数据（密码进行可逆伪装）
    final deviceFingerprint = await UserAgentUtil.getDeviceFingerprintPayload();
    UserAgentUtil.getOrCreateVideoPlayerDeviceIdSync();
    final requestData = {
      'username': serverInfo.username,
      'password': obfuscatePassword(serverInfo.password!),
      'device_fingerprint': deviceFingerprint,
    };

    // 使用BaseApiService的API请求方法
    final apiResponse = await apiPost<LoginResponse>(
      loginUrl,
      body: requestData,
      dataParser: (dataJson, code) => LoginResponse.fromJson(dataJson, code),
      showLoading: showLoading,
      showNetworkIssueOnFailure: false,
    );
    if (!apiResponse.success) {
      return LoginResponse(
        success: false,
        message: apiResponse.message ?? 'auth_login_failure'.tr,
        code: apiResponse.code,
      );
    }
    final data = apiResponse.data!;
    if (data.twoFactorRequired == true) {
      return data;
    }

    final userMap = data.user;
    if (userMap != null) {
      CurrentUserController.instance.setUserFromMap(userMap);
    }

    final appsMap = data.apps;
    print("appsMap:$appsMap");
    if (appsMap != null) {
      CurrentUserController.instance.setApps(appsMap);
    }

    final wallpaperMap = data.wallpaper;
    if (wallpaperMap != null) {
      CurrentUserController.instance.setWallpaper(wallpaperMap);
    }

    return data;
  }

  Future<LoginResponse> verifyTwoFactorLogin({
    required String tempToken,
    required String code,
  }) async {
    final url = '/api/auth/2fa/login/verify';
    final deviceFingerprint = await UserAgentUtil.getDeviceFingerprintPayload();
    UserAgentUtil.getOrCreateVideoPlayerDeviceIdSync();
    final apiResponse = await apiPost<LoginResponse>(
      url,
      body: {
        'tempToken': tempToken,
        'code': code,
        'device_fingerprint': deviceFingerprint,
      },
      dataParser: (dataJson, code) => LoginResponse.fromJson(dataJson, code),
      showLoading: false,
      showNetworkIssueOnFailure: false,
    );
    if (!apiResponse.success) {
      return LoginResponse(
        success: false,
        message: apiResponse.message ?? 'auth_login_failure'.tr,
        code: apiResponse.code,
      );
    }
    final data = apiResponse.data!;

    final userMap = data.user;
    if (userMap != null) {
      CurrentUserController.instance.setUserFromMap(userMap);
    }

    final appsMap = data.apps;
    if (appsMap != null) {
      CurrentUserController.instance.setApps(appsMap);
    }

    final wallpaperMap = data.wallpaper;
    if (wallpaperMap != null) {
      CurrentUserController.instance.setWallpaper(wallpaperMap);
    }

    return data;
  }

  Future<ApiResponse<Map<String, dynamic>>> getTwofaStatus({
    bool showLoading = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/auth/2fa/status',
      showLoading: showLoading,
      showNetworkIssueOnFailure: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setupTwofa({
    String? issuer,
    String? accountName,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/auth/2fa/setup',
      body: {
        if (issuer != null) 'issuer': issuer,
        if (accountName != null) 'accountName': accountName,
      },
      showNetworkIssueOnFailure: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> enableTwofa({
    required String code,
    String? secret,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/auth/2fa/enable',
      body: {'code': code, if (secret != null) 'secret': secret},
      showNetworkIssueOnFailure: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> disableTwofa({
    required String code,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/auth/2fa/disable',
      body: {'code': code},
      showNetworkIssueOnFailure: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> rotateTwofaBackupCodes({
    required String code,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/auth/2fa/backup/rotate',
      body: {'code': code},
      showNetworkIssueOnFailure: false,
    );
  }

  /// 检查服务器状态并判断是否为NasCab服务器
  Future<ServerStatusResponse> checkServerStatus(
    bool showLoading, {
    Duration timeout = const Duration(seconds: 5),
    int maxRetries = 1,
  }) async {
    // 临时设置基础URL进行服务器状态检查
    try {
      final checkUrl = '/api/auth/isNasCabServer';
      print('🟣 [CheckServer] 请求: $checkUrl, timeout: $timeout');

      final apiResponse = await apiGet<Map<String, dynamic>>(
        checkUrl,
        timeout: timeout,
        maxRetries: maxRetries,
        dataParser: (json, code) => json,
        showLoading: showLoading,
        showNetworkIssueOnFailure: false,
      );

      print(
        '🟣 [CheckServer] 响应: success=${apiResponse.success}, code=${apiResponse.code}',
      );
      print('🟣 [CheckServer] data: ${apiResponse.data}');
      print('🟣 [CheckServer] message: ${apiResponse.message}');

      if (!apiResponse.success) {
        return ServerStatusResponse(
          success: false,
          message: apiResponse.message,
          isNasCabServer: false,
          serverData: null,
        );
      } else {
        final isNasCabServer = apiResponse.data?['isNasCabOSServer'] == true;
        print('🟣 [CheckServer] isNasCabOSServer: $isNasCabServer');
        return ServerStatusResponse(
          success: true,
          message: apiResponse.message,
          isNasCabServer: isNasCabServer,
          serverData: apiResponse.data,
        );
      }
    } catch (e) {
      print('🔴 [CheckServer] 异常: $e');
      rethrow;
    } finally {}
  }

  /// 刷新访问令牌
  Future<LoginResponse> refreshTokenApi(String refreshToken) async {
    final refreshUrl = '/api/auth/refreshJwt';

    final requestData = {'refreshToken': refreshToken};

    final apiResponse = await apiPost<LoginResponse>(
      refreshUrl,
      body: requestData,
      dataParser: (json, code) => LoginResponse.fromJson(json, code),
      showLoading: false,
      showNetworkIssueOnFailure: false,
    );

    // 处理API响应
    if (!apiResponse.success) {
      return LoginResponse(
        success: false,
        message: apiResponse.message ?? 'auth_token_refresh_failure'.tr,
      );
    }

    return apiResponse.data!;
  }

  /// 创建超级管理员
  Future<LoginResponse> createSuperAdmin({
    required String username,
    required String password,
    required String securityQuestion,
    required String securityAnswer,
  }) async {
    final createUrl = '/api/auth/createSuperAdmin';

    // 准备请求数据（密码进行可逆伪装）
    final requestData = {
      'username': username,
      'password': obfuscatePassword(password),
      'question': securityQuestion,
      'answer': encryptPassword(securityAnswer),
    };

    final apiResponse = await apiPost<LoginResponse>(
      createUrl,
      body: requestData,
      dataParser: (json, code) => LoginResponse.fromJson(json, code),
      showNetworkIssueOnFailure: false,
    );

    // 处理API响应
    if (!apiResponse.success) {
      return LoginResponse(
        success: false,
        message: apiResponse.message ?? 'admin_create_failure'.tr,
      );
    }

    return apiResponse.data!;
  }

  /// 对密保答案进行SHA256加密
  static String encryptPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 对密码进行可逆伪装（base64）
  static String obfuscatePassword(String password) {
    final b64 = base64Encode(utf8.encode(password));
    return 'b64:$b64';
  }

  /// 找回管理员密码
  Future<LoginResponse> recoverAdminPassword({
    required String username,
    required String answer,
    required String newPassword,
  }) async {
    final recoverUrl = '/api/auth/recoverPassword';
    final requestData = {
      'username': username,
      'answer': encryptPassword(answer),
      'newPassword': obfuscatePassword(newPassword),
    };
    final apiResponse = await apiPost<LoginResponse>(
      recoverUrl,
      body: requestData,
      dataParser: (json, code) => LoginResponse.fromJson(json, code),
      showNetworkIssueOnFailure: false,
    );
    if (!apiResponse.success) {
      return LoginResponse(
        success: false,
        message: apiResponse.message ?? 'recover_failure'.tr,
      );
    }
    return apiResponse.data!;
  }

  /// 获取找回密码信息（按用户名）
  Future<RecoverInfoResponse> getRecoverInfo({required String username}) async {
    final recoverInfoUrl = '/api/auth/recoverInfo';

    final apiResponse = await apiGet<Map<String, dynamic>>(
      recoverInfoUrl,
      queryParams: {'username': username},
      timeout: const Duration(seconds: 10),
      maxRetries: 2,
      dataParser: (json, code) => json,
      showNetworkIssueOnFailure: false,
    );

    if (!apiResponse.success) {
      return RecoverInfoResponse(
        success: false,
        message: apiResponse.message ?? 'auth_recover_info_failure'.tr,
        question: null,
        username: null,
      );
    }

    return RecoverInfoResponse(
      success: true,
      message: apiResponse.message,
      question: apiResponse.data?['question'],
      username: apiResponse.data?['username'],
    );
  }
}
