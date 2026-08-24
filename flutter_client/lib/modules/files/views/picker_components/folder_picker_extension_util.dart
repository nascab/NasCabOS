import 'package:path/path.dart' as p;

String normalizePickerExtension(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return '';
  return text.startsWith('.') ? text.substring(1) : text;
}

bool folderPickerPathMatchesExtension(String path, List<String> allowedExtensions) {
  if (allowedExtensions.isEmpty) return true;
  final ext = normalizePickerExtension(p.extension(path));
  if (ext.isEmpty) return false;
  for (final allowed in allowedExtensions) {
    if (ext == normalizePickerExtension(allowed)) return true;
  }
  return false;
}

String folderPickerAllowedExtensionsLabel(List<String> allowedExtensions) {
  return allowedExtensions
      .map(normalizePickerExtension)
      .where((ext) => ext.isNotEmpty)
      .map((ext) => '.$ext')
      .join(', ');
}
