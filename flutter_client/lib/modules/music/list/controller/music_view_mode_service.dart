import 'package:get/get.dart';

import '../../../../utils/cache_manager.dart';

/// 音乐列表显示模式的全局共享状态。
///
/// 曲库歌曲/收藏列表与专辑/艺人列表共用同一份响应式状态：
/// 任一页面切换显示模式后，其他页面立即同步；同时写入本地缓存，应用重启后保持。
class MusicViewModeService extends GetxService {
  static const String defaultMode = 'grid';

  /// 支持的显示模式：网格 / 列表
  static const List<String> supportedModes = ['grid', 'list'];

  static MusicViewModeService get instance => Get.find<MusicViewModeService>();

  static MusicViewModeService ensure() {
    if (Get.isRegistered<MusicViewModeService>()) {
      return Get.find<MusicViewModeService>();
    }
    return Get.put(MusicViewModeService(), permanent: true);
  }

  /// 当前显示模式，全局唯一
  final RxString mode = defaultMode.obs;

  MusicViewModeService() {
    final cached = _readMode();
    if (cached != null && supportedModes.contains(cached)) {
      mode.value = cached;
    }
  }

  String? _readMode() {
    try {
      return CacheManager().getString(CacheKeys.musicViewMode);
    } catch (_) {
      return null;
    }
  }

  /// 切换显示模式（非法值忽略），并持久化到本地
  void setMode(String next) {
    if (!supportedModes.contains(next) || next == mode.value) return;
    mode.value = next;
    try {
      CacheManager().setString(CacheKeys.musicViewMode, next);
    } catch (_) {}
  }

  /// 在网格 / 列表之间切换
  void toggle() {
    setMode(mode.value == 'list' ? 'grid' : 'list');
  }
}
