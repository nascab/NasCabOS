part of '../file_controller.dart';

extension FileControllerSelection on FileController {
  void toggleSelect(String path) {
    if (selected.contains(path)) {
      selected.remove(path);
    } else {
      selected.add(path);
    }
    selected.refresh();
  }

  void clearSelect() {
    selected.clear();
    selected.refresh();
  }

  /// 仅选中指定项目
  void selectOnly(String path) {
    selected
      ..clear()
      ..add(path);
    selected.refresh(); // 通知监听器集合变化
  }

  List<String> getSelected() => selected.toList(growable: false);

  /// 与列表项 `type` 对齐：`dir` → 目录；其它非空类型 → 文件；找不到或 `type` 为空 → 未知。
  bool? remoteIsDirectoryHintForPath(String path) {
    for (final e in displayItems) {
      if (e['path']?.toString() == path) {
        final t = e['type']?.toString() ?? '';
        if (t == 'dir') return true;
        if (t.isEmpty) return null;
        return false;
      }
    }
    return null;
  }

  /// 与 [paths] 顺序一一对应，供 [DownloadController.handleDownload] 使用。
  List<bool?> remoteIsDirectoryHintsForPaths(Iterable<String> paths) {
    return paths.map(remoteIsDirectoryHintForPath).toList(growable: false);
  }

  bool get isAdditiveSelectionActive {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    bool hasShift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight) ||
        keys.contains(LogicalKeyboardKey.shift);
    bool hasMeta =
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.meta);
    bool hasCtrl =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.control);
    return hasShift || hasMeta || hasCtrl;
  }
}
