import 'dart:async';
import 'dart:convert';

import 'package:NasCabOS/core/api/api_controller.dart';
import 'package:NasCabOS/core/api/base_api_service.dart';
import 'package:NasCabOS/core/api/dio_bad_certificate_compat.dart';
import 'package:NasCabOS/core/api/p2p_rtc_stub.dart'
    if (dart.library.html) 'package:NasCabOS/core/api/p2p_rtc_web.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class NotesApiService extends BaseApiService {
  NotesApiService._();

  static final NotesApiService instance = NotesApiService._();

  String get modulePath => '/api/notes';

  Future<ApiResponse<Map<String, dynamic>>> getNotebookStatus() {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/notebook/status',
      showLoading: false,
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> selectNotebook(String folderPath) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/notebook/select',
      body: {'folderPath': folderPath},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getState({
    required String groupId,
    required String keyword,
    required bool includeDeleted,
  }) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/state',
      showLoading: false,
      body: {
        'groupId': groupId,
        'keyword': keyword,
        'includeDeleted': includeDeleted,
      },
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createGroup(String name) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/group/create',
      body: {'name': name},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateGroup({
    required String groupId,
    required String name,
  }) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/group/update',
      body: {'groupId': groupId, 'name': name},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteGroup(String groupId) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/group/delete',
      body: {'groupId': groupId},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> reorderGroups(
    List<String> orderedGroupIds,
  ) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/group/reorder',
      body: {'orderedGroupIds': orderedGroupIds},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> createNote({
    required String groupId,
    String title = '',
  }) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/create',
      body: {'groupId': groupId, 'title': title},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> getNoteDetail(String noteId) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/detail',
      showLoading: false,
      body: {'noteId': noteId},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> saveNote({
    required String noteId,
    required String title,
    required int baseRevision,
    List<dynamic>? deltaPatch,
  }) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/save',
      showLoading: false,
      body: {
        'noteId': noteId,
        'title': title,
        'baseRevision': baseRevision,
        if (deltaPatch != null) 'deltaPatch': deltaPatch,
      },
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateNoteMeta({
    required List<String> noteIds,
    String? title,
    String? tagColor,
    bool? isPinned,
  }) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/meta',
      showLoading: false,
      body: {
        'noteIds': noteIds,
        if (title != null) 'title': title,
        if (tagColor != null) 'tagColor': tagColor,
        if (isPinned != null) 'isPinned': isPinned,
      },
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> moveNote({
    required String noteId,
    required String targetGroupId,
  }) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/move',
      body: {'noteId': noteId, 'targetGroupId': targetGroupId},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<int>> batchMoveNotes({
    required List<String> noteIds,
    required String targetGroupId,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '$modulePath/note/batchMove',
      body: {'noteIds': noteIds, 'targetGroupId': targetGroupId},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final count = (data['movedCount'] is num)
        ? (data['movedCount'] as num).toInt()
        : int.tryParse('${data['movedCount']}') ?? 0;
    return ApiResponse.success(
      count,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> deleteNote(String noteId) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/delete',
      body: {'noteId': noteId},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<int>> batchDeleteNotes(List<String> noteIds) async {
    final res = await apiPost<Map<String, dynamic>>(
      '$modulePath/note/batchDelete',
      body: {'noteIds': noteIds},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final count = (data['deletedCount'] is num)
        ? (data['deletedCount'] as num).toInt()
        : int.tryParse('${data['deletedCount']}') ?? 0;
    return ApiResponse.success(
      count,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> restoreNote(String noteId) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/restore',
      body: {'noteId': noteId},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<int>> batchRestoreNotes(List<String> noteIds) async {
    final res = await apiPost<Map<String, dynamic>>(
      '$modulePath/note/batchRestore',
      body: {'noteIds': noteIds},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final count = (data['restoredCount'] is num)
        ? (data['restoredCount'] as num).toInt()
        : int.tryParse('${data['restoredCount']}') ?? 0;
    return ApiResponse.success(
      count,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> permanentlyDeleteNote(
    String noteId,
  ) {
    return apiPost<Map<String, dynamic>>(
      '$modulePath/note/permanentDelete',
      body: {'noteId': noteId},
      dataParser: (json, _) => Map<String, dynamic>.from(json),
    );
  }

  Future<ApiResponse<int>> batchPermanentlyDeleteNotes(
    List<String> noteIds,
  ) async {
    final res = await apiPost<Map<String, dynamic>>(
      '$modulePath/note/batchPermanentDelete',
      body: {'noteIds': noteIds},
      showLoading: false,
    );
    if (!res.success) {
      return ApiResponse.failure(
        res.message ?? 'network_failure',
        code: res.code,
        rawResponse: res.rawResponse,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final count = (data['deletedCount'] is num)
        ? (data['deletedCount'] as num).toInt()
        : int.tryParse('${data['deletedCount']}') ?? 0;
    return ApiResponse.success(
      count,
      message: res.message,
      code: res.code,
      rawResponse: res.rawResponse,
    );
  }

  Map<String, String>? buildAuthHeaders() {
    final accessToken = (ApiController.instance.accessToken ?? '').trim();
    if (accessToken.isEmpty) return null;
    return <String, String>{'Authorization': 'Bearer $accessToken'};
  }

  String buildAssetUrl({required String noteId, required String assetName}) {
    final params = <String, String>{'noteId': noteId, 'name': assetName};
    return ApiController.instance.buildAuthedApiUrl(
      '$modulePath/note/asset',
      queryParameters: params,
      p2pChannel: 'file',
    );
  }

  String buildExportUrl({required String noteId, required String format}) {
    final ext = format.trim().toLowerCase() == 'markdown'
        ? 'md'
        : format.trim().toLowerCase();
    final params = <String, String>{
      'noteId': noteId,
      'format': format,
      'fileName': 'note.$ext',
    };
    return ApiController.instance.buildAuthedApiUrl(
      '$modulePath/note/export',
      queryParameters: params,
    );
  }

  Future<String> uploadAsset({
    required String noteId,
    required PlatformFile file,
  }) async {
    final base = ApiController.instance.baseUrl;
    final filePath = file.path?.trim() ?? '';
    final fileName = file.name.trim().isEmpty
        ? p.basename(filePath.isEmpty ? 'asset.bin' : filePath)
        : file.name.trim();
    if (file.bytes == null && filePath.isEmpty) {
      throw Exception('upload_failed'.tr);
    }
    if (base.trim() == ApiController.p2pBaseUrl) {
      final bytes =
          file.bytes ?? await XFile(filePath, name: fileName).readAsBytes();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$base$modulePath/note/uploadAsset'),
      );
      req.headers['authorization'] =
          'Bearer ${ApiController.instance.accessToken ?? ''}';
      req.fields['noteId'] = noteId;
      req.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
      final neverCompletes = Completer<void>();
      final streamed = await ApiController.instance.sendP2pRequestOnChannel(
        req,
        timeout: const Duration(minutes: 2),
        channel: P2pRtcChannel.upload,
        cancelFuture: neverCompletes.future,
      );
      final bodyBytes = await http.ByteStream(streamed.stream).toBytes();
      final body = _decodeJsonMap(utf8.decode(bodyBytes, allowMalformed: true));
      final success = body['success'] == true || body['success'] == 'true';
      if (!success || streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final message = body['message']?.toString() ?? 'operation_failed'.tr;
        throw Exception(message);
      }
      final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
      final assetName = data['assetName']?.toString() ?? '';
      if (assetName.isEmpty) {
        throw Exception('operation_failed'.tr);
      }
      return buildAssetUrl(noteId: noteId, assetName: assetName);
    }
    final uploader = createDioWithBadCertificateCompat();
    final multipart = file.bytes != null
        ? dio.MultipartFile.fromBytes(file.bytes!, filename: fileName)
        : await dio.MultipartFile.fromFile(filePath, filename: fileName);
    final form = dio.FormData.fromMap({'noteId': noteId, 'file': multipart});
    final resp = await uploader.post(
      '$base$modulePath/note/uploadAsset',
      data: form,
      options: dio.Options(
        contentType: 'multipart/form-data',
        headers: buildAuthHeaders(),
        validateStatus: (_) => true,
      ),
    );
    final body = resp.data is Map<String, dynamic>
        ? resp.data as Map<String, dynamic>
        : _decodeJsonMap(jsonEncode(resp.data));
    final success = body['success'] == true || body['success'] == 'true';
    if (!success) {
      final message = body['message']?.toString() ?? 'operation_failed'.tr;
      throw Exception(message);
    }
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    final assetName = data['assetName']?.toString() ?? '';
    if (assetName.isEmpty) {
      throw Exception('operation_failed'.tr);
    }
    return buildAssetUrl(noteId: noteId, assetName: assetName);
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw Exception('operation_failed'.tr);
  }

  String normalizeEmbedForSave({
    required String noteId,
    required String value,
  }) {
    final trimmed = value.trim();
    if (trimmed.startsWith('assets/')) return trimmed;
    final uri = Uri.tryParse(trimmed);
    final assetName = uri?.queryParameters['name']?.trim() ?? '';
    final requestNoteId = uri?.queryParameters['noteId']?.trim() ?? '';
    if (assetName.isNotEmpty && requestNoteId == noteId) {
      return 'assets/$assetName';
    }
    return trimmed;
  }

  String expandEmbedForEditor({required String noteId, required String value}) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('assets/')) return trimmed;
    return buildAssetUrl(
      noteId: noteId,
      assetName: trimmed.replaceFirst('assets/', ''),
    );
  }
}
