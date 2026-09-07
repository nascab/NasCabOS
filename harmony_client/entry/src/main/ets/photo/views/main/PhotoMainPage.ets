import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { BottomTabBar, BottomTabItem } from '../../../common/components/BottomTabBar';
import { TimelineController } from '../../controllers/TimelineController';
import { PhotoTimelineView } from '../timeline/PhotoTimelineView';
import { PhotoTimelineYearView } from '../timeline/PhotoTimelineYearView';
import { PhotoMultiSelectBar } from '../timeline/PhotoMultiSelectBar';
import { PhotoFootprintMapView } from '../map/PhotoFootprintMapView';
import { PhotoModeBar } from './PhotoModeBar';
import { PhotoAlbumHomeView } from '../album/PhotoAlbumHomeView';
import { PhotoAiHomeView } from '../ai/PhotoAiHomeView';
import { PhotoSettingsPageParam } from '../settings/PhotoSettingsPage';
import { PhotoAlbumListPageParam } from '../album/PhotoAlbumListPage';
import { PhotoTrashPageParam } from '../trash/PhotoTrashPage';

/** 照片主页路由参数（对齐 Flutter AppPhotoMainRoutePage） */
export class PhotoMainPageParam {
  title: string = '';
}

/**
 * 照片主页（对齐 Flutter AppPhotoMainView 移动端布局）：
 * 顶部标题栏（返回/搜索/回收站/设置或创建）+ 中部内容（按 currentTab 切换）+
 * 浮动模式条（全部/按年/今日/收藏）+ 底部 5 标签导航（照片/足迹/相册/AI/文件）。
 */
@ComponentV2
export struct PhotoMainPage {
  @Param param: PhotoMainPageParam = new PhotoMainPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local currentTab: number = 0;
  @Local yearMode: boolean = false;
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  private ctrl: TimelineController = new TimelineController();
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
  };

  aboutToAppear(): void {
    this.ctrl.configure('timeline', 0, 0, 0, 0, '', false, '', 0, true);
    void this.ctrl.refreshTimeline();
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 恢复透明状态栏背景 + 白色文字（对齐 PageScaffold 行为）
    PhotoMainPage.setStatusBar(getContext(this), '#FFFFFF', '#00000000');
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
    PhotoMainPage.setStatusBar(getContext(this), p.statusBarContent, p.surfaceBg);
  }

  /** 点击搜索时确保 tab=照片 且非年视图/年份筛选，再走控制器搜索（对齐 Flutter _ensureSearchContext） */
  private ensureSearchContext(): void {
    if (this.currentTab !== 0) {
      this.currentTab = 0;
    }
    this.applyTimelineMode('timeline', false);
  }

  /**
   * 切换时间线模式（模式栏/搜索共用）：先清年份筛选再切模式，
   * 保证只触发一次刷新（避免两次 refreshTimeline 触发 loadingTimeline 互斥被吞）。
   */
  private applyTimelineMode(listType: string, loadTheDay: boolean): void {
    this.yearMode = false;
    const hadYearFilter: boolean = this.ctrl.year !== 0;
    this.ctrl.year = 0;
    const modeChanged: boolean = this.ctrl.listType !== listType || this.ctrl.loadTheDay !== loadTheDay;
    this.ctrl.setTimelineMode(listType, loadTheDay);
    if (hadYearFilter && !modeChanged) {
      void this.ctrl.refreshTimeline();
    }
  }

  build() {
    NavDestination() {
      Column() {
        if (this.currentTab !== 4) {
          this.Header()
        }
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            if (this.currentTab === 0) {
              if (this.yearMode) {
                PhotoTimelineYearView({
                  ctrl: this.ctrl,
                  onYearPicked: (_y: number): void => {
                    this.yearMode = false;
                  }
                })
              } else {
                PhotoTimelineView({ ctrl: this.ctrl, showSearchAction: false })
              }
            } else if (this.currentTab === 1) {
              PhotoFootprintMapView()
            } else if (this.currentTab === 2) {
              PhotoAlbumHomeView()
            } else if (this.currentTab === 3) {
              PhotoAiHomeView()
            } else {
              // 文件视图（对齐 Flutter AppFolderViewPage）后续任务接入
              Column() {
                EmptyState({ message: L10n.t('feature_coming_soon', '敬请期待') })
              }
              .width('100%')
              .height('100%')
            }
          }
          .width('100%')
          .height('100%')
          // 浮动模式条仅照片 tab + 非多选时显示
          if (this.currentTab === 0 && !this.ctrl.isMultiSelectMode) {
            PhotoModeBar({
              ctrl: this.ctrl,
              yearMode: this.yearMode,
              onModeSelected: (listType: string, loadTheDay: boolean): void => {
                this.applyTimelineMode(listType, loadTheDay);
              },
              onYearSelected: (): void => {
                this.yearMode = true;
              }
            })
          }
        }
        .width('100%')
        .layoutWeight(1)

        if (this.currentTab === 0 && this.ctrl.isMultiSelectMode) {
          PhotoMultiSelectBar({ ctrl: this.ctrl })
        } else {
          BottomTabBar({
            items: this.tabItems(),
            selectedIndex: this.currentTab,
            onSelect: (index: number): void => {
              if (this.ctrl.isMultiSelectMode) {
                this.ctrl.exitMultiSelectMode();
              }
              if (index !== 0 && this.yearMode) {
                this.yearMode = false;
              }
              this.currentTab = index;
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.current().pageBg)
      // 依赖 themeTick：主题切换后触发整页刷新（含配色与文案）
      .opacity(this.themeTick >= 0 ? 1 : 1)
    }
    .hideTitleBar(true)
    .onBackPressed((): boolean => {
      // 多选模式下返回先退出多选（对齐 Flutter PopScope）
      if (this.currentTab === 0 && this.ctrl.isMultiSelectMode) {
        this.ctrl.exitMultiSelectMode();
        return true;
      }
      this.popPage();
      return true;
    })
  }

  /** 顶部标题栏（对齐 Flutter _buildHeader）：56 高，左右 6 内边距，文件 tab 隐藏 */
  @Builder
  Header() {
    Row({ space: 8 }) {
      if (this.currentTab === 0 && this.ctrl.isMultiSelectMode) {
        // 多选模式：取消按钮 + 已选数量
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(22)
          .fontColor([AppTheme.current().onSurface])
          .padding({ left: 6, right: 2 })
          .onClick(() => {
            this.ctrl.exitMultiSelectMode();
          })
        Text(`${this.ctrl.selectedIds.length} ${L10n.t('selected', '已选择')}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      } else {
        BorderedIconButton({
          icon: $r('sys.symbol.house'),
          onTap: (): void => {
            this.popPage();
          }
        })
        SearchInputBar({
          hintText: L10n.t('photo_timeline_search_hint', '照片搜索'),
          text: this.ctrl.searchKeyword,
          onChanged: (v: string): void => {
            this.ensureSearchContext();
            this.ctrl.onSearchChanged(v);
          },
          onClear: (): void => {
            this.ctrl.clearSearch();
          }
        })
          .layoutWeight(1)
        if (this.currentTab === 0) {
          BorderedIconButton({
            icon: $r('sys.symbol.trash'),
            onTap: (): void => {
              // 打开回收站页（对齐 Flutter AppPhotoMainView 回收站入口）
              NavUtil.push(AppRouter.PHOTO_TRASH, new PhotoTrashPageParam());
            }
          })
        }
        if (this.currentTab === 2) {
          BorderedIconButton({
            icon: $r('sys.symbol.plus'),
            onTap: (): void => {
              // 打开相册列表页并自动弹出创建相册（对齐 Flutter AppPhotoMainView autoOpenCreate: true）
              const p = new PhotoAlbumListPageParam();
              p.autoOpenCreate = true;
              NavUtil.push(AppRouter.PHOTO_ALBUM_LIST, p);
            }
          })
        } else if (this.currentTab === 0) {
          BorderedIconButton({
            icon: $r('sys.symbol.gearshape'),
            onTap: (): void => {
              // 打开照片设置页（对齐 Flutter AppPhotoMainView 设置入口）
              NavUtil.push(AppRouter.PHOTO_SETTINGS, new PhotoSettingsPageParam());
            }
          })
        }
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 6, right: 6 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  /** 底部 5 标签数据（照片/足迹/相册/AI/文件） */
  private tabItems(): BottomTabItem[] {
    return [
      new BottomTabItem($r('sys.symbol.picture'), L10n.t('app_photo_tab_photos', '照片')),
      new BottomTabItem($r('sys.symbol.map'), L10n.t('app_photo_tab_footprint', '足迹')),
      new BottomTabItem($r('sys.symbol.rectangle_stack'), L10n.t('app_photo_tab_album', '相册')),
      new BottomTabItem($r('sys.symbol.wand_and_stars'), L10n.t('app_photo_tab_ai', 'AI')),
      new BottomTabItem($r('sys.symbol.folder'), L10n.t('file', '文件'))
    ];
  }
}
