part of '../pc_file_explorer_controller.dart';

extension PcFileExplorerViewMode on PcFileExplorerController {
  /// 获取文件类型字符串
  String getFileTypeStr(String type) {
    switch (type) {
      case 'dir':
        return 'dir'.tr;
      case 'image':
        return 'file_type_image'.tr;
      case 'video':
        return 'file_type_video'.tr;
      case 'archive':
        return 'file_type_archive'.tr;
      default:
        return 'file'.tr;
    }
  }

  /// 从缓存加载视图模式
  void _loadViewMode() {
    final cachedMode = CacheManager().getString(CacheKeys.fileViewMode);
    if (cachedMode != null &&
        (cachedMode == 'grid' ||
            cachedMode == 'list' ||
            cachedMode == 'large_grid')) {
      viewMode.value = cachedMode;
    }
  }

  /// 切换视图模式
  void toggleViewMode(String mode) {
    if (mode == 'grid' || mode == 'list' || mode == 'large_grid') {
      viewMode.value = mode;
      // 保存到缓存
      CacheManager().setString(CacheKeys.fileViewMode, mode);
    }
  }
}
