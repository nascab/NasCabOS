import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

class TransmissionApiService extends BaseApiService {
  static TransmissionApiService get instance =>
      Get.isRegistered<TransmissionApiService>()
          ? Get.find<TransmissionApiService>()
          : TransmissionApiService();

  Future<ApiResponse<Map<String, dynamic>>> getStatus() {
    return apiGet<Map<String, dynamic>>(
      '/api/transmission/status',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getConfig() {
    return apiGet<Map<String, dynamic>>(
      '/api/transmission/config',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> saveConfig(Map<String, dynamic> body) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/config/save',
      body: body,
      dataParser: (json, code) => json,
      showLoading: false,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setRpcPort(int port) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/config/ports',
      body: {'rpc_port': port},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> startService() {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/start',
      body: const <String, dynamic>{},
      dataParser: (json, code) => json,
      timeout: const Duration(seconds: 30),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stopService() {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/stop',
      body: const <String, dynamic>{},
      dataParser: (json, code) => json,
      timeout: const Duration(seconds: 20),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> restartService() {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/restart',
      body: const <String, dynamic>{},
      dataParser: (json, code) => json,
      timeout: const Duration(seconds: 30),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getSession() {
    return apiGet<Map<String, dynamic>>(
      '/api/transmission/session',
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> listTorrents({
    List<int>? ids,
    List<String>? fields,
  }) {
    final query = <String, String>{};
    if (ids != null && ids.isNotEmpty) {
      query['ids'] = ids.join(',');
    }
    if (fields != null && fields.isNotEmpty) {
      query['fields'] = fields.join(',');
    }
    return apiGet<Map<String, dynamic>>(
      '/api/transmission/torrents/list',
      queryParams: query.isEmpty ? null : query,
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> addTorrent({
    String? url,
    String? metainfo,
    String? filename,
    String? downloadDir,
    bool paused = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/torrents/add',
      body: {
        if (url != null) 'url': url,
        if (metainfo != null) 'metainfo': metainfo,
        if (filename != null) 'filename': filename,
        if (downloadDir != null && downloadDir.isNotEmpty) 'download_dir': downloadDir,
        'paused': paused,
      },
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setTorrentLocation({
    required List<int> ids,
    required String location,
    bool move = true,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/torrents/set-location',
      body: {
        'ids': ids,
        'location': location,
        'move': move,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> startTorrents(List<int> ids) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/torrents/start',
      body: {'ids': ids},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> stopTorrents(List<int> ids) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/torrents/stop',
      body: {'ids': ids},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> removeTorrents(
    List<int> ids, {
    bool deleteLocalData = false,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/torrents/remove',
      body: {'ids': ids, 'deleteLocalData': deleteLocalData},
      dataParser: (json, code) => json,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getTorrentFiles(int id) {
    return apiGet<Map<String, dynamic>>(
      '/api/transmission/torrents/files',
      queryParams: {'id': '$id'},
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> setTorrentFiles({
    required int id,
    List<int>? filesWanted,
    List<int>? filesUnwanted,
  }) {
    return apiPost<Map<String, dynamic>>(
      '/api/transmission/torrents/files/set',
      body: {
        'id': id,
        if (filesWanted != null && filesWanted.isNotEmpty) 'files_wanted': filesWanted,
        if (filesUnwanted != null && filesUnwanted.isNotEmpty) 'files_unwanted': filesUnwanted,
      },
      dataParser: (json, code) => json,
      showLoading: false,
    );
  }
}
