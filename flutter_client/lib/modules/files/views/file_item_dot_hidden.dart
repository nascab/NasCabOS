/// 与服务端目录列出逻辑一致：名称以 `.` 开头（虚拟行除外）。
bool fileItemIsDotHidden(Map<String, dynamic> item) {
  final vt = item['virtualType']?.toString() ?? '';
  if (vt.isNotEmpty) return false;
  final n = item['name']?.toString() ?? '';
  return n.isNotEmpty && n.startsWith('.');
}

/// 隐藏文件在列表中的不透明度（半透效果）
const double kFileHiddenListOpacity = 0.52;
