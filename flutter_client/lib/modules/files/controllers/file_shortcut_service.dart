import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../home/views/pc_home_controller.dart';
import 'pc_file_explorer_controller.dart';
import '../views/pc_components/pc_file_context_menu_handler.dart';

class FileShortcutService extends GetxService {
  static FileShortcutService ensure() {
    if (Get.isRegistered<FileShortcutService>()) {
      return Get.find<FileShortcutService>();
    }
    return Get.put(FileShortcutService(), permanent: true);
  }

  final Map<String, PcFileExplorerController> _controllersByWindowId = {};
  bool _handlerInstalled = false;

  void register({
    required String windowId,
    required PcFileExplorerController controller,
  }) {
    _controllersByWindowId[windowId] = controller;
    _installHandlerIfNeeded();
  }

  void unregister(String windowId) {
    _controllersByWindowId.remove(windowId);
  }

  void _installHandlerIfNeeded() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    ServicesBinding.instance.keyboard.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final home = PcHomeController.instance;
    final topmostWindowId = home.topmostApp;
    if (topmostWindowId.isEmpty) return false;
    if (!_isFolderWindowId(topmostWindowId)) return false;

    final ctrl = _controllersByWindowId[topmostWindowId];
    if (ctrl == null) return false;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (!ctrl.pointerInView.value) return false;
      if (ctrl.selected.length != 1) return false;
      PcFileContextMenuHandler.showPropertiesDialog(ctrl.selected.toList());
      return true;
    }

    final isCtrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!isCtrlOrMeta) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyA) {
      if (!ctrl.pointerInView.value) return false;
      ctrl.selectAllVisible();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      if (ctrl.selected.isNotEmpty) {
        ctrl.copyToClipboard();
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyX) {
      if (ctrl.selected.isNotEmpty) {
        ctrl.cutToClipboard();
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      // “最近”“收藏”列表不能作为黏贴目的地，不响应 Ctrl+V / Cmd+V
      final mod = ctrl.currentModule.value;
      if (mod == 'recent' || mod == 'favorites') return false;
      if (ctrl.clipboardItems.isNotEmpty) {
        ctrl.pasteFromClipboard();
        return true;
      }
      return false;
    }

    return false;
  }

  bool _isFolderWindowId(String windowId) {
    return windowId == 'folder' || windowId.startsWith('folder_');
  }
}
