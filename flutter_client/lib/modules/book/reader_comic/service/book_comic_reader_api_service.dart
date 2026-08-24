import 'package:get/get.dart';
import '../../../../core/api/api_controller.dart';
import '../../../../core/api/base_api_service.dart';

class BookComicReaderApiService extends BaseApiService {
  static BookComicReaderApiService get instance =>
      Get.isRegistered<BookComicReaderApiService>()
      ? Get.find<BookComicReaderApiService>()
      : BookComicReaderApiService();

  Future<Map<String, dynamic>?> getProgress({
    required String fileHash,
    bool showLoading = false,
  }) async {
    final fh = fileHash.trim();
    if (fh.isEmpty) return null;

    final res = await apiGet<Map<String, dynamic>>(
      '/api/book/history',
      queryParams: {'file_hash': fh},
      showLoading: showLoading,
    );
    if (!res.success) return null;
    return res.data;
  }

  Future<Map<String, dynamic>?> upsertProgress({
    required String fileHash,
    required int currentPage,
    required int totalPage,
    bool showLoading = false,
  }) async {
    final fh = fileHash.trim();
    if (fh.isEmpty) return null;

    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/history',
      body: {
        'file_hash': fh,
        'current_page': currentPage,
        'total_page': totalPage,
      },
      showLoading: showLoading,
    );
    if (!res.success) return null;
    return res.data;
  }

  Future<List<Map<String, dynamic>>> listArchiveImages({
    required String fileHash,
    bool onlyImg = true,
    bool showLoading = false,
  }) async {
    final fh = fileHash.trim();
    if (fh.isEmpty) return <Map<String, dynamic>>[];

    final res = await apiPost<Map<String, dynamic>>(
      '/api/book/archive/list',
      body: {'file_hash': fh, 'only_img': onlyImg},
      showLoading: showLoading,
    );
    if (!res.success) return <Map<String, dynamic>>[];

    final raw = res.data;
    final items = raw == null ? null : raw['items'];
    if (items is! List) return <Map<String, dynamic>>[];

    final out = <Map<String, dynamic>>[];
    for (final it in items) {
      if (it is! Map) continue;
      final m = it.cast<String, dynamic>();
      final innerPath = (m['path'] ?? '').toString();
      if (innerPath.trim().isEmpty) continue;
      out.add({
        ...m,
        'url': buildArchiveFileUrl(fileHash: fh, innerPath: innerPath),
      });
    }
    return out;
  }

  String buildArchiveFileUrl({
    required String fileHash,
    required String innerPath,
  }) {
    final fh = fileHash.trim();
    final ip = innerPath;
    final token = ApiController.instance.accessToken;

    final qp = <String, String>{
      'file_hash': fh,
      'inner_path': ip,
      if (token != null && token.trim().isNotEmpty) 'accessToken': token.trim(),
    };

    final uri = Uri.parse(
      '${ApiController.instance.baseUrl}/api/book/archive/file',
    ).replace(queryParameters: qp);
    return uri.toString();
  }
}
