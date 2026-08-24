part of '../pc_file_explorer_controller.dart';

extension PcFileExplorerLifecycle on PcFileExplorerController {
  void _onControllerInit() {
    PcFileExplorerViewMode(this)._loadViewMode();
  }

  void _onControllerClose() {
    print('控制器已经销毁 PcFileExplorerController onClose');
  }
}
