import 'dart:async';
import 'dart:io' show Platform;

import 'package:window_manager/window_manager.dart';

void appWindowTitleSetImpl(String title) {
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    return;
  }
  unawaited(_setDesktopTitle(title));
}

Future<void> _setDesktopTitle(String title) async {
  try {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(title);
  } catch (_) {}
}
