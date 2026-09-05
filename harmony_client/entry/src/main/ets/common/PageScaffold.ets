import { window } from '@kit.ArkUI';
import { AppTheme, ThemePalette } from '../core/theme/AppTheme';
import { ThemeManager } from '../core/theme/ThemeManager';
import { AppEventBus } from './AppEventBus';

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
  @Param onBack: () => void = () => {
  };
  /** 自定义返回拦截：返回 true 表示已消费（用于 Web 页回退历史等） */
  @Param customBack: () => boolean = () => false;
  @BuilderParam actions: () => void = PageScaffoldEmptyActions;
  @BuilderParam content: () => void;
  /** 主题变化刷新计数（依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  private themeListener: (data: string) => void = (_data: string) => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.applyStatusBar();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 恢复透明状态栏背景 + 白色文字（首页/登录等深色沉浸页面）
    PageScaffold.setStatusBar(getContext(this), '#FFFFFF', '#00000000');
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private applyStatusBar(): void {
    const p = AppTheme.current();
    PageScaffold.setStatusBar(getContext(this), p.statusBarContent, p.appBarBg);
  }

  private static setStatusBar(ctx: Context, contentColor: string, bgColor: string): void {
    try {
      window.getLastWindow(ctx).then((w) => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
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
      }
      .width('100%')
      .height('100%')
      // 依赖 themeTick：主题切换后触发整页刷新（含 L10n 文案与配色）
      .opacity(this.themeTick >= 0 ? 1 : 1)
    }
    .hideTitleBar(true)
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
