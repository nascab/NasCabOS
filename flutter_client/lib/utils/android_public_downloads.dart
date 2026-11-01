import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// 把下载完成的文件写入 Android 公共 Download 目录。
/// Android 10+ 通过 MediaStore 写入（无需存储权限）；Android 9 及以下写入公共目录并申请写权限。
class AndroidPublicDownloads {
  AndroidPublicDownloads._();

  static const MethodChannel _channel = MethodChannel(
    'com.nascabos/public_downloads',
  );

  /// 拷贝 [sourcePath] 到公共目录下的 [relativeDir]（如 `Download/NasCabOS`）。
  /// 返回写入后的绝对路径；失败或非 Android 平台返回 `null`。
  static Future<String?> save({
    required String sourcePath,
    required String fileName,
    required String relativeDir,
  }) async {
    if (!Platform.isAndroid) return null;
    if (!await _ensureLegacyWritePermission()) return null;
    try {
      final result = await _channel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'relativeDir': relativeDir,
      });
      final path = result?.trim();
      return (path == null || path.isEmpty) ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// Android 10 起分区存储下写公共 Download 不需要权限；更低版本需写外部存储权限。
  static Future<bool> _ensureLegacyWritePermission() async {
    try {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdkInt >= 29) return true;
    } catch (_) {
      return true;
    }
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    final result = await Permission.storage.request();
    return result.isGranted;
  }
}
