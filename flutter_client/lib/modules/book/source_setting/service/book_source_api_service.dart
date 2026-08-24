import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/book_source.dart';

class BookSourceApiService extends BaseApiService {
  static BookSourceApiService get instance =>
      Get.isRegistered<BookSourceApiService>()
      ? Get.find<BookSourceApiService>()
      : BookSourceApiService();

  Future<List<BookSource>> listSources({bool showLoading = false}) async {
    final res = await apiPost<List<dynamic>>(
      '/api/book/source/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return <BookSource>[];

    final raw = res.data ?? <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => BookSource.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ApiResponse<Map<String, dynamic>>> addSource(
    String path, {
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/source/add',
      body: {'path': path},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateSource(
    int id,
    Map<String, dynamic> payload, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/source/update/$id',
      body: payload,
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSource(
    int id, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/source/delete',
      body: {'id': id},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> relocateSource(
    int id,
    String newPath, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/source/relocate/$id',
      body: {'new_path': newPath},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> scanSource(
    String path, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/book/source/scan',
      body: {'path': path},
      showLoading: showLoading,
    );
  }
}
