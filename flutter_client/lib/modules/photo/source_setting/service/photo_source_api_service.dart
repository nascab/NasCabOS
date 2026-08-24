import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/photo_source.dart';

class PhotoSourceApiService extends BaseApiService {
  static PhotoSourceApiService get instance =>
      Get.isRegistered<PhotoSourceApiService>()
      ? Get.find<PhotoSourceApiService>()
      : PhotoSourceApiService();

  Future<List<PhotoSource>> listSources({bool showLoading = false}) async {
    final res = await apiPost<List<dynamic>>(
      '/api/photo/source/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return <PhotoSource>[];

    final raw = res.data ?? <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => PhotoSource.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ApiResponse<Map<String, dynamic>>> addSource(
    String path, {
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/source/add',
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
      '/api/photo/source/update/$id',
      body: payload,
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSource(
    int id, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/source/delete',
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
      '/api/photo/source/relocate/$id',
      body: {'new_path': newPath},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> scanSource(
    String path, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/source/scan',
      body: {'path': path},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> preGenerateThumbnails({
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/photo/source/regenerate_thumbnails',
      body: {},
      showLoading: showLoading,
    );
  }
}
