import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';

class PhotoHomeApiService extends BaseApiService {
  static PhotoHomeApiService get instance =>
      Get.isRegistered<PhotoHomeApiService>()
      ? Get.find<PhotoHomeApiService>()
      : PhotoHomeApiService();

  Future<ApiResponse<int>> getTotalCount({List<String>? sourceList}) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/photo/timeline/count',
      body: {if (sourceList != null) 'sourceList': sourceList},
      showLoading: false,
    );

    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }

    final data = res.data ?? {};
    final rawTotal = data['total'];
    final total = rawTotal is num
        ? rawTotal.toInt()
        : int.tryParse(rawTotal?.toString() ?? '') ?? 0;

    return ApiResponse.success(
      total,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
