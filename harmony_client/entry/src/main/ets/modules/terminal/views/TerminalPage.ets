import { window } from '@kit.ArkUI';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { L10n } from '../../../core/localization/L10n';
import { TerminalController } from '../controllers/TerminalController';
import { TerminalOutputView } from '../components/TerminalOutputView';
import { showTerminalSettingsSheet } from '../components/TerminalSettingsSheet';
import { TerminalMainPageParam } from '../router/TerminalRoutes';

/**
 * 终端页（对齐 Flutter TerminalPage 移动端布局）：
 * 顶栏（返回 + 标题）→ 状态条（连接中/断开等，空时隐藏）→ 终端输出区 → 命令输入行（历史/发送）
 * → 底部工具栏（win32 shell 切换、复制/粘贴、Ctrl+C、重连、设置）。
 * 全屏交互页：根组件 NavDestination，自行处理沉浸式与状态栏。
 */
@ComponentV2
export struct TerminalPage {
  @Param param: TerminalMainPageParam = new TerminalMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: TerminalController = TerminalController.getInstance();
  @Local inputText: string = '';
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  @Local statusBarHeight: number = 0;
  @Local navigationBarHeight: number = 0;
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
    void this.ctrl.attach(this.param.instanceId);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    this.applyStatusBar();
    this.ctrl.detach();
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

  // ===== 交互 =====

  private sendInput(): void {
    this.ctrl.sendCommand(this.inputText);
    this.inputText = '';
  }

  private historyUp(): void {
    this.inputText = this.ctrl.historyBack(this.inputText);
  }

  private historyDown(): void {
    this.inputText = this.ctrl.historyForward();
  }

  private async pasteFromClipboard(): Promise<void> {
    const text = await this.ctrl.pasteFromClipboard();
    if (text.length > 0) {
      this.inputText = text;
    }
  }

  private openSettings(): void {
    showTerminalSettingsSheet(this.ctrl);
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

  /** 命令输入行：历史上下翻 + 输入框 + 发送 */
  @Builder
  InputBar() {
    Row({ space: 6 }) {
      this.IconButton($r('sys.symbol.chevron_up'), (): void => {
        this.historyUp();
      }, true, L10n.t('terminal_input_hint', '输入命令'))
      this.IconButton($r('sys.symbol.chevron_down'), (): void => {
        this.historyDown();
      }, true, L10n.t('terminal_input_hint', '输入命令'))

      TextInput({
        text: this.inputText,
        placeholder: L10n.t('terminal_input_hint', '输入命令')
      })
        .enterKeyType(EnterKeyType.Send)
        .fontSize(14)
        .fontFamily('monospace')
        .fontColor(this.ctrl.uiConfig.foreground)
        .caretColor(this.ctrl.uiConfig.cursor)
        .placeholderColor(AppTheme.withAlpha(this.ctrl.uiConfig.foreground, 0.4))
        .backgroundColor(AppTheme.withAlpha(this.ctrl.uiConfig.foreground, 0.08))
        .border({ width: 1, color: AppTheme.withAlpha(this.ctrl.uiConfig.foreground, 0.15) })
        .borderRadius(8)
        .height(38)
        .layoutWeight(1)
        .onChange((v: string): void => {
          this.inputText = v;
        })
        .onSubmit((_enterKey: EnterKeyType, _event: SubmitEvent): void => {
          this.sendInput();
        })

      Button() {
        SymbolGlyph($r('sys.symbol.paperplane'))
          .fontSize(16)
          .fontColor([this.palette().buttonText])
      }
      .type(ButtonType.Circle)
      .width(34)
      .height(34)
      .backgroundColor(this.palette().primary)
      .onClick((): void => {
        this.sendInput();
      })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .border({ width: { top: 1 }, color: this.palette().divider })
    .backgroundColor(this.ctrl.uiConfig.background)
  }

  /** 底部工具栏（对齐 Flutter _TerminalBottomBar，移动端布局） */
  @Builder
  BottomBar() {
    Row() {
      if (this.ctrl.isWin32) {
        this.ShellChip('PowerShell', this.ctrl.currentShell === 'powershell', (): void => {
          this.ctrl.switchShell('powershell');
        })
        this.ShellChip('CMD', this.ctrl.currentShell === 'cmd', (): void => {
          this.ctrl.switchShell('cmd');
        })
      }
      Blank()

      Row({ space: 4 }) {
        // 移动端无右键菜单，提供复制/粘贴按钮（对齐 Flutter isMobile 分支）
        this.BarButton($r('sys.symbol.doc_filled_on_doc'), (): void => {
          this.ctrl.copyBufferToClipboard();
        }, true)
        this.BarButton($r('sys.symbol.text_clipboard'), (): void => {
          void this.pasteFromClipboard();
        }, true)
        this.BarButton($r('sys.symbol.xmark_circle'), (): void => {
          this.ctrl.interruptRunningCommand();
        }, this.ctrl.connected)
        this.BarButton($r('sys.symbol.arrow_clockwise'), (): void => {
          this.ctrl.reconnectNow();
        }, true)
        this.BarButton($r('sys.symbol.gearshape'), (): void => {
          this.openSettings();
        }, true)
      }
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(44 + this.navigationBarHeight)
    .padding({ left: 10, right: 10, bottom: this.navigationBarHeight })
    .border({ width: { top: 1 }, color: this.palette().divider })
    .backgroundColor(this.palette().surfaceBg)
  }

  @Builder
  ShellChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(selected ? this.palette().buttonText : this.palette().onSurface)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(6)
      .backgroundColor(selected ? this.palette().primary : this.palette().inputFill)
      .margin({ right: 6 })
      .onClick((): void => {
        onTap();
      })
  }

  /** 工具栏图标按钮（36x30 点击区，禁用时半透明） */
  @Builder
  BarButton(icon: Resource, onTap: () => void, enabled: boolean) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([enabled
          ? this.palette().onSurface
          : AppTheme.withAlpha(this.palette().onSurface, 0.45)])
    }
    .width(36)
    .height(30)
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (enabled) {
        onTap();
      }
    })
  }

  /** 输入行小图标按钮（历史上下翻） */
  @Builder
  IconButton(icon: Resource, onTap: () => void, enabled: boolean, hint: string = '') {
    Row() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([enabled
          ? this.palette().subText
          : AppTheme.withAlpha(this.palette().onSurface, 0.3)])
    }
    .width(30)
    .height(30)
    .borderRadius(8)
    .justifyContent(FlexAlign.Center)
    .accessibilityText(hint)
    .onClick((): void => {
      if (enabled) {
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
        Column() {
          TerminalOutputView({ ctrl: this.ctrl })
        }
        .width('100%')
        .layoutWeight(1)

        this.InputBar()
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
