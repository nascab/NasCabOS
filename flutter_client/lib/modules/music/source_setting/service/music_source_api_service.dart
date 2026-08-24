import 'package:get/get.dart';
import '../../../../core/api/base_api_service.dart';
import '../models/music_source.dart';

class MusicSourceApiService extends BaseApiService {
  static MusicSourceApiService get instance =>
      Get.isRegistered<MusicSourceApiService>()
      ? Get.find<MusicSourceApiService>()
      : MusicSourceApiService();

  Future<List<MusicSource>> listSources({bool showLoading = false}) async {
    final res = await apiPost<List<dynamic>>(
      '/api/music/source/list',
      body: {},
      showLoading: showLoading,
    );
    if (!res.success) return <MusicSource>[];

    final raw = res.data ?? <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => MusicSource.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<ApiResponse<Map<String, dynamic>>> addSource(
    String path, {
    bool showLoading = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/music/source/add',
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
      '/api/music/source/update/$id',
      body: payload,
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteSource(
    int id, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/music/source/delete',
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
      '/api/music/source/relocate/$id',
      body: {'new_path': newPath},
      showLoading: showLoading,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> scanSource(
    String path, {
    bool showLoading = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/music/source/scan',
      body: {'path': path},
      showLoading: showLoading,
    );
  }
}
