import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { AppEventBus } from '../../common/AppEventBus';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { PageScaffold } from '../../common/PageScaffold';
import { SearchInputBar } from '../../common/components/SearchInputBar';
import { LanguageService } from '../../core/localization/LanguageService';
import { DialogUtil } from '../../common/DialogUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { AppRouter } from '../../router/AppRouter';
import { FileController, FileUiHook } from '../controllers/FileController';
import { FileItem, FileModelAccess } from '../models/FileModels';
import {
  showFileAddCustomPathSheet, showFileCreateSheet, showFileFilterSheet,
  showFileMoreSheet, showFileSearchOptionsSheet, showFileSortSheet
} from './FileSheets';
import { pickTargetFolderViaSheet } from './FolderPickerSheet';
import { FileGridItem, FileListItem } from './FileItems';

/** 文件浏览器页面参数 */
export class FileBrowserParam {
  initialPath: string = '';
  initFolderName: string = '';
  isRootPage: boolean = true;
}

/**
 * 文件管理页面（对齐 Flutter AppFileBrowser 移动端布局）：
 * 顶部操作栏 + 搜索栏 + 视图工具栏 + 文件列表（网格/大图/列表）+ 底部导航（根页）/多选操作栏。
 */
@ComponentV2
export struct FileBrowserPage {
  @Param param: FileBrowserParam = new FileBrowserParam();
  /** 上推新页面（进入子目录） */
  @Param pushPage: (name: string, param?: object) => void = (_n: string, _p?: object): void => {
  };
  /** 返回上一页 */
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: FileController = new FileController(false);
  @Local refreshing: boolean = false;
  @Local gridCols: number = 3;
  @Local gridThumb: number = 80;
  @Local gridItemHeight: number = 158;
  private gridAreaWidth: number = 0;
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  /** 视图模式切换后按新模式重算网格布局（onAreaChange 不会因内容变化再触发） */
  @Monitor('ctrl.viewMode')
  onViewModeChange(): void {
    this.updateGridLayout(this.gridAreaWidth);
  }

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    const hook: FileUiHook = {
      showAddCustomPath: (): void => {
        showFileAddCustomPathSheet(this.ctrl);
      },
      pickTargetFolder: (): Promise<string[]> => {
        return new Promise<string[]>((resolve: (paths: string[]) => void) => {
          pickTargetFolderViaSheet('', (paths: string[]): void => {
            resolve(paths);
          });
        });
      }
    };
    this.ctrl.uiHook = hook;
    this.ctrl.init();
    void this.ctrl.listDirectory(this.param.initialPath, 'normal');
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    this.ctrl.close();
  }

  private get isRootPage(): boolean {
    return this.param.isRootPage;
  }

  private pageTitle(): string {
    if (!this.isRootPage) {
      const t = this.param.initFolderName.trim();
      return t.length > 0 ? t : L10n.t('app_folder', '文件');
    }
    const m = this.ctrl.currentModule;
    if (m === 'favorites') {
      return L10n.t('favorites', '收藏');
    }
    if (m === 'recent') {
      return L10n.t('recent', '最近');
    }
    return L10n.t('app_folder', '文件');
  }

  private moduleIndex(): number {
    const m = this.ctrl.currentModule;
    if (m === 'favorites') {
      return 1;
    }
    if (m === 'recent') {
      return 2;
    }
    return 0;
  }

  private handleBack(): void {
    if (this.ctrl.isMultiSelectMode) {
      this.ctrl.exitMultiSelectMode();
      return;
    }
    if (this.isRootPage) {
      // 根页返回由外层（首页容器）处理：直接 pop
    }
    this.popPage();
  }

  private customBack(): boolean {
    if (this.ctrl.isMultiSelectMode) {
      this.ctrl.exitMultiSelectMode();
      return true;
    }
    return false;
  }

  private openDir(path: string, folderName: string): void {
    const p = new FileBrowserParam();
    p.initialPath = path;
    p.initFolderName = folderName;
    p.isRootPage = false;
    this.pushPage(AppRouter.FILES, p);
  }

  private async clearRecentConfirm(): Promise<void> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('recent_clear_confirm', '确定要清除最近访问记录吗？'));
    if (confirmed === true) {
      const ok = await this.ctrl.clearRecent();
      if (!ok) {
        DialogUtil.showErrorDialog(L10n.operationFailed);
      }
    }
  }

  build() {
    PageScaffold({
      title: '',
      showBack: false,
      statusBarBg: AppTheme.current().pageBg,
      customBack: (): boolean => this.customBack(),
      onBack: (): void => {
        this.handleBack();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    Column() {
      // 顶部操作栏
      this.TopActionsBar()
      // 搜索栏
      Column() {
        this.SearchBarRow()
        if (this.hasSearchState()) {
          Column({ space: 8 }) {
            this.SearchChip(this.scopeLabel(), this.ctrl.globalSearchLoading && this.ctrl.searchScope !== 'current')
            this.SearchChip(this.filterLabel(), false)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 8 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 4, bottom: 10 })
      // 视图工具栏
      this.FileToolbar()
      Divider()
        .color(AppTheme.current().divider)
      // 主列表
      Column() {
        this.ListBody()
      }
      .width('100%')
      .layoutWeight(1)
      // 底部：多选操作栏 / 根页底部导航
      if (this.ctrl.isMultiSelectMode) {
        this.MultiSelectBar()
      } else if (this.isRootPage) {
        this.BottomNavBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
  }

  private hasSearchState(): boolean {
    return this.ctrl.searchQuery.trim().length > 0 ||
      this.ctrl.searchScope !== 'current' ||
      this.ctrl.filterType !== 'all';
  }

  private scopeLabel(): string {
    const scope = this.ctrl.searchScope;
    if (scope === 'subtree') {
      return L10n.t('file_search_scope_current_dir_subtree', '当前目录及子目录');
    }
    if (scope === 'global') {
      return L10n.t('file_search_scope_global', '全局搜索');
    }
    return L10n.t('file_search_scope_current_dir', '当前目录');
  }

  private filterLabel(): string {
    switch (this.ctrl.filterType) {
      case 'dir':
        return L10n.t('dir', '文件夹');
      case 'document':
        return L10n.t('folder_filter_document', '文档');
      case 'video':
        return L10n.t('folder_filter_video', '视频');
      case 'audio':
        return L10n.t('folder_filter_audio', '音频');
      case 'image':
        return L10n.t('folder_filter_image', '图片');
      case 'archive':
        return L10n.t('folder_filter_archive', '压缩包');
      case 'file':
        return L10n.t('file', '文件');
      default:
        return L10n.t('all', '全部');
    }
  }

  @Builder
  TopActionsBar() {
    Row() {
      BorderedIconButton({
        icon: $r('sys.symbol.arrow_left'),
        onTap: (): void => {
          this.handleBack();
        }
      })
      if (!this.isRootPage) {
        BorderedIconButton({
          icon: $r('sys.symbol.xmark'),
          onTap: (): void => {
            // 关闭子页面：回到根文件页由路由栈 pop 完成
            this.popPage();
          }
        })
          .margin({ left: 10 })
      }
      Text(this.pageTitle())
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      BorderedIconButton({
        icon: $r('sys.symbol.plus'),
        onTap: (): void => {
          showFileCreateSheet(this.ctrl);
        }
      })
        .margin({ left: 10 })
      BorderedIconButton({
        icon: $r('sys.symbol.list_bullet'),
        onTap: (): void => {
          // 任务中心依赖传输模块（未迁移）
          ToastUtil.show(L10n.featureComingSoon);
        }
      })
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 6 })
  }

  @Builder
  SearchBarRow() {
    Row({ space: 8 }) {
      SearchInputBar({
        hintText: L10n.t('folder_search_placeholder', '搜索'),
        text: this.ctrl.searchQuery,
        onChanged: (v: string): void => {
          this.ctrl.setSearchQuery(v);
        },
        onClear: (): void => {
          this.ctrl.setSearchQuery('');
        }
      })
        .layoutWeight(1)
      if (this.ctrl.globalSearchLoading) {
        Column() {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(AppTheme.current().primary)
        }
        .width(36)
        .height(36)
        .borderRadius(10)
        .border({ width: 1, color: AppTheme.current().primary })
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.12))
      } else {
        BorderedIconButton({
          icon: $r('sys.symbol.slider_horizontal_2'),
          fillColor: this.hasSearchState() ?
            AppTheme.withAlpha(AppTheme.current().primary, 0.12) : '',
          onTap: (): void => {
            showFileSearchOptionsSheet(this.ctrl);
          }
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SearchChip(label: string, loading: boolean) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(12)
        .fontColor(AppTheme.current().onSurface)
      if (loading) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(AppTheme.current().primary)
      }
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(999)
    .border({ width: 1, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
    .onClick((): void => {
      showFileSearchOptionsSheet(this.ctrl);
    })
  }

  private sortLabel(): string {
    switch (this.ctrl.sortMode) {
      case 'name_asc':
        return L10n.t('folder_picker_sort_name_asc', '名称升序');
      case 'name_desc':
        return L10n.t('folder_picker_sort_name_desc', '名称降序');
      case 'size_asc':
        return L10n.t('folder_picker_sort_size_asc', '大小升序');
      case 'size_desc':
        return L10n.t('folder_picker_sort_size_desc', '大小降序');
      case 'type_asc':
        return L10n.t('folder_picker_sort_type_asc', '类型升序');
      case 'type_desc':
        return L10n.t('folder_picker_sort_type_desc', '类型降序');
      case 'mtime_asc':
        return L10n.t('folder_picker_sort_mtime_asc', '修改时间升序');
      case 'mtime_desc':
      default:
        return L10n.t('folder_picker_sort_mtime_desc', '修改时间降序');
    }
  }

  private viewIcon(): Resource {
    switch (this.ctrl.viewMode) {
      case 'list':
        return $r('sys.symbol.list_bullet');
      // 大图标模式用 2x2 疏格，普通网格用通用网格线，与 Flutter grid_view/grid_on 对应
      case 'large_grid':
        return $r('sys.symbol.square_grid_2x2');
      case 'grid':
      default:
        return $r('sys.symbol.grid');
    }
  }

  @Builder
  FileToolbar() {
    Row() {
      // 排序 / 清除最近
      Row({ space: 4 }) {
        if (this.ctrl.currentModule === 'recent') {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(18)
            .fontColor([AppTheme.current().subText])
        }
        Text(this.ctrl.currentModule === 'recent' ?
          L10n.t('recent_clear', '清除记录') : this.sortLabel())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
        if (this.ctrl.currentModule !== 'recent') {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(18)
            .fontColor([AppTheme.current().subText])
        }
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(10)
      .onClick((): void => {
        if (this.ctrl.currentModule === 'recent') {
          void this.clearRecentConfirm();
          return;
        }
        showFileSortSheet(this.ctrl);
      })
      Blank()
      BorderedIconButton({
        icon: this.ctrl.showHidden ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'),
        onTap: (): void => {
          void this.ctrl.toggleShowHidden();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        active: this.ctrl.filterType !== 'all',
        onTap: (): void => {
          showFileFilterSheet(this.ctrl);
        }
      })
        .margin({ left: 10 })
      BorderedIconButton({
        icon: this.viewIcon(),
        onTap: (): void => {
          const modes: string[] = ['grid', 'large_grid', 'list'];
          const idx = modes.indexOf(this.ctrl.viewMode);
          this.ctrl.setViewMode(modes[(idx + 1) % modes.length]);
        }
      })
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ListBody() {
    Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.loading && this.ctrl.items.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.displayItems.length === 0) {
        Column() {
          EmptyState({})
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else {
        this.ItemsByViewMode()
      }
    }
    .width('100%')
    .height('100%')
    .onRefreshing((): void => {
      this.refreshing = true;
      this.ctrl.refreshPage();
      // 刷新动画最短展示，完成后复位
      setTimeout((): void => {
        this.refreshing = false;
      }, 600);
    })
  }

  @Builder
  ItemsByViewMode() {
    if (this.ctrl.viewMode === 'list') {
      List({ space: 0 }) {
        ForEach(this.ctrl.displayItems, (it: FileItem, idx: number): void => {
          ListItem() {
            Column() {
              FileListItem({
                ctrl: this.ctrl,
                item: it,
                allItems: this.ctrl.displayItems,
                onOpenDir: (p: string, n: string): void => {
                  this.openDir(p, n);
                }
              })
              if (idx < this.ctrl.displayItems.length - 1) {
                Divider()
                  .color(AppTheme.withAlpha(AppTheme.current().divider, 0.6))
                  .strokeWidth(0.5)
                  .margin({ left: 12, right: 12 })
              }
            }
            .width('100%')
          }
        }, (it: FileItem): string => FileModelAccess.path(it))
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(8)
    } else {
      this.GridView()
    }
  }

  @Builder
  GridView() {
    Column() {
      Grid() {
        ForEach(this.ctrl.displayItems, (it: FileItem): void => {
          GridItem() {
            FileGridItem({
              ctrl: this.ctrl,
              item: it,
              allItems: this.ctrl.displayItems,
              thumbSize: this.gridThumb,
              itemHeight: this.gridItemHeight,
              onOpenDir: (p: string, n: string): void => {
                this.openDir(p, n);
              }
            })
          }
        }, (it: FileItem): string => FileModelAccess.path(it))
      }
      .columnsTemplate(`repeat(${this.gridCols}, 1fr)`)
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(4)
      .padding({ left: 12, right: 12, top: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area): void => {
      const width = Number(n.width);
      if (!Number.isFinite(width) || width <= 0) {
        return;
      }
      this.gridAreaWidth = width;
      this.updateGridLayout(width);
    })
  }

  /** 按容器宽与当前视图模式计算列数/缩略图尺寸/等高条目高度（对齐 Flutter app_file_list_body） */
  private updateGridLayout(width: number): void {
    if (width <= 0) {
      return;
    }
    const large = this.ctrl.viewMode === 'large_grid';
    const minItem = large ? 140 : 110;
    const spacing = 10;
    const count = Math.floor((width + spacing) / (minItem + spacing));
    const cols = count > 0 ? count : 1;
    const itemWidth = (width - 24 - (cols - 1) * spacing) / cols;
    const thumbMax = large ? 128 : 80;
    const thumb = Math.max(60, Math.min(thumbMax, itemWidth - 20));
    // desiredHeight = padding20 + thumb + 4 + name行高17 + 2 + rowHeight35
    const itemHeight = 20 + thumb + 4 + 17 + 2 + 35;
    this.gridCols = cols;
    this.gridThumb = Math.round(thumb);
    this.gridItemHeight = Math.round(itemHeight);
  }

  @Builder
  MultiSelectAction(icon: Resource, label: string, enabled: boolean, danger: boolean, onTap: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([enabled ? (danger ? '#E53935' : AppTheme.current().onSurface) : AppTheme.current().hint])
      Text(label)
        .fontSize(10)
        .fontColor(enabled ? (danger ? '#E53935' : AppTheme.current().onSurface) : AppTheme.current().hint)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .onClick((): void => {
      if (enabled) {
        onTap();
      }
    })
  }

  private async confirmDeleteSelected(): Promise<void> {
    const count = `${this.ctrl.selected.length}`;
    const content = L10n.t('folder_delete_confirm', '确定删除这 @fileCount 项吗？',
      L10n.paramsOf('fileCount', count));
    if (this.ctrl.shellSupported) {
      await DialogUtil.showConfirmThreeButtonsDialog(
        L10n.t('need_confirm', '需要确认'),
        content,
        (): void => {
          void this.ctrl.deleteSelectedEntries(false);
        },
        (): void => {
          void this.ctrl.deleteSelectedEntries(true);
        },
        L10n.cancel,
        L10n.t('delete', '删除'),
        L10n.t('put_in_recycle_bin', '放入回收站'));
    } else {
      const confirmed = await DialogUtil.showConfirmDialog(
        L10n.t('need_confirm', '需要确认'), content);
      if (confirmed === true) {
        await this.ctrl.deleteSelectedEntries(false);
      }
    }
  }

  @Builder
  MultiSelectBar() {
    Row() {
      this.MultiSelectAction(
        this.ctrl.currentModule === 'favorites' ? $r('sys.symbol.star') : $r('sys.symbol.star_fill'),
        this.ctrl.currentModule === 'favorites' ?
          L10n.t('unfavorite', '取消收藏') : L10n.t('folder_add_favorite', '添加到收藏'),
        this.ctrl.selected.length > 0, false, (): void => {
          const inFav = this.ctrl.currentModule === 'favorites';
          const paths = this.ctrl.getSelected();
          if (paths.length === 0) {
            return;
          }
          const fut = inFav ? this.ctrl.removeFavorites(paths) : this.ctrl.addFavorites(paths);
          void fut.then((ok: boolean): void => {
            ToastUtil.show(ok ? L10n.t('operation_success', '操作成功') : L10n.operationFailed);
            this.ctrl.clearSelect();
          });
        })
      this.MultiSelectAction(
        $r('sys.symbol.square_and_arrow_down'),
        L10n.t('download', '下载'),
        this.ctrl.selected.length > 0, false, (): void => {
          // 下载依赖传输模块（未迁移）
          ToastUtil.show(L10n.featureComingSoon);
        })
      this.MultiSelectAction(
        $r('sys.symbol.trash'),
        L10n.t('delete', '删除'),
        this.ctrl.selected.length > 0, true, (): void => {
          void this.confirmDeleteSelected();
        })
      this.MultiSelectAction(
        $r('sys.symbol.more'),
        L10n.t('more', '更多'),
        this.ctrl.selected.length > 0, false, (): void => {
          showFileMoreSheet(this.ctrl);
        })
      Divider()
        .vertical(true)
        .height(36)
        .color(AppTheme.current().divider)
      Column({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(22)
          .fontColor([AppTheme.current().onSurface])
        Text(L10n.cancel)
          .fontSize(10)
          .fontColor(AppTheme.current().onSurface)
      }
      .justifyContent(FlexAlign.Center)
      .width(64)
      .padding({ top: 6, bottom: 6 })
      .onClick((): void => {
        this.ctrl.exitMultiSelectMode();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
    .shadow({ radius: 12, color: '#1A000000', offsetY: -2 })
    // 多选栏同样延伸到底部安全区，保持与 tab 栏一致的底色
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  BottomNavBarItem(icon: Resource, label: string, index: number) {
    Column({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.moduleIndex() === index ? AppTheme.current().primary : AppTheme.current().subText])
      Text(label)
        .fontSize(11)
        .fontColor(this.moduleIndex() === index ? AppTheme.current().primary : AppTheme.current().subText)
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .onClick((): void => {
      if (index === this.moduleIndex()) {
        return;
      }
      if (index === 1) {
        void this.ctrl.listDirectory('', 'favorites');
        return;
      }
      if (index === 2) {
        void this.ctrl.listDirectory('', 'recent');
        return;
      }
      void this.ctrl.listDirectory('', 'normal');
    })
  }

  @Builder
  BottomNavBar() {
    Row() {
      this.BottomNavBarItem($r('sys.symbol.folder'), L10n.t('app_folder', '文件'), 0)
      this.BottomNavBarItem($r('sys.symbol.star'), L10n.t('favorites', '收藏'), 1)
      this.BottomNavBarItem($r('sys.symbol.clock'), L10n.t('recent', '最近'), 2)
    }
    .width('100%')
    .border({ width: { top: 0.5 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
    // 背景延伸到底部导航条安全区，避免露出页面底色
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
