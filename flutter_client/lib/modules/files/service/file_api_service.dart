import 'package:get/get.dart';
import '../../../core/api/base_api_service.dart';

enum ServerDirAccessStatus {
  ok,
  notExists,
  notDirectory,
  noWriteAccess,
  failed,
}

class FileApiService extends BaseApiService {
  static FileApiService get instance => Get.isRegistered<FileApiService>()
      ? Get.find<FileApiService>()
      : FileApiService();

  Future<bool> existsResolved({
    required String targetDir,
    required String relativePath,
  }) async {
    final target = targetDir.trim();
    final rel = relativePath.trim();
    if (target.isEmpty || rel.isEmpty) return false;

    final res = await apiGet<Map<String, dynamic>>(
      '/api/file/exists',
      showLoading: false,
      queryParams: {'targetDir': target, 'relativePath': rel},
    );

    if (!res.success) return false;
    final data = res.data;
    return data?['exists'] == true;
  }

  Future<ServerDirAccessStatus> checkServerDirAccess(String dir) async {
    final path = dir.trim();
    if (path.isEmpty) return ServerDirAccessStatus.failed;

    final res = await apiGet<Map<String, dynamic>>(
      '/api/file/fs-access',
      showLoading: false,
      queryParams: {'path': path},
      timeout: const Duration(seconds: 15),
    );
    if (!res.success || res.data == null) return ServerDirAccessStatus.failed;

    final data = res.data!;
    if (data['exists'] != true) return ServerDirAccessStatus.notExists;
    if (data['isDirectory'] != true) return ServerDirAccessStatus.notDirectory;
    if (data['canWrite'] != true) return ServerDirAccessStatus.noWriteAccess;
    return ServerDirAccessStatus.ok;
  }

  Future<bool> isServerDirWritable(String dir) async {
    return await checkServerDirAccess(dir) == ServerDirAccessStatus.ok;
  }

  /// 文件/目录属性（含 isDirectory、size），用于下载前判断类型且避免走 /api/file/list
  Future<Map<String, dynamic>?> getPathAttributes(
    String filePath, {
    bool showLoading = false,
  }) async {
    final p = filePath.trim();
    if (p.isEmpty) return null;
    final res = await apiGet<Map<String, dynamic>>(
      '/api/file/attributes',
      showLoading: showLoading,
      queryParams: {'path': p},
    );
    if (!res.success || res.data == null) return null;
    return res.data;
  }

  Future<ApiResponse<Map<String, dynamic>>> getIndexSettings({
    bool showLoading = false,
  }) async {
    final res = await apiGet<Map<String, dynamic>>(
      '/api/file/config/index',
      showLoading: showLoading,
    );
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> saveIndexSettings({
    required bool enabled,
    required int intervalHours,
    bool showLoading = true,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/config/index',
      body: {'enabled': enabled, 'intervalHours': intervalHours},
      showLoading: showLoading,
    );
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> resetIndex({
    bool showLoading = true,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/config/index/reset',
      body: {},
      showLoading: showLoading,
    );
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> addCustomPath({
    required String name,
    required String path,
    bool showLoading = true,
  }) async {
    final n = name.trim();
    final p = path.trim();
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/customPath/add',
      body: {'name': n, 'path': p},
      showLoading: showLoading,
    );
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> removeCustomPath({
    required String path,
    bool showLoading = true,
  }) async {
    final p = path.trim();
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/customPath/remove',
      body: {'path': p},
      showLoading: showLoading,
    );
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> searchGlobal({
    required String keyword,
    String? directory,
    List<String>? suffixes,
    String? mode,
    int? limit,
    int? offset,
    String? sourceType,
    String apiPath = '/api/file/search',
    bool showLoading = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      apiPath,
      body: {
        'keyword': keyword,
        if (directory != null) 'directory': directory,
        if (suffixes != null) 'suffixes': suffixes,
        if (mode != null) 'mode': mode,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
        if (sourceType != null) 'sourceType': sourceType,
      },
      showLoading: showLoading,
    );
    return res;
  }

  Future<Map<String, dynamic>> listDirectory(
    String path, {
    bool onlyDir = true,
    bool includeHidden = false,
    String? source,
    String? sourceType,
    String apiPath = '/api/file/list',
    bool showLoading = true,
  }) async {
    print('列出目录 $path');
    final res = await apiPost<Map<String, dynamic>>(
      apiPath,
      body: {
        'path': path,
        'onlyDir': onlyDir ? 'true' : 'false',
        'includeHidden': includeHidden ? 'true' : 'false',
        if (source != null) 'source': source,
        if (sourceType != null) 'sourceType': sourceType,
      },
      showLoading: showLoading,
    );
    return res.data ?? {};
  }

  /// 创建文件夹
  Future<ApiResponse> mkdir(String basePath, String name) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/mkdir',
      body: {'base': basePath, 'name': name},
    );
    return res;
  }

  /// 新建文件（仅支持 txt / md）
  Future<ApiResponse<Map<String, dynamic>>> createFile(
    String basePath,
    String name, {
    required String type,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/create',
      body: {'base': basePath, 'name': name, 'type': type},
    );
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> checkMkdirSupport(
    String basePath,
  ) async {
    return await apiPost<Map<String, dynamic>>(
      '/api/file/mkdir/check',
      body: {'base': basePath},
      showLoading: false,
    );
  }

  /// 删除多个文件或文件夹
  Future<ApiResponse> deleteEntries(
    List<String> paths, {
    bool recycle = false,
    bool deleteScrapeFiles = false,
  }) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/delete',
      body: {
        'paths': paths,
        'recycle': recycle,
        if (deleteScrapeFiles) 'deleteScrapeFiles': true,
      },
    );
    return res;
  }

  /// 列出收藏
  Future<List<Map<String, dynamic>>> listFavorites() async {
    final res = await apiPost<List<Map<String, dynamic>>>(
      '/api/file/quick/favorites/list',
    );
    return (res.data ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 添加收藏
  Future<bool> addFavorites(List<String> paths) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/quick/favorites/add',
      body: {'paths': paths},
    );
    return res.success;
  }

  /// 移除收藏
  Future<bool> removeFavorites(List<String> paths) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/quick/favorites/remove',
      body: {'paths': paths},
    );
    return res.success;
  }

  /// 最近访问
  Future<List<Map<String, dynamic>>> listRecent() async {
    final res = await apiPost<List<Map<String, dynamic>>>(
      '/api/file/quick/recent',
    );
    return (res.data ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  /// 清除最近访问记录
  Future<bool> clearRecent() async {
    print("清除最近访问记录");
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/quick/recent/clear',
      body: {},
    );
    return res.success;
  }

  /// 复制文件
  Future<ApiResponse> copyFiles(List<String> paths, String targetPath) async {
    return await apiPost<Map<String, dynamic>>(
      '/api/file/copy',
      body: {'paths': paths, 'targetPath': targetPath},
    );
  }

  /// 移动文件
  Future<ApiResponse> moveFiles(List<String> paths, String targetPath) async {
    return await apiPost<Map<String, dynamic>>(
      '/api/file/move',
      body: {'paths': paths, 'targetPath': targetPath},
    );
  }

  /// 重命名文件或文件夹
  Future<ApiResponse> rename(String path, String newName) async {
    final res = await apiPost<Map<String, dynamic>>(
      '/api/file/rename',
      body: {'path': path, 'newName': newName},
    );
    return res;
  }

  /// 在系统中用默认程序打开文件/文件夹（仅本机连接时有效）
  Future<ApiResponse> openInSystem(String path) async {
    return await apiPost<Map<String, dynamic>>(
      '/api/file/system/open',
      body: {'path': path},
      showLoading: false,
    );
  }

  /// 在系统文件管理器中选中并显示文件/文件夹（仅本机连接时有效）
  Future<ApiResponse> showInSystem(String path) async {
    return await apiPost<Map<String, dynamic>>(
      '/api/file/system/show',
      body: {'path': path},
      showLoading: false,
    );
  }
}
