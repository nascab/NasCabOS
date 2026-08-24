import 'package:get/get.dart';
import '../../user/service/user_api_service.dart';
import '../service/file_share_server_api_service.dart';
import '../service/user_share_folder_api_service.dart';
import '../../../utils/dialog_util.dart';
import '../../../utils/toast_util.dart';
import '../../../core/api/base_api_service.dart';
import '../../../utils/device_utils.dart';
import '../../../core/services/mount_plugin_status_service.dart';

class FileShareServerController extends GetxController {
  static const List<String> supportedTypes = ['WebDav', 'FTP', 'SFTP'];

  final String? initialPageKey;
  FileShareServerController({this.initialPageKey});

  final _api = FileShareServerApiService();
  final _userApi = UserApiService();
  final _userShareApi = UserShareFolderApiService();

  final RxString currentPageKey = 'share.webdav'.obs;
  final RxDouble leftWidth = 160.0.obs;
  final RxBool sidebarCollapsed = false.obs;

  final RxBool isShareManageExpanded = true.obs;
  final RxBool isSettingsExpanded = true.obs;

  final RxBool openPortsSettingsOnInit = false.obs;

  final currentType = 'WebDav'.obs;
  final configsByType = <String, List<Map<String, dynamic>>>{}.obs;
  final portsByType = <String, Map<String, dynamic>>{}.obs;
  final statusByType = <String, String>{}.obs;
  final actualPortsByType = <String, Map<String, dynamic>>{}.obs;
  final opLoadingByType = <String, bool>{}.obs;

  final usersById = <int, Map<String, dynamic>>{}.obs;

  final userShareFolders = <Map<String, dynamic>>[].obs;
  final userShareFoldersLoading = false.obs;
  bool _pendingUserShareFoldersRefresh = false;

  @override
  void onInit() {
    super.onInit();
    final initialKey = initialPageKey?.toString().trim() ?? '';
    if (initialKey.isNotEmpty) {
      if (DeviceUtils.isMobile && initialKey == 'settings.ports') {
        openPortsSettingsOnInit.value = true;
      } else {
        selectPage(initialKey);
      }
    } else {
      final args = Get.arguments;
      if (args is Map) {
        final pageKey = args['pageKey']?.toString().trim() ?? '';
        if (pageKey.isNotEmpty) {
          if (DeviceUtils.isMobile && pageKey == 'settings.ports') {
            openPortsSettingsOnInit.value = true;
          } else {
            selectPage(pageKey);
          }
        }
      }
    }
    refreshAll(showLoading: false);
  }

  void selectPage(String key) {
    currentPageKey.value = key;
    if (key == 'share.webdav') currentType.value = 'WebDav';
    if (key == 'share.ftp') currentType.value = 'FTP';
    if (key == 'share.sftp') currentType.value = 'SFTP';
    if (key == 'share.user_folders') {
      refreshUserShareFolders(showLoading: false);
    }
  }

  Future<void> refreshAll({bool showLoading = true}) async {
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      await _refreshUsers();
      for (final t in supportedTypes) {
        await refreshType(t, showLoading: false);
      }
      await refreshUserShareFolders(showLoading: false);
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
    }
  }

  Future<void> refreshUserShareFolders({
    bool showLoading = true,
    bool force = false,
  }) async {
    if (userShareFoldersLoading.value && !force) {
      _pendingUserShareFoldersRefresh = true;
      return;
    }
    userShareFoldersLoading.value = true;
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);
      final res = await _userShareApi.list();
      if (!res.success) {
        ToastUtil.show(res.message ?? 'operation_failed'.tr);
        return;
      }
      final data = res.data ?? {};
      final rawItems = data['items'];
      final list = (rawItems is List ? rawItems : const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      userShareFolders.assignAll(list);
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
      userShareFoldersLoading.value = false;
      if (_pendingUserShareFoldersRefresh) {
        _pendingUserShareFoldersRefresh = false;
        await refreshUserShareFolders(showLoading: false, force: true);
      }
    }
  }

  Future<void> addUserShareFolder({
    required String path,
    String? name,
    bool? allowDownload,
  }) async {
    final p = path.trim();
    if (p.isEmpty) return;
    final res = await _userShareApi.add(
      path: p,
      name: name,
      allowDownload: allowDownload,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await refreshUserShareFolders(showLoading: false, force: true);
    await Future.delayed(const Duration(milliseconds: 200));
    await refreshUserShareFolders(showLoading: false, force: true);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> removeUserShareFolder(String path) async {
    final p = path.trim();
    if (p.isEmpty) return;
    final res = await _userShareApi.remove(path: p);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await refreshUserShareFolders(showLoading: false, force: true);
    await Future.delayed(const Duration(milliseconds: 200));
    await refreshUserShareFolders(showLoading: false, force: true);
    ToastUtil.show('delete_success'.tr);
  }

  Future<void> setUserShareAllowDownload({
    required String path,
    required bool allowDownload,
  }) async {
    final p = path.trim();
    final res = await _userShareApi.setAllowDownload(
      path: p,
      allowDownload: allowDownload,
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await refreshUserShareFolders(showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> refreshType(String serverType, {bool showLoading = true}) async {
    final type = serverType.trim();
    if (type.isEmpty) return;
    try {
      if (showLoading) DialogUtil.showLoading(message: 'loading'.tr);

      final portsRes = await _api.getPorts(serverType: type);
      if (portsRes.success) {
        portsByType[type] = (portsRes.data ?? {}).cast<String, dynamic>();
        portsByType.refresh();
      }

      final listRes = await _api.list(serverType: type);
      final rawList = listRes.success ? (listRes.data ?? []) : [];
      final list = rawList
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      configsByType[type] = list;
      configsByType.refresh();

      final status = _deriveStatusFromRows(list);
      statusByType[type] = status;
      statusByType.refresh();

      final actual = _derivePortsFromRows(list);
      if (actual.isNotEmpty) {
        actualPortsByType[type] = actual;
        actualPortsByType.refresh();
      }
    } catch (_) {
      ToastUtil.show('operation_failed'.tr);
    } finally {
      if (showLoading) DialogUtil.dismissLoading(force: true);
    }
  }

  String getStatus(String serverType) {
    return statusByType[serverType] ?? 'stopped';
  }

  Map<String, dynamic> getDisplayPorts(String serverType) {
    final status = getStatus(serverType);
    if (status == 'running') {
      final actual = actualPortsByType[serverType];
      if (actual != null && actual.isNotEmpty) return actual;
    }
    return portsByType[serverType] ?? {};
  }

  Future<void> start(String serverType) async {
    final type = serverType.trim();
    if (type.isEmpty) return;
    final plugin = MountPluginStatusService.ensure();
    if (!plugin.canUseFileServer) {
      plugin.showNotReadyToast();
      return;
    }
    final list = configsByType[type] ?? const [];
    if (list.isEmpty) {
      DialogUtil.showErrorDialog(
        message: 'file_share_server_cannot_start_no_config'.tr,
      );
      return;
    }
    opLoadingByType[type] = true;
    opLoadingByType.refresh();
    final res = await _api.start(serverType: type);
    opLoadingByType[type] = false;
    opLoadingByType.refresh();
    if (!res.success) {
      final msg = (res.apiErrorKey == 'mountShare.PLUGIN_NOT_READY')
          ? 'mount_share_plugin_not_ready'.tr
          : (res.message ?? 'operation_failed'.tr);
      ToastUtil.show(msg);
      return;
    }
    await refreshType(type, showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<void> stop(String serverType) async {
    final type = serverType.trim();
    if (type.isEmpty) return;
    opLoadingByType[type] = true;
    opLoadingByType.refresh();
    final res = await _api.stop(serverType: type);
    opLoadingByType[type] = false;
    opLoadingByType.refresh();
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return;
    }
    await refreshType(type, showLoading: false);
    ToastUtil.show('operation_success'.tr);
  }

  Future<bool> upsertConfig({
    required int uid,
    required String serverType,
    required List<Map<String, dynamic>> rootPath,
  }) async {
    final type = serverType.trim();
    if (type.isEmpty) return false;
    final res = await _api.upsert(
      uid: uid,
      serverType: type,
      rootPath: rootPath,
      config: const {},
    );
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    await refreshType(type, showLoading: false);
    ToastUtil.show('operation_success'.tr);
    return true;
  }

  Future<bool> deleteConfig({
    required int uid,
    required String serverType,
  }) async {
    final type = serverType.trim();
    if (type.isEmpty) return false;
    final res = await _api.delete(uid: uid, serverType: type);
    if (!res.success) {
      ToastUtil.show(res.message ?? 'operation_failed'.tr);
      return false;
    }
    await refreshType(type, showLoading: false);
    ToastUtil.show('delete_success'.tr);
    return true;
  }

  Future<ApiResponse<Map<String, dynamic>>> setPorts({
    required String serverType,
    int? httpPort,
    int? httpsPort,
  }) async {
    final type = serverType.trim();
    if (type.isEmpty) {
      return ApiResponse.failure('operation_failed'.tr);
    }
    final res = await _api.setPorts(
      serverType: type,
      httpPort: httpPort,
      httpsPort: httpsPort,
    );
    if (res.success) {
      await refreshType(type, showLoading: false);
      ToastUtil.show('operation_success'.tr);
    }
    return res;
  }

  Future<void> _refreshUsers() async {
    final list = await _userApi.fetchUsers(limit: 100, keyword: '');
    final map = <int, Map<String, dynamic>>{};
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is int) {
        map[id] = item.map((k, v) => MapEntry(k.toString(), v));
      }
    }
    usersById.assignAll(map);
  }

  String usernameForUid(dynamic uid) {
    if (uid == null) return '';
    final id = int.tryParse(uid.toString());
    if (id == null) return '';
    final u = usersById[id];
    return u?['username']?.toString() ?? '';
  }

  String _deriveStatusFromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 'stopped';
    final first = rows.first;
    final s = first['status']?.toString();
    if (s == 'running' || s == 'error' || s == 'stopped') return s ?? 'stopped';
    return 'stopped';
  }

  Map<String, dynamic> _derivePortsFromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return {};
    final first = rows.first;
    final httpPort = first['http_port'];
    final httpsPort = first['https_port'];
    final out = <String, dynamic>{};
    if (httpPort != null) out['http_port'] = httpPort;
    if (httpsPort != null) out['https_port'] = httpsPort;
    return out;
  }
}
