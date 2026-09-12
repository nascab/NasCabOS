import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { MusicMainPageParam } from '../router/MusicRoutes';
import { MusicPlayService } from '../service/MusicPlayService';
import { MusicListPage, MusicListPageParam } from './MusicListPage';
import { MusicListSortBy, MusicListSortOrder } from '../controllers/MusicListController';
import { MusicSubListPage } from './MusicSubListPage';
import { MusicSubListPayload } from '../controllers/MusicSubListController';
import { MusicAlbumArtistPage } from './MusicAlbumArtistPage';
import { MusicPlayListPage } from './MusicPlayListPage';
import { MusicCollectionPage } from './MusicCollectionPage';
import { MusicFloatingBar } from '../components/MusicFloatingBar';
import { FolderViewBody } from '../../../modules/folder_view/views/FolderViewBody';
import { FolderViewModuleType } from '../../../modules/folder_view/models/FolderViewModuleType';

/**
 * 音乐主页（对齐 Flutter AppMusicMainFrameView + AppMusicMainView 移动端布局）：
 * 底部 4 标签（音乐库/歌单/合集/文件）+ 音乐库内顶部标签（歌曲/收藏/历史/专辑/艺人）+
 * 音乐库模式下左上主页按钮与右上设置按钮（管理员）+ 悬浮播放条（多选模式隐藏）。
 */
@ComponentV2
export struct MusicMainPage {
  @Param param: MusicMainPageParam = new MusicMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 底部标签：0 音乐库 1 歌单 2 合集 3 文件 */
  @Local activeTab: number = 0;
  /** 音乐库内顶部标签：0 歌曲 1 收藏 2 历史 3 专辑 4 艺人 */
  @Local libraryIndex: number = 0;
  /** 多选模式隐藏悬浮播放条（歌曲/收藏/历史列表共用） */
  @Local hideFloatingBar: boolean = false;
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后顶栏用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp）：全屏布局后底部标签栏用它避让 */
  @Local navigationBarHeight: number = 0;
  /** 避让布局重试定时器（纠正 push 转场对窗口布局写入的回滚） */
  private retryTimer: number = -1;
  private svc: MusicPlayService = MusicPlayService.getInstance();
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 沉浸全屏布局（对齐 VideoMainPage）：页面自管安全区避让，tab 栏走 bottomInset 显式垫高，
    // 避免 expandSafeArea 背景延伸在避让布局下不可靠，导致 tab 栏与底部安全区之间露缝
    this.setFullScreen(true);
    this.fetchSafeAreas();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    // 不恢复非全屏：返回目标是沉浸式壁纸首页/全屏播放页（其 onShown 确保 true），
    // 在此写 false 会导致返回时布局跳动
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
    // 钳制到合理范围，防止转场/布局切换瞬间返回异常值导致页面错乱
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
    MusicMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  private openFullscreen(): void {
    NavUtil.push(AppRouter.MUSIC_PLAYER, new Object());
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
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              this.TabBody()
            }
            .width('100%')
            .height('100%')

            // 悬浮播放条（对齐 Flutter Positioned bottom+5；多选模式隐藏）
            if (!this.hideFloatingBar) {
              Column() {
                MusicFloatingBar({
                  onOpenFullscreen: (): void => {
                    this.openFullscreen();
                  },
                  onOpenPlaylist: (): void => {
                    this.openFullscreen();
                  }
                })
              }
              .width('100%')
              .padding({ left: 12, right: 12, bottom: 8 })
              .onClick(() => {
                // 拦截子组件冒泡（MusicFloatingBar 主体自身处理点击）
              })
            }
          }
          .width('100%')
          .layoutWeight(1)

          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.activeTab,
            // 全屏布局下显式垫高避让导航条（expandSafeArea 模式在避让布局下不可靠）
            bottomInset: this.navigationBarHeight,
            onSelect: (index: number): void => {
              if (index !== this.activeTab) {
                this.hideFloatingBar = false;
                this.activeTab = index;
              }
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
      // 每次显示都确保全屏布局（从设置页等常规子页返回后覆盖其写入的 false）
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
      this.fetchSafeAreas();
      this.applyStatusBar();
    })
    .onHidden((): void => {
      // push 子页时本页不销毁，清理重试定时器防止残留写入污染子页面
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }

  /** 底部 4 标签（音乐库/歌单/合集/文件） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.house'), L10n.t('home', '首页')),
      new BottomTabItem($r('sys.symbol.music_note_list'), L10n.t('music_menu_library_playlists', '歌单')),
      new BottomTabItem($r('sys.symbol.rectangle_stack'), L10n.t('music_collection_title', '合集')),
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('file', '文件'))
    ];
  }

  /** tab 主体 */
  @Builder
  TabBody() {
    if (this.activeTab === 0) {
      Column() {
        this.LibraryTopBar()
        this.LibraryTabContent()
      }
      .width('100%')
      .height('100%')
    } else if (this.activeTab === 1) {
      // 嵌入页顶栏需自避让状态栏（主页为沉浸全屏布局）
      MusicPlayListPage({ statusBarHeight: this.statusBarHeight })
    } else if (this.activeTab === 2) {
      MusicCollectionPage({ statusBarHeight: this.statusBarHeight })
    } else {
      // 文件视图（对齐 Flutter AppFolderViewPage，music 模块）
      // 嵌入沉浸式全屏主页，需避让状态栏
      FolderViewBody({ moduleType: FolderViewModuleType.Music, statusBarHeight: this.statusBarHeight })
    }
  }

  /** 音乐库顶部栏（对齐 AppMusicMainView 顶栏）：主页按钮 + 5 标签 + 设置（管理员） */
  @Builder
  LibraryTopBar() {
    Row() {
      BorderedIconButton({
        icon: $r('sys.symbol.house'),
        btnSize: 40,
        iconSize: 20,
        corner: 20,
        onTap: (): void => {
          this.popPage();
        }
      })

      Scroll() {
        Row({ space: 22 }) {
          this.LibraryTabChip(L10n.t('music_menu_library_songs', '歌曲'), 0)
          this.LibraryTabChip(L10n.t('favorites', '收藏'), 1)
          this.LibraryTabChip(L10n.t('music_menu_library_history', '历史'), 2)
          this.LibraryTabChip(L10n.t('music_menu_library_albums', '专辑'), 3)
          this.LibraryTabChip(L10n.t('music_menu_library_artists', '艺人'), 4)
        }
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Center)

      if (CurrentUserStore.getInstance().isAdmin) {
        BorderedIconButton({
          icon: $r('sys.symbol.gearshape'),
          btnSize: 40,
          iconSize: 20,
          corner: 20,
          onTap: (): void => {
            NavUtil.push(AppRouter.MUSIC_SETTINGS, new Object());
          }
        })
      }
    }
    .width('100%')
    .height(56 + this.statusBarHeight)
    .padding({ left: 12, right: 12, top: this.statusBarHeight })
    .border({ width: { bottom: 0.8 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  /** 顶部标签 chip（选中态读取 this.libraryIndex 保证响应式） */
  @Builder
  LibraryTabChip(label: string, index: number) {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(this.libraryIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.libraryIndex === index ? AppTheme.current().onSurface
          : AppTheme.withAlpha(AppTheme.current().onSurface, 0.55))
        .maxLines(1)
      Rect()
        .width(20)
        .height(2.5)
        .radius(1.25)
        .fill(this.libraryIndex === index ? AppTheme.current().primary : Color.Transparent)
        .margin({ top: 3 })
    }
    .constraintSize({ minWidth: 30 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.libraryIndex = index;
    })
  }

  /** 音乐库 5 标签内容（对齐 AppMusicMainView TabBarView） */
  @Builder
  LibraryTabContent() {
    if (this.libraryIndex === 0) {
      MusicListPage({
        param: this.makeListParam(false, MusicListSortBy.title, MusicListSortOrder.asc),
        onMultiSelectChanged: (v: boolean): void => {
          this.hideFloatingBar = v;
        }
      })
    } else if (this.libraryIndex === 1) {
      MusicListPage({
        param: this.makeListParam(true, MusicListSortBy.favoriteTime, MusicListSortOrder.desc),
        onMultiSelectChanged: (v: boolean): void => {
          this.hideFloatingBar = v;
        }
      })
    } else if (this.libraryIndex === 2) {
      MusicSubListPage({
        payload: new MusicSubListPayload('history', L10n.t('music_menu_library_history', '历史'),
          0, 0, '', 0, false, true),
        embedded: true,
        onMultiSelectChanged: (v: boolean): void => {
          this.hideFloatingBar = v;
        }
      })
    } else if (this.libraryIndex === 3) {
      MusicAlbumArtistPage({ keyType: 'album' })
    } else {
      MusicAlbumArtistPage({ keyType: 'artist' })
    }
  }

  private makeListParam(isFavorite: boolean, sortBy: MusicListSortBy,
    sortOrder: MusicListSortOrder): MusicListPageParam {
    const p = new MusicListPageParam();
    p.isFavorite = isFavorite;
    p.initialSortBy = sortBy;
    p.initialSortOrder = sortOrder;
    return p;
  }
}
