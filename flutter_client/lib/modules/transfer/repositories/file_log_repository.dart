import '../../../core/api/base_api_service.dart';
import '../models/file_operation_log.dart';

class FileLogRepository extends BaseApiService {
  Future<ApiResponse<FileLogListResponse>> getFileLogs({
    List<String>? types,
    int page = 1,
    int pageSize = 20,
    List<String>? stateList,
    String? keyword,
  }) {
    return apiPost<FileLogListResponse>(
      '/api/file/log/list',
      body: {
        'types': types,
        'page': page,
        'pageSize': pageSize,
        'stateList': stateList,
        'keyword': keyword,
      },
      dataParser: (data, _) => FileLogListResponse.fromJson(data),
      showLoading:
          false, // Don't show global loading for list fetch, manage locally
    );
  }

  Future<ApiResponse<void>> cancelFileOperation(int id) {
    return apiPost<void>(
      '/api/file/cancel_file_operation',
      body: {'id': id},
      showLoading: true,
    );
  }

  Future<ApiResponse<void>> clearLogs({List<String>? stateList}) {
    return apiPost<void>(
      '/api/file/log/clear',
      body: {'stateList': stateList},
      showLoading: true,
    );
  }
}
