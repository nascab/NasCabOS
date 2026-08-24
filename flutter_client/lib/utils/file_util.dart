import 'dart:math';

class FileUtil {
  static String formatSize(int? bytes) {
    bytes ??= 0;
    if (bytes <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // 简单的单位转换辅助函数
  // Simple unit conversion helper
  static double? parseSizeToBytes(String sizeFormatted) {
    try {
      final parts = sizeFormatted.trim().split(' ');
      if (parts.length != 2) return null;
      final value = double.tryParse(parts[0]);
      final unit = parts[1].toUpperCase();
      if (value == null) return null;

      switch (unit) {
        case 'TB':
          return value * 1024 * 1024 * 1024 * 1024;
        case 'GB':
          return value * 1024 * 1024 * 1024;
        case 'MB':
          return value * 1024 * 1024;
        case 'KB':
          return value * 1024;
        case 'B':
          return value;
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }
}
