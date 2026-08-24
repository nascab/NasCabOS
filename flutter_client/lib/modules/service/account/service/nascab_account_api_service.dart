import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class NasCabAccountApiService extends BaseApiService {
  static NasCabAccountApiService get instance =>
      Get.isRegistered<NasCabAccountApiService>()
      ? Get.find<NasCabAccountApiService>()
      : NasCabAccountApiService();

  Future<ApiResponse<Map<String, dynamic>>> query() {
    return apiGet<Map<String, dynamic>>(
      '/api/service/nascab/query',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> login(String jwt) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/login',
      body: {'jwt': jwt},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  /// 使用登录页回调的临时 code 登录（避免 JWT 暴露在 URL 中）
  Future<ApiResponse<Map<String, dynamic>>> loginWithCode(String code) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/login',
      body: {'code': code},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> logout() {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/logout',
      body: {},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> refresh() {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/refresh',
      body: {},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getP2pPairCode() {
    return apiGet<Map<String, dynamic>>(
      '/api/service/nascab/p2p/pairCode',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> resetP2pPairCode() {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/p2p/pairCode/reset',
      body: {},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> customP2pPairCode(String pairCode) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/p2p/pairCode/custom',
      body: {'pairCode': pairCode},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getP2pRemoteAccess() {
    return apiGet<Map<String, dynamic>>(
      '/api/service/nascab/p2p/remoteAccess',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setP2pRemoteAccess(bool enabled) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/p2p/remoteAccess',
      body: {'enabled': enabled},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setP2pNodePreference(
    String domain,
  ) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/p2p/nodePreference',
      body: {'domain': domain},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  /// 绑定当前设备到 NasCab 账号（用于 P2P 远程连接）
  Future<ApiResponse<Map<String, dynamic>>> bindP2pDevice() {
    return apiPost<Map<String, dynamic>>(
      '/api/service/nascab/p2p/bindDevice',
      body: {},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  /// 获取购买页临时 code，用于打开 https://nas.cab/user/order?code=xxxx
  Future<ApiResponse<Map<String, dynamic>>> getTempCode() {
    return apiGet<Map<String, dynamic>>(
      '/api/service/nascab/tempCode',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getDdnsStatus() {
    return apiGet<Map<String, dynamic>>(
      '/api/service/ddns/status',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setDdnsDomain({
    required String ddnsDomain,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/ddns/domain',
      body: {
        'ddnsDomain': ddnsDomain,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setDdnsType(String ddnsType) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/ddns/type',
      body: {'ddnsType': ddnsType},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setDdnsEnabled(bool enabled) {
    return apiPost<Map<String, dynamic>>(
      '/api/service/ddns/enabled',
      body: {'enabled': enabled},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }
}
