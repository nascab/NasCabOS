import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题管理器 - 负责主题设置的持久化保存和读取
class ThemeManager {
  static const String _themeModeKey = 'app_theme_mode';

  static final ThemeManager _instance = ThemeManager._internal();

  factory ThemeManager() {
    return _instance;
  }

  ThemeManager._internal();

  late SharedPreferences _prefs;

  /// 初始化主题管理器
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 保存主题模式
  Future<bool> saveThemeMode(ThemeMode themeMode) async {
    try {
      final themeValue = _themeModeToInt(themeMode);
      return await _prefs.setInt(_themeModeKey, themeValue);
    } catch (e) {
      print('保存主题模式失败: $e');
      return false;
    }
  }

  /// 获取保存的主题模式，如果没有保存则返回默认的深色模式
  ThemeMode getThemeMode() {
    try {
      final themeValue = _prefs.getInt(_themeModeKey);
      if (themeValue != null) {
        return _intToThemeMode(themeValue);
      }
    } catch (e) {
      print('获取主题模式失败: $e');
    }

    // 如果没有找到缓存，默认使用深色模式
    return ThemeMode.dark;
  }

  /// 将ThemeMode转换为整数存储
  int _themeModeToInt(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return 0;
      case ThemeMode.dark:
        return 1;
      case ThemeMode.system:
        return 2;
    }
  }

  /// 将整数转换为ThemeMode
  ThemeMode _intToThemeMode(int value) {
    switch (value) {
      case 0:
        return ThemeMode.light;
      case 1:
        return ThemeMode.dark;
      case 2:
        return ThemeMode.system;
      default:
        return ThemeMode.dark; // 默认值
    }
  }

  /// 清除主题设置
  Future<bool> clearThemeMode() async {
    try {
      return await _prefs.remove(_themeModeKey);
    } catch (e) {
      print('清除主题模式失败: $e');
      return false;
    }
  }
}
