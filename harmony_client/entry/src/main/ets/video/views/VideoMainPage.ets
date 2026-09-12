import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { ThemeManager } from '../../core/theme/ThemeManager';
import { AppEventBus } from '../../common/AppEventBus';
import { WindowStore } from '../../common/WindowStore';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../common/components/BottomTabBar';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { FolderViewBody } from '../../modules/folder_view/views/FolderViewBody';
import { FolderViewModuleType } from '../../modules/folder_view/models/FolderViewModuleType';
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
  /** 状态栏高度（vp）：全屏布局后非沉浸内容用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp）：全屏布局后底部标签栏用它避让 */
  @Local navigationBarHeight: number = 0;
  /** 延迟重设全屏的定时器（push 转场期间系统可能回滚全屏设置，转场后纠正） */
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.applyStatusBar();
    this.setFullScreen(true);
    this.fetchSafeAreas();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    // 不恢复非全屏：唯一入口/出口是沉浸式首页（onShown 确保 true），在此切 false 会导致返回时布局跳动
    this.applyStatusBar();
  }

  /** 全屏沉浸布局：同步调用，写顺序=调用顺序，杜绝异步竞态 */
  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      hilog.error(0x0000, 'FullScreen', 'VideoMain mainWindow undefined');
      return;
    }
    w.setWindowLayoutFullScreen(full).then((): void => {
      hilog.info(0x0000, 'FullScreen', 'VideoMain set %{public}s ok, now=%{public}s',
        `${full}`, `${w.getWindowProperties().isLayoutFullScreen}`);
    }).catch((e: Object): void => {
      hilog.error(0x0000, 'FullScreen', 'VideoMain set %{public}s failed: %{public}s',
        `${full}`, JSON.stringify(e));
    });
  }

  /** onShown 后延迟重设全屏：纠正系统在 push 转场期间对全屏设置的回滚 */
  private scheduleFullScreenRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
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
    this.statusBarHeight = px2vp(top.topRect.height);
    const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.navigationBarHeight = px2vp(bottom.bottomRect.height);
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
    // 状态栏透明（对齐 Flutter edgeToEdge）：全屏布局时区域被内容覆盖，非全屏时透出深色内容观感一致
    VideoMainPage.setStatusBar(getContext(this), '#FFFFFF', '#00000000');
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
              .padding({ left: 12, right: 12, top: this.statusBarHeight + 10 })
              .position({ x: 0, y: 0 })
            }
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.activeTab,
            bottomInset: this.navigationBarHeight,
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
    .onShown((): void => {
      // 转场动画完成后再次确保全屏（aboutToAppear 期间设置可能被转场覆盖）
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
    })
    .onHidden((): void => {
      // 页面被覆盖（push 子页）时取消延迟重设，避免污染子页面的全屏状态
      this.clearRetryTimer();
    })
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

  /** tab 主体（对齐 _buildTabBody）：全屏布局下非首页 tab 需避让状态栏 */
  @Builder
  TabBody() {
    if (this.activeTab === 0 && this.libraryIndex === 0) {
      // 首页轮播顶格沉浸，不做状态栏避让
      this.TabBodyInner()
    } else {
      Column() {
        this.TabBodyInner()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight })
    }
  }

  @Builder
  TabBodyInner() {
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
      // 文件视图（对齐 Flutter AppFolderViewPage，video 模块）
      FolderViewBody({ moduleType: FolderViewModuleType.Video })
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
