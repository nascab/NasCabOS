/// Web 或非 IO 环境占位（无托盘、无拦截关窗）。
class DesktopTray {
  DesktopTray._();

  static Future<void> init() async {}
  static Future<void> updateMenu() async {}
}
