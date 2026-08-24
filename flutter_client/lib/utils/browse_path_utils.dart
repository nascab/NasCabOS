import 'package:path/path.dart' as p;

final _pathWindows = p.Context(style: p.Style.windows);

/// 远端/库路径常为 Windows 盘符或 UNC；在 macOS/iOS 等非 Windows 客户端上默认 POSIX 的 [p.dirname]
/// 会把 `E:\dir\a.mp4` 当成无分隔符的单段路径，得到 `.`。对明显为 Windows 的路径改用 Windows 语义。
bool looksLikeWindowsServerPath(String s) {
  final t = s.trim();
  if (t.length >= 3) {
    final a = t.codeUnitAt(0);
    final letter = (a >= 0x41 && a <= 0x5A) || (a >= 0x61 && a <= 0x7A);
    if (letter && t[1] == ':' && (t[2] == r'\' || t[2] == '/')) {
      return true;
    }
  }
  if (t.startsWith(r'\\')) return true;
  return false;
}

/// 在非 Windows 客户端上正确解析远端 Windows/UNC 路径的父目录。
String browsePathDirname(String path) {
  final s = path.trim();
  if (s.isEmpty) return s;
  if (looksLikeWindowsServerPath(s)) {
    return _pathWindows.dirname(s);
  }
  return p.dirname(s);
}

/// 文件浏览需传入目录：若 [path] 的扩展名属于 [fileLikeExtensions]（小写，含点）则取父目录。
String browseFolderPathForKnownFile(
  String path,
  Set<String> fileLikeExtensions,
) {
  final s = path.trim();
  if (s.isEmpty) return '';
  final ext = p.extension(s).toLowerCase();
  if (ext.isEmpty) return s;
  if (fileLikeExtensions.contains(ext)) {
    return browsePathDirname(s);
  }
  return s;
}

const Set<String> kBrowseVideoFileExtensions = {
  '.mkv',
  '.mp4',
  '.avi',
  '.mov',
  '.wmv',
  '.flv',
  '.webm',
  '.m4v',
  '.ts',
  '.m2ts',
  '.mts',
  '.mpg',
  '.mpeg',
  '.mpe',
  '.divx',
  '.rm',
  '.rmvb',
  '.iso',
  '.strm',
  '.srt',
  '.ass',
  '.ssa',
  '.sub',
  '.idx',
  '.sup',
  '.nfo',
};

const Set<String> kBrowseAudioFileExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.wav',
  '.wma',
  '.ape',
  '.alac',
  '.aiff',
  '.aif',
  '.mpc',
  '.tta',
  '.wv',
  '.dsf',
  '.dff',
  '.ac3',
  '.dts',
};

const Set<String> kBrowseBookFileExtensions = {
  '.pdf',
  '.epub',
  '.mobi',
  '.azw',
  '.azw3',
  '.kfx',
  '.txt',
  '.djvu',
  '.chm',
  '.cbr',
  '.cbz',
  '.fb2',
};

/// 照片/实况常见后缀（含实况视频侧车 .mov/.mp4）。
const Set<String> kBrowsePhotoFileExtensions = {
  '.jpg',
  '.jpeg',
  '.jpe',
  '.jfif',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.tif',
  '.tiff',
  '.heic',
  '.heif',
  '.avif',
  '.cr2',
  '.cr3',
  '.nef',
  '.nrw',
  '.arw',
  '.orf',
  '.raf',
  '.dng',
  '.raw',
  '.rw2',
  '.pef',
  '.srw',
  '.livp',
  '.mp4',
  '.mov',
  '.m4v',
};

String browseFolderPathVideo(String path) =>
    browseFolderPathForKnownFile(path, kBrowseVideoFileExtensions);

String browseFolderPathMusic(String path) =>
    browseFolderPathForKnownFile(path, kBrowseAudioFileExtensions);

String browseFolderPathBook(String path) =>
    browseFolderPathForKnownFile(path, kBrowseBookFileExtensions);

String browseFolderPathPhoto(String path) =>
    browseFolderPathForKnownFile(path, kBrowsePhotoFileExtensions);
