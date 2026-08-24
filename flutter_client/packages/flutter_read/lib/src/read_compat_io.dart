import 'dart:io';

class ReadCompat {
  static final ReadCompat _instance = ReadCompat._internal();

  factory ReadCompat() {
    return _instance;
  }

  ReadCompat._internal();

  bool? _isDartVersionAtLeast300;

  bool isDartVersionAtLeast300() {
    if (_isDartVersionAtLeast300 != null) {
      return _isDartVersionAtLeast300!;
    }
    final versionPattern = RegExp(r'(\d+)\.(\d+)\.(\d+)');
    final match = versionPattern.firstMatch(Platform.version);

    if (match != null && match.groupCount == 3) {
      final major = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minor = int.tryParse(match.group(2) ?? '0') ?? 0;
      final patch = int.tryParse(match.group(3) ?? '0') ?? 0;

      if (major > 3 ||
          (major == 3 && (minor > 0 || (minor == 0 && patch >= 0)))) {
        return _isDartVersionAtLeast300 = true;
      }
    }
    return _isDartVersionAtLeast300 = false;
  }
}
