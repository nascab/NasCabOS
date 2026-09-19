import { window } from '@kit.ArkUI';
import { WindowStore } from './WindowStore';

/** 系统栏（状态栏 + 底部导航条）配色 */
export interface SystemBarColors {
  /** 状态栏图标/文字颜色 */
  statusBarContentColor: string;
  /** 状态栏背景色（沉浸页传 #00000000 透明，让应用背景透出） */
  statusBarColor: string;
  /** 底部导航条图标颜色 */
  navigationBarContentColor: string;
  /** 底部导航条背景色 */
  navigationBarColor: string;
}

/** 页面窗口样式：系统栏配色 + 全屏沉浸布局 + 系统栏显隐 */
export interface PageWindowStyle {
  /** 系统栏配色 */
  colors: SystemBarColors;
  /**
   * 是否全屏沉浸布局（setWindowLayoutFullScreen）：
   * true=内容顶到系统栏后方，页面自行用避让区 padding；
   * false=系统默认安全区布局（PageScaffold 类常规页）。
   */
  fullscreen: boolean;
  /**
   * 系统栏是否可见，默认 true。
   * 阅读器等场景可传 false 彻底隐藏状态栏与导航条。
   */
  barsVisible?: boolean;
}

interface WindowStyleEntry {
  /** 通常为页面组件实例（this），用于在样式栈中唯一标识一个页面 */
  owner: object;
  style: PageWindowStyle;
}

/**
 * 全局系统栏/沉浸式窗口样式管理。
 *
 * 用法（每个页面只需两行）：
 * ```ts
 * aboutToAppear() { SystemBars.activate(this, { colors: SystemBars.immersiveColors(), fullscreen: true }); }
 * aboutToDisappear() { SystemBars.deactivate(this); }
 * ```
 *
 * 原理：页面显示时 activate 把样式压栈，页面销毁/登出清空导航栈时 deactivate 出栈，
 * 窗口始终应用栈顶样式 —— 出栈后自动恢复上一页样式，无需各页面在返回时手动重置，
 * 也不存在“子页异步写入晚于父页重置”的竞态。
 *
 * 所有写入都走 WindowStore 缓存的主窗口同步调用（写顺序=调用顺序），
 * 并在 120ms 后重放一次栈顶样式，纠正 push/pop 转场期间系统对窗口布局写入的回滚。
 */
export class SystemBars {
  /** 转场回滚重试延迟（vp 页面实测值，与原各页面 scheduleXxxRetry 保持一致） */
  private static readonly RETRY_DELAY_MS: number = 120;

  private static stack: WindowStyleEntry[] = [];
  private static retryTimer: number = -1;
  /** 最近一次写入的系统栏显隐状态，避免相同值重复调用造成闪烁 */
  private static lastBarsVisible: boolean = true;

  /** 深色沉浸页统一配色：透明系统栏 + 白色图标（壁纸/深色背景图透出） */
  static immersiveColors(): SystemBarColors {
    return {
      statusBarContentColor: '#FFFFFF',
      statusBarColor: '#00000000',
      navigationBarContentColor: '#FFFFFF',
      navigationBarColor: '#00000000'
    };
  }

  /** 快速构造状态栏/导航条同色配色 */
  static colors(contentColor: string, bgColor: string): SystemBarColors {
    return {
      statusBarContentColor: contentColor,
      statusBarColor: bgColor,
      navigationBarContentColor: contentColor,
      navigationBarColor: bgColor
    };
  }

  /**
   * 页面可见时激活自己的窗口样式（aboutToAppear / onShown 调用，重复调用幂等）。
   * 同一 owner 再次调用会更新样式并移到栈顶。
   */
  static activate(owner: object, style: PageWindowStyle): void {
    const idx = SystemBars.stack.findIndex((e: WindowStyleEntry): boolean => e.owner === owner);
    if (idx >= 0) {
      SystemBars.stack.splice(idx, 1);
    }
    SystemBars.stack.push({ owner, style });
    SystemBars.render();
  }

  /**
   * 页面销毁时注销（aboutToDisappear 调用）。
   * 注销后自动应用当前栈顶（上一页）样式；栈空时仅取消重试。
   */
  static deactivate(owner: object): void {
    const idx = SystemBars.stack.findIndex((e: WindowStyleEntry): boolean => e.owner === owner);
    if (idx >= 0) {
      SystemBars.stack.splice(idx, 1);
    }
    const top = SystemBars.top();
    if (top !== undefined) {
      SystemBars.render();
    } else {
      SystemBars.cancelRetry();
    }
  }

  /**
   * 主题切换等场景更新已激活页面的样式（页面仍在栈中，不改变栈顺序）。
   * 仅当该页面位于栈顶时立即写入。
   */
  static update(owner: object, style: PageWindowStyle): void {
    const entry = SystemBars.stack.find((e: WindowStyleEntry): boolean => e.owner === owner);
    if (entry === undefined) {
      return;
    }
    entry.style = style;
    if (SystemBars.top() === entry) {
      SystemBars.render();
    }
  }

  /** 应用栈顶样式并安排一次转场重试 */
  private static render(): void {
    const top = SystemBars.top();
    if (top === undefined) {
      SystemBars.cancelRetry();
      return;
    }
    SystemBars.applyStyle(top.style);
    SystemBars.scheduleRetry();
  }

  /** 同步写入窗口样式（统一走缓存主窗口，杜绝 getLastWindow 异步竞态） */
  private static applyStyle(style: PageWindowStyle): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const barsVisible = style.barsVisible ?? true;
    if (barsVisible !== SystemBars.lastBarsVisible) {
      SystemBars.lastBarsVisible = barsVisible;
      w.setWindowSystemBarEnable(barsVisible ? ['status', 'navigation'] : [])
        .catch((_e: Object): void => {
        });
    }
    w.setWindowLayoutFullScreen(style.fullscreen).catch((_e: Object): void => {
    });
    w.setWindowSystemBarProperties({
      statusBarContentColor: style.colors.statusBarContentColor,
      statusBarColor: style.colors.statusBarColor,
      navigationBarContentColor: style.colors.navigationBarContentColor,
      navigationBarColor: style.colors.navigationBarColor
    }).catch((_e: Object): void => {
    });
  }

  /** push/pop 转场会回滚窗口布局写入（实测）：延迟重放栈顶样式兜底 */
  private static scheduleRetry(): void {
    SystemBars.cancelRetry();
    SystemBars.retryTimer = setTimeout((): void => {
      SystemBars.retryTimer = -1;
      const top = SystemBars.top();
      if (top !== undefined) {
        SystemBars.applyStyle(top.style);
      }
    }, SystemBars.RETRY_DELAY_MS);
  }

  private static cancelRetry(): void {
    if (SystemBars.retryTimer >= 0) {
      clearTimeout(SystemBars.retryTimer);
      SystemBars.retryTimer = -1;
    }
  }

  private static top(): WindowStyleEntry | undefined {
    return SystemBars.stack.length > 0 ? SystemBars.stack[SystemBars.stack.length - 1] : undefined;
  }
}
