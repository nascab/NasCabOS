import 'package:get/get.dart';
import '../../modules/auth/views/server_list/server_list_view.dart';
import '../../modules/settings/views/settings_view.dart';
import '../../modules/auth/views/login/login_view.dart';
import '../../modules/auth/views/admin_create/admin_create_page.dart';
import '../../modules/auth/views/recover_password/recover_password_view.dart';
import '../../modules/home/views/pc_home_page.dart';
import '../../modules/user/views/user_management_view.dart';
import '../../modules/home/views/app_home_page.dart';
import '../../modules/files/views/app_file_browser.dart';
import '../../modules/photo/timeline/view/pc_photo_timeline.dart';
import '../../modules/photo/timeline/view/app_photo_timeline_view.dart';
import '../../modules/video/detail/view/video_detail_page.dart';
import '../../modules/video_player/views/app_video_player_page.dart';
import '../../modules/video_player/views/pc_video_player_view.dart';
import '../../modules/video/video_main/controller/video_main_controller.dart';
import '../../modules/fileShareServer/views/file_share_server_view.dart';
import '../../modules/fileMount/views/file_mount_view.dart';
import '../../modules/fileBackup/backupMain/file_backup_view.dart';
import '../../modules/service/account/view/nascab_callback_view.dart';
import '../../modules/terminal/views/terminal_view.dart';
import '../../modules/encryptedSpace/views/encrypted_space_view.dart';
import '../../modules/transfer/views/upload/app_upload_center_view.dart';
import '../../modules/photoBackup/view/app_photo_backup_view.dart';
import '../../utils/device_utils.dart';

class AppRoutes {
  static const String serverList = '/server_list';
  static const String serverAdd = '/server_add';
  static const String adminCreate = '/admin_create';
  static const String settings = '/settings';
  static const String login = '/login';

  /// 配对码登录页（与 login 共用同一视图，公司站时先配对码再账号密码）
  static const String paircodeLogin = '/paircode_login';
  static const String recover = '/recover';
  static const String home = '/home';
  static const String userManagement = '/user_management';
  static const String files = '/files';
  static const String photoTimeline = '/photo_timeline';
  static const String videoDetail = '/video_detail';
  static const String fileShareServer = '/file_share_server';
  static const String mounts = '/mounts';
  static const String backup = '/backup';
  static const String nascabCallback = '/nascab-callback';
  static const String terminal = '/terminal';
  static const String encryptedSpace = '/encrypted_space';
  static const String appUploadCenter = '/app_upload_center';
  static const String appPhotoBackup = '/app_photo_backup';
  static bool _videoPlayerOpening = false;

  static List<GetPage> getPages = [
    GetPage(name: serverList, page: () => const ServerListView()),
    GetPage(name: settings, page: () => SettingsView()),
    GetPage(name: login, page: () => const LoginView()),
    GetPage(name: paircodeLogin, page: () => const LoginView()),
    GetPage(name: adminCreate, page: () => AdminCreatePage()),
    GetPage(name: recover, page: () => RecoverView()),
    GetPage(
      name: files,
      page: () {
        final args = Get.arguments;
        final initialPath = args is Map
            ? args['initialPath']?.toString()
            : null;
        return AppFileBrowser(initialPath: initialPath);
      },
    ),
    GetPage(
      name: photoTimeline,
      page: () {
        if (DeviceUtils.isMobile) {
          return const AppPhotoTimelinePage();
        }
        return const PcPhotoTimelineView();
      },
    ),
    GetPage(name: fileShareServer, page: () => const FileShareServerView()),
    GetPage(name: mounts, page: () => const FileMountView()),
    GetPage(name: backup, page: () => const FileBackupView()),
    GetPage(name: nascabCallback, page: () => const NasCabCallbackView()),
    GetPage(name: terminal, page: () => const TerminalPage()),
    GetPage(name: encryptedSpace, page: () => const EncryptedSpaceView()),
    GetPage(
      name: appUploadCenter,
      page: () {
        final args = Get.arguments;
        String? initialTargetDir;
        if (args is Map) {
          final v = args['targetDir']?.toString().trim() ?? '';
          if (v.isNotEmpty) initialTargetDir = v;
        }
        return AppUploadCenterView(initialTargetDir: initialTargetDir);
      },
    ),
    GetPage(name: appPhotoBackup, page: () => const AppPhotoBackupView()),
    GetPage(
      name: home,
      page: () {
        if (DeviceUtils.isMobile) {
          return const AppHomePage();
        }
        return PcHomePage();
      },
    ),
    GetPage(name: userManagement, page: () => UserManagementView()),
    GetPage(name: videoDetail, page: () => const VideoDetailPage()),
  ];

  static Future<void> toVideoPlayer({
    required List<Map<String, dynamic>> playlist,
    int initialIndex = 0,
    int ignoreFindSub = 1,
    Transition? transition,
  }) async {
    if (playlist.isEmpty) return;
    if (_videoPlayerOpening) return;
    _videoPlayerOpening = true;
    try {
    final routeArgs = <String, dynamic>{
      'playlist': playlist,
      'initialIndex': initialIndex,
      'ignoreFindSub': ignoreFindSub,
    };
    final t = transition ?? Transition.noTransition;
    if (DeviceUtils.isDesktop) {
      await Get.to(
        () => PcVideoPlayerView(playlist: playlist, initialIndex: initialIndex),
        transition: t,
        duration: Duration.zero,
        arguments: routeArgs,
      );
      return;
    }
    await Get.to(
      () => AppVideoPlayerPage(playlist: playlist, initialIndex: initialIndex),
      transition: t,
      duration: Duration.zero,
      arguments: routeArgs,
    );
    } finally {
      _videoPlayerOpening = false;
    }
  }

  static void toFiles({String? initialPath}) {
    if (initialPath != null && initialPath.trim().isNotEmpty) {
      Get.toNamed(files, arguments: {'initialPath': initialPath});
      return;
    }
    Get.toNamed(files);
  }

  static void toPhotoTimeline() {
    Get.toNamed(photoTimeline);
  }

  /// 导航到服务器列表页面
  static void toServerList() {
    Get.offAllNamed(serverList);
  }

  /// 导航到服务器列表页面
  static void toLogin() {
    Get.offAllNamed(login);
  }

  /// 导航到设置页面
  static void toSettings() {
    Get.toNamed(settings);
  }

  static void toTerminal() {
    Get.toNamed(terminal);
  }

  static void toHome({Transition transition = Transition.leftToRight}) {
    Get.offAll(() {
      if (DeviceUtils.isMobile) {
        return const AppHomePage();
      }
      return PcHomePage();
    }, transition: transition);
  }

  /// 返回上一页
  static void back() {
    Get.back();
  }

  static void toVideoDetail(int indexId) {
    if (Get.isRegistered<VideoMainController>()) {
      Get.find<VideoMainController>().openDetail(indexId);
      return;
    }
    Get.toNamed(videoDetail, arguments: {'index_id': indexId});
  }

  static void toVideoSubDetail(int indexId) {
    if (Get.isRegistered<VideoMainController>()) {
      Get.find<VideoMainController>().openSubDetail(indexId);
      return;
    }
    Get.toNamed(videoDetail, arguments: {'index_id': indexId});
  }
}
