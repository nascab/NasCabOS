import 'package:get/get.dart';
import '../../utils/cache_manager.dart';
import '../../../core/api/api_controller.dart';
import '../../../modules/photoBackup/controller/photo_backup_controller.dart';

class UserApps {
  final List<String> hideApp;
  final List<String> allApp;

  UserApps({this.hideApp = const [], this.allApp = const []});

  List<String> get showApp =>
      allApp.where((e) => !hideApp.contains(e)).toList();

  factory UserApps.fromMap(Map<String, dynamic> map) {
    final all = map['all_app'] != null
        ? List<String>.from(map['all_app'])
        : <String>[];
    final hide = map['hide_app'] != null
        ? List<String>.from(map['hide_app'])
        : <String>[];
    final sanitizedHide = hide.where((e) => all.contains(e)).toList();
    return UserApps(hideApp: sanitizedHide, allApp: all);
  }

  @override
  String toString() {
    return 'UserApps(hideApp: $hideApp, allApp: $allApp)';
  }
}

class UserWallpaper {
  final String? name;
  final String? url;
  final String? type;

  UserWallpaper({this.name, this.url, this.type});

  factory UserWallpaper.fromMap(Map<String, dynamic> map) {
    return UserWallpaper(
      name: map['name']?.toString(),
      url: map['url']?.toString(),
      type: map['type']?.toString(),
    );
  }

  @override
  String toString() {
    return 'UserWallpaper(name: $name, url: $url, type: $type)';
  }
}

class CurrentUser {
  final int? id;
  final String? username;
  final String? phone;
  final String? language;
  final String? question;
  final String? answer;
  final String? avatar;
  final String? type;

  CurrentUser({
    this.id,
    this.username,
    this.phone,
    this.language,
    this.question,
    this.answer,
    this.avatar,
    this.type,
  });
  @override
  toString() {
    return 'CurrentUser(id: $id, username: $username, phone: $phone, language: $language, question: $question, answer: $answer, avatar: $avatar, type: $type)';
  }

  factory CurrentUser.fromMap(Map<String, dynamic> map) {
    return CurrentUser(
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}'),
      username: map['username']?.toString(),
      phone: map['phone']?.toString(),
      language: map['language']?.toString(),
      question: map['question']?.toString(),
      avatar: map['avatar']?.toString(),
      type: map['type']?.toString(),
    );
  }
}

class CurrentUserController extends GetxController {
  static CurrentUserController get instance =>
      Get.find<CurrentUserController>();
  final Rxn<CurrentUser> _current = Rxn<CurrentUser>();
  final Rxn<UserApps> _apps = Rxn<UserApps>();
  final Rxn<UserWallpaper> _wallpaper = Rxn<UserWallpaper>();

  CurrentUser? get current => _current.value;
  // 示例数据 {hide_app: [photo, video, folder, setting, book, music], all_app: [photo, video, folder, setting, book, music]}
  UserApps? get apps => _apps.value;
  // 示例数据 {name: 1.webp, url: /wallpaper/1.webp, type: webp}
  UserWallpaper? get wallpaper => _wallpaper.value;
  String? get wallPapperUrl => ApiController.instance.getWallPapperUrl();

  bool get isLoggedIn => _current.value != null;
  bool get isAdmin =>
      (_current.value?.type == 'super_admin' ||
      _current.value?.type == 'admin');

  void setUser(CurrentUser user) {
    _current.value = user;
    CacheManager().setJson(CacheKeys.userInfo, {
      'id': user.id,
      'username': user.username,
      'phone': user.phone,
      'language': user.language,
      'question': user.question,
      'answer': user.answer,
      'avatar': user.avatar,
      'type': user.type,
    });
    if (Get.isRegistered<PhotoBackupController>()) {
      Get.find<PhotoBackupController>().onSessionMaybeChanged();
    }
  }

  void setUserFromMap(Map<String, dynamic> map) {
    _current.value = CurrentUser.fromMap(map);
    CacheManager().setJson(CacheKeys.userInfo, map);
    if (Get.isRegistered<PhotoBackupController>()) {
      Get.find<PhotoBackupController>().onSessionMaybeChanged();
    }
  }

  void setApps(Map<String, dynamic> map) {
    _apps.value = UserApps.fromMap(map);
    CacheManager().setJson(CacheKeys.userApps, map);
  }

  void setWallpaper(Map<String, dynamic> map) {
    _wallpaper.value = UserWallpaper.fromMap(map);
    CacheManager().setJson(CacheKeys.userWallpaper, map);
  }

  void clearWallpaper() {
    _wallpaper.value = null;
    CacheManager().remove(CacheKeys.userWallpaper);
  }

  void clear() {
    _current.value = null;
    _apps.value = null;
    _wallpaper.value = null;
    CacheManager().remove(CacheKeys.userInfo);
    CacheManager().remove(CacheKeys.userApps);
    CacheManager().remove(CacheKeys.userWallpaper);
    if (Get.isRegistered<PhotoBackupController>()) {
      Get.find<PhotoBackupController>().onSessionMaybeChanged();
    }
  }

  @override
  void onInit() {
    super.onInit();
    final userJson = CacheManager().getJson(CacheKeys.userInfo);
    if (userJson is Map<String, dynamic>) {
      _current.value = CurrentUser.fromMap(userJson);
    }
    final appsJson = CacheManager().getJson(CacheKeys.userApps);
    if (appsJson is Map<String, dynamic>) {
      _apps.value = UserApps.fromMap(appsJson);
    }
    final wallJson = CacheManager().getJson(CacheKeys.userWallpaper);
    if (wallJson is Map<String, dynamic>) {
      _wallpaper.value = UserWallpaper.fromMap(wallJson);
    }
  }
}
