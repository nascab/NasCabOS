import 'package:get/get.dart';
import '../../core/api/base_api_service.dart';

class SecurityApiService extends BaseApiService {
  static SecurityApiService get instance =>
      Get.isRegistered<SecurityApiService>()
      ? Get.find<SecurityApiService>()
      : SecurityApiService();

  Future<ApiResponse<Map<String, dynamic>>> getConfig({
    bool showLoading = false,
  }) {
    return apiGet<Map<String, dynamic>>(
      '/api/security/config',
      showLoading: showLoading,
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setConfig({
    required bool banEnabled,
    required int maxFailedAttempts,
    required int banMinutes,
    required bool bypassLanAuth,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/security/config',
      body: {
        'banEnabled': banEnabled,
        'maxFailedAttempts': maxFailedAttempts,
        'banMinutes': banMinutes,
        'bypassLanAuth': bypassLanAuth,
      },
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<List<dynamic>>> listIpBlacklist({
    bool showLoading = false,
  }) {
    return apiGet<List<dynamic>>(
      '/api/security/ipBlacklist',
      showLoading: showLoading,
      dataParser: (json, code) => json['items'] as List<dynamic>,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteIpBlacklist(String ip) {
    return apiPost<Map<String, dynamic>>(
      '/api/security/ipBlacklist/delete',
      body: {'ip': ip},
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> clearIpBlacklist() {
    return apiPost<Map<String, dynamic>>(
      '/api/security/ipBlacklist/clear',
      body: const {},
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<List<dynamic>>> listDevices({bool showLoading = false}) {
    return apiGet<List<dynamic>>(
      '/api/auth/devices',
      showLoading: showLoading,
      dataParser: (json, code) => json['items'] as List<dynamic>,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> kickDevice(String deviceId) {
    return apiPost<Map<String, dynamic>>(
      '/api/auth/devices/kick',
      body: {'deviceId': deviceId},
      dataParser: (json, code) => json,
    );
  }
}
