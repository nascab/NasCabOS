import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/user/current_user_controller.dart';
import '../service/apps_api_service.dart';
import '../../../core/api/api_controller.dart';
import '../../auth/beans/server_info_bean.dart';
import '../../auth/service/server_storage_service.dart';
import '../../../core/routes/app_routes.dart';
import '../../mediaTool/media_tool_view.dart';
import '../../monitor/app_monitor_view.dart';
import '../../transfer/views/app_task_center_page.dart';
import '../../security/security_center_view.dart'
    show SecurityCenterScope, AppSecurityCenterPage;
import '../../photo/photo_main/view/app_photo_main_view.dart';
import '../../book/book_main/view/app_book_main_view.dart';
import '../../video/video_main/view/app_video_main_view.dart';
import '../../music/music_main/view/app_music_main_frame_view.dart';
import '../../user/views/user_management_view.dart';
import '../../service/service_main/view/service_mobile_view.dart';
import '../../process/views/app_process_list_page.dart';
import '../../docker/view/docker_manager_view.dart';
import '../../transmission/transmission_view.dart';
import '../../notes/view/notes_view.dart';
import '../../photoBackup/controller/photo_backup_controller.dart';
import '../../../utils/device_utils.dart';

class AppHomeController extends GetxController {
  static AppHomeController get instance => Get.find<AppHomeController>();

  final CurrentUserController _user = CurrentUserController.instance;
  final AppsApiService _service = AppsApiService();

  // App列表
  final RxList<String> _allApps = <String>[].obs;
  final RxList<String> _hideApps = <String>[].obs;

  // 搜索
  final RxString _searchQuery = ''.obs;
  final TextEditingController searchController = TextEditingController();

  // 服务器信息
  final Rxn<ServerInfoBean> _currentServer = Rxn<ServerInfoBean>();

  /// 当前会话所连服务器 OS（[ApiController.serverPlatform]，如 win32）
  bool get _isServerWin32 {
    if (!Get.isRegistered<ApiController>()) return false;
    return (ApiController.instance.serverPlatform ?? '').toLowerCase() ==
        'win32';
  }

  List<String> get showApps {
    return _allApps
        .where((e) => !_hideApps.contains(e))
        .where((e) => isAdmin || e != 'backup')
        .where((e) => isAdmin || e != 'process')
        .where((e) => !DeviceUtils.isMobile || e != 'task_center')
        // .where((e) => e != 'mounts' || !_isServerWin32) // 桌面端已注释，保持一致
        .toList();
  }

  bool get isAdmin => _user.isAdmin;
  ServerInfoBean? get currentServer => _currentServer.value;
  String get searchQuery => _searchQuery.value;

  // 模拟服务器消息
  final RxString serverMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _initApps();
    _loadServerInfo();
    _loadHomeConfig();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  void _initApps() {
    final cached = _user.apps;
    if (cached != null) {
      _hideApps.assignAll(cached.hideApp);
      _allApps.assignAll(cached.allApp);
    }
  }

  void _loadServerInfo() {
    try {
      final currentServerId = ApiController.instance.state.serverId;
      final currentBaseUrl = ApiController.instance.state.baseUrl;
      final servers = ServerStorageService.loadServers();
      final currentUsername = (_user.current?.username ?? '').trim();

      ServerInfoBean? server;
      // Try to find by serverId first
      if (currentServerId.isNotEmpty) {
        try {
          if (currentUsername.isNotEmpty) {
            server = servers.firstWhere(
              (s) =>
                  s.serverId == currentServerId &&
                  (s.username ?? '').trim() == currentUsername,
            );
          } else {
            server = servers.firstWhere((s) => s.serverId == currentServerId);
          }
        } catch (_) {}
      }

      // Fallback to url
      if (server == null) {
        try {
          if (currentUsername.isNotEmpty) {
            server = servers.firstWhere(
              (s) =>
                  s.serverUrl == currentBaseUrl &&
                  (s.username ?? '').trim() == currentUsername,
            );
          } else {
            server = servers.firstWhere((s) => s.serverUrl == currentBaseUrl);
          }
        } catch (_) {}
      }

      _currentServer.value = server;
    } catch (e) {
      print('Error loading server info: $e');
    }
  }

  Future<void> _loadHomeConfig() async {
    try {
      final res = await _service.getHomeConfig(showLoading: false);
      if (!res.success) {
        serverMessage.value = '';
        return;
      }
      final msg = (res.data?['newMessage']?.toString() ?? '').trim();
      serverMessage.value = msg;
      // 冷启动或切服后：首页接口成功说明当前连接可用，再触发「APP 打开时自动开启备份」
      if (Get.isRegistered<PhotoBackupController>()) {
        Get.find<PhotoBackupController>().onConnectionConfirmed();
      }
    } catch (_) {
      serverMessage.value = '';
    }
  }

  void updateSearch(String q) {
    _searchQuery.value = q;
  }

  List<String> filteredApps() {
    final q = _searchQuery.value.trim().toLowerCase();
    final visible = showApps;
    if (q.isEmpty) return visible;
    return visible.where((e) {
      final k = e.toLowerCase();
      final name = ("app_$e").tr.toLowerCase();
      return k.contains(q) || name.contains(q);
    }).toList();
  }

  Future<void> saveOrder() async {
    _user.setApps({'hide_app': _hideApps, 'all_app': _allApps});
    await _service.setAppsOrder(_allApps);
  }

  void reorderApp(int oldIndex, int newIndex) {
    final visible = showApps;
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex < 0 || newIndex >= visible.length) return;

    final item = visible[oldIndex];
    // 在allApps中移动位置
    _allApps.remove(item);

    // 找到新的插入位置
    if (newIndex < visible.length) {
      final anchor = visible[newIndex];
      final anchorIdx = _allApps.indexOf(anchor);
      final insertIdx = anchorIdx >= 0 ? anchorIdx : _allApps.length;
      _allApps.insert(insertIdx, item);
    } else {
      _allApps.add(item);
    }

    saveOrder();
  }

  //app端打开应用
  void openApp(String app) {
    print('Open App: $app');
    // if (app == 'mounts' && _isServerWin32) { return; } // 桌面端已注释，保持一致
    if (DeviceUtils.isMobile && app == 'task_center') {
      return;
    }
    if (app == 'setting') {
      AppRoutes.toSettings();
      return;
    } else if (app == 'folder') {
      AppRoutes.toFiles();
      return;
    } else if (app == 'file_share_server') {
      Get.toNamed(AppRoutes.fileShareServer);
      return;
    } else if (app == 'mounts') {
      Get.toNamed(AppRoutes.mounts);
      return;
    } else if (app == 'backup') {
      Get.toNamed(AppRoutes.backup);
      return;
    } else if (app == 'monitor') {
      Get.to(() => const AppMonitorView());
      return;
    } else if (app == 'task_center') {
      Get.to(() => const AppTaskCenterPage());
      return;
    } else if (app == 'terminal') {
      AppRoutes.toTerminal();
      return;
    } else if (app == 'media_tool') {
      Get.to(() => const MediaToolView());
      return;
    } else if (app == 'encrypted') {
      Get.toNamed(AppRoutes.encryptedSpace);
      return;
    } else if (app == 'security') {
      Get.to(() => const SecurityCenterScope(child: AppSecurityCenterPage()));
      return;
    } else if (app == 'photo') {
      Get.to(() => const AppPhotoMainView());
      return;
    } else if (app == 'movie') {
      Get.to(() => const AppVideoMainView());
      return;
    } else if (app == 'book') {
      Get.to(() => const AppBookMainView());
      return;
    } else if (app == 'music') {
      Get.to(() => const AppMusicMainFrameView());
      return;
    } else if (app == 'user') {
      Get.to(() => const UserManagementView());
      return;
    } else if (app == 'nascab_service') {
      Get.to(() => const ServiceMobileView());
      return;
    } else if (app == 'docker') {
      Get.to(() => const DockerManagerView(appMode: true));
      return;
    } else if (app == 'transmission') {
      Get.to(() => const TransmissionView(appMode: true));
      return;
    } else if (app == 'note') {
      Get.to(() => const NotesView(appMode: true));
      return;
    } else if (app == 'process') {
      Get.to(() => const AppProcessListPage());
      return;
    } else if (app == 'share') {
      Get.toNamed(AppRoutes.fileShareServer);
      return;
    }
    // 其他App暂时只打印
    // Placeholder for other apps
  }
}
