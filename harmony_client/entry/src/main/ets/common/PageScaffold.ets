import { AppTheme, ThemePalette } from '../core/theme/AppTheme';
import { ThemeManager } from '../core/theme/ThemeManager';
import { AppEventBus } from './AppEventBus';
import { SystemBars, PageWindowStyle } from './SystemBars';

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
  private themeListener: (data: string) => void = (_data: string) => {
    this.themeTick++;
    SystemBars.update(this, this.windowStyle());
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 常规页统一为非全屏避让布局 + 主题配色系统栏（从全屏沉浸页 push 过来时由样式栈恢复）
    SystemBars.activate(this, this.windowStyle());
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 出栈后自动恢复上一页窗口样式（首页/登录等沉浸页透明系统栏），无需手动重置
    SystemBars.deactivate(this);
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 常规页窗口样式：非全屏避让布局，状态栏跟随顶栏色，底部导航条跟随内容区底色 */
  private windowStyle(): PageWindowStyle {
    const p = AppTheme.current();
    const statusBg = this.statusBarBg.length > 0 ? this.statusBarBg : p.appBarBg;
    return {
      colors: {
        statusBarContentColor: p.statusBarContent,
        statusBarColor: statusBg,
        navigationBarContentColor: p.statusBarContent,
        navigationBarColor: p.surfaceBg
      },
      fullscreen: false
    };
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
      // 每次显示重新激活本页样式（从沉浸子页返回时由样式栈统一恢复并做转场重试）
      SystemBars.activate(this, this.windowStyle());
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
