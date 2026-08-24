import '../../../../core/api/api_controller.dart';
import '../beans/video_item_bean.dart';

class VideoUtils {
  static String getPosterUrl(VideoHomeItemBean item, {int? size}) {
    final posterPath = item.posterPath.trim();
    size ??= 500;
    if (posterPath.isNotEmpty) {
      return ApiController.instance.getTinyUrl(posterPath, size: size);
    }

    final fallbackFilePath = item.firstFilePath.isNotEmpty
        ? item.firstFilePath
        : item.fullPath;
    if (fallbackFilePath.trim().isEmpty) return '';
    return ApiController.instance.getTinyUrl(fallbackFilePath, size: size);
  }

  static String getFanartUrl(VideoHomeItemBean item, {int? size}) {
    size ??= 1600;
    final fanartPath = item.fanartPath.trim();
    if (fanartPath.isNotEmpty) {
      return ApiController.instance.getRawFileUrl(fanartPath);
    }
    // 没有 fanart 时回退到 poster，用 rawFile 避免加载 tiny 缩略图
    final posterPath = item.posterPath.trim();
    if (posterPath.isNotEmpty) {
      return ApiController.instance.getRawFileUrl(posterPath);
    }
    return getPosterUrl(item, size: size);
  }
}
