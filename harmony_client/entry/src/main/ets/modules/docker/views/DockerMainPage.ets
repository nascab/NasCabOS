import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { DockerController } from '../controllers/DockerController';
import { DockerErrorBanner } from './parts/DockerSharedWidgets';
import { DockerOverviewTab } from './DockerOverviewTab';
import { DockerImagesTab } from './DockerImagesTab';
import { DockerContainersTab } from './DockerContainersTab';
import { DockerTasksTab } from './DockerTasksTab';
import { DockerMainPageParam } from '../router/DockerRoutes';

/**
 * Docker 主页（对齐 Flutter DockerManagerView 移动端 appMode 形态）：
 * 顶栏 返回 + 标题 + 刷新，底部 4 标签（总览/镜像/容器/任务），
 * 错误文案以横幅展示在页签上方（对齐 Flutter _DockerBody 的 _ErrorBanner 分支）。
 */
@ComponentV2
export struct DockerMainPage {
  @Param param: DockerMainPageParam = new DockerMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 控制器随页面创建销毁（对齐 Flutter GetBuilder init/dispose 生命周期） */
  @Local ctrl: DockerController = new DockerController();
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
    // 沉浸全屏布局（对齐 Transmission/笔记主页）：页面自管安全区避让
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
    DockerMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  /** 底部标签（对齐 Flutter BottomNavigationBar 4 项） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.square_grid_2x2'),
        L10n.t('docker_tab_overview', '总览')),
      new BottomTabItem($r('sys.symbol.square_stack_3d'),
        L10n.t('docker_tab_images', '镜像')),
      new BottomTabItem($r('sys.symbol.archivebox'),
        L10n.t('docker_tab_containers', '容器')),
      new BottomTabItem($r('sys.symbol.list_bullet'),
        L10n.t('docker_tab_tasks', '任务'))
    ];
  }

  private tabIndexOf(tab: string): number {
    if (tab === 'images') {
      return 1;
    }
    if (tab === 'containers') {
      return 2;
    }
    if (tab === 'tasks') {
      return 3;
    }
    return 0;
  }

  private tabForIndex(index: number): string {
    if (index === 1) {
      return 'images';
    }
    if (index === 2) {
      return 'containers';
    }
    if (index === 3) {
      return 'tasks';
    }
    return 'overview';
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
            if (this.ctrl.errorText.trim().length > 0) {
              Column() {
                DockerErrorBanner({ text: this.ctrl.errorText })
              }
              .margin({ left: 12, right: 12, top: 12 })
              .width('100%')
            }
            this.Body()
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.tabIndexOf(this.ctrl.currentTab),
            bottomInset: this.navigationBarHeight,
            onSelect: (index: number): void => {
              this.ctrl.changeTab(this.tabForIndex(index));
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

  /** 顶栏（对齐 Flutter AppBar：返回 + 标题 + 刷新） */
  @Builder
  Header() {
    Row() {
      BorderedIconButton({
        icon: $r('sys.symbol.chevron_left'),
        onTap: (): void => {
          this.popPage();
        }
      })
      Text(this.param.title.length > 0 ? this.param.title : L10n.t('app_docker', 'Docker'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 8 })
      Row({ space: 8 }) {
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

  /** 主体（对齐 _DockerBody 按 tab 切换） */
  @Builder
  Body() {
    if (this.ctrl.currentTab === 'images') {
      DockerImagesTab({ ctrl: this.ctrl })
    } else if (this.ctrl.currentTab === 'containers') {
      DockerContainersTab({ ctrl: this.ctrl })
    } else if (this.ctrl.currentTab === 'tasks') {
      DockerTasksTab({ ctrl: this.ctrl })
    } else {
      DockerOverviewTab({ ctrl: this.ctrl })
    }
  }
}
