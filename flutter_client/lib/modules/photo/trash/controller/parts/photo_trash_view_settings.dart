part of '../photo_trash_controller.dart';

// 视图设置管理
extension PhotoTrashViewSettings on PhotoTrashController {
  /// 调整缩略图大小
  void adjustItemSize(double delta) {
    double newSize = itemSize.value + delta;
    newSize = newSize.clamp(minItemSize.toDouble(), maxItemSize.toDouble());
    itemSize.value = newSize;
  }

  /// 放大缩略图
  void zoomIn() {
    adjustItemSize(60);
  }

  /// 缩小缩略图
  void zoomOut() {
    adjustItemSize(-60);
  }
}
