import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<int> getImageDiskCacheSizeBytes() async {
  final roots = <Directory>[];
  try {
    roots.add(await getTemporaryDirectory());
  } catch (_) {}
  try {
    roots.add(await getApplicationSupportDirectory());
  } catch (_) {}

  final candidates = <Directory>[];
  for (final root in roots) {
    for (final name in const [
      'libCachedImageData', // flutter_cache_manager DefaultCacheManager
      'customCacheKey', // CustomCacheManager
      'cacheimage', // extended_image_library 直连网络图磁盘缓存目录
      'extended_image_cache',
      'extended_image',
    ]) {
      candidates.add(Directory(p.join(root.path, name)));
    }
  }

  int total = 0;
  for (final dir in candidates) {
    total += await _safeDirectorySize(dir);
  }
  return total;
}

Future<int> _safeDirectorySize(Directory dir) async {
  try {
    if (!await dir.exists()) return 0;
  } catch (_) {
    return 0;
  }

  int size = 0;
  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          size += await entity.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return size;
}
