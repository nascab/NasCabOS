import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import '../../../../utils/browse_path_utils.dart';
import '../beans/video_item_bean.dart';

String videoMediaTypeText(String mediaType) {
  final t = mediaType.toLowerCase();
  if (t == 'tv' || t == 'episod' || t == 'season') {
    return 'video_home_type_tv'.tr;
  }
  if (t == 'movie' || t == 'bdmv' || t == 'video_ts') return 'video_home_type_movie'.tr;
  return mediaType;
}

String buildVideoHomeMeta(VideoHomeItemBean item) {
  String pickFirst(String s) {
    final parts = s
        .split(RegExp(r'[,，/|、]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.first;
  }

  final country = pickFirst(item.nfoRegions);
  final genre = pickFirst(item.nfoGenres);
  if (country.isEmpty && genre.isEmpty) return '';
  if (country.isEmpty) return genre;
  if (genre.isEmpty) return country;
  return '$country · $genre';
}

String resolveVideoBrowsePath(VideoHomeItemBean item) {
  final t = item.mediaType.toLowerCase().trim();
  if (t == 'movie' || t == 'bdmv' || t == 'video_ts') {
    final full = item.fullPath.trim().isNotEmpty
        ? item.fullPath.trim()
        : (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty)
        ? p.join(item.path.trim(), item.filename.trim())
        : '';
    return full.isNotEmpty ? browseFolderPathVideo(full) : '';
  }
  if (t == 'tv' || t == 'season' || t == 'episod') {
    final full = item.fullPath.trim();
    if (full.isNotEmpty) return browseFolderPathVideo(full);
  }
  final base = item.path.trim();
  if (base.isNotEmpty) return browseFolderPathVideo(base);
  final full = item.fullPath.trim();
  return full.isNotEmpty ? browseFolderPathVideo(full) : '';
}

String resolveVideoDeletePath(VideoHomeItemBean item) {
  final t = item.mediaType.toLowerCase().trim();
  if (t == 'movie' || t == 'bdmv' || t == 'video_ts') {
    if (item.fullPath.trim().isNotEmpty) return item.fullPath.trim();
    if (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty) {
      return p.join(item.path.trim(), item.filename.trim());
    }
  }
  if (t == 'tv' || t == 'season') {
    final full = item.fullPath.trim();
    if (full.isNotEmpty) return full;
  }
  final base = item.path.trim();
  if (base.isNotEmpty) return base;
  return item.fullPath.trim();
}

String resolveVideoDownloadPath(VideoHomeItemBean item) {
  final t = item.mediaType.toLowerCase().trim();
  if (t == 'movie' || t == 'bdmv' || t == 'video_ts') {
    if (item.fullPath.trim().isNotEmpty) return item.fullPath.trim();
    if (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty) {
      return p.join(item.path.trim(), item.filename.trim());
    }
    return '';
  }

  if (t == 'tv' || t == 'season') {
    if (item.fullPath.trim().isNotEmpty) return item.fullPath.trim();
    if (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty) {
      return p.join(item.path.trim(), item.filename.trim());
    }
    return item.path.trim();
  }

  if (item.fullPath.trim().isNotEmpty) return item.fullPath.trim();
  if (item.path.trim().isNotEmpty && item.filename.trim().isNotEmpty) {
    return p.join(item.path.trim(), item.filename.trim());
  }
  return item.path.trim();
}
