import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地数据缓存管理器
/// 支持结构化数据的存储和读取
class CacheManager {
  static final CacheManager _instance = CacheManager._internal();

  factory CacheManager() {
    return _instance;
  }

  CacheManager._internal();

  late SharedPreferences _prefs;

  /// 初始化缓存管理器
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 存储字符串数据
  Future<bool> setString(String key, String value) async {
    return await _prefs.setString(key, value);
  }

  /// 获取字符串数据
  String? getString(String key) {
    return _prefs.getString(key);
  }

  /// 存储整数数据
  Future<bool> setInt(String key, int value) async {
    return await _prefs.setInt(key, value);
  }

  /// 获取整数数据
  int? getInt(String key) {
    return _prefs.getInt(key);
  }

  /// 存储布尔数据
  Future<bool> setBool(String key, bool value) async {
    return await _prefs.setBool(key, value);
  }

  /// 获取布尔数据
  bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  /// 存储双精度浮点数数据
  Future<bool> setDouble(String key, double value) async {
    return await _prefs.setDouble(key, value);
  }

  /// 获取双精度浮点数数据
  double? getDouble(String key) {
    return _prefs.getDouble(key);
  }

  /// 存储字符串列表数据
  Future<bool> setStringList(String key, List<String> value) async {
    return await _prefs.setStringList(key, value);
  }

  /// 获取字符串列表数据
  List<String>? getStringList(String key) {
    return _prefs.getStringList(key);
  }

  /// 存储JSON对象（Map或List）
  Future<bool> setJson(String key, dynamic jsonObject) async {
    try {
      final jsonString = jsonEncode(jsonObject);
      return await setString(key, jsonString);
    } catch (e) {
      print('存储JSON对象失败: $e');
      return false;
    }
  }

  /// 获取JSON对象
  dynamic getJson(String key) {
    try {
      final jsonString = getString(key);
      if (jsonString != null) {
        return jsonDecode(jsonString);
      }
      return null;
    } catch (e) {
      print('获取JSON对象失败: $e');
      return null;
    }
  }

  /// 存储自定义对象（需要实现toJson方法）
  Future<bool> setObject<T>(String key, T object) async {
    try {
      if (object is Map || object is List) {
        return await setJson(key, object);
      } else if (object is String) {
        return await setString(key, object);
      } else if (object is int) {
        return await setInt(key, object);
      } else if (object is bool) {
        return await setBool(key, object);
      } else if (object is double) {
        return await setDouble(key, object);
      } else {
        // 尝试调用toJson方法
        final json = _toJson(object);
        if (json != null) {
          return await setJson(key, json);
        }
        return false;
      }
    } catch (e) {
      print('存储对象失败: $e');
      return false;
    }
  }

  /// 获取自定义对象（需要提供fromJson工厂方法）
  T? getObject<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    try {
      final jsonData = getJson(key);
      if (jsonData is Map<String, dynamic>) {
        return fromJson(jsonData);
      }
      return null;
    } catch (e) {
      print('获取对象失败: $e');
      return null;
    }
  }

  /// 获取对象列表
  List<T>? getObjectList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    try {
      final jsonData = getJson(key);
      if (jsonData is List) {
        return jsonData
            .map((item) {
              if (item is Map<String, dynamic>) {
                return fromJson(item);
              }
              return null;
            })
            .where((item) => item != null)
            .cast<T>()
            .toList();
      }
      return null;
    } catch (e) {
      print('获取对象列表失败: $e');
      return null;
    }
  }

  /// 检查是否存在某个key
  bool containsKey(String key) {
    return _prefs.containsKey(key);
  }

  /// 删除指定key的数据
  Future<bool> remove(String key) async {
    return await _prefs.remove(key);
  }

  /// 清空所有缓存数据
  Future<bool> clear() async {
    return await _prefs.clear();
  }

  /// 获取所有key
  Set<String> getKeys() {
    return _prefs.getKeys();
  }

  /// 带过期时间的存储
  Future<bool> setWithExpiry(
    String key,
    String value,
    Duration expiryDuration,
  ) async {
    final expiryTime = DateTime.now()
        .add(expiryDuration)
        .millisecondsSinceEpoch;
    final data = {'value': value, 'expiry': expiryTime};
    return await setJson('_expiry_$key', data);
  }

  /// 获取带过期时间的数据
  String? getWithExpiry(String key) {
    final data = getJson('_expiry_$key');
    if (data is Map<String, dynamic>) {
      final expiry = data['expiry'] as int?;
      final value = data['value'] as String?;

      if (expiry != null && value != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now <= expiry) {
          return value;
        } else {
          // 数据已过期，删除它
          remove('_expiry_$key');
        }
      }
    }
    return null;
  }

  /// 私有方法：尝试将对象转换为JSON
  dynamic _toJson(dynamic object) {
    try {
      // 尝试调用toJson方法
      if (object != null && object is Map) {
        return object;
      }

      // 使用dart:mirrors的替代方案
      final json = _convertToJson(object);
      return json;
    } catch (e) {
      print('对象转换JSON失败: $e');
      return null;
    }
  }

  /// 简单的对象转JSON转换（适用于简单对象）
  Map<String, dynamic>? _convertToJson(dynamic object) {
    if (object == null) return null;

    // 这里可以扩展支持更多类型的对象转换
    // 目前只支持基本类型和Map
    if (object is Map) {
      return Map<String, dynamic>.from(object);
    }

    return null;
  }
}

/// 缓存键常量类
class CacheKeys {
  static const String userInfo = 'user_info';
  static const String userApps = 'user_apps';
  static const String userWallpaper = 'user_wallpaper';
  static const String appSettings = 'app_settings';
  static const String themeMode = 'theme_mode';
  static const String language = 'language';
  static const String lastLoginTime = 'last_login_time';
  static const String cachedData = 'cached_data';
  static const String token = 'auth_token';
  static const String refreshToken = 'refresh_token';
  static const String nascabOsJwt = 'nascab_os_jwt';
  static const String p2pLastPairCode = 'p2p_last_pair_code';
  static const String windowStates = 'window_states';
  static const String deviceFingerprintSeed = 'device_fingerprint_seed';
  static const String videoPlayerDeviceId = 'video_player_device_id';
  static const String fileViewMode = 'file_view_mode';
  static const String photoFootprintMapState = 'photo_footprint_map_state';
  static const String musicDiscStyleIndex = 'music_disc_style_index';
  static const String musicLoopModeIndex = 'music_loop_mode_index';
  static const String musicVolume = 'music_volume';
  static const String musicVolumeBeforeMute = 'music_volume_before_mute';
  static const String musicAudioCacheEnabled = 'music_audio_cache_enabled';
  static const String musicAudioCacheMaxItems = 'music_audio_cache_max_items';
  static const String musicAudioCacheIndex = 'music_audio_cache_index';
  static const String musicFullScreenShowLyrics =
      'music_fullscreen_show_lyrics';
  static const String imageCompressQuality = 'image_compress_quality';
  static const String imageCompressFormat = 'image_compress_format';
  static const String imageCompressSize = 'image_compress_size';
  static const String imageCompressCustomOutSize =
      'image_compress_custom_out_size';
  static const String imageCompressWithMeta = 'image_compress_with_meta';
  static const String bookListSelectedPaths = 'book_list_selected_paths';
  static const String musicListSelectedPaths = 'music_list_selected_paths';

  /// 图书列表排序（与 [BookListController] 的 scope 拼接，见该控制器内缓存键构造）
  static const String bookListSortByPrefix = 'book_list_sort_by_';
  static const String bookListSortOrderPrefix = 'book_list_sort_order_';

  /// 音乐曲库列表排序（与 [MusicListController] 的 scope 拼接）
  static const String musicListSortByPrefix = 'music_list_sort_by_';
  static const String musicListSortOrderPrefix = 'music_list_sort_order_';

  /// 音乐二级列表排序（所有二级列表共用）
  static const String musicSubListSortBy = 'music_sub_list_sort_by';
  static const String musicSubListSortOrder = 'music_sub_list_sort_order';

  /// 照片预览：WiFi 下默认浏览原图（仅手机端，本地缓存）
  static const String photoPreviewWifiOriginal = 'photo_preview_wifi_original';
}
