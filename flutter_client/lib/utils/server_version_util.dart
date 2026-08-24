class ServerVersionUtil {
  const ServerVersionUtil._();

  static int? parseMajorVersion(String? version) {
    if (version == null) return null;
    final trimmed = version.trim();
    if (trimmed.isEmpty) return null;
    final normalized = (trimmed.startsWith('v') || trimmed.startsWith('V'))
        ? trimmed.substring(1)
        : trimmed;
    final parts = normalized.split('.');
    if (parts.isEmpty) return null;
    final match = RegExp(r'(\d+)').firstMatch(parts.first);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static bool isAtLeast(
    String? version,
    int majorVersion, {
    bool unknownAsSupported = true,
  }) {
    final major = parseMajorVersion(version);
    if (major == null) return unknownAsSupported;
    return major >= majorVersion;
  }
}
