import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_controller.dart';
import '../../../core/user/current_user_controller.dart';
import '../service/apps_api_service.dart';
import '../../gallery/controllers/custom_gallery_controller.dart';
import 'pc_components/pc_window_manager.dart';
import '../../settings/views/settings_view.dart';
import '../../user/views/user_management_view.dart';
import '../../files/views/pc_file_browser.dart';
import '../../gallery/views/custom_gallery.dart';
import '../../monitor/monitor_view.dart';
import '../../transfer/views/task_center_view.dart';
import '../../photo/photo_main/view/photo_home_view.dart';
import '../../video/video_main/view/video_main_view.dart';
import '../../book/book_main/view/book_main_view.dart';
import '../../music/music_main/view/music_main_view.dart';
import '../../fileShareServer/views/file_share_server_view.dart';
import '../../fileMount/views/file_mount_view.dart';
import '../../fileBackup/backupMain/file_backup_view.dart';
import '../../mediaTool/media_tool_view.dart';
import '../../service/service_main/view/service_main_view.dart';
import '../../terminal/views/terminal_view.dart';
import '../../encryptedSpace/views/encrypted_space_view.dart';
import '../../editor/controllers/editor_session_controller.dart';
import '../../security/security_center_view.dart';
import '../../message/views/message_center_view.dart';
import '../../process/views/process_list_view.dart';
import '../../docker/view/docker_manager_view.dart';
import '../../transmission/transmission_view.dart';
import '../../notes/view/notes_view.dart';
import '../../notes/view/parts/notes_layout.dart';
import '../../video_player/controllers/video_player_controller.dart';
import '../../../utils/toast_util.dart';
import '../../../utils/device_utils.dart';
import '../../../utils/update_check_helper.dart';

class PcHomeController extends GetxController {
  static PcHomeController get instance => Get.find<PcHomeController>();

  final CurrentUserController _user = CurrentUserController.instance;
  final AppsApiService _service = AppsApiService();
  final PcWindowManager windows = Get.put(PcWindowManager());

  final RxList<String> _hideApps = <String>[].obs;
  final RxList<String> _allApps = <String>[].obs;
  final RxBool _showAllAppsOverlay = false.obs; //是否显示全部app
  final RxString _searchQuery = ''.obs; //搜索关键字
  final RxnString folderNavigatePath = RxnString();
  final RxInt folderNavigateNonce = 0.obs;
  final RxnString quickShareCreatePath = RxnString();
  final RxInt quickShareCreateNonce = 0.obs;
  final RxInt quickShareCreateHandledNonce = 0.obs;

  final RxBool showP2pConnectingHint = false.obs;
  final RxString p2pConnectionState = ''.obs;

  StreamSubscription<String>? _p2pConnectionStateSub;
  String _lastP2pToastToken = '';
  static bool _updatePromptCheckedThisLaunch = false;

  bool get _isNormalUser => !_user.isAdmin;

  /// 当前会话连接的服务器 OS（登录后写入 ApiState，见 [ApiController.serverPlatform]）
  bool get _isServerWin32 {
    if (!Get.isRegistered<ApiController>()) return false;
    return (ApiController.instance.serverPlatform ?? '').toLowerCase() ==
        'win32';
  }

  bool _isAppBlocked(String appKey) {
    // Windows 服务端不支持远程挂载能力，桌面不展示该应用
    // if (appKey == 'mounts' && _isServerWin32) return true;
    if (!_isNormalUser) return false;
    if (kIsWeb && appKey == 'backup') return true;
    if (appKey == 'process') return true;
    return false;
  }

  List<String> get _effectiveAllApps =>
      _allApps.where((e) => !_isAppBlocked(e)).toList();

  List<String> get showApps => _effectiveAllApps
      .where((e) => !_hideApps.contains(e) && !_isAppBlocked(e))
      .toList();
  List<String> get allApps => _effectiveAllApps;
  List<String> get openedApps => windows.openedWindowIds;
  List<String> get minimizedApps => windows.minimizedWindowIds;
  List<String> get dockApps => windows.dockWindowIds;
  String get topmostApp => windows.topmostWindowId;
  bool isMaximized(String windowId) => windows.isMaximized(windowId);
  bool get showAllAppsOverlay => _showAllAppsOverlay.value;
  String get searchQuery => _searchQuery.value;
  Offset? windowPosition(String windowId) => windows.windowPosition(windowId);
  Size? windowSize(String windowId) => windows.windowSize(windowId);

  double get dockOuterWidthPc => windows.dockOuterWidthPc;
  final itemHeightPc = 130.0;

  @override
  void onInit() {
    super.onInit();
    _initApps();
    _initP2pStateListener();
    // 延迟到首帧后，确保 overlayContext 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUpdateAndPromptOnceAfterLogin();
    });
  }

  @override
  void onClose() {
    try {
      _p2pConnectionStateSub?.cancel();
    } catch (_) {}
    _p2pConnectionStateSub = null;
    super.onClose();
  }

  Future<void> _checkUpdateAndPromptOnceAfterLogin() async {
    // ignore: avoid_print
    void log(String msg) => print('[UpdatePrompt] $msg');

    if (_updatePromptCheckedThisLaunch) return;
    _updatePromptCheckedThisLaunch = true;
    if (kIsWeb) {
      log('skip: kIsWeb=true');
      return;
    }
    if (!DeviceUtils.isDesktop) {
      log('skip: not desktop platform');
      return;
    }
    if (Get.overlayContext == null) {
      log('skip: Get.overlayContext=null');
      return;
    }

    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;
      log('currentVersion=$currentVersion');
      // 触发后台检查（24h 内可能不发请求），并读取缓存用于展示
      final hasUpdate = await UpdateCheckHelper.checkForUpdate(currentVersion);
      log('checkForUpdate hasUpdate=$hasUpdate');
      final info = await UpdateCheckHelper.getUpdateInfoIfNewer(currentVersion);
      if (info == null) {
        log('getUpdateInfoIfNewer: null');
        return;
      }
      log('newVersion=${info.newVersion} openUrl=${info.openUrl}');

      final shouldPrompt =
          await UpdateCheckHelper.shouldPromptForVersion(info.newVersion);
      log('shouldPromptForVersion=$shouldPrompt');
      if (!shouldPrompt) return;

      final openUrl = info.openUrl.trim();
      if (openUrl.isEmpty) {
        log('skip: openUrl empty');
        return;
      }

      // 先写入，避免用户重复触发弹窗（例如页面重建/热重载）
      await UpdateCheckHelper.markPromptedVersion(info.newVersion);

      if (Get.isDialogOpen == true) return;
      await Get.dialog(
        AlertDialog(
          title: Text('settings_update_available'.tr),
          content: Text('($currentVersion → ${info.newVersion})'),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () async {
                Get.back();
                try {
                  final uri = Uri.parse(openUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  } else {
                    ToastUtil.show('operation_failed'.tr);
                  }
                } catch (_) {
                  ToastUtil.show('operation_failed'.tr);
                }
              },
              child: Text('confirm'.tr),
            ),
          ],
        ),
        barrierDismissible: true,
      );
    } catch (_) {}
  }

  void _initP2pStateListener() {
    if (!Get.isRegistered<ApiController>()) return;
    final api = ApiController.instance;
    _p2pConnectionStateSub = api.onP2pConnectionStateChanged.listen((state) {
      final s = state.trim().toLowerCase();
      p2pConnectionState.value = s;

      final connecting = s == 'connecting' || s == 'reconnecting';
      showP2pConnectingHint.value = api.isP2pMode && connecting;

      if (s == 'failed') {
        showP2pConnectingHint.value = false;
        final err = api.p2pLastConnectError;
        final msg = err == null
            ? 'server_connect_fail'.tr
            : ApiController.formatP2pConnectError(err);
        final token = '$s|${err?.toString() ?? ''}';
        if (_lastP2pToastToken != token) {
          _lastP2pToastToken = token;
          ToastUtil.show(msg);
        }
      } else if (s == 'connected' || s == 'disconnected') {
        showP2pConnectingHint.value = false;
      }
    });
  }

  Rect getDeskRect() => windows.getDeskRect();
  Offset getWindowPos(String windowId) => windows.getWindowPos(windowId);
  Size getWindowSize(String windowId) => windows.getWindowSize(windowId);
  bool windowCanResize(String windowId) => windows.isResizable(windowId);
  bool windowCanMaximize(String windowId) => windows.isMaximizable(windowId);
  bool windowCanMinimize(String windowId) => windows.isMinimizable(windowId);
  Size? windowMinSize(String windowId) => windows.minSizeOf(windowId);
  String? windowTitle(String windowId) => windows.titleOf(windowId);
  bool windowShowTitle(String windowId) => windows.showTitleOf(windowId);
  String? windowTitleTooltip(String windowId) =>
      windows.titleTooltipOf(windowId);
  String? windowHelpText(String windowId) => windows.helpTextOf(windowId);
  Widget? windowIcon(String windowId) => windows.iconOf(windowId);
  WidgetBuilder? windowViewBuilder(String windowId) =>
      windows.viewBuilderOf(windowId);

  Future<void> _initApps() async {
    final cached = _user.apps;
    if (cached != null) {
      _hideApps.assignAll(cached.hideApp);
      _allApps.assignAll(cached.allApp);
    }
  }

  //根据app名称构架icon
  Widget buildAppIcon(String appKey, {double size = 28}) {
    return Image.asset(
      'assets/app_icons/$appKey.webp',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      errorBuilder: (c, e, s) {
        return Icon(Icons.apps, size: size);
      },
    );
  }

  //根据app名称构架view
  WidgetBuilder builtinAppViewBuilder(String appKey) {
    print("打开app:$appKey");
    if (_isAppBlocked(appKey)) return (_) => const SizedBox.shrink();
    switch (appKey) {
      case 'encrypted':
        return (_) => const EncryptedSpaceView();
      case 'nascab_service':
        return (_) => const ServiceMainView();
      case 'media_tool':
        return (_) => const MediaToolView();
      case 'user':
        return (_) => const UserManagementView();
      case 'folder':
        return (_) => const PcFileBrowser(windowId: 'folder');
      case 'image_view':
        return (_) => const CustomGallery();
      case 'monitor':
        return (_) => const MonitorView();
      case 'task_center':
        return (_) => const TaskCenterView();
      case 'photo':
        return (_) => const PhotoHomeView();
      case 'movie':
        return (_) => const VideoMainView();
      case 'book':
        return (_) => const BookMainView();
      case 'music':
        return (_) => const MusicMainView();
      case 'setting':
        return (_) => const SettingsView();
      case 'share':
        return (_) => const FileShareServerView();
      case 'mounts':
        return (_) => const FileMountView();
      case 'backup':
        return (_) => const FileBackupView();
      case 'terminal':
        return (_) => const TerminalPage();
      case 'security':
        return (_) => const SecurityCenterScope(child: SecurityCenterView());
      case 'message_center':
        return (_) => const MessageCenterView();
      case 'process':
        return (_) => const ProcessListView();
      case 'docker':
        return (_) => const DockerManagerView();
      case 'transmission':
        return (_) => const TransmissionView();
      case 'note':
        return (_) => const NotesView();
      default:
        return (_) => const SizedBox.shrink();
    }
  }

  // 打开图片浏览器
  void openImageViewer(
    List<Map<String, dynamic>> items,
    int index, {
    bool showInfo = true,
    Future<bool> Function(Map<String, dynamic> item, int index)? deleteHandler,
    Future<void> Function(Map<String, dynamic> item, int index)?
    downloadHandler,
  }) {
    if (!Get.isRegistered<CustomGalleryController>()) {
      // 未注册：创建实例并注册（仅执行一次）
      Get.put(CustomGalleryController());
    }
    CustomGalleryController ctrl = CustomGalleryController.instance;
    ctrl.configure(
      showInfo: showInfo,
      deleteHandler: deleteHandler,
      downloadHandler: downloadHandler,
    );
    //默认显示操控组件
    ctrl.isControlsVisible.value = true;
    ctrl.galleryItems = items;
    ctrl.galleryInitialIndex.value = index;
    openApp(
      windowId: 'image_view',
      viewBuilder: builtinAppViewBuilder('image_view'),
      title: 'app_image_view'.tr,
      icon: buildAppIcon('image_view'),
      maximize: true,
    );
  }

  void toggleAllAppsOverlay(bool show) {
    _showAllAppsOverlay.value = show;
  }

  void updateSearch(String q) {
    _searchQuery.value = q;
  }

  List<String> filteredAllApps() {
    final q = _searchQuery.value.trim().toLowerCase();
    final apps = _effectiveAllApps;
    if (q.isEmpty) return apps;
    return apps.where((e) {
      final k = e.toLowerCase();
      final name = ("app_$e").tr.toLowerCase();
      return k.contains(q) || name.contains(q);
    }).toList();
  }

  bool isInDesktop(String app) =>
      !_hideApps.contains(app) && !_isAppBlocked(app);

  Future<void> addToDesktop(String app) async {
    if (_isAppBlocked(app)) return;
    if (!_hideApps.contains(app)) return;
    _hideApps.remove(app);
    _user.setApps({'hide_app': _hideApps, 'all_app': _allApps});
    await _service.unhideApp(app);
  }

  Future<void> removeFromDesktop(String app) async {
    if (_isAppBlocked(app)) return;
    if (_hideApps.contains(app)) return;
    _hideApps.add(app);
    _user.setApps({'hide_app': _hideApps, 'all_app': _allApps});
    await _service.hideApp(app);
  }

  Future<void> saveOrder() async {
    _user.setApps({'hide_app': _hideApps, 'all_app': _allApps});
    await _service.setAppsOrder(_allApps);
  }

  void reorderIcon(int oldIndex, int newIndex) {
    final visible = showApps;
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex < 0 || newIndex >= visible.length) return;
    final item = visible[oldIndex];
    _allApps.remove(item);
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

  void openApp({
    required String windowId,
    required WidgetBuilder viewBuilder,
    String? title,
    String? titleTooltip,
    String? helpText,
    Widget? icon,
    bool maximize = false,
    bool resizable = true,
    bool maximizable = true,
    bool minimizable = true,
    bool showTitle = true,
    Size? minSize,
    Size? initialSize,
    Offset? initialPosition,
  }) {
    if (_isAppBlocked(windowId)) return;
    final resolvedMinSize = windowId == 'note'
        ? const Size(
            NotesLayout.minDesktopWidth,
            NotesLayout.minDesktopHeight,
          )
        : (minSize ?? const Size(600, 500));
    final resolvedInitialSize = windowId == 'note'
        ? const Size(900, 600)
        : initialSize;
    final resolvedHelpText =
        (helpText ?? _defaultHelpTextKeyForWindow(windowId))?.trim();
    windows.openApp(
      windowId: windowId,
      viewBuilder: viewBuilder,
      title: title,
      titleTooltip: titleTooltip,
      helpText: resolvedHelpText != null && resolvedHelpText.isNotEmpty
          ? resolvedHelpText
          : null,
      icon: icon,
      showTitle: showTitle,
      maximize: maximize,
      resizable: resizable,
      maximizable: maximizable,
      minimizable: minimizable,
      minSize: resolvedMinSize,
      initialSize: resolvedInitialSize,
      initialPosition: initialPosition,
    );
  }

  String? _defaultHelpTextKeyForWindow(String windowId) {
    switch (windowId) {
      case 'folder':
      case 'photo':
      case 'book':
      case 'music':
      case 'encrypted':
      case 'media_tool':
      case 'terminal':
      case 'mounts':
      case 'share':
      case 'docker':
        return 'app_help_$windowId';
      default:
        return null;
    }
  }

  void openFolderAt(String targetPath) {
    final p = targetPath.trim();
    if (p.isEmpty) return;
    folderNavigatePath.value = p;
    folderNavigateNonce.value += 1;
    openApp(
      windowId: 'folder',
      viewBuilder: builtinAppViewBuilder('folder'),
      title: 'app_folder'.tr,
      icon: buildAppIcon('folder'),
    );
  }

  void closeApp(String app) {
    if (app.startsWith('editor_')) {
      if (Get.isRegistered<EditorSessionController>(tag: app)) {
        Get.delete<EditorSessionController>(tag: app, force: true);
      }
    }
    if (app == 'video_player') {
      if (Get.isRegistered<PlayerController>()) {
        Get.delete<PlayerController>(force: true);
      }
    }
    windows.closeWindow(app);
  }

  void minimizeApp(String app) {
    windows.minimizeWindow(app);
  }

  void maximizeApp(String app) {
    windows.toggleMaximize(app);
  }

  void focusWindow(String app) {
    windows.focusWindow(app);
  }

  void restoreFromDock(String app) {
    windows.restoreWindow(app);
  }

  void setWindowPosition(String app, Offset pos) {}

  void setLastPosition(String app, Offset pos) {
    windows.setLastPosition(app, pos);
  }

  void setLastSize(String app, Size size) {
    windows.setLastSize(app, size);
  }
}
