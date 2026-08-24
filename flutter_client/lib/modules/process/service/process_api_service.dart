import 'package:get/get.dart';

import '../../../core/api/base_api_service.dart';
import '../models/worker_process_item.dart';

class ProcessApiService extends BaseApiService {
  Future<ApiResponse<List<WorkerProcessItem>>> fetchWorkerProcessList() async {
    final res = await apiGet<dynamic>(
      '/api/service/process',
      showLoading: false,
      timeout: const Duration(seconds: 15),
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure'.tr,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final raw = res.data;
    if (raw is! List) {
      return ApiResponse.success(
        [],
        message: res.message,
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final list = raw
        .whereType<Map>()
        .map((e) => WorkerProcessItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return ApiResponse.success(
      list,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }
}
