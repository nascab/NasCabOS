import { window } from '@kit.ArkUI';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { ThemeManager } from '../../core/theme/ThemeManager';
import { AppEventBus } from '../../common/AppEventBus';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { BottomTabBar, BottomTabItem } from '../../common/components/BottomTabBar';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { VideoListPageParam } from '../router/VideoRoutes';
import { VideoListPage } from './VideoListPage';
import { VideoHomePage } from './VideoHomePage';
import { VideoAlbumsHomePage } from './VideoAlbumsHomePage';

/**
 * 影音管理主页（对齐 Flutter AppVideoMainView 移动端布局）：
 * 底部 4 标签（影库/历史/相册/文件）+ 影库内浮动模式条（首页/电影/电视剧/收藏）+
 * 首页模式下左上主页按钮与右上设置按钮（管理员）。
 */
@ComponentV2
export struct VideoMainPage {
  @Param param: VideoMainPageParam = new VideoMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local activeTab: number = 0;
  @Local libraryIndex: number = 0;
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 恢复透明状态栏背景 + 白色文字（对齐 PageScaffold 行为）
    VideoMainPage.setStatusBar(getContext(this), '#FFFFFF', '#00000000');
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
    VideoMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  private get isHomeMode(): boolean {
    return this.activeTab === 0 && this.libraryIndex === 0;
  }

  build() {
    NavDestination() {
      Stack() {
        // 底部安全区背景层：与底部 tab 栏同底色（surfaceBg），延伸到底部导航条安全区
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.current().surfaceBg)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

        Column() {
          // 内容区：tab 主体 + 浮动模式条
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              this.TabBody()
            }
            .width('100%')
            .height('100%')

            if (this.activeTab === 0) {
              this.FloatingModeBar()
            }

            // 首页模式下浮动主页/设置按钮（对齐 Flutter Positioned top+10）
            if (this.isHomeMode) {
              Row() {
                BorderedIconButton({
                  icon: $r('sys.symbol.house'),
                  btnSize: 42,
                  iconSize: 22,
                  corner: 21,
                  fillColor: AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.75),
                  onTap: (): void => {
                    this.popPage();
                  }
                })
                Blank()
                if (CurrentUserStore.getInstance().isAdmin) {
                  BorderedIconButton({
                    icon: $r('sys.symbol.gearshape'),
                    btnSize: 42,
                    iconSize: 22,
                    corner: 21,
                    fillColor: AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.75),
                    onTap: (): void => {
                      NavUtil.push(AppRouter.VIDEO_SETTINGS, new Object());
                    }
                  })
                }
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10 })
              .position({ x: 0, y: 0 })
            }
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.activeTab,
            onSelect: (index: number): void => {
              this.activeTab = index;
            }
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(AppTheme.current().pageBg)
        .opacity(this.themeTick >= 0 ? 1 : 1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }

  /** 影库浮动模式条（对齐 _buildFloatingModeBar：首页/电影/电视剧/收藏） */
  @Builder
  FloatingModeBar() {
    Row() {
      this.ModeChip(L10n.t('home', '首页'), 0, (): void => {
        this.libraryIndex = 0;
      })
      this.ModeChip(L10n.t('video_home_type_movie', '电影'), 1, (): void => {
        this.libraryIndex = 1;
      })
      this.ModeChip(L10n.t('video_home_type_tv', '电视剧'), 2, (): void => {
        this.libraryIndex = 2;
      })
      this.ModeChip(L10n.t('favorites', '收藏'), 3, (): void => {
        this.libraryIndex = 3;
      })
    }
    .width('100%')
    .height(45)
    .padding({ left: 6, right: 6 })
    .borderRadius(22.5)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
    .margin({ left: 16, right: 16, bottom: 10 })
  }

  /** 选中态在 @Builder 内直接读取 this.libraryIndex（@Builder 按值传参不随状态刷新） */
  @Builder
  ModeChip(label: string, index: number, onTap: () => void) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.libraryIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.libraryIndex === index ? '#FFFFFF' : AppTheme.current().onSurface)
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.libraryIndex === index ? AppTheme.current().primary : Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  /** tab 主体（对齐 _buildTabBody） */
  @Builder
  TabBody() {
    if (this.activeTab === 0) {
      if (this.libraryIndex === 0) {
        VideoHomePage({
          onOpenMovie: (): void => {
            this.libraryIndex = 1;
          },
          onOpenTv: (): void => {
            this.libraryIndex = 2;
          },
          onOpenHistory: (): void => {
            this.activeTab = 1;
          },
          onOpenSettings: (): void => {
            NavUtil.push(AppRouter.VIDEO_SETTINGS, new Object());
          }
        })
      } else if (this.libraryIndex === 1) {
        this.EmbeddedList('movie', '')
      } else if (this.libraryIndex === 2) {
        this.EmbeddedList('tv', '')
      } else if (this.libraryIndex === 3) {
        this.EmbeddedList('', 'favorite')
      }
    } else if (this.activeTab === 1) {
      this.EmbeddedList('', 'history')
    } else if (this.activeTab === 2) {
      VideoAlbumsHomePage()
    } else {
      // 文件视图（对齐 Flutter AppFolderViewPage）后续任务接入（同照片主页处理方式）
      Column() {
        EmptyState({ message: L10n.t('feature_coming_soon', '敬请期待') })
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  EmbeddedList(initialMediaType: string, listType: string) {
    VideoListPage({
      param: this.makeListParam(initialMediaType, listType),
      embedded: true,
      onBackHome: (): void => {
        this.activeTab = 0;
        this.libraryIndex = 0;
      },
      popPage: (): void => {
        this.activeTab = 0;
        this.libraryIndex = 0;
      }
    })
  }

  private makeListParam(initialMediaType: string, listType: string): VideoListPageParam {
    const p = new VideoListPageParam();
    p.initialMediaType = initialMediaType;
    p.listType = listType;
    return p;
  }

  /** 底部 4 标签（影库/历史/相册/文件） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.film'), L10n.t('video_menu_library', '影库')),
      new BottomTabItem($r('sys.symbol.clock'), L10n.t('video_menu_library_history', '历史')),
      new BottomTabItem($r('sys.symbol.rectangle_stack'), L10n.t('video_menu_albums', '相册')),
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('file', '文件'))
    ];
  }
}

/** 影音主页路由参数（对齐 Flutter AppVideoMainRoutePage） */
export class VideoMainPageParam {
  title: string = '';
}
