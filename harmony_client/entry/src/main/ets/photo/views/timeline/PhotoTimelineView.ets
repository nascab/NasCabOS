import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { TimelineController, TimelineRowItem } from '../../controllers/TimelineController';
import { TimelinePhotoItem } from '../../models/PhotoModels';
import { PhotoTimelineItem } from './PhotoTimelineItem';
import { PhotoTimelineDateHeader } from './PhotoTimelineDateHeader';
import { PhotoTimelineSidebar } from './PhotoTimelineSidebar';
import { showPhotoTimelineFilterSheet } from './PhotoTimelineFilterSheet';

/** 列表项包装：0=顶部加载 1=照片行 2=底部加载/没有更多 */
class TimelineEntry {
  kind: number = 1;
  row: TimelineRowItem = new TimelineRowItem();

  static topLoading(): TimelineEntry {
    const e = new TimelineEntry();
    e.kind = 0;
    return e;
  }

  static footer(): TimelineEntry {
    const e = new TimelineEntry();
    e.kind = 2;
    return e;
  }
}

class TimelineRowsDataSource implements IDataSource {
  private entries: TimelineEntry[] = [];
  private listeners: DataChangeListener[] = [];

  sync(ctrl: TimelineController): void {
    const next: TimelineEntry[] = [];
    if (ctrl.isLoadingUp) {
      next.push(TimelineEntry.topLoading());
    }
    for (const r of ctrl.rows) {
      const e = new TimelineEntry();
      e.kind = 1;
      e.row = r;
      next.push(e);
    }
    if (ctrl.isLoadingDown || !ctrl.hasMoreDown) {
      next.push(TimelineEntry.footer());
    }
    this.entries = next;
    this.notifyReload();
  }

  private notifyReload(): void {
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): TimelineEntry {
    return this.entries[index];
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
 * 照片时间线视图（对齐 Flutter AppPhotoTimelineView）：
 * 工具栏（排序/搜索/范围/缩放/筛选）+ 网格列表 + 右侧日期手柄 + 下拉刷新 + 双指捏合缩放。
 * showSearchAction=false 时（照片主页内嵌）显示多选入口按钮。
 */
@ComponentV2
export struct PhotoTimelineView {
  @Param ctrl: TimelineController = new TimelineController();
  @Param showSearchAction: boolean = false;
  private ds: TimelineRowsDataSource = new TimelineRowsDataSource();
  private scroller: Scroller = new Scroller();
  private scrollPos: number = 0;
  /** 双指捏合 */
  private pinchStartSize: number = 0;
  private pinchLastApplied: number = 0;
  private pinchDirty: boolean = false;
  @Local isRefreshing: boolean = false;

  aboutToAppear(): void {
    this.ctrl.onRowsChanged = (): void => {
      this.ds.sync(this.ctrl);
    };
    this.ctrl.onTimelineReset = (): void => {
      this.scrollPos = 0;
      this.scroller.scrollToIndex(0, false);
    };
    this.ds.sync(this.ctrl);
  }

  aboutToDisappear(): void {
    this.ctrl.onRowsChanged = undefined;
    this.ctrl.onTimelineReset = undefined;
  }

  @Monitor('ctrl.isLoadingUp', 'ctrl.isLoadingDown', 'ctrl.hasMoreDown', 'ctrl.isLoadingDates')
  onLoadingChange(): void {
    this.ds.sync(this.ctrl);
  }

  build() {
    Column() {
      if (!this.ctrl.isMultiSelectMode) {
        this.Toolbar()
      }
      Stack() {
        if (this.ctrl.isLoadingDates && this.ctrl.dateList.length === 0) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(AppTheme.current().primary)
        } else if (this.ctrl.rows.length === 0 && !this.ctrl.isLoadingDates && !this.ctrl.isLoadingDown) {
          EmptyState({ message: L10n.t('no_photo', '暂无照片') })
        } else {
          Refresh({ refreshing: this.isRefreshing }) {
            this.ListContent()
          }
          .onRefreshing(() => {
            this.isRefreshing = true;
            this.ctrl.refreshTimeline().finally(() => {
              this.isRefreshing = false;
            });
          })
          PhotoTimelineSidebar({ ctrl: this.ctrl })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((_o: Area, n: Area): void => {
        const w = Number(n.width);
        if (w > 0) {
          this.ctrl.updateLayout(w - 12);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
  }

  @Builder
  ListContent() {
    List({ scroller: this.scroller, space: 1 }) {
      LazyForEach(this.ds, (entry: TimelineEntry, idx: number): void => {
        ListItem() {
          if (entry.kind === 0) {
            // 顶部加载指示
            Row() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(AppTheme.current().primary)
            }
            .width('100%')
            .height(56)
            .justifyContent(FlexAlign.Center)
          } else if (entry.kind === 2) {
            // 底部：加载中 / 没有更多
            Column() {
              if (this.ctrl.isLoadingDown) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(AppTheme.current().primary)
              } else {
                Text(L10n.t('no_more', '没有更多'))
                  .fontSize(13)
                  .fontColor(AppTheme.current().hint)
              }
            }
            .width('100%')
            .padding({ top: 16, bottom: 25 })
            .justifyContent(FlexAlign.Center)
          } else {
            TimelineRowView({ row: entry.row, ctrl: this.ctrl })
              .margin({ left: 6, right: 6 })
          }
        }
      }, (entry: TimelineEntry, idx: number): string => `${entry.kind}_${idx}_${entry.row.date}_${entry.row.photos.length}`)
    }
    .width('100%')
    .height('100%')
    .cachedCount(6)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .maintainVisibleContentPosition(true)
    .onScrollIndex((first: number, last: number): void => {
      const topOffset = this.ctrl.isLoadingUp ? 1 : 0;
      this.ctrl.onListScroll(Math.max(0, first - topOffset), Math.max(0, last - topOffset), this.scrollPos);
    })
    .onDidScroll((delta: number): void => {
      if (this.ctrl.rows.length > 0) {
        this.scrollPos += delta;
      }
    })
    .gesture(PinchGesture({ fingers: 2 })
      .onActionStart((_e: GestureEvent) => {
        this.pinchStartSize = this.ctrl.itemSize;
        this.pinchLastApplied = this.ctrl.itemSize;
        this.pinchDirty = false;
      })
      .onActionUpdate((e: GestureEvent) => {
        const scale = e.scale;
        if (scale <= 0) {
          return;
        }
        const next = Math.min(Math.max(this.pinchStartSize * scale,
          this.ctrl.minItemSize), this.ctrl.maxItemSize);
        if (Math.abs(next - this.pinchLastApplied) < 2) {
          return;
        }
        this.pinchLastApplied = next;
        this.pinchDirty = true;
        this.ctrl.setItemSize(next, false);
      })
      .onActionEnd(() => {
        if (this.pinchDirty) {
          this.ctrl.setItemSize(this.ctrl.itemSize, true);
        }
        this.pinchDirty = false;
      }))
  }

  @Builder
  Toolbar() {
    Row({ space: 8 }) {
      BorderedIconButton({
        icon: this.ctrl.sortOrder === 'desc'
          ? $r('sys.symbol.arrow_counterclockwise')
          : $r('sys.symbol.arrow_clockwise'),
        active: false,
        onTap: (): void => {
          this.ctrl.toggleSortOrder();
        }
      })
      if (this.showSearchAction) {
        SearchInputBar({
          hintText: L10n.t('photo_timeline_search_hint', '照片搜索'),
          text: this.ctrl.searchKeyword,
          onChanged: (v: string): void => {
            this.ctrl.onSearchChanged(v);
          },
          onClear: (): void => {
            this.ctrl.clearSearch();
          }
        })
          .layoutWeight(1)
      } else {
        Blank()
        BorderedIconButton({
          icon: $r('sys.symbol.checkmark_circle'),
          active: false,
          onTap: (): void => {
            this.ctrl.toggleMultiSelectMode();
          }
        })
      }
      this.NearbyRangePicker()
      if (this.ctrl.baseGeohash.trim().length === 0) {
        BorderedIconButton({
          icon: $r('sys.symbol.minus_circle'),
          isEnabled: this.ctrl.itemSize > this.ctrl.minItemSize,
          onTap: (): void => {
            this.ctrl.changeItemSize(-20);
          }
        })
        BorderedIconButton({
          icon: $r('sys.symbol.plus_circle'),
          isEnabled: this.ctrl.itemSize < this.ctrl.maxItemSize,
          onTap: (): void => {
            this.ctrl.changeItemSize(20);
          }
        })
      }
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        active: this.ctrl.selectedPaths.length > 0 || this.ctrl.fileType !== 'all',
        onTap: (): void => {
          showPhotoTimelineFilterSheet(this.ctrl);
        }
      })
    }
    .width('100%')
    .height(52)
    .padding({ left: 6, right: 6 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  @Builder
  NearbyRangePicker() {
    if (this.ctrl.baseGeohash.trim().length > 0) {
      BorderedIconButton({
        icon: $r('sys.symbol.mappin_and_rectangle'),
        active: this.ctrl.nearbyRangeKm !== 2,
        onTap: (): void => {
          const options: PickOption[] = [
            new PickOption('2', '2km'),
            new PickOption('5', '5km'),
            new PickOption('10', '10km'),
            new PickOption('50', '50km'),
            new PickOption('80', '80km')
          ];
          showOptionPickSheet('', options, `${this.ctrl.nearbyRangeKm}`, (key: string): void => {
            this.ctrl.setNearbyRangeKm(parseInt(key, 10));
          });
        }
      })
    }
  }
}

/** 单行渲染（header 行或一行照片），独立组件以便观察尺寸/选中变化 */
@ComponentV2
struct TimelineRowView {
  @Param row: TimelineRowItem = new TimelineRowItem();
  @Param ctrl: TimelineController = new TimelineController();

  build() {
    if (this.row.isHeader) {
      Column() {
        PhotoTimelineDateHeader({ date: this.row.date, ctrl: this.ctrl })
      }
      .height(54)
      .width('100%')
    } else {
      Row({ space: 1 }) {
        ForEach(this.row.photos, (p: TimelinePhotoItem): void => {
          PhotoTimelineItem({ item: p, ctrl: this.ctrl })
            .width(this.ctrl.cellExtent)
            .height(this.cellHeight())
        }, (p: TimelinePhotoItem): string => `${p.id}`)
      }
      .width('100%')
      .height(this.cellHeight())
      .alignItems(VerticalAlign.Top)
    }
  }

  /** 读取 itemSize 建立观察依赖（缩放时行高刷新） */
  private cellHeight(): number {
    const _size = this.ctrl.itemSize;
    return this.ctrl.cellExtent;
  }
}
