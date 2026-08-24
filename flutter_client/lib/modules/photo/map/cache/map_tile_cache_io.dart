import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 与图片缓存同根目录，单独子文件夹，便于统计与清理（cacheimage 已递归统计）
const String _mapTileCacheSubPath = 'cacheimage/map_tiles';

Future<String?> _cacheDirPath() async {
  try {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, _mapTileCacheSubPath);
  } catch (_) {}
  return null;
}

Future<Uint8List?> readMapTileCache(String cacheKey) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, _mapTileCacheSubPath, cacheKey));
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {}
  return null;
}

Future<void> writeMapTileCache(String cacheKey, Uint8List bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, _mapTileCacheSubPath));
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File(p.join(folder.path, cacheKey));
    await file.writeAsBytes(bytes);
  } catch (_) {}
}

/// 清空全部地图瓦片磁盘缓存（切换瓦片服务器时调用）
Future<void> clearMapTileCache() async {
  try {
    final path = await _cacheDirPath();
    if (path == null) return;
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  } catch (_) {}
}
