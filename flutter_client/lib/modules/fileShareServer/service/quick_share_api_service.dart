import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class QuickShareApiService extends BaseApiService {
  static QuickShareApiService get instance =>
      Get.isRegistered<QuickShareApiService>()
      ? Get.find<QuickShareApiService>()
      : QuickShareApiService();

  Future<ApiResponse<Map<String, dynamic>>> list() {
    return apiGet<Map<String, dynamic>>(
      '/api/quickShare/list',
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> create({
    required String path,
    String? pwd,
    String? remark,
    int? durationValue,
    String? durationUnit,
    bool? noLimit,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/quickShare/create',
      body: {
        'path': path,
        if (pwd != null) 'pwd': pwd,
        if (remark != null) 'remark': remark,
        if (durationValue != null) 'durationValue': durationValue,
        if (durationUnit != null) 'durationUnit': durationUnit,
        if (noLimit != null) 'noLimit': noLimit,
      },
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> delete({required int id}) {
    return apiPost<Map<String, dynamic>>(
      '/api/quickShare/delete',
      body: {'id': id},
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> cleanExpired() {
    return apiPost<Map<String, dynamic>>('/api/quickShare/cleanExpired');
  }
}
