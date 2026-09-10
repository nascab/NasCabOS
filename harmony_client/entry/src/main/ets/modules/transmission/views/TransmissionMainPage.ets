import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { TransmissionController } from '../controllers/TransmissionController';
import { showAddTorrentSheet } from '../components/AddTorrentSheet';
import { TransmissionOverviewTab } from './TransmissionOverviewTab';
import { TransmissionTorrentsTab } from './TransmissionTorrentsTab';
import { TransmissionSettingsTab } from './TransmissionSettingsTab';
import { TransmissionMainPageParam } from '../router/TransmissionRoutes';

/**
 * Transmission 主页（对齐 Flutter TransmissionView 移动端 appMode 形态）：
 * 顶栏 返回 + 标题 + 添加任务 + 刷新，底部 3 标签（总览/任务/设置），
 * 服务端版本过低时整页展示错误文案（对齐 Flutter errorText 分支）。
 */
@ComponentV2
export struct TransmissionMainPage {
  @Param param: TransmissionMainPageParam = new TransmissionMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器随页面创建销毁（对齐 Flutter GetBuilder init/dispose 生命周期） */
  @Local ctrl: TransmissionController = new TransmissionController();
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后顶栏用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp）：全屏布局后底部标签栏用它避让 */
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
    // 沉浸全屏布局（对齐笔记/影音主页）：页面自管安全区避让
    this.setFullScreen(true);
    this.fetchSafeAreas();
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    this.ctrl.onClose();
    this.applyStatusBar();
  }

  /** 全屏布局开关（窗口主窗口同步单例，写顺序=调用顺序） */
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
    TransmissionMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  /** 底部标签（对齐 Flutter BottomNavigationBar 3 项） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.square_grid_2x2'),
        L10n.t('transmission_tab_overview', '总览')),
      new BottomTabItem($r('sys.symbol.download'),
        L10n.t('transmission_tab_torrents', '任务')),
      new BottomTabItem($r('sys.symbol.gearshape'),
        L10n.t('transmission_tab_settings', '设置'))
    ];
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    NavDestination() {
      Stack() {
        // 底部安全区背景层：与底部标签栏同底色
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.palette().surfaceBg)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

        Column() {
          this.Header()
          Column() {
            if (this.ctrl.errorText.length > 0) {
              this.ErrorBody()
            } else {
              this.Body()
            }
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.tabIndexOf(this.ctrl.currentTab),
            bottomInset: this.navigationBarHeight,
            onSelect: (index: number): void => {
              this.ctrl.currentTab = this.tabForIndex(index);
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().pageBg)
        .opacity(this.themeTick >= 0 ? 1 : 1)
      }
      .width('100%')
      .height('100%')
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

  private tabIndexOf(tab: string): number {
    if (tab === 'torrents') {
      return 1;
    }
    if (tab === 'settings') {
      return 2;
    }
    return 0;
  }

  private tabForIndex(index: number): string {
    if (index === 1) {
      return 'torrents';
    }
    if (index === 2) {
      return 'settings';
    }
    return 'overview';
  }

  /** 顶栏（对齐 Flutter AppBar：返回 + 标题 + 添加 + 刷新） */
  @Builder
  Header() {
    Row() {
      BorderedIconButton({
        icon: $r('sys.symbol.chevron_left'),
        onTap: (): void => {
          this.popPage();
        }
      })
      Text(L10n.t('app_transmission', 'Transmission'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 8 })
      Row({ space: 8 }) {
        BorderedIconButton({
          icon: $r('sys.symbol.plus'),
          onTap: (): void => {
            showAddTorrentSheet(this.ctrl);
          }
        })
        BorderedIconButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          onTap: (): void => {
            void this.ctrl.refreshAll(false);
          }
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 10, right: 10, top: this.statusBarHeight })
    .backgroundColor(this.palette().surfaceBg)
  }

  /** 主体（对齐 _TransmissionBody 按 tab 切换） */
  @Builder
  Body() {
    if (this.ctrl.currentTab === 'torrents') {
      TransmissionTorrentsTab({ ctrl: this.ctrl })
    } else if (this.ctrl.currentTab === 'settings') {
      TransmissionSettingsTab({ ctrl: this.ctrl })
    } else {
      TransmissionOverviewTab({ ctrl: this.ctrl })
    }
  }

  /** 错误页（对齐 Flutter errorText 分支：整页居中文案） */
  @Builder
  ErrorBody() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(44)
        .fontColor([this.palette().error])
      Text(this.ctrl.errorText)
        .fontSize(14)
        .fontColor(this.palette().subText)
        .textAlign(TextAlign.Center)
        .lineHeight(21)
        .margin({ top: 16 })
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
