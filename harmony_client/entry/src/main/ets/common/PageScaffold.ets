import { window } from '@kit.ArkUI';
import { AppTheme, ThemePalette } from '../core/theme/AppTheme';
import { ThemeManager } from '../core/theme/ThemeManager';
import { AppEventBus } from './AppEventBus';
import { WindowStore } from './WindowStore';

@Builder
function PageScaffoldEmptyActions() {
}

/**
 * 通用页面框架（对齐 Flutter AppBasePage / CustomTitleBar）：
 * - 顶部与底部全部沉浸：背景层延伸到系统安全区外，内容层保持在安全区内
 * - 标题栏：返回按钮 + 标题 + 右侧 actions（builder）
 * - 跟随主题切换即时刷新配色，并同步状态栏文字颜色
 */
@ComponentV2
export struct PageScaffold {
  @Param title: string = '';
  @Param showBack: boolean = true;
  /** 自定义状态栏背景色（默认取 appBarBg；文件页等内容型页面可传入内容区背景色） */
  @Param statusBarBg: string = '';
  /** 底部导航条安全区背景色（默认取 pageBg；带底部标签栏的页面传 surfaceBg 与标签栏同色，
   *  对齐照片主页背景层模式：窗口 navigationBarColor 属性在鸿蒙上不生效，靠应用内渲染层延伸） */
  @Param bottomSafeAreaBg: string = '';
  @Param onBack: () => void = () => {
  };
  /** 自定义返回拦截：返回 true 表示已消费（用于 Web 页回退历史等） */
  @Param customBack: () => boolean = () => false;
  @BuilderParam actions: () => void = PageScaffoldEmptyActions;
  @BuilderParam content: () => void;
  /** 全屏浮层（如相册编辑弹窗）：渲染在 NavDestination 内部顶层，保证随页面挂载显示 */
  @BuilderParam overlayContent: () => void = PageScaffoldEmptyActions;
  /** 主题变化刷新计数（依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 避让布局重试定时器（纠正 push 转场对窗口布局写入的回滚） */
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string) => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 常规页面强制非全屏布局：从全屏沉浸页面（影音主页/详情页/图片浏览器）push 过来时恢复避让布局
    PageScaffold.setFullScreen(getContext(this), false);
    this.applyStatusBar();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    // 恢复透明状态栏/导航条背景 + 白色文字（首页/登录等深色沉浸页面）
    PageScaffold.setSystemBars(getContext(this), '#FFFFFF', '#00000000', '#00000000');
  }

  /** push 转场会回滚窗口布局写入（实测，对齐沉浸页 scheduleFullScreenRetry）：延迟重设纠正 */
  private scheduleAvoidRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      PageScaffold.setFullScreen(getContext(this), false);
    }, 120);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private applyStatusBar(): void {
    const p = AppTheme.current();
    const bg = this.statusBarBg.length > 0 ? this.statusBarBg : p.appBarBg;
    // 底部导航条颜色与底部标签栏底色（surfaceBg）一致，避免导航条区域露出系统默认色
    PageScaffold.setSystemBars(getContext(this), p.statusBarContent, bg, p.surfaceBg);
  }

  private static setSystemBars(ctx: Context, contentColor: string, bgColor: string, navBgColor: string): void {
    try {
      window.getLastWindow(ctx).then((w) => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor,
          navigationBarContentColor: contentColor,
          navigationBarColor: navBgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
    }
  }

  /** 全屏布局开关：同步调用，写顺序=调用顺序（沉浸页面 onShown 设 true，常规页面强制 false） */
  private static setFullScreen(_ctx: Context, full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w !== undefined) {
      w.setWindowLayoutFullScreen(full);
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 沉浸式背景层：上下延伸到系统安全区外
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.palette().pageBg)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 底部安全区背景层：与底部标签栏同底色（照片主页同款模式）
        if (this.bottomSafeAreaBg.length > 0) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.bottomSafeAreaBg)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }

        // 内容层：默认位于安全区内（标题栏紧贴状态栏下方）
        Column() {
          if (this.title.trim().length > 0) {
            this.TitleBar()
          }
          Column() {
            this.content()
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')

        // 全屏浮层：置于内容层之上（仍在 NavDestination 内，随页面正常挂载）
        this.overlayContent()
      }
      .width('100%')
      .height('100%')
      // 依赖 themeTick：主题切换后触发整页刷新（含 L10n 文案与配色）
      .opacity(this.themeTick >= 0 ? 1 : 1)
    }
    .hideTitleBar(true)
    .onShown((): void => {
      // 每次显示都确保非全屏避让布局（从沉浸页返回/push 进入均覆盖）
      PageScaffold.setFullScreen(getContext(this), false);
      this.scheduleAvoidRetry();
      // 从子页返回时子页已恢复透明系统栏，这里重新应用本页配色
      this.applyStatusBar();
    })
    .onHidden((): void => {
      // push 子页时本页不销毁，清理重试定时器防止残留写入污染子页面
      this.clearRetryTimer();
    })
    .onBackPressed(() => {
      if (this.customBack()) {
        return true;
      }
      if (this.showBack) {
        this.onBack();
        return true;
      }
      return false;
    })
  }

  @Builder
  TitleBar() {
    Row({ space: 8 }) {
      if (this.showBack) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(24)
          .fontColor([this.palette().appBarFg])
          .onClick(() => {
            this.onBack();
          })
      }
      Text(this.title)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().appBarFg)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      this.actions()
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.palette().appBarBg)
  }
}
