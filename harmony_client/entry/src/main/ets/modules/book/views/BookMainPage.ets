import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { SystemBars, PageWindowStyle } from '../../../common/SystemBars';
import { WindowStore } from '../../../common/WindowStore';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { BookMainPageParam } from '../router/BookRoutes';
import {
  BookListController, BookHistoryController, ensureBookCoverScaleLoaded
} from '../controllers/BookControllers';
import { BookLibraryView } from './BookLibraryView';
import { BookCustomListView } from './BookCustomListView';
import { BookCollectionView } from './BookCollectionView';
import { BookMultiSelectBar } from '../components/BookMultiSelectBar';
import { BookLocalCacheService } from '../services/BookLocalCacheService';
import { FolderViewBody } from '../../../modules/folder_view/views/FolderViewBody';
import { FolderViewModuleType } from '../../../modules/folder_view/models/FolderViewModuleType';

/**
 * 图书馆主页（对齐 Flutter AppBookMainView 移动端布局）：
 * 底部 4 标签（图书库/书单/合集/文件）+ 图书库内悬浮 chips（图书/漫画/收藏/历史）+
 * 多选时底部标签栏替换为多选操作栏（对齐 Flutter bottomNavigationBar 置 null）。
 */
@ComponentV2
export struct BookMainPage {
  @Param param: BookMainPageParam = new BookMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  /** 底部标签：0 图书库 1 书单 2 合集 3 文件 */
  @Local activeTab: number = 0;
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后顶栏用它避让 */
  @Local statusBarHeight: number = 0;
  /** 底部导航条高度（vp） */
  @Local navigationBarHeight: number = 0;
  private ctrlBook: BookListController = new BookListController('book', false, 0, 0, 0, true);
  private ctrlComic: BookListController = new BookListController('comic', false, 0, 0, 0, true);
  private ctrlFav: BookListController = new BookListController('', true, 0, 0, 0, true);
  private ctrlHistory: BookHistoryController = new BookHistoryController();
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    SystemBars.update(this, this.windowStyle());
  };

  aboutToAppear(): void {
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 沉浸全屏布局（对齐 MusicMainPage 模式）
    SystemBars.activate(this, this.windowStyle());
    this.fetchSafeAreas();
    ensureBookCoverScaleLoaded();
    this.ctrlBook.onInit();
    this.ctrlComic.onInit();
    this.ctrlFav.onInit();
    BookLocalCacheService.getInstance().refreshCachedHashes();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 出栈后自动恢复上一页窗口样式，无需手动重置
    SystemBars.deactivate(this);
  }

  /** 沉浸页窗口样式：全屏布局，状态栏/导航条跟随主题底色 */
  private windowStyle(): PageWindowStyle {
    const p = AppTheme.current();
    return { colors: SystemBars.colors(p.statusBarContent, p.surfaceBg), fullscreen: true };
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

  private openSettings(): void {
    NavUtil.push(AppRouter.BOOK_SETTINGS, new Object());
  }

  /** 当前库内激活的列表控制器（历史视图除外）；libraryIndex 由 BookLibraryView 回写同步 */
  @Local libraryIndex: number = 0;

  private activeListCtrl(): BookListController {
    const idx = this.libraryIndex;
    if (idx === 1) {
      return this.ctrlComic;
    }
    if (idx === 2) {
      return this.ctrlFav;
    }
    return this.ctrlBook;
  }

  build() {
    NavDestination() {
      Stack() {
        // 底部安全区背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.current().surfaceBg)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

        Column() {
          Stack() {
            if (this.activeTab === 0) {
              BookLibraryView({
                statusBarHeight: this.statusBarHeight,
                ctrlBook: this.ctrlBook,
                ctrlComic: this.ctrlComic,
                ctrlFav: this.ctrlFav,
                ctrlHistory: this.ctrlHistory,
                popPage: (): void => {
                  this.popPage();
                },
                onOpenSettings: (): void => {
                  this.openSettings();
                },
                onLibraryIndexChanged: (index: number): void => {
                  this.libraryIndex = index;
                }
              })
            } else if (this.activeTab === 1) {
              BookCustomListView({
                statusBarHeight: this.statusBarHeight,
                popPage: (): void => {
                  this.popPage();
                }
              })
            } else if (this.activeTab === 2) {
              BookCollectionView({
                statusBarHeight: this.statusBarHeight,
                popPage: (): void => {
                  this.popPage();
                }
              })
            } else {
              // 文件视图（对齐 Flutter AppFolderViewPage，book 模块）
              // 嵌入沉浸式全屏主页，需避让状态栏
              FolderViewBody({ moduleType: FolderViewModuleType.Book, statusBarHeight: this.statusBarHeight })
            }
          }
          .width('100%')
          .layoutWeight(1)

          // 多选模式：底部标签栏替换为多选操作栏（对齐 Flutter bottomNavigationBar 置 null）
          if (this.activeTab === 0 && this.libraryIndex !== 3 && this.activeListCtrl().isMultiSelectMode) {
            Column() {
              BookMultiSelectBar({
                selectedCount: this.activeListCtrl().selectedItems.size,
                inCustomList: this.activeListCtrl().isInCustomList,
                allFavorited: this.activeListCtrl().isSelectedAllFavorited,
                onDelete: (): void => {
                  void this.activeListCtrl().deleteSelected();
                },
                onToggleFavorite: (): void => {
                  void this.activeListCtrl().toggleFavoriteSelected();
                },
                onAddToList: (): void => {
                  void this.activeListCtrl().addToBookListSelected();
                },
                onRemoveFromList: (): void => {
                  void this.activeListCtrl().removeFromBookListSelected();
                }
              })
            }
            .width('100%')
            // 整体（含 padding 出的底部安全区）surface 背景：菜单与底部安全区同色
            .backgroundColor(AppTheme.current().surfaceBg)
            .border({ width: { top: 0.8 }, color: AppTheme.current().divider })
            .padding({ bottom: this.navigationBarHeight })
          } else {
            BottomTabBar({
              items: this.tabItems(),
              selectedIndex: this.activeTab,
              bottomInset: this.navigationBarHeight,
              onSelect: (index: number): void => {
                if (index !== this.activeTab) {
                  this.activeTab = index;
                }
              }
            })
          }
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
      // 每次显示重新激活本页样式（内部含 120ms 转场重试）
      SystemBars.activate(this, this.windowStyle());
      this.fetchSafeAreas();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }

  /** 底部 4 标签（图书库/书单/合集/文件） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.house'), L10n.t('home', '首页')),
      new BottomTabItem($r('sys.symbol.bookmark'), L10n.t('book_menu_book_list_custom', '书单')),
      new BottomTabItem($r('sys.symbol.rectangle_stack'), L10n.t('book_collection_title', '合集')),
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('file', '文件'))
    ];
  }
}
