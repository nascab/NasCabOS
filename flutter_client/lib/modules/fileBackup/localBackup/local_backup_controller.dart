import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../core/api/api_controller.dart';
import '../../../core/api/dio_bad_certificate_compat.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';
import '../../transfer/controllers/upload_parts/upload_core.dart';
import '../../transfer/controllers/upload_parts/upload_transfer_helper.dart';
import 'local_backup_storage.dart';

class LocalBackupRuntime {
  final RxString status = 'idle'.obs;
  final RxString lastError = ''.obs;
  final RxInt lastRunAtMs = 0.obs;
  final RxInt lastSuccessAtMs = 0.obs;

  final RxInt totalFiles = 0.obs;
  final RxInt processedFiles = 0.obs;
  final RxInt totalBytes = 0.obs;
  final RxInt processedBytes = 0.obs;
  final RxString currentRelPath = ''.obs;

  final RxBool busy = false.obs;

  double get progress {
    final total = totalBytes.value;
    if (total <= 0) return 0;
    final done = processedBytes.value;
    if (done <= 0) return 0;
    if (done >= total) return 1;
    return done / total;
  }
}

class LocalBackupCleanupEntry {
  final String serverPath;
  final String relPath;
  final bool isDir;

  const LocalBackupCleanupEntry({
    required this.serverPath,
    required this.relPath,
    required this.isDir,
  });
}

class LocalBackupCleanupProgress {
  final String currentServerDir;
  final int scannedDirs;
  final int scannedItems;
  final int orphanedFound;

  const LocalBackupCleanupProgress({
    required this.currentServerDir,
    required this.scannedDirs,
    required this.scannedItems,
    required this.orphanedFound,
  });
}

class LocalBackupCleanupCancelled implements Exception {
  @override
  String toString() => 'cancelled';
}

class _LocalExistence {
  final Set<String> files;
  final Set<String> dirs;

  const _LocalExistence({required this.files, required this.dirs});
}

class LocalBackupController extends GetxController {
  final _storage = LocalBackupStorage.instance;

  final RxList<LocalBackupProfile> profiles = <LocalBackupProfile>[].obs;
  final RxBool isLoading = false.obs;

  final Map<int, LocalBackupRuntime> _runtimeById = {};

  final Map<int, Timer> _intervalTimers = {};
  final Map<int, StreamSubscription<FileSystemEvent>> _watchSubs = {};
  final Map<int, Timer> _debounceTimers = {};
  final Map<int, bool> _queuedAfterRun = {};
  final Map<int, int> _macosSourceAccessHandleByProfile = {};

  late dio.Dio _dio;
  final Map<int, dio.CancelToken> _cancelTokenByProfile = {};
  final Map<int, dio.CancelToken> _cleanupCancelTokenByProfile = {};

  static const int _realtimeDebounceSeconds = 30;
  static const int _maxUploadLogs = 3000;
  static const Duration _stableFilePollInterval = Duration(milliseconds: 350);
  static const Duration _stableFileWindow = Duration(seconds: 2);
  static const Duration _stableFileTimeout = Duration(seconds: 60);
  static const Duration _unstableRetryBudget = Duration(minutes: 30);
  static const Duration _unstableRetryIdleDelay = Duration(milliseconds: 500);
  static const int _md5ThresholdBytes = 50 * 1024 * 1024;
  static const int _md5ChunkSizeBytes = 1024 * 1024;

  void _logBackup(int profileId, String message) {
    print('[LocalBackup][$profileId] $message');
  }

  static Future<FileStat?> waitForStableFileStat(
    String filePath, {
    Duration pollInterval = _stableFilePollInterval,
    Duration stableWindow = _stableFileWindow,
    Duration timeout = _stableFileTimeout,
    dio.CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (pollInterval <= Duration.zero) return null;
    if (stableWindow <= Duration.zero) return null;
    if (timeout <= Duration.zero) return null;

    int stableMs = 0;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    FileStat? prev;

    while (true) {
      if (cancelToken?.isCancelled == true) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - startedAt > timeout.inMilliseconds) return null;

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      if (stat.size <= 0) return null;

      if (prev != null &&
          prev.size == stat.size &&
          prev.modified == stat.modified) {
        stableMs += pollInterval.inMilliseconds;
        if (stableMs >= stableWindow.inMilliseconds) return stat;
      } else {
        stableMs = 0;
        prev = stat;
      }

      await Future<void>.delayed(pollInterval);
    }
  }

  static Future<FileStat?> tryGetStableFileStatOnce(
    String filePath, {
    Duration settleDelay = const Duration(milliseconds: 350),
    dio.CancelToken? cancelToken,
  }) async {
    if (settleDelay <= Duration.zero) return null;
    final file = File(filePath);
    final a = await file.stat();
    if (a.type != FileSystemEntityType.file) return null;
    if (a.size <= 0) return null;
    await Future<void>.delayed(settleDelay);
    if (cancelToken?.isCancelled == true) {
      throw dio.DioException(
        requestOptions: dio.RequestOptions(path: ''),
        type: dio.DioExceptionType.cancel,
      );
    }
    final b = await file.stat();
    if (b.type != FileSystemEntityType.file) return null;
    if (b.size <= 0) return null;
    if (a.size != b.size) return null;
    if (a.modified != b.modified) return null;
    return b;
  }

  bool get _isP2pMode => ApiController.instance.baseUrl.trim() == ApiController.p2pBaseUrl;

  void _throwIfCancelled(dio.CancelToken? cancelToken) {
    if (cancelToken?.isCancelled == true) {
      throw dio.DioException(
        requestOptions: dio.RequestOptions(path: ''),
        type: dio.DioExceptionType.cancel,
      );
    }
  }

  bool _isAuthError(dynamic e) {
    if (e is dio.DioException) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return true;
    }
    final msg = UploadTransferHelper.getServerMessage(e).toLowerCase();
    return msg.contains('unauthorized') ||
        msg.contains('token') && msg.contains('expir');
  }

  Future<String> _resolveAccessToken({bool forceRefresh = false}) async {
    final api = ApiController.instance;
    if (forceRefresh || api.isTokenExpiringSoon) {
      await api.refreshAuthToken();
    }
    final token = api.accessToken?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('network_failure'.tr);
    }
    return token;
  }

  Map<String, String> _stringQuery(Map<String, dynamic>? queryParameters) {
    final out = <String, String>{};
    if (queryParameters == null || queryParameters.isEmpty) return out;
    queryParameters.forEach((k, v) {
      if (v == null) return;
      out[k] = v.toString();
    });
    return out;
  }

  Future<Map<String, dynamic>> _requestJsonGet(
    String path, {
    Map<String, dynamic>? queryParameters,
    dio.CancelToken? cancelToken,
    bool retriedAuth = false,
  }) async {
    final baseUrl = ApiController.instance.baseUrl;
    final token = await _resolveAccessToken();
    _throwIfCancelled(cancelToken);

    try {
      if (_isP2pMode) {
        final uri = Uri.parse('$baseUrl$path').replace(
          queryParameters: _stringQuery(queryParameters),
        );
        final req = http.Request('GET', uri);
        req.headers['authorization'] = 'Bearer $token';
        req.headers['accept'] = 'application/json';
        final streamed = await ApiController.instance.sendP2pRequest(
          req,
          timeout: const Duration(minutes: 5),
          cancelFuture: cancelToken?.whenCancel,
        );
        final bytes = await http.ByteStream(streamed.stream).toBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw Exception('invalid_response');
      }

      final res = await _dio.get(
        '$baseUrl$path',
        queryParameters: queryParameters,
        options: dio.Options(headers: {'Authorization': 'Bearer $token'}),
        cancelToken: cancelToken,
      );
      final body = res.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      return <String, dynamic>{};
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: path),
          type: dio.DioExceptionType.cancel,
          error: e,
        );
      }
      if (!retriedAuth && _isAuthError(e)) {
        final refreshed = await ApiController.instance.refreshAuthToken();
        if (refreshed) {
          return _requestJsonGet(
            path,
            queryParameters: queryParameters,
            cancelToken: cancelToken,
            retriedAuth: true,
          );
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _requestJsonPost(
    String path, {
    Map<String, dynamic>? data,
    dio.CancelToken? cancelToken,
    bool retriedAuth = false,
  }) async {
    final baseUrl = ApiController.instance.baseUrl;
    final token = await _resolveAccessToken();
    _throwIfCancelled(cancelToken);

    try {
      if (_isP2pMode) {
        final uri = Uri.parse('$baseUrl$path');
        final req = http.Request('POST', uri);
        req.headers['authorization'] = 'Bearer $token';
        req.headers['content-type'] = 'application/json; charset=utf-8';
        req.headers['accept'] = 'application/json';
        req.body = jsonEncode(data ?? const <String, dynamic>{});
        final streamed = await ApiController.instance.sendP2pRequest(
          req,
          timeout: const Duration(minutes: 5),
          cancelFuture: cancelToken?.whenCancel,
        );
        final bytes = await http.ByteStream(streamed.stream).toBytes();
        final text = utf8.decode(bytes, allowMalformed: true);
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw Exception('invalid_response');
      }

      final res = await _dio.post(
        '$baseUrl$path',
        data: data,
        options: dio.Options(headers: {'Authorization': 'Bearer $token'}),
        cancelToken: cancelToken,
      );
      final body = res.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      return <String, dynamic>{};
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: path),
          type: dio.DioExceptionType.cancel,
          error: e,
        );
      }
      if (!retriedAuth && _isAuthError(e)) {
        final refreshed = await ApiController.instance.refreshAuthToken();
        if (refreshed) {
          return _requestJsonPost(
            path,
            data: data,
            cancelToken: cancelToken,
            retriedAuth: true,
          );
        }
      }
      rethrow;
    }
  }

  @override
  void onInit() {
    super.onInit();
    _dio = createDioWithBadCertificateCompat(
      dio.BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    refreshProfiles();
  }

  @override
  void onClose() {
    for (final t in _intervalTimers.values) {
      t.cancel();
    }
    _intervalTimers.clear();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    for (final s in _watchSubs.values) {
      s.cancel();
    }
    _watchSubs.clear();
    for (final h in _macosSourceAccessHandleByProfile.values) {
      MacOSFileAccess.stopAccessing(h);
    }
    _macosSourceAccessHandleByProfile.clear();
    for (final c in _cancelTokenByProfile.values) {
      if (!c.isCancelled) c.cancel();
    }
    _cancelTokenByProfile.clear();
    super.onClose();
  }

  LocalBackupRuntime runtimeOf(int profileId) {
    return _runtimeById.putIfAbsent(profileId, () => LocalBackupRuntime());
  }

  /// 当前应使用的 serverId（与任务执行、调度校验一致）
  String get _currentServerId => ApiController.instance.state.serverId.trim();

  /// 供 UI 判断任务是否属于当前服务器，非当前服务器的任务不可运行/编辑
  String get currentServerId => _currentServerId;

  Future<void> refreshProfiles() async {
    isLoading.value = true;
    try {
      final list = await _storage.listProfiles();
      profiles.assignAll(list);
      for (final p in list) {
        final rt = runtimeOf(p.id);
        if (rt.busy.value) continue;
        rt.lastRunAtMs.value = p.lastRunAtMs;
        rt.lastSuccessAtMs.value = p.lastSuccessAtMs;
      }
      _syncSchedules();
    } finally {
      isLoading.value = false;
    }
  }

  /// 桌面端本机 hostname（用于判断是否与服务端同机）
  static Future<String?> getLocalHostname() async {
    if (!DeviceUtils.isDesktop) return null;
    try {
      final result = await Process.run('hostname', [], runInShell: true);
      if (result.exitCode == 0 && result.stdout != null) {
        final name = (result.stdout as String).trim();
        return name.isEmpty ? null : name;
      }
    } catch (_) {}
    return null;
  }

  /// 判断两条路径是否相同或互相包含（用于同机备份时避免无限循环）
  static bool _isMutualConflictPath(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final sep = DeviceUtils.isWindows ? '\\' : '/';
    if (a.length < b.length) {
      return b == a || b.startsWith('$a$sep');
    }
    if (b.length < a.length) {
      return a == b || a.startsWith('$b$sep');
    }
    return false;
  }

  Future<bool> upsertProfile({
    int? id,
    required String name,
    required String sourceDir,
    String? sourceBookmark,
    required String targetDir,
    required List<String> excludeItems,
    required bool realtime,
    required int intervalMinutes,
    required int debounceSeconds,
    required String nameStrategy,
    required bool enabled,
  }) async {
    final s = sourceDir.trim();
    final t = targetDir.trim();
    if (s.isEmpty || t.isEmpty) {
      ToastUtil.show('local_backup_required'.tr);
      return false;
    }
    if (!realtime && intervalMinutes <= 0) {
      ToastUtil.show('local_backup_frequency_invalid'.tr);
      return false;
    }

    String normalizeLocalPath(String v) {
      var x = v.trim();
      if (x.isEmpty) return x;
      x = p.normalize(x);
      while (x.length > 1 && (x.endsWith('/') || x.endsWith('\\'))) {
        x = x.substring(0, x.length - 1);
      }
      if (DeviceUtils.isWindows) x = x.toLowerCase();
      return x;
    }

    String normalizeServerPath(String v) {
      var x = v.trim();
      if (x.isEmpty) return x;
      x = x.replaceAll('\\', '/');
      x = x.replaceAll(RegExp('/+'), '/');
      while (x.length > 1 && x.endsWith('/')) {
        x = x.substring(0, x.length - 1);
      }
      return x;
    }

    final existingList = profiles.isNotEmpty
        ? profiles.toList()
        : await _storage.listProfiles();
    final sourceKey = normalizeLocalPath(s);
    final targetKey = normalizeServerPath(t);
    final currentId = id ?? 0;
    final curServerId = _currentServerId;
    final dup = existingList.firstWhereOrNull((e) {
      if (currentId > 0 && e.id == currentId) return false;
      if (e.serverId != curServerId) return false;
      return normalizeLocalPath(e.sourceDir) == sourceKey &&
          normalizeServerPath(e.targetDir) == targetKey;
    });
    if (dup != null) {
      ToastUtil.show('local_backup_duplicate'.tr);
      return false;
    }

    // 桌面端与服务端同机时，源目录与目标目录不能相同或互相包含，否则会导致无限循环备份；hostname 获取失败或异常时跳过检查
    if (DeviceUtils.isDesktop) {
      try {
        final localHost = await getLocalHostname();
        final serverHost = ApiController.instance.serverHostname?.trim() ?? '';
        if (localHost != null &&
            localHost.isNotEmpty &&
            serverHost.isNotEmpty &&
            localHost.toLowerCase() == serverHost.toLowerCase()) {
          final targetNormForConflict = normalizeLocalPath(t);
          if (targetNormForConflict.isNotEmpty &&
              _isMutualConflictPath(sourceKey, targetNormForConflict)) {
            ToastUtil.show('invalid_path_relation'.tr);
            return false;
          }
        }
      } catch (e) {
        print(e);
        // hostname 或同机判断异常时跳过检查，允许创建
      }
    }

    final nextName = name.trim().isEmpty ? p.basename(s) : name.trim();
    final bookmark = sourceBookmark?.trim() ?? '';
    if (DeviceUtils.isMacOS && bookmark.isEmpty) {
      ToastUtil.show('local_backup_permission_need_reselect'.tr);
      return false;
    }
    final serverId = _currentServerId;
    final exclude = <String>[];
    for (final e in excludeItems) {
      final v = e.trim();
      if (v.isNotEmpty) exclude.add(v);
    }
    final effectiveDebounceSeconds = realtime
        ? _realtimeDebounceSeconds
        : debounceSeconds;
    await _storage.upsertProfile(
      id: id,
      name: nextName,
      sourceDir: s,
      sourceBookmark: bookmark,
      targetDir: t,
      excludeItems: exclude,
      realtime: realtime,
      intervalMinutes: intervalMinutes,
      debounceSeconds: effectiveDebounceSeconds,
      nameStrategy: nameStrategy,
      enabled: enabled,
      serverId: serverId,
    );
    await refreshProfiles();
    return true;
  }

  Future<Map<String, Object?>?> checkTargetDirFsAccess(String targetDir) async {
    final dir = targetDir.trim();
    if (dir.isEmpty) return null;

    final token = ApiController.instance.accessToken;
    if (token == null || token.trim().isEmpty) return null;

    try {
      final body = await _requestJsonGet(
        '/api/file/fs-access',
        queryParameters: {'path': dir},
      );
      final data = body['data'];
      if (data is! Map) return null;
      return <String, Object?>{
        'canRead': data['canRead'] == true,
        'canWrite': data['canWrite'] == true,
        'exists': data['exists'] == true,
        'isDirectory': data['isDirectory'] == true,
        'isProtected': data['isProtected'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  void stopBackup(int profileId) {
    _queuedAfterRun.remove(profileId);
    final c = _cancelTokenByProfile[profileId];
    if (c != null && !c.isCancelled) c.cancel();
  }

  /// 登出或切换服务器前调用：停止所有进行中的本机备份上传。
  void stopAllRunningBackups() {
    for (final p in profiles) {
      if (runtimeOf(p.id).busy.value) {
        stopBackup(p.id);
      }
    }
  }

  void cancelCleanup(int profileId) {
    final c = _cleanupCancelTokenByProfile[profileId];
    if (c != null && !c.isCancelled) c.cancel();
  }

  Future<List<LocalBackupCleanupEntry>> detectCleanupDiff(
    LocalBackupProfile profile, {
    bool includeHidden = false,
    void Function(LocalBackupCleanupProgress progress)? onProgress,
  }) async {
    final profileId = profile.id;
    cancelCleanup(profileId);
    final cancelToken = dio.CancelToken();
    _cleanupCancelTokenByProfile[profileId] = cancelToken;

    try {
      final local = await _withMacOSSourceAccess(
        profile,
        () => _collectLocalExistence(profile, cancelToken: cancelToken),
      );
      final serverBaseDir = await _resolveBackupRootServerDir(
        profile,
        cancelToken: cancelToken,
      );
      if (serverBaseDir == null || serverBaseDir.trim().isEmpty) {
        return const <LocalBackupCleanupEntry>[];
      }
      final result = await _scanServerOrphans(
        serverBaseDir,
        local,
        includeHidden: includeHidden,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      result.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.relPath.compareTo(b.relPath);
      });
      return result;
    } on dio.DioException catch (e) {
      if (e.type == dio.DioExceptionType.cancel) {
        throw LocalBackupCleanupCancelled();
      }
      rethrow;
    } finally {
      _cleanupCancelTokenByProfile.remove(profileId);
    }
  }

  Future<String?> _resolveBackupRootServerDir(
    LocalBackupProfile profile, {
    required dio.CancelToken cancelToken,
  }) async {
    final sourceDir = profile.sourceDir.trim();
    if (sourceDir.isEmpty) return null;
    final rootName = p.basename(sourceDir).trim();
    if (rootName.isEmpty) return null;

    final token = ApiController.instance.accessToken;
    if (token == null || token.trim().isEmpty) return null;

    final body = await _requestJsonGet(
      '/api/file/attributes/resolve',
      queryParameters: {
        'targetDir': profile.targetDir,
        'relativePath': rootName,
      },
      cancelToken: cancelToken,
    );
    final data = body['data'];
    final map = data is Map ? data.cast<String, dynamic>() : const {};

    final exists = map['exists'] == true;
    final isDir = map['isDirectory'] == true;
    final isFile = map['isFile'] == true;
    final pathRaw = map['path'];
    final pathStr = pathRaw is String ? pathRaw.trim() : '';

    if (!exists) return null;
    if (isFile) {
      throw Exception('目标路径不是目录，无法检测差异');
    }
    if (!isDir) return null;
    if (pathStr.isEmpty) return null;
    return _normalizeServerPath(pathStr);
  }

  Future<bool> deleteServerEntries(
    List<String> paths, {
    required bool recycle,
  }) async {
    final token = ApiController.instance.accessToken;
    if (token == null || token.trim().isEmpty) return false;
    final targets =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toList()..sort();
    if (targets.isEmpty) return false;

    try {
      final body = await _requestJsonPost(
        '/api/file/delete',
        data: {'paths': targets, 'recycle': recycle},
      );
      final map = body;
      final ok = map['success'] == true || map['code'] == 0;
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteProfile(int id) async {
    _stopScheduleFor(id);
    _cancelTokenByProfile[id]?.cancel();
    _cancelTokenByProfile.remove(id);
    await _storage.deleteProfile(id);
    profiles.removeWhere((e) => e.id == id);
  }

  Future<Map<String, dynamic>> _listServerDirectoryByDio(
    String path, {
    required bool onlyDir,
    required bool includeHidden,
    required dio.CancelToken cancelToken,
  }) async {
    final p0 = path.trim();
    final token = ApiController.instance.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw Exception('network_failure'.tr);
    }

    final body = await _requestJsonPost(
      '/api/file/list',
      data: {
        'path': p0,
        'onlyDir': onlyDir ? 'true' : 'false',
        'includeHidden': includeHidden ? 'true' : 'false',
      },
      cancelToken: cancelToken,
    );
    final map = body;
    final ok = map['success'] == true || map['code'] == 0;
    if (!ok) {
      final msg = map['message']?.toString().trim();
      throw Exception(msg == null || msg.isEmpty ? 'operation_failed'.tr : msg);
    }
    final data = map['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  static String _normalizeServerPath(String v) {
    var x = v.trim();
    if (x.isEmpty) return x;
    x = x.replaceAll('\\', '/');
    x = x.replaceAll(RegExp('/+'), '/');
    while (x.length > 1 && x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  static String _serverRelPath(String base, String full) {
    final b = _normalizeServerPath(base);
    final f = _normalizeServerPath(full);
    if (b.isEmpty) return f;
    if (f == b) return '';
    final prefix = '$b/';
    if (!f.startsWith(prefix)) return '';
    return f.substring(prefix.length);
  }

  Future<List<LocalBackupCleanupEntry>> _scanServerOrphans(
    String serverBaseDir,
    _LocalExistence local, {
    required bool includeHidden,
    required dio.CancelToken cancelToken,
    void Function(LocalBackupCleanupProgress progress)? onProgress,
  }) async {
    final base = _normalizeServerPath(serverBaseDir);
    final q = Queue<String>()..add(base);

    var scannedDirs = 0;
    var scannedItems = 0;
    var orphanedFound = 0;
    final out = <LocalBackupCleanupEntry>[];

    while (q.isNotEmpty) {
      if (cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }

      final dir = q.removeFirst();
      onProgress?.call(
        LocalBackupCleanupProgress(
          currentServerDir: dir,
          scannedDirs: scannedDirs,
          scannedItems: scannedItems,
          orphanedFound: orphanedFound,
        ),
      );

      final res = await _listServerDirectoryByDio(
        dir,
        onlyDir: false,
        includeHidden: includeHidden,
        cancelToken: cancelToken,
      );

      scannedDirs += 1;
      final items = (res['items'] as List?) ?? const [];
      for (final raw in items) {
        if (cancelToken.isCancelled) {
          throw dio.DioException(
            requestOptions: dio.RequestOptions(path: ''),
            type: dio.DioExceptionType.cancel,
          );
        }

        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final fullPath = item['path']?.toString().trim() ?? '';
        if (fullPath.isEmpty) continue;
        final type = item['type']?.toString().trim().toLowerCase() ?? '';
        final isDir = type == 'dir';

        final rel = _serverRelPath(base, fullPath);
        if (rel.isEmpty) continue;
        final relKey = DeviceUtils.isWindows ? rel.toLowerCase() : rel;

        scannedItems += 1;
        if (isDir) {
          final exists = local.dirs.contains(relKey);
          if (!exists) {
            orphanedFound += 1;
            out.add(
              LocalBackupCleanupEntry(
                serverPath: _normalizeServerPath(fullPath),
                relPath: rel,
                isDir: true,
              ),
            );
          } else {
            q.add(_normalizeServerPath(fullPath));
          }
        } else {
          final exists = local.files.contains(relKey);
          if (!exists) {
            orphanedFound += 1;
            out.add(
              LocalBackupCleanupEntry(
                serverPath: _normalizeServerPath(fullPath),
                relPath: rel,
                isDir: false,
              ),
            );
          }
        }
      }
    }

    onProgress?.call(
      LocalBackupCleanupProgress(
        currentServerDir: base,
        scannedDirs: scannedDirs,
        scannedItems: scannedItems,
        orphanedFound: orphanedFound,
      ),
    );

    return out;
  }

  Future<_LocalExistence> _collectLocalExistence(
    LocalBackupProfile profile, {
    required dio.CancelToken cancelToken,
  }) async {
    final root = profile.sourceDir.trim();
    final dir = Directory(root);
    if (!dir.existsSync()) {
      return _LocalExistence(files: <String>{}, dirs: <String>{});
    }

    final files = <String>{};
    final dirs = <String>{};

    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (cancelToken.isCancelled) {
        throw dio.DioException(
          requestOptions: dio.RequestOptions(path: ''),
          type: dio.DioExceptionType.cancel,
        );
      }
      final rel = p.relative(e.path, from: root).trim();
      if (rel.isEmpty || rel == '.') continue;
      final relPosix = p.posix.normalize(rel.replaceAll('\\', '/'));
      final key = DeviceUtils.isWindows ? relPosix.toLowerCase() : relPosix;
      if (e is Directory) {
        dirs.add(key);
      } else if (e is File) {
        files.add(key);
      } else {
        files.add(key);
      }
    }

    return _LocalExistence(files: files, dirs: dirs);
  }

  void _syncSchedules() {
    final curServerId = _currentServerId;
    final existing = _intervalTimers.keys.toSet()
      ..addAll(_watchSubs.keys)
      ..addAll(_debounceTimers.keys);
    final wanted = profiles
        .where((p) => p.serverId == curServerId && p.enabled)
        .map((e) => e.id)
        .toSet();
    for (final id in existing.difference(wanted)) {
      _stopScheduleFor(id);
    }
    for (final p in profiles) {
      if (p.serverId != curServerId) {
        _stopScheduleFor(p.id);
        continue;
      }
      if (!p.enabled) {
        _stopScheduleFor(p.id);
        continue;
      }
      if (p.realtime) {
        _ensureRealtimeWatch(p);
        _stopIntervalTimer(p.id);
      } else {
        _ensureIntervalTimer(p);
        _stopRealtimeWatch(p.id);
      }
    }
  }

  void _stopScheduleFor(int id) {
    _stopIntervalTimer(id);
    _stopRealtimeWatch(id, logRelease: false);
    _debounceTimers[id]?.cancel();
    _debounceTimers.remove(id);
  }

  /// 登出时调用：先暂停所有正在运行的备份，再释放实时监控与定时任务
  void releaseRealtimeWatchers() {
    _queuedAfterRun.clear();
    for (final id in _cancelTokenByProfile.keys.toList()) {
      final c = _cancelTokenByProfile[id];
      if (c != null && !c.isCancelled) c.cancel();
      _cancelTokenByProfile.remove(id);
      final rt = _runtimeById[id];
      if (rt != null) {
        rt.busy.value = false;
        rt.status.value = 'idle';
      }
    }
    final ids = _watchSubs.keys.toList();
    for (final id in ids) {
      _stopRealtimeWatch(id, logRelease: true);
    }
    for (final id in _intervalTimers.keys.toList()) {
      _intervalTimers[id]?.cancel();
      _intervalTimers.remove(id);
    }
    _debounceTimers.values.forEach((t) => t.cancel());
    _debounceTimers.clear();
    print('[LocalBackup] 释放实时备份监控，共 ${ids.length} 个任务');
  }

  /// 登入后调用：刷新当前 server 的任务列表并恢复实时监控，若有实时任务则立刻执行一次备份新增
  Future<void> restartRealtimeWatchersForCurrentServer() async {
    print('[LocalBackup] restartRealtimeWatchersForCurrentServer 被调用');
    await refreshProfiles();
    final curServerId = _currentServerId;
    final realtimeProfiles = profiles
        .where((e) => e.serverId == curServerId && e.enabled && e.realtime)
        .toList();
    final realtimeCount = realtimeProfiles.length;
    print('[LocalBackup] 开始实时备份监控，当前 server 共 $realtimeCount 个实时任务');
    for (final p in realtimeProfiles) {
      backupNew(p.id);
    }
  }

  void _stopIntervalTimer(int id) {
    _intervalTimers[id]?.cancel();
    _intervalTimers.remove(id);
  }

  void _stopRealtimeWatch(int id, {bool logRelease = false}) {
    final hadWatch = _watchSubs.containsKey(id);
    _watchSubs[id]?.cancel();
    _watchSubs.remove(id);
    _debounceTimers[id]?.cancel();
    _debounceTimers.remove(id);
    final handle = _macosSourceAccessHandleByProfile.remove(id);
    if (handle != null) {
      MacOSFileAccess.stopAccessing(handle);
    }
    if (logRelease && hadWatch) {
      print('[LocalBackup] 释放实时备份监控: 任务#$id');
    }
  }

  void _ensureIntervalTimer(LocalBackupProfile p) {
    final id = p.id;
    final exists = _intervalTimers[id];
    if (exists != null && exists.isActive) return;
    final minutes = p.intervalMinutes <= 0 ? 60 : p.intervalMinutes;
    final interval = Duration(minutes: minutes);
    final lastRunAtMs = runtimeOf(id).lastRunAtMs.value;
    if (lastRunAtMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastRunAtMs >= interval.inMilliseconds) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          final current = profiles.firstWhereOrNull((e) => e.id == id);
          if (current == null) return;
          if (!current.enabled || current.realtime) return;
          backupNew(id, triggeredBySchedule: true);
        });
      }
    }
    _intervalTimers[id] = Timer.periodic(
      interval,
      (_) => backupNew(id, triggeredBySchedule: true),
    );
  }

  void _ensureRealtimeWatch(LocalBackupProfile p) {
    final id = p.id;
    if (p.serverId != _currentServerId ||
        !ApiController.instance.state.isAuthenticated) {
      return;
    }
    final existing = _watchSubs[id];
    if (existing != null) return;
    final dirPath = p.sourceDir.trim();
    if (dirPath.isEmpty) return;
    if (DeviceUtils.isMacOS) {
      final bookmark = p.sourceBookmark.trim();
      if (bookmark.isEmpty) return;
      MacOSFileAccess.startAccessing(bookmark).then((session) {
        if (session == null) return;
        _macosSourceAccessHandleByProfile[id] = session.handle;
        if (session.refreshedBookmark != null) {
          _storage.upsertProfile(
            id: id,
            name: p.name,
            sourceDir: p.sourceDir,
            sourceBookmark: session.refreshedBookmark!,
            targetDir: p.targetDir,
            excludeItems: p.excludeItems,
            realtime: p.realtime,
            intervalMinutes: p.intervalMinutes,
            debounceSeconds: p.debounceSeconds,
            nameStrategy: p.nameStrategy,
            enabled: p.enabled,
            serverId: p.serverId,
          );
        }
        final dir = Directory(dirPath);
        if (!dir.existsSync()) return;
        _watchSubs[id] = dir.watch(recursive: true).listen((event) {
          if (event is FileSystemModifyEvent ||
              event is FileSystemCreateEvent ||
              event is FileSystemMoveEvent) {
            _debounceRealtimeTrigger(p);
          }
        });
        print('[LocalBackup] 开始实时备份监控: 任务#${p.id} (${p.name})');
      });
      return;
    }
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return;
    _watchSubs[id] = dir.watch(recursive: true).listen((event) {
      if (event is FileSystemModifyEvent ||
          event is FileSystemCreateEvent ||
          event is FileSystemMoveEvent) {
        _debounceRealtimeTrigger(p);
      }
    });
    print('[LocalBackup] 开始实时备份监控: 任务#${p.id} (${p.name})');
  }

  void _debounceRealtimeTrigger(LocalBackupProfile p) {
    final id = p.id;
    final rt = runtimeOf(id);
    if (rt.busy.value) {
      _queuedAfterRun[id] = true;
      return;
    }
    _debounceTimers[id]?.cancel();
    _debounceTimers[id] = Timer(
      const Duration(seconds: _realtimeDebounceSeconds),
      () {
        backupNew(id, triggeredBySchedule: true);
      },
    );
  }

  Future<void> backupNew(
    int profileId, {
    bool triggeredBySchedule = false,
  }) async {
    await _runBackup(profileId, modeAll: false);
  }

  Future<void> backupAll(int profileId) async {
    await _runBackup(profileId, modeAll: true);
  }

  Future<void> clearLogs(int profileId) async {
    await _storage.clearUploadLogs(profileId);
  }

  Future<List<LocalBackupUploadLog>> listLogs(
    int profileId, {
    int limit = 200,
    int offset = 0,
  }) async {
    return await _storage.listUploadLogs(
      profileId: profileId,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> _runBackup(int profileId, {required bool modeAll}) async {
    final profile = profiles.firstWhereOrNull((e) => e.id == profileId);
    if (profile == null) return;
    final rt = runtimeOf(profileId);
    if (rt.busy.value) return;

    final currentServerId = _currentServerId;
    if (currentServerId.isEmpty || profile.serverId != currentServerId) {
      return;
    }
    if (!ApiController.instance.state.isAuthenticated) {
      return;
    }

    final sourceDir = profile.sourceDir.trim();
    if (sourceDir.isEmpty) return;

    final baseUrl = ApiController.instance.baseUrl;
    try {
      await _resolveAccessToken();
    } catch (_) {
      return;
    }

    rt.busy.value = true;
    rt.status.value = 'running';
    rt.lastError.value = '';
    rt.currentRelPath.value = '';
    rt.totalFiles.value = 0;
    rt.processedFiles.value = 0;
    rt.totalBytes.value = 0;
    rt.processedBytes.value = 0;
    rt.lastRunAtMs.value = DateTime.now().millisecondsSinceEpoch;
    await _storage.updateProfileRunTimes(
      profileId: profileId,
      lastRunAtMs: rt.lastRunAtMs.value,
    );

    final cancelToken = dio.CancelToken();
    _cancelTokenByProfile[profileId]?.cancel();
    _cancelTokenByProfile[profileId] = cancelToken;

    try {
      await _withMacOSSourceAccess(profile, () async {
        _logBackup(
          profileId,
          'start mode=${modeAll ? 'all' : 'new'} source="${profile.sourceDir}" target="${profile.targetDir}"',
        );
        await _storage.pruneUploadLogs(
          profileId: profileId,
          maxCount: _maxUploadLogs,
        );
        if (modeAll) {
          await _storage.clearFileState(profileId);
        }

        final sourceDirEntity = Directory(sourceDir);
        if (!await sourceDirEntity.exists()) {
          rt.lastError.value = 'source_not_found'.tr;
          rt.status.value = 'error';
          return;
        }

        final entries = await _scanLocalFiles(
          sourceDir,
          excludeItems: profile.excludeItems,
        );
        if (entries.isEmpty) {
          rt.status.value = 'idle';
          rt.busy.value = false;
          return;
        }

        final fileStateMap = modeAll
            ? <String, LocalBackupFileState>{}
            : await _storage.loadFileStateMap(profileId);
        final toUpload = <_LocalFileEntry>[];
        int totalBytes = 0;
        for (final e in entries) {
          final st = fileStateMap[e.relPath];
          final need =
              st == null || st.size != e.size || st.mtimeMs != e.mtimeMs;
          if (!need) continue;
          toUpload.add(e);
          totalBytes += e.size;
        }

        rt.totalFiles.value = toUpload.length;
        rt.totalBytes.value = totalBytes;
        rt.processedFiles.value = 0;
        rt.processedBytes.value = 0;
        _logBackup(
          profileId,
          'scan done totalEntries=${entries.length} toUpload=${toUpload.length} totalBytes=$totalBytes',
        );

        if (toUpload.isEmpty) {
          _logBackup(profileId, 'nothing to upload');
          rt.status.value = 'idle';
          rt.lastSuccessAtMs.value = DateTime.now().millisecondsSinceEpoch;
          await _storage.updateProfileRunTimes(
            profileId: profileId,
            lastSuccessAtMs: rt.lastSuccessAtMs.value,
          );
          rt.busy.value = false;
          return;
        }

        final rootName = p.basename(sourceDir);
        Future<void> uploadWithStat(
          _LocalFileEntry e,
          FileStat stableStat,
        ) async {
          if (cancelToken.isCancelled) {
            throw dio.DioException(
              requestOptions: dio.RequestOptions(path: ''),
              type: dio.DioExceptionType.cancel,
            );
          }

          final stableSize = stableStat.size;
          final stableMtimeMs = stableStat.modified.millisecondsSinceEpoch;
          if (stableSize != e.size) {
            rt.totalBytes.value += (stableSize - e.size);
            if (rt.totalBytes.value < 0) rt.totalBytes.value = 0;
          }

          final startedAt = DateTime.now().millisecondsSinceEpoch;
          rt.currentRelPath.value = e.relPath;

          final remoteRel = p.posix.join(rootName, e.relPath);
          final fileName = p.basename(remoteRel);
          final fileHash = sha256
              .convert(utf8.encode('$remoteRel|$stableSize|$stableMtimeMs'))
              .toString();

          String status = 'success';
          String error = '';
          var skipped = false;
          try {
            final resolvedBody = await _requestJsonGet(
              '/api/file/attributes/resolve',
              queryParameters: {
                'targetDir': profile.targetDir,
                'relativePath': remoteRel,
              },
              cancelToken: cancelToken,
            );
            final resolvedData = resolvedBody['data'];
            final Map resolvedMap = resolvedData is Map
                ? resolvedData
                : const {};

            final remoteExists = resolvedMap['exists'] == true;
            final remoteIsFile = remoteExists && resolvedMap['isFile'] == true;
            final remoteSizeRaw = resolvedMap['size'];
            final remoteSize = remoteSizeRaw is int
                ? remoteSizeRaw
                : (remoteSizeRaw is num ? remoteSizeRaw.toInt() : null);

            var md5Equal = false;
            if (remoteIsFile && remoteSize == stableSize) {
              final remotePathRaw = resolvedMap['path'];
              final remotePath = remotePathRaw is String ? remotePathRaw : '';
              if (remotePath.isNotEmpty) {
                final localMd5 = await UploadTransferHelper.computeFileMd5(
                  e.localPath,
                  fileSize: stableSize,
                  thresholdBytes: _md5ThresholdBytes,
                  chunkSizeBytes: _md5ChunkSizeBytes,
                );
                final md5Body = await _requestJsonGet(
                  '/api/file/md5',
                  queryParameters: {
                    'path': remotePath,
                    'thresholdBytes': _md5ThresholdBytes,
                    'chunkSizeBytes': _md5ChunkSizeBytes,
                  },
                  cancelToken: cancelToken,
                );
                final md5Data = md5Body['data'];
                final remoteMd5 = md5Data is Map && md5Data['md5'] is String
                    ? md5Data['md5'] as String
                    : '';
                md5Equal = remoteMd5.isNotEmpty && remoteMd5 == localMd5;
              }
            }

            final decision = UploadTransferHelper.decideSmartUpload(
              remoteExists: remoteExists,
              remoteIsFile: remoteIsFile,
              remoteSize: remoteSize,
              localSize: stableSize,
              md5Equal: md5Equal,
            );

            if (decision == SmartUploadDecision.error) {
              skipped = true;
              status = 'error';
              error = '目标路径不是文件，无法覆盖上传';
              _logBackup(
                profileId,
                'decision=error rel="$remoteRel" reason="$error"',
              );
              rt.lastError.value = error;
            } else if (decision == SmartUploadDecision.skip) {
              skipped = true;
              status = 'skipped';
              error = 'MD5相同，跳过上传';
              _logBackup(
                profileId,
                'decision=skip rel="$remoteRel" reason="$error" size=$stableSize',
              );
              rt.processedBytes.value += stableSize;
              await _storage.upsertFileState(
                LocalBackupFileState(
                  profileId: profileId,
                  relPath: e.relPath,
                  size: stableSize,
                  mtimeMs: stableMtimeMs,
                  uploadedAtMs: DateTime.now().millisecondsSinceEpoch,
                ),
              );
            }

            if (!skipped) {
              _logBackup(
                profileId,
                'decision=upload rel="$remoteRel" size=$stableSize',
              );
              final xfile = XFile(e.localPath);
              Future<void> doUpload({bool forceRefresh = false}) async {
                final uploadToken = await _resolveAccessToken(
                  forceRefresh: forceRefresh,
                );
                await UploadCore.processFile(
                  dioClient: _dio,
                  baseUrl: baseUrl,
                  token: uploadToken,
                  fileRef: xfile,
                  fileName: fileName,
                  fileSize: stableSize,
                  remotePath: profile.targetDir,
                  nameStrategy: 'overwrite',
                  fileHash: fileHash,
                  cancelToken: cancelToken,
                  relativePath: remoteRel,
                  fileMtimeMs: stableMtimeMs,
                  onProgress: (increment) {
                    rt.processedBytes.value += increment;
                  },
                  onCompleted: (_) {},
                );
              }

              try {
                await doUpload();
              } catch (uploadEx) {
                if (_isAuthError(uploadEx) &&
                    await ApiController.instance.refreshAuthToken()) {
                  await doUpload(forceRefresh: true);
                } else {
                  rethrow;
                }
              }
              _logBackup(profileId, 'upload=success rel="$remoteRel"');

              await _storage.upsertFileState(
                LocalBackupFileState(
                  profileId: profileId,
                  relPath: e.relPath,
                  size: stableSize,
                  mtimeMs: stableMtimeMs,
                  uploadedAtMs: DateTime.now().millisecondsSinceEpoch,
                ),
              );
            }
          } catch (ex) {
            status = 'error';
            error = UploadTransferHelper.getServerMessage(ex);
            _logBackup(
              profileId,
              'upload=failed rel="$remoteRel" err="$error"',
            );
            rt.lastError.value = error;
          } finally {
            if (status != 'skipped') {
              final finishedAt = DateTime.now().millisecondsSinceEpoch;
              await _storage.insertUploadLog(
                profileId: profileId,
                relPath: remoteRel,
                localPath: e.localPath,
                size: stableSize,
                mtimeMs: stableMtimeMs,
                startedAtMs: startedAt,
                finishedAtMs: finishedAt,
                status: status,
                error: error,
              );
            }
          }

          rt.processedFiles.value += 1;
          if (rt.totalBytes.value == 0) {
            rt.processedBytes.value = 0;
          } else if (rt.processedBytes.value > rt.totalBytes.value) {
            rt.processedBytes.value = rt.totalBytes.value;
          }
        }

        Future<void> recordSkippedUnstable(
          _LocalFileEntry e,
          String message,
        ) async {}

        final unstable = <_LocalFileEntry>[];
        for (final e in toUpload) {
          if (cancelToken.isCancelled) {
            throw dio.DioException(
              requestOptions: dio.RequestOptions(path: ''),
              type: dio.DioExceptionType.cancel,
            );
          }

          rt.currentRelPath.value = e.relPath;

          final stableStat = await tryGetStableFileStatOnce(
            e.localPath,
            cancelToken: cancelToken,
          );
          if (stableStat == null) {
            unstable.add(e);
            await recordSkippedUnstable(
              e,
              'local_backup_file_unstable_retry'.tr,
            );
            continue;
          }
          await uploadWithStat(e, stableStat);
        }

        if (unstable.isNotEmpty) {
          _logBackup(profileId, 'unstable files count=${unstable.length}, retrying');
          final retryStart = DateTime.now().millisecondsSinceEpoch;
          var pending = List<_LocalFileEntry>.from(unstable);
          while (pending.isNotEmpty) {
            if (cancelToken.isCancelled) {
              throw dio.DioException(
                requestOptions: dio.RequestOptions(path: ''),
                type: dio.DioExceptionType.cancel,
              );
            }

            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - retryStart > _unstableRetryBudget.inMilliseconds) {
              for (final e in pending) {
                _logBackup(
                  profileId,
                  'unstable timeout skip rel="${e.relPath}"',
                );
                rt.totalBytes.value -= e.size;
                if (rt.totalBytes.value < 0) rt.totalBytes.value = 0;
                await recordSkippedUnstable(
                  e,
                  'local_backup_file_unstable_timeout'.tr,
                );
                rt.processedFiles.value += 1;
              }
              if (rt.processedBytes.value > rt.totalBytes.value) {
                rt.processedBytes.value = rt.totalBytes.value;
              }
              break;
            }

            final next = <_LocalFileEntry>[];
            var progressed = false;
            for (final e in pending) {
              final stableStat = await waitForStableFileStat(
                e.localPath,
                cancelToken: cancelToken,
              );
              if (stableStat == null) {
                next.add(e);
                continue;
              }
              progressed = true;
              await uploadWithStat(e, stableStat);
            }

            pending = next;
            if (pending.isNotEmpty && !progressed) {
              await Future<void>.delayed(_unstableRetryIdleDelay);
            }
          }
        }

        rt.status.value = rt.lastError.value.trim().isEmpty ? 'idle' : 'error';
        _logBackup(
          profileId,
          'finished status=${rt.status.value} processedFiles=${rt.processedFiles.value}/${rt.totalFiles.value} processedBytes=${rt.processedBytes.value}/${rt.totalBytes.value}',
        );
        if (rt.lastError.value.trim().isEmpty) {
          rt.lastSuccessAtMs.value = DateTime.now().millisecondsSinceEpoch;
          await _storage.updateProfileRunTimes(
            profileId: profileId,
            lastSuccessAtMs: rt.lastSuccessAtMs.value,
          );
        }

        await _storage.pruneUploadLogs(
          profileId: profileId,
          maxCount: _maxUploadLogs,
        );
      });
    } catch (e) {
      if (e is dio.DioException && e.type == dio.DioExceptionType.cancel) {
        _logBackup(profileId, 'cancelled by user');
        rt.status.value = 'idle';
      } else if (_isMacOSPermissionError(e)) {
        _logBackup(profileId, 'failed macos permission error');
        rt.status.value = 'error';
        rt.lastError.value = 'local_backup_permission_need_reselect'.tr;
      } else {
        rt.status.value = 'error';
        final msg = UploadTransferHelper.getServerMessage(e);
        rt.lastError.value = msg.trim().isNotEmpty
            ? msg
            : (e.toString().trim().isNotEmpty ? e.toString() : '$e');
        _logBackup(profileId, 'failed unexpected err="${rt.lastError.value}"');
      }
    } finally {
      rt.busy.value = false;
      rt.currentRelPath.value = '';
      final queued = _queuedAfterRun[profileId] == true;
      _queuedAfterRun.remove(profileId);
      if (queued) {
        backupNew(profileId, triggeredBySchedule: true);
      }
    }
  }

  List<_ExcludeMatcher> _compileExcludeMatchers(List<String> excludeItems) {
    String normalize(String v) {
      var x = v.trim();
      if (x.isEmpty) return '';
      x = x.replaceAll('\\', '/');
      x = x.replaceAll(RegExp('/+'), '/');
      while (x.startsWith('./')) {
        x = x.substring(2);
      }
      while (x.startsWith('/')) {
        x = x.substring(1);
      }
      if (x.endsWith('/')) x = '$x**';
      return x.trim();
    }

    String globToRegex(String glob) {
      final sb = StringBuffer('^');
      var i = 0;
      while (i < glob.length) {
        final ch = glob[i];
        if (ch == '*') {
          var j = i;
          while (j < glob.length && glob[j] == '*') {
            j++;
          }
          final starCount = j - i;
          if (starCount >= 2) {
            sb.write('.*');
            i = j;
            continue;
          }
          sb.write('[^/]*');
          i++;
          continue;
        }
        if (ch == '?') {
          sb.write('[^/]');
          i++;
          continue;
        }
        const specials = r'\.^$|+()[]{}';
        if (specials.contains(ch)) {
          sb.write('\\$ch');
        } else {
          sb.write(ch);
        }
        i++;
      }
      sb.write(r'$');
      return sb.toString();
    }

    final out = <_ExcludeMatcher>[];
    for (final raw in excludeItems) {
      final pat = normalize(raw);
      if (pat.isEmpty) continue;
      final isPathPattern = pat.contains('/');
      final basePat = isPathPattern ? pat : pat;
      final regex = globToRegex(
        DeviceUtils.isWindows ? basePat.toLowerCase() : basePat,
      );
      out.add(
        _ExcludeMatcher(matchBasename: !isPathPattern, re: RegExp(regex)),
      );
    }
    return out;
  }

  bool _isExcluded({
    required String relPosix,
    required String baseName,
    required List<_ExcludeMatcher> matchers,
  }) {
    if (matchers.isEmpty) return false;
    final rel = DeviceUtils.isWindows ? relPosix.toLowerCase() : relPosix;
    final base = DeviceUtils.isWindows ? baseName.toLowerCase() : baseName;
    for (final m in matchers) {
      final ok = m.matchBasename ? m.re.hasMatch(base) : m.re.hasMatch(rel);
      if (ok) return true;
    }
    return false;
  }

  Future<List<_LocalFileEntry>> _scanLocalFiles(
    String sourceDir, {
    List<String> excludeItems = const [],
  }) async {
    final root = Directory(sourceDir);
    if (!await root.exists()) return const [];

    final matchers = _compileExcludeMatchers(excludeItems);
    final out = <_LocalFileEntry>[];
    await for (final ent in root.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final filePath = ent.path;
      final rel = p.relative(filePath, from: sourceDir);
      final relPosix = p.posix.joinAll(p.split(rel));
      final base = p.basename(relPosix);
      if (UploadTransferHelper.shouldIgnore(base)) continue;
      if (_isExcluded(relPosix: relPosix, baseName: base, matchers: matchers)) {
        continue;
      }
      final stat = await ent.stat();
      final size = stat.size;
      if (size <= 0) continue;
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      out.add(
        _LocalFileEntry(
          localPath: filePath,
          relPath: relPosix,
          size: size,
          mtimeMs: mtimeMs,
        ),
      );
    }
    return out;
  }

  Future<T> _withMacOSSourceAccess<T>(
    LocalBackupProfile profile,
    Future<T> Function() fn,
  ) async {
    if (!DeviceUtils.isMacOS) return await fn();
    final bookmark = profile.sourceBookmark.trim();
    if (bookmark.isEmpty) {
      throw Exception('local_backup_permission_need_reselect'.tr);
    }
    final session = await MacOSFileAccess.startAccessing(bookmark);
    if (session == null) {
      throw Exception('local_backup_permission_need_reselect'.tr);
    }
    try {
      if (session.refreshedBookmark != null) {
        await _storage.upsertProfile(
          id: profile.id,
          name: profile.name,
          sourceDir: profile.sourceDir,
          sourceBookmark: session.refreshedBookmark!,
          targetDir: profile.targetDir,
          excludeItems: profile.excludeItems,
          realtime: profile.realtime,
          intervalMinutes: profile.intervalMinutes,
          debounceSeconds: profile.debounceSeconds,
          nameStrategy: profile.nameStrategy,
          enabled: profile.enabled,
          serverId: profile.serverId,
        );
      }
      return await fn();
    } finally {
      await MacOSFileAccess.stopAccessing(session.handle);
    }
  }

  bool _isMacOSPermissionError(Object e) {
    if (!DeviceUtils.isMacOS) return false;
    if (e is FileSystemException) {
      final msg = e.osError?.message ?? e.message;
      final lower = msg.toLowerCase();
      return lower.contains('operation not permitted') ||
          lower.contains('errno = 1');
    }
    final s = e.toString().toLowerCase();
    return s.contains('pathaccessexception') &&
        (s.contains('operation not permitted') || s.contains('errno = 1'));
  }

  Future<String?> createMacOSBookmarkForPath(String path) async {
    if (!DeviceUtils.isMacOS) return null;
    return await MacOSFileAccess.createBookmark(path);
  }
}

class _ExcludeMatcher {
  final bool matchBasename;
  final RegExp re;
  const _ExcludeMatcher({required this.matchBasename, required this.re});
}

class MacOSAccessSession {
  final int handle;
  final String path;
  final String? refreshedBookmark;
  const MacOSAccessSession({
    required this.handle,
    required this.path,
    required this.refreshedBookmark,
  });
}

class MacOSFileAccess {
  static const MethodChannel _channel = MethodChannel(
    'nascab/macos_file_access',
  );

  static Future<String?> createBookmark(String path) async {
    try {
      final res = await _channel.invokeMethod<String>('createBookmark', {
        'path': path,
      });
      return res?.trim().isEmpty == true ? null : res?.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<MacOSAccessSession?> startAccessing(String bookmark) async {
    try {
      final res = await _channel.invokeMethod<Map>('startAccessing', {
        'bookmark': bookmark,
      });
      if (res == null) return null;
      final handle = int.tryParse(res['handle']?.toString() ?? '') ?? -1;
      if (handle <= 0) return null;
      final path = res['path']?.toString() ?? '';
      final refreshed = res['bookmark']?.toString();
      final refreshedBookmark = (refreshed == null || refreshed.trim().isEmpty)
          ? null
          : refreshed;
      return MacOSAccessSession(
        handle: handle,
        path: path,
        refreshedBookmark: refreshedBookmark,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> stopAccessing(int handle) async {
    if (handle <= 0) return;
    try {
      await _channel.invokeMethod('stopAccessing', {'handle': handle});
    } catch (_) {}
  }
}

class _LocalFileEntry {
  final String localPath;
  final String relPath;
  final int size;
  final int mtimeMs;

  const _LocalFileEntry({
    required this.localPath,
    required this.relPath,
    required this.size,
    required this.mtimeMs,
  });
}
