import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 与 extended_image_library 共用目录，便于统计与清理
const String _p2pCacheFolderName = 'cacheimage';

Future<Uint8List?> readP2pImageCache(String cacheKey) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, _p2pCacheFolderName, cacheKey));
    if (await file.exists()) return await file.readAsBytes();
  } catch (_) {}
  return null;
}

Future<void> writeP2pImageCache(String cacheKey, Uint8List bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, _p2pCacheFolderName));
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File(p.join(folder.path, cacheKey));
    await file.writeAsBytes(bytes);
  } catch (_) {}
}
