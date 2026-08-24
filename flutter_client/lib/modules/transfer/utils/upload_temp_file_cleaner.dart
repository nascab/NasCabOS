import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// iOS 下相册/文件选择器可能会把资源导出到应用沙盒的临时/缓存目录。
/// 这些文件在上传完成或任务被移除后可以安全清理，避免残留占用空间。
class UploadTempFileCleaner {
  static final UploadTempFileCleaner instance = UploadTempFileCleaner._();

  UploadTempFileCleaner._();

  Directory? _tmpDir;
  Directory? _cacheDir;
  Directory? _supportDir;

  Future<void> _ensureDirs() async {
    _tmpDir ??= await getTemporaryDirectory();
    try {
      _cacheDir ??= await getApplicationCacheDirectory();
    } catch (_) {
      // Older path_provider versions may not support this API.
    }
    _supportDir ??= await getApplicationSupportDirectory();
  }

  bool _isUnder(Directory dir, String filePath) {
    final root = p.normalize(dir.path);
    final f = p.normalize(filePath);
    if (root.isEmpty || f.isEmpty) return false;
    if (root == f) return true;
    return f.startsWith('$root${p.separator}') || f.startsWith('$root/');
  }

  /// 尝试删除 iOS 应用沙盒临时/缓存目录下的文件。
  /// 非 iOS、Web、或非沙盒临时/缓存目录内的路径会被忽略。
  Future<void> maybeDeleteSandboxTempFile(String path) async {
    if (kIsWeb) return;
    if (!Platform.isIOS) return;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;

    await _ensureDirs();
    final tmp = _tmpDir;
    final cache = _cacheDir;
    final support = _supportDir;

    final inTmp = tmp != null && _isUnder(tmp, trimmed);
    final inCache = cache != null && _isUnder(cache, trimmed);
    final inSupport = support != null && _isUnder(support, trimmed);
    if (!inTmp && !inCache && !inSupport) return;

    try {
      final f = File(trimmed);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  /// 启动时兜底：清理 iOS 沙盒临时/缓存目录中“过期”的文件。
  ///
  /// - 只在 iOS 非 Web 生效
  /// - 默认只扫描 tmp + cache（support 默认不扫，避免误删业务持久化文件）
  /// - 只删除 lastModified 早于 [maxAge] 的文件
  Future<void> sweepStaleFiles({
    Duration maxAge = const Duration(hours: 24),
    bool includeCache = true,
    bool includeSupport = false,
  }) async {
    if (kIsWeb) return;
    // if (!Platform.isIOS) return;
    if (maxAge <= Duration.zero) return;

    await _ensureDirs();
    final now = DateTime.now();

    final dirs = <Directory>[
      if (_tmpDir != null) _tmpDir!,
      if (includeCache && _cacheDir != null) _cacheDir!,
      if (includeSupport && _supportDir != null) _supportDir!,
    ];
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) continue;
      } catch (_) {
        continue;
      }

      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            final age = now.difference(stat.modified);
            if (age >= maxAge) {
              await entity.delete();
            }
          } catch (_) {
            // ignore per-file errors
          }
        }
      } catch (_) {
        // ignore per-dir errors
      }
    }
  }
}

