part of '../pc_file_explorer_controller.dart';

extension PcFileExplorerLayout on PcFileExplorerController {
  /// 设置左侧面板宽度
  void setLeftWidth(double w) {
    if (w < 120) w = 120;
    if (w > 300) w = 300;
    leftWidth.value = w;
  }
}
