import 'dart:io';

class EncryptedSpaceDropHelper {
  static Future<bool> isDirectory(String path) async {
    try {
      return FileSystemEntity.isDirectory(path);
    } catch (_) {
      return false;
    }
  }

  static Stream<String> listFilesRecursively(String dirPath) async* {
    final root = Directory(dirPath);
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        yield entity.path;
      }
    }
  }
}
