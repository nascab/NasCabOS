import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_utils.dart';
import '../core/config/nascab_endpoints.dart';

/// 新版本检测：仅 android/linux/mac/windows，24 小时最多检测一次，缓存上次成功结果，所有异常内部吞掉不外溢。
class UpdateCheckHelper {
  UpdateCheckHelper._();

  static const String _baseUrl =
      '${NasCabEndpoints.websiteBaseUrl}/config/updateInfo';
  static const String _keyLastCheckTime = 'update_check_last_time_ms';
  static const String _keyCachedJson = 'update_info_cached_json';
  static const String _keyLastPromptedVersion =
      'update_prompt_last_version_shown';
  static const int _checkIntervalMs = 24 * 60 * 60 * 1000;

  /// 当前平台对应的 JSON 文件名，不检测的平台返回 null。
  static String? get _platformId {
    if (kIsWeb) return null;
    if (DeviceUtils.isAndroid) return 'android';
    if (DeviceUtils.isLinux) return 'linux';
    if (DeviceUtils.isMacOS) return 'mac';
    if (DeviceUtils.isWindows) return 'windows';
    return null;
  }

  static void _log(String msg) {
    // ignore: avoid_print
    print('[UpdateCheck] $msg');
  }

  /// 解析并返回缓存的更新信息；解析失败或未缓存返回 null。不抛异常。
  static Future<UpdateInfo?> getCachedUpdateInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_keyCachedJson);
      if (jsonStr == null || jsonStr.isEmpty) return null;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>?;
      if (map == null) return null;
      final newVersion = map['new_version']?.toString();
      final openUrl = map['open_url']?.toString();
      if (newVersion == null || newVersion.isEmpty) return null;
      return UpdateInfo(newVersion: newVersion, openUrl: openUrl ?? '');
    } catch (_) {
      return null;
    }
  }

  /// 若 newVersion > currentVersion 返回 true，否则 false。异常或格式不符返回 false。
  static bool isNewVersionGreater(String? newVersion, String? currentVersion) {
    try {
      if (newVersion == null ||
          newVersion.isEmpty ||
          currentVersion == null ||
          currentVersion.isEmpty) return false;
      final newParts = _parseVersion(newVersion);
      final curParts = _parseVersion(currentVersion);
      if (newParts == null || curParts == null) return false;
      for (int i = 0; i < 3; i++) {
        final n = newParts[i];
        final c = curParts[i];
        if (n > c) return true;
        if (n < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int>? _parseVersion(String v) {
    final parts = v.trim().split('.');
    if (parts.isEmpty) return null;
    final out = <int>[];
    for (int i = 0; i < 3; i++) {
      final s = i < parts.length ? parts[i].trim() : '0';
      final n = int.tryParse(s) ?? 0;
      out.add(n);
    }
    return out;
  }

  /// 执行检测：先读缓存并立即返回；若平台支持且距上次检测已超过 24 小时则后台请求并更新缓存。
  /// [currentVersion] 当前应用版本，用于与缓存的 new_version 比较。
  /// 返回是否有可用更新（new_version > currentVersion）；任何异常都不会外溢，仅返回 false 或之前缓存结果。
  static Future<bool> checkForUpdate(String? currentVersion) async {
    try {
      _log('checkForUpdate currentVersion=$currentVersion');
      final cached = await getCachedUpdateInfo();
      final hasUpdateFromCache =
          cached != null && isNewVersionGreater(cached.newVersion, currentVersion);
      if (cached != null) {
        _log('cached: newVersion=${cached.newVersion} openUrl=${cached.openUrl} hasUpdateFromCache=$hasUpdateFromCache');
      } else {
        _log('no cached update info');
      }

      final platformId = _platformId;
      if (platformId == null) {
        _log('platformId=null, skip fetch (not android/linux/mac/windows)');
        return hasUpdateFromCache;
      }
      _log('platformId=$platformId');

      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_keyLastCheckTime);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (lastMs != null && (now - lastMs) < _checkIntervalMs) {
        _log('within 24h since last check, skip fetch. lastMs=$lastMs now=$now');
        return hasUpdateFromCache;
      }

      final url = '$_baseUrl/$platformId.json';
      _log('fetch url=$url');
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('', 408),
          );
      _log('response statusCode=${response.statusCode} bodyLength=${response.body.length} body=${response.body.isEmpty ? "(empty)" : response.body}');
      if (response.statusCode != 200 || response.body.isEmpty) {
        _log('skip: statusCode!=200 or empty body');
        return hasUpdateFromCache;
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      if (map == null) {
        _log('skip: json decode null');
        return hasUpdateFromCache;
      }

      final newVersion = map['new_version']?.toString();
      if (newVersion == null || newVersion.isEmpty) {
        _log('skip: new_version missing or empty');
        return hasUpdateFromCache;
      }

      await prefs.setString(_keyCachedJson, response.body);
      await prefs.setInt(_keyLastCheckTime, now);
      _log('cached updated newVersion=$newVersion');
      return isNewVersionGreater(newVersion, currentVersion);
    } catch (e, st) {
      _log('exception: $e');
      _log('stackTrace: $st');
      try {
        final cached = await getCachedUpdateInfo();
        return cached != null &&
            isNewVersionGreater(cached.newVersion, currentVersion);
      } catch (_) {
        return false;
      }
    }
  }

  /// 获取用于展示的更新信息（来自缓存或 null）。不抛异常。
  static Future<UpdateInfo?> getUpdateInfoIfNewer(String? currentVersion) async {
    try {
      final cached = await getCachedUpdateInfo();
      if (cached == null) return null;
      if (!isNewVersionGreater(cached.newVersion, currentVersion)) return null;
      return cached;
    } catch (_) {
      return null;
    }
  }

  /// 该版本是否需要弹窗提示（每个版本最多提示一次）。
  /// - 若未曾提示过该版本，返回 true
  /// - 若已提示过同版本，返回 false
  ///
  /// 仅做“是否已提示过”判断，不做版本大小比较。
  static Future<bool> shouldPromptForVersion(String? newVersion) async {
    try {
      final v = (newVersion ?? '').trim();
      if (v.isEmpty) return false;
      final prefs = await SharedPreferences.getInstance();
      final last = (prefs.getString(_keyLastPromptedVersion) ?? '').trim();
      return last != v;
    } catch (_) {
      return false;
    }
  }

  /// 记录该版本已提示过（用于“每版本最多一次”的去重）。
  static Future<void> markPromptedVersion(String? newVersion) async {
    try {
      final v = (newVersion ?? '').trim();
      if (v.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastPromptedVersion, v);
    } catch (_) {}
  }
}

class UpdateInfo {
  final String newVersion;
  final String openUrl;

  const UpdateInfo({required this.newVersion, required this.openUrl});
}
