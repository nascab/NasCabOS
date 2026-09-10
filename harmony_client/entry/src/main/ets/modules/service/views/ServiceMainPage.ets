import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { DialogUtil } from '../../../common/DialogUtil';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { ServiceMainController } from '../controllers/ServiceMainController';
import { ServicePageKeys, ServiceMainPageParam } from '../router/ServiceRoutes';
import { ServiceAccountView } from './ServiceAccountView';
import { ServiceRemoteAccessView } from './ServiceRemoteAccessView';
import { ServiceDdnsView } from './ServiceDdnsView';

/**
 * 服务主页（对齐 Flutter ServiceMobileView）：底部 3 页签
 * （NasCab 账号 / 远程访问 / DDNS），顶栏标题随页签切换。
 * 进入页面时启动配对码轮询并初始化 DDNS（对齐 Flutter IndexedStack 三个子页同时挂载的 initState 行为）。
 */
@ComponentV2
export struct ServiceMainPage {
  @Param param: ServiceMainPageParam = new ServiceMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: ServiceMainController = ServiceMainController.getInstance();
  /** 底部页签：0 账号 1 远程访问 2 DDNS */
  @Local activeTab: number = 0;
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后顶栏用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp）：全屏布局后底部标签栏用它避让 */
  @Local navigationBarHeight: number = 0;
  /** 服务端版本过低提示只弹一次（对齐 Flutter _lowVersionDialogShown） */
  private lowVersionDialogShown: boolean = false;
  /** 避让布局重试定时器（纠正 push 转场对窗口布局写入的回滚） */
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 沉浸全屏布局（对齐笔记主页等移动端页面）：页面自管安全区避让
    this.setFullScreen(true);
    this.fetchSafeAreas();
    // 初始页签（对齐 Flutter ServiceMainView.initialPageKey）
    const initKey = this.param.initialPageKey.trim();
    if (initKey.length > 0) {
      const index = this.indexOfKey(initKey);
      if (index >= 0) {
        this.activeTab = index;
      }
    }
    // 启动配对码轮询 + 初始化 DDNS（对齐 Flutter 子视图 initState）
    this.ctrl.startPairCodePolling();
    void this.initDdns();
  }

  aboutToDisappear(): void {
    this.ctrl.stopPairCodePolling();
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    this.applyStatusBar();
  }

  private async initDdns(): Promise<void> {
    if (this.ctrl.isServerVersionTooLow()) {
      this.showLowVersionDialogOnce();
      return;
    }
    await this.ctrl.initDdns();
  }

  /** 服务端版本过低提示（对齐 Flutter _showLowServerVersionDialogOnce） */
  private showLowVersionDialogOnce(): void {
    if (this.lowVersionDialogShown) {
      return;
    }
    this.lowVersionDialogShown = true;
    void DialogUtil.showInfoDialog(
      L10n.t('tip', '提示'),
      L10n.t('server_version_too_low', '您的服务端版本太低，请升级到最新版本再使用此功能'));
  }

  private keyForTab(index: number): string {
    if (index === 1) {
      return ServicePageKeys.REMOTE_ACCESS;
    }
    if (index === 2) {
      return ServicePageKeys.DDNS;
    }
    return ServicePageKeys.ACCOUNT_NASCAB;
  }

  private indexOfKey(key: string): number {
    if (key === ServicePageKeys.REMOTE_ACCESS) {
      return 1;
    }
    if (key === ServicePageKeys.DDNS) {
      return 2;
    }
    return 0;
  }

  /** 标题（对齐 Flutter _titleForIndex） */
  private titleForTab(index: number): string {
    if (index === 2) {
      return L10n.t('service_menu_remote_access_ddns', '远程访问 DDNS');
    }
    if (index === 1) {
      return L10n.t('service_menu_remote_access', '远程访问');
    }
    return L10n.t('service_menu_account_nascab', 'NasCab 账号');
  }

  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.person_crop_circle_fill'), L10n.t('service_menu_account_nascab', 'NasCab 账号')),
      new BottomTabItem($r('sys.symbol.cloud'), L10n.t('service_menu_remote_access', '远程访问')),
      new BottomTabItem($r('sys.symbol.computer'), L10n.t('service_menu_remote_access_ddns', '远程访问 DDNS'))
    ];
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
    ServiceMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  /** 页签切换（对齐 Flutter ctrl.selectPage） */
  private selectTab(index: number): void {
    this.activeTab = index;
    this.ctrl.selectPage(this.keyForTab(index));
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
            this.Body()
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.activeTab,
            bottomInset: this.navigationBarHeight,
            onSelect: (index: number): void => {
              this.selectTab(index);
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

  /** 顶栏（对齐 Flutter AppBar：返回 + 居中标题） */
  @Builder
  Header() {
    Column() {
      Stack() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(24)
            .fontColor([this.palette().onSurface])
            .padding(8)
            .onClick((): void => {
              this.popPage();
            })
        }
        .width('100%')

        Text(this.titleForTab(this.activeTab))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.palette().surfaceBg)
  }

  @Builder
  Body() {
    if (this.activeTab === 0) {
      ServiceAccountView({ showTitle: false })
    } else if (this.activeTab === 1) {
      ServiceRemoteAccessView({
        showTitle: false,
        onGotoAccount: (): void => {
          this.selectTab(0);
        }
      })
    } else {
      ServiceDdnsView({
        showTitle: false,
        onGotoAccount: (): void => {
          this.selectTab(0);
        }
      })
    }
  }
}
