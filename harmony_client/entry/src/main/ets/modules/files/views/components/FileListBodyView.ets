import { AppTheme } from '../../../../core/theme/AppTheme';
import { EmptyState } from '../../../../common/components/EmptyState';
import { FileController } from '../../controllers/FileController';
import { FileItem, FileModelAccess } from '../../models/FileModels';
import { FileGridItem, FileListItem } from '../FileItems';

/**
 * 文件列表懒加载数据源：用 ForEach 会一次性构建目录内全部条目及其缩略图组件
 * （每个 FileThumb 都会发起 tiny URL 解析与图片加载），几百上千项时首屏与滑动都会卡顿。
 * LazyForEach 只构建可见项 + cachedCount 邻项，缩略图请求随之按需发起。
 * 数据更新仅使用 onDataReloaded（同一 listener 不可混用其他 DataChangeListener 接口，否则运行时崩溃 401）。
 */
class FileItemsSource implements IDataSource {
  private items: FileItem[] = [];
  private listeners: DataChangeListener[] = [];

  /** 用控制器当前展示列表同步；内容未变化时跳过通知，避免重复重建可见条目 */
  sync(next: FileItem[]): void {
    if (this.isSame(this.items, next)) {
      return;
    }
    this.items = next;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  private isSame(a: FileItem[], b: FileItem[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      const x = a[i];
      const y = b[i];
      if (x === y) {
        continue;
      }
      // displayItems 每次都会重建 custom_add 虚拟行，按 path 视为同一行
      if (FileModelAccess.virtualType(y).length > 0 && FileModelAccess.path(x) === FileModelAccess.path(y)) {
        continue;
      }
      return false;
    }
    return true;
  }

  /** 当前展示列表整份数据（条目打开图集/连播时需与其他条目同一引用定位同目录文件） */
  all(): FileItem[] {
    return this.items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): FileItem {
    return this.items[index];
  }

  registerDataChangeListener(l: DataChangeListener): void {
    if (this.listeners.indexOf(l) < 0) {
      this.listeners.push(l);
    }
  }

  unregisterDataChangeListener(l: DataChangeListener): void {
    const idx = this.listeners.indexOf(l);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }
}

/**
 * 文件主列表（通用组件，对齐 Flutter app_file_list_body）：
 * 下拉刷新 + 加载/空态 + 列表视图 + 网格视图（按容器宽与视图模式动态计算列数）。
 */
@ComponentV2
export struct FileListBodyView {
  @Param ctrl: FileController = new FileController(false);
  /** 进入子目录回调 */
  @Param onOpenDir: (path: string, folderName: string) => void = (_p: string, _n: string): void => {
  };
  @Local refreshing: boolean = false;
  @Local gridCols: number = 3;
  @Local gridThumb: number = 80;
  @Local gridItemHeight: number = 158;
  private gridAreaWidth: number = 0;
  /** 懒加载数据源（仅构建可见条目） */
  private source: FileItemsSource = new FileItemsSource();

  aboutToAppear(): void {
    this.source.sync(this.ctrl.displayItems);
  }

  /** 展示列表的依赖项变化时同步数据源（ctrl.displayItems 本身每次读取都会重算，故不逐项读取） */
  @Monitor('ctrl.items', 'ctrl.searchQuery', 'ctrl.searchScope', 'ctrl.filterType',
    'ctrl.globalSearchItems', 'ctrl.currentPath', 'ctrl.currentModule')
  onListDataChange(): void {
    this.source.sync(this.ctrl.displayItems);
  }

  /** 视图模式切换后按新模式重算网格布局（onAreaChange 不会因内容变化再触发） */
  @Monitor('ctrl.viewMode')
  onViewModeChange(): void {
    this.updateGridLayout(this.gridAreaWidth);
  }

  build() {
    Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.loading && this.ctrl.displayItems.length === 0) {
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
        LazyForEach(this.source, (it: FileItem): void => {
          ListItem() {
            FileListItem({
              ctrl: this.ctrl,
              item: it,
              allItems: this.source.all(),
              onOpenDir: (p: string, n: string): void => {
                this.onOpenDir(p, n);
              }
            })
          }
        }, (it: FileItem): string => FileModelAccess.path(it))
      }
      .width('100%')
      .height('100%')
      .divider({
        strokeWidth: 0.5,
        color: AppTheme.withAlpha(AppTheme.current().divider, 0.6),
        startMargin: 12,
        endMargin: 12
      })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(10)
    } else {
      this.GridView()
    }
  }

  @Builder
  GridView() {
    Column() {
      Grid() {
        LazyForEach(this.source, (it: FileItem): void => {
          GridItem() {
            FileGridItem({
              ctrl: this.ctrl,
              item: it,
              allItems: this.source.all(),
              thumbSize: this.gridThumb,
              itemHeight: this.gridItemHeight,
              onOpenDir: (p: string, n: string): void => {
                this.onOpenDir(p, n);
              }
            })
          }
          // 固定行高：懒加载时未创建的条目也能按等高参与滚动布局计算
          .height(this.gridItemHeight)
        }, (it: FileItem): string => FileModelAccess.path(it))
      }
      .columnsTemplate(`repeat(${this.gridCols}, 1fr)`)
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(8)
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
}
