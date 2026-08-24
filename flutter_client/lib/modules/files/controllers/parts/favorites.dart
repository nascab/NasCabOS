part of '../file_controller.dart';

extension FileControllerFavorites on FileController {
  /// 加载快捷访问：收藏与最近
  Future<void> loadQuickAccess() async {
    try {
      await _api.listRecent();
    } catch (_) {}
  }

  Future<bool> clearRecent() async {
    try {
      final ok = await _api.clearRecent();
      if (ok && currentModule.value == 'recent') {
        await listDirectory('', 'recent');
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// 添加到收藏
  Future<bool> addFavorites(List<String> paths) async {
    try {
      final ok = await _api.addFavorites(paths);
      if (currentModule.value == 'favorites') {
        await refreshPage();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// 取消收藏
  Future<bool> removeFavorites(List<String> paths) async {
    try {
      final ok = await _api.removeFavorites(paths);
      if (currentModule.value == 'favorites') {
        await refreshPage();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }
}
