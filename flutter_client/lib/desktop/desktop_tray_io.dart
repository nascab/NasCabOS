import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/languages/language_service.dart';

/// 桌面端：关窗时收到托盘而非退出；托盘菜单可恢复窗口或彻底退出。
class DesktopTray {
  DesktopTray._();

  static bool _inited = false;

  static String _label(String key) {
    final loc = LanguageService.to.currentLocale;
    final map = LanguageService.to.keys[loc];
    return map?[key] ?? key;
  }

  static Future<void> _showMainWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  static Future<void> _quitApp() async {
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  static Future<void> _applyContextMenu() async {
    final menu = Menu(
      items: [
        MenuItem(
          key: 'tray_show',
          label: _label('tray_show_main_window'),
          onClick: (_) {
            Future<void>(() => _showMainWindow());
          },
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'tray_exit',
          label: _label('tray_exit_app'),
          onClick: (_) {
            Future<void>(() => _quitApp());
          },
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  static Future<void> updateMenu() async {
    if (!_inited) return;
    await _applyContextMenu();
  }

  static Future<void> init() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;

    if (_inited) return;
    _inited = true;

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);

    if (Platform.isWindows) {
      await trayManager.setIcon('assets/tray_icon_round.ico');
    } else {
      await trayManager.setIcon('assets/home/logo_round.png');
    }
    await trayManager.setToolTip('NasCabOS');
    await _applyContextMenu();

    trayManager.addListener(_DesktopTrayListener());
    windowManager.addListener(_DesktopWindowListener());

    LanguageService.to.addOnLanguageChangedCallback(updateMenu);
  }
}

class _DesktopTrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    Future<void>(() => DesktopTray._showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}

class _DesktopWindowListener with WindowListener {
  @override
  void onWindowClose() {
    windowManager.hide();
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'close') {
      windowManager.hide();
    }
  }
}
