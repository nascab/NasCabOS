import { window } from '@kit.ArkUI';

/**
 * 主窗口缓存：EntryAbility 启动时写入。
 * 沉浸式页面切换 setWindowLayoutFullScreen 必须同步调用
 * （getLastWindow 异步 promise 顺序不可控，会产生竞态），统一从这里取窗口实例。
 */
export class WindowStore {
  private static mainWindow: window.Window | undefined = undefined;

  static setMainWindow(w: window.Window): void {
    WindowStore.mainWindow = w;
  }

  static getMainWindow(): window.Window | undefined {
    return WindowStore.mainWindow;
  }
}
