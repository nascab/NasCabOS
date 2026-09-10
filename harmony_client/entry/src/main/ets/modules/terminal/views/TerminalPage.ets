import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import pasteboard from '@ohos.pasteboard';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { TerminalController } from '../controllers/TerminalController';
import { showTerminalSettingsSheet } from '../components/TerminalSettingsSheet';
import { TerminalMainPageParam } from '../router/TerminalRoutes';

const TAG = '[TerminalPage]';
/** Web 终端本地源（onInterceptRequest 拦截到 rawfile/terminal/） */
const TERMINAL_ORIGIN: string = 'http://nascab.terminal';
const TERMINAL_START_URL: string = `${TERMINAL_ORIGIN}/index.html`;
const TERMINAL_RAW_BASE: string = 'terminal/';

// ===== Web 桥 =====

/** JS → 原生回调集合（javaScriptProxy 注册对象；方法名与 index.html 协议一致） */
class TerminalWebProxy {
  onReady: () => void = (): void => {
  };
  onData: (data: string) => void = (_data: string): void => {
  };
  onResize: (cols: number, rows: number) => void = (_cols: number, _rows: number): void => {
  };
}

/** 解包 runJavaScript 的字符串返回（内核可能 JSON 引号包裹） */
function unwrapJsString(v: string): string {
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    try {
      const parsed = JSON.parse(v) as Object;
      if (typeof parsed === 'string') {
        return parsed as string;
      }
    } catch (_e) {
      // 非引号包裹原样返回
    }
  }
  return v;
}

function mimeOf(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return 'text/html';
  }
  if (lower.endsWith('.js')) {
    return 'application/javascript';
  }
  if (lower.endsWith('.css')) {
    return 'text/css';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  return 'application/octet-stream';
}

/**
 * 终端页（对齐 Flutter TerminalPage 移动端布局）：
 * 顶栏（返回 + 标题）→ 状态条（连接中/断开等，空时隐藏）→ Web xterm.js 终端区
 * → 底部工具栏（win32 shell 切换、复制/粘贴、Ctrl+C、重连、设置）。
 * 渲染采用 Web xterm.js（对齐 Flutter xterm 包的完整 VT/转义序列能力）；
 * WebSocket 数据经 TerminalController 批量转发到 term.write，键盘输入经桥回传服务端。
 * 全屏交互页：根组件 NavDestination，自行处理沉浸式与状态栏。
 */
@ComponentV2
export struct TerminalPage {
  @Param param: TerminalMainPageParam = new TerminalMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: TerminalController = TerminalController.getInstance();
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  @Local statusBarHeight: number = 0;
  @Local navigationBarHeight: number = 0;
  private webController: webview.WebviewController = new webview.WebviewController();
  private webProxy: TerminalWebProxy = new TerminalWebProxy();
  /** Web xterm 是否已就绪（onReady 后为 true） */
  private webReady: boolean = false;
  /** Web 未就绪期间的输出缓冲（ready 后一次性写入） */
  private pendingWebData: string = '';
  /** 避让布局重试定时器（纠正 push 转场对窗口布局写入的回滚） */
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.setFullScreen(true);
    this.fetchSafeAreas();
    this.bindBridge();
    this.ctrl.onTerminalData = (data: string): void => {
      this.writeToWeb(data);
    };
    this.ctrl.onUiConfigChanged = (): void => {
      this.pushConfigToWeb();
    };
    void this.ctrl.attach(this.param.instanceId);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    this.applyStatusBar();
    this.ctrl.onTerminalData = undefined;
    this.ctrl.onUiConfigChanged = undefined;
    this.ctrl.detach();
  }

  // ===== Web 桥 =====

  private bindBridge(): void {
    this.webProxy.onReady = (): void => {
      this.webReady = true;
      this.pushConfigToWeb();
      if (this.pendingWebData.length > 0) {
        const buffered = this.pendingWebData;
        this.pendingWebData = '';
        this.runJs(`window.__termWrite(${JSON.stringify(buffered)})`);
      }
      this.runJs('window.__termFocus()');
    };
    this.webProxy.onData = (data: string): void => {
      this.ctrl.sendRawInput(data);
    };
    this.webProxy.onResize = (cols: number, rows: number): void => {
      this.ctrl.sendResize(cols, rows);
    };
  }

  private runJs(script: string): void {
    if (!this.webReady) {
      return;
    }
    try {
      this.webController.runJavaScript(script);
    } catch (e) {
      hilog.error(0x0000, TAG, 'runJavaScript failed: %{public}s', `${JSON.stringify(e)}`);
    }
  }

  /** Web 未就绪时缓冲输出，就绪后直写 */
  private writeToWeb(data: string): void {
    if (!this.webReady) {
      this.pendingWebData += data;
      return;
    }
    this.runJs(`window.__termWrite(${JSON.stringify(data)})`);
  }

  /** 推送 UI 配置（颜色/字号/行高/光标）到 Web xterm */
  private pushConfigToWeb(): void {
    this.runJs(`window.__termApply(${JSON.stringify(this.ctrl.uiConfig.toJson())})`);
  }

  /** 复制当前选区（无选区提示），对齐 Flutter xterm 复制体验 */
  private async copySelection(): Promise<void> {
    let text = '';
    try {
      const raw = await this.webController.runJavaScript('window.__termSelection()');
      text = unwrapJsString(raw ?? '');
    } catch (_e) {
      text = '';
    }
    if (text.trim().length === 0) {
      ToastUtil.show(L10n.t('terminal_no_selection', '没有选中的内容'));
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setPasteData(data);
      ToastUtil.show(L10n.t('quick_share_copied', '已复制'));
    } catch (_e) {
      // 剪贴板不可用时忽略
    }
  }

  /** 粘贴剪贴板文本到终端（对齐 Flutter TerminalView.paste） */
  private async pasteFromClipboard(): Promise<void> {
    const text = await this.ctrl.pasteFromClipboard();
    if (text.length === 0) {
      return;
    }
    this.runJs(`window.__termPaste(${JSON.stringify(text)})`);
  }

  private openSettings(): void {
    showTerminalSettingsSheet(this.ctrl);
  }

  // ===== 沉浸式与状态栏（参考 NotesMainPage） =====

  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w !== undefined) {
      w.setWindowLayoutFullScreen(full);
    }
  }

  /** push 转场会回滚窗口布局写入（实测）：延迟重设纠正 */
  private scheduleFullScreenRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.setFullScreen(true);
    }, 120);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private fetchSafeAreas(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = Math.min(Math.max(px2vp(top.topRect.height), 0), 140);
    const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.navigationBarHeight = Math.min(Math.max(px2vp(bottom.bottomRect.height), 0), 60);
  }

  private static setStatusBar(ctx: Context, contentColor: string, bgColor: string): void {
    try {
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
    }
  }

  private applyStatusBar(): void {
    const p = AppTheme.current();
    TerminalPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  // ===== Web 资源拦截 =====

  /** 本地资源拦截：http://nascab.terminal/<rest> → rawfile/terminal/<rest> */
  private interceptRequest(event: OnInterceptRequestEvent): WebResourceResponse | null {
    const url = event.request.getRequestUrl();
    if (!url.startsWith(TERMINAL_ORIGIN)) {
      return null;
    }
    let path = url.substring(TERMINAL_ORIGIN.length);
    const q = path.indexOf('?');
    if (q >= 0) {
      path = path.substring(0, q);
    }
    let rest = path === '/' || path === '' ? 'index.html' : path.substring(1);
    if (rest.length === 0 || rest.includes('..')) {
      return null;
    }
    const resp = new WebResourceResponse();
    resp.setResponseData($rawfile(TERMINAL_RAW_BASE + rest));
    resp.setResponseMimeType(mimeOf(rest));
    if (rest.endsWith('.html') || rest.endsWith('.js') || rest.endsWith('.css')) {
      resp.setResponseEncoding('utf-8');
    }
    resp.setResponseCode(200);
    resp.setReasonMessage('OK');
    resp.setResponseIsReady(true);
    const headers: Header[] = [];
    headers.push({ headerKey: 'Cache-Control', headerValue: 'no-store' });
    resp.setResponseHeader(headers);
    return resp;
  }

  // ===== UI =====

  @Builder
  TopBar() {
    Column() {
      Row({ space: 4 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(24)
            .fontColor([this.palette().onSurface])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => {
          this.popPage();
        })

        Text(L10n.t('terminal_title', '终端'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(this.ctrl.isWin32
          ? (this.ctrl.currentShell === 'cmd' ? 'CMD' : 'PowerShell')
          : '')
          .fontSize(12)
          .fontColor(this.palette().subText)
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 14 })
    }
    .width('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.palette().surfaceBg)
  }

  @Builder
  StatusBanner() {
    Text(this.ctrl.statusText)
      .fontSize(13)
      .fontColor(this.palette().onSurface)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.palette().inputFill)
  }

  /** Web xterm 终端区（占满剩余空间，xterm fit 自适应） */
  @Builder
  TerminalWeb() {
    Web({ src: TERMINAL_START_URL, controller: this.webController })
      .width('100%')
      .layoutWeight(1)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .zoomAccess(false)
      .backgroundColor(this.ctrl.uiConfig.background)
      .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
        return this.interceptRequest(event);
      })
      .javaScriptProxy({
        object: this.webProxy,
        name: 'natBridge',
        methodList: ['onReady', 'onData', 'onResize'],
        controller: this.webController
      })
      .onTouch((_event: TouchEvent): void => {
        // 触摸终端区时聚焦 xterm（弹出软键盘）
        if (!this.webReady) {
          return;
        }
        try {
          this.webController.runJavaScript('window.__termFocus()');
        } catch (_e) {
          // 忽略
        }
      })
  }

  /** 底部工具栏（对齐 Flutter _TerminalBottomBar，移动端布局） */
  @Builder
  BottomBar() {
    Row() {
      if (this.ctrl.isWin32) {
        this.ShellChip('powershell', 'PowerShell')
        this.ShellChip('cmd', 'CMD')
      }
      Blank()

      Row({ space: 4 }) {
        // 移动端无右键菜单，提供复制/粘贴按钮（对齐 Flutter isMobile 分支）
        this.BarButton($r('sys.symbol.doc_filled_on_doc'), (): void => {
          void this.copySelection();
        }, 'always')
        this.BarButton($r('sys.symbol.text_clipboard'), (): void => {
          void this.pasteFromClipboard();
        }, 'always')
        this.BarButton($r('sys.symbol.xmark_circle'), (): void => {
          this.ctrl.interruptRunningCommand();
        }, 'connectedOnly')
        this.BarButton($r('sys.symbol.arrow_clockwise'), (): void => {
          this.ctrl.reconnectNow();
        }, 'always')
        this.BarButton($r('sys.symbol.gearshape'), (): void => {
          this.openSettings();
        }, 'always')
      }
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(44 + this.navigationBarHeight)
    .padding({ left: 10, right: 10, bottom: this.navigationBarHeight })
    .border({ width: { top: 1 }, color: this.palette().divider })
    .backgroundColor(this.palette().surfaceBg)
  }

  /** shell 切换芯片：选中态在 Builder 内直接读 @Trace 属性，保证切换后 UI 刷新 */
  @Builder
  ShellChip(shellType: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.ctrl.currentShell === shellType ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.ctrl.currentShell === shellType
        ? this.palette().buttonText : this.palette().onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(6)
      .backgroundColor(this.ctrl.currentShell === shellType
        ? this.palette().primary : this.palette().inputFill)
      .margin({ right: 6 })
      .onClick((): void => {
        this.ctrl.switchShell(shellType);
      })
  }

  /** 工具栏图标按钮（36x30 点击区，禁用时半透明）；enabled 在 Builder 内读取 @Trace 保证刷新 */
  @Builder
  BarButton(icon: Resource, onTap: () => void, state: string) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([state === 'always' || this.ctrl.connected
          ? this.palette().onSurface
          : AppTheme.withAlpha(this.palette().onSurface, 0.45)])
    }
    .width(36)
    .height(30)
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (state === 'always' || this.ctrl.connected) {
        onTap();
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        this.TopBar()
        if (this.ctrl.statusText.trim().length > 0) {
          this.StatusBanner()
        }
        this.TerminalWeb()
        this.BottomBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().surfaceBg)
      .opacity(this.themeTick >= 0 ? 1 : 1)
    }
    .hideTitleBar(true)
    .onShown((): void => {
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
      this.fetchSafeAreas();
      this.applyStatusBar();
      // 兜底自愈：页面可见但连接既未建立也未在连接中时，强制重连
      // （覆盖单例控制器状态残留、首次连接失败后自动重连被禁等场景）
      setTimeout((): void => {
        if (!this.ctrl.connected && !this.ctrl.connecting) {
          this.ctrl.reconnectNow();
        }
      }, 600);
    })
    .onHidden((): void => {
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }
}
