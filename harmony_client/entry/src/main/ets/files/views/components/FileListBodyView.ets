import { AppTheme } from '../../../core/theme/AppTheme';
import { EmptyState } from '../../../common/components/EmptyState';
import { FileController } from '../../controllers/FileController';
import { FileItem, FileModelAccess } from '../../models/FileModels';
import { FileGridItem, FileListItem } from '../FileItems';

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

  /** 视图模式切换后按新模式重算网格布局（onAreaChange 不会因内容变化再触发） */
  @Monitor('ctrl.viewMode')
  onViewModeChange(): void {
    this.updateGridLayout(this.gridAreaWidth);
  }

  build() {
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
                  this.onOpenDir(p, n);
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
                this.onOpenDir(p, n);
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
}
