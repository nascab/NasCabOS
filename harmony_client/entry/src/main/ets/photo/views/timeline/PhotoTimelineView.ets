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
  static readonly TOP_LOADING_KEY: string = '__timeline_top_loading__';
  static readonly FOOTER_KEY: string = '__timeline_footer__';
  kind: number = 1;
  row: TimelineRowItem = new TimelineRowItem();
  key: string = '';

  static topLoading(): TimelineEntry {
    const e = new TimelineEntry();
    e.kind = 0;
    e.key = TimelineEntry.TOP_LOADING_KEY;
    return e;
  }

  static footer(): TimelineEntry {
    const e = new TimelineEntry();
    e.kind = 2;
    e.key = TimelineEntry.FOOTER_KEY;
    return e;
  }
}

class TimelineRowsDataSource implements IDataSource {
  private entries: TimelineEntry[] = [];
  private listeners: DataChangeListener[] = [];

  sync(ctrl: TimelineController): void {
    const next: TimelineEntry[] = [];
    // 程序化定位（jumpToDate 向上补页）期间不插入顶部 loading 哨兵：
    // 哨兵的插入/移除会触发两次全量 onDataReloaded，打断 LazyForEach 布局与
    // maintainVisibleContentPosition 的位置保持，表现为补页后画面停在最新日期近 1 秒再跳。
    if (ctrl.isLoadingUp && !ctrl.programmaticScroll) {
      next.push(TimelineEntry.topLoading());
    }
    for (const r of ctrl.rows) {
      const e = new TimelineEntry();
      e.kind = 1;
      e.row = r;
      e.key = r.key;
      next.push(e);
    }
    if (ctrl.isLoadingDown || !ctrl.hasMoreDown) {
      next.push(TimelineEntry.footer());
    }
    // key 序列与行对象引用完全相同则短路（如程序化补页开始时 isLoadingUp 置位但不插哨兵的
    // 那次刷新）：rebuildRows 总会生成全新 row 对象，因此任何真实数据变化都不会被误跳过
    if (next.length === this.entries.length) {
      let same = true;
      for (let i = 0; i < next.length; i++) {
        if (next[i].key !== this.entries[i].key) {
          same = false;
          break;
        }
        // 数据行还要求 row 引用一致（哨兵/footer 每次新建，只比 key）
        if (next[i].kind === 1 && next[i].row !== this.entries[i].row) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
    }
    // 程序化定位的“向上补页”是纯头部插入：用增量通知替代全量刷新，
    // 配合 List.maintainVisibleContentPosition 让目标日自动保持在原位（可见项下标
    // 自动前移），无需 scrollTo——远距 scrollTo 会触发上千行按需布局，阻塞主线程近 1 秒。
    if (ctrl.programmaticScroll && this.applyPrependIfMatched(next)) {
      return;
    }
    // 全量替换：全程只使用 onDatasetChange（ArkUI 约束：同一 listener 一旦用过
    // onDatasetChange，就不能再混用 onDataReloaded 等其他通知接口，否则运行时崩溃 401）
    const oldLen = this.entries.length;
    this.entries = next;
    const ops: DataOperation[] = [];
    if (oldLen > 0) {
      ops.push({ type: DataOperationType.DELETE, index: 0, count: oldLen });
    }
    ops.push({ type: DataOperationType.ADD, index: 0, count: next.length });
    this.notifyDatasetChange(ops);
  }

  /**
   * 检测 next 相对当前 entries 是否为“头部插入若干行 + 至多删除 1 个重合 header”，
   * 命中则发增量删除/插入通知并返回 true；形态不符返回 false 由调用方全量刷新。
   */
  private applyPrependIfMatched(next: TimelineEntry[]): boolean {
    const old = this.entries;
    if (old.length === 0 || next.length <= old.length) {
      return false;
    }
    // 尾部哨兵序列必须一致（程序化期间无顶部哨兵）
    const oldSentinelCount = old.length - this.lastDataIndex(old) - 1;
    const nextSentinelCount = next.length - this.lastDataIndex(next) - 1;
    if (oldSentinelCount !== nextSentinelCount || oldSentinelCount > 1) {
      return false;
    }
    for (let k = 1; k <= oldSentinelCount; k++) {
      if (old[old.length - k].key !== next[next.length - k].key) {
        return false;
      }
    }
    const oldDataLen = old.length - oldSentinelCount;
    const nextDataLen = next.length - nextSentinelCount;
    // 最长公共后缀
    let common = 0;
    while (common < oldDataLen && common < nextDataLen
      && old[oldDataLen - 1 - common].key === next[nextDataLen - 1 - common].key) {
      common++;
    }
    if (common === 0) {
      return false;
    }
    const removed = oldDataLen - common;
    const inserted = nextDataLen - common;
    if (inserted <= 0 || removed > 1) {
      return false;
    }
    // 删除的只允许是边界重合的 header（mergeIncomingPhotos 的唯一删除形态）
    if (removed === 1 && !old[0].key.startsWith('h_')) {
      return false;
    }
    this.entries = next;
    const ops: DataOperation[] = [];
    if (removed > 0) {
      ops.push({ type: DataOperationType.DELETE, index: 0, count: removed });
    }
    // 单次批量插入区间，避免逐条 onDataAdd 触发上百次增量布局（实测可阻塞主线程近 0.9s）
    ops.push({ type: DataOperationType.ADD, index: 0, count: inserted });
    // TODO(diag) 跳转整天丢失排查，定位后删除
    console.info(`[TimelineJump] prependIncremental inserted=${inserted} removed=${removed}`);
    this.notifyDatasetChange(ops);
    return true;
  }

  private lastDataIndex(list: TimelineEntry[]): number {
    for (let i = list.length - 1; i >= 0; i--) {
      if (list[i].kind === 1) {
        return i;
      }
    }
    return -1;
  }

  /** 统一通知出口：全工程只允许使用 onDatasetChange，不可混用其他 DataChangeListener 接口 */
  private notifyDatasetChange(ops: DataOperation[]): void {
    for (const l of this.listeners) {
      l.onDatasetChange(ops);
    }
  }

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): TimelineEntry {
    return this.entries[index];
  }

  /** 精确 key（header/行/头尾哨兵）所在条目下标 */
  indexOfKey(key: string): number {
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].key === key) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 锚点定位：h_日期 直接匹配 header；
   * id_/r_照片id 匹配包含该照片的行（向上分页合并后行可能重排，不能依赖行 key 不变）。
   */
  indexOfAnchor(anchor: string): number {
    if (anchor.startsWith('h_')) {
      return this.indexOfKey(anchor);
    }
    let idPart = '';
    if (anchor.startsWith('id_')) {
      idPart = anchor.substring(3);
    } else if (anchor.startsWith('r_')) {
      idPart = anchor.substring(2);
    } else {
      return this.indexOfKey(anchor);
    }
    const photoId = parseInt(idPart, 10);
    if (isNaN(photoId)) {
      return -1;
    }
    for (let i = 0; i < this.entries.length; i++) {
      const e = this.entries[i];
      if (e.kind !== 1 || e.row.isHeader) {
        continue;
      }
      for (const p of e.row.photos) {
        if (p.id === photoId) {
          return i;
        }
      }
    }
    return -1;
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
  /**
   * 滚动指令代次：每次“回顶/锚点恢复”都会 +1。
   * jumpToDate 早期发出的回顶重试链，必须被后续的锚点恢复指令作废，
   * 否则迟到的 scrollToIndex(0) 会把已定位到目标日期的列表重新拽回顶部
   *（表现为拖到 2/1 却停在窗口最新日期 2/8）。
   */
  private scrollEpoch: number = 0;
  private disposed: boolean = false;
  /** onScrollIndex 实际上报的首个可见项下标，用于定位后反馈校正 */
  private observedFirst: number = 0;

  aboutToAppear(): void {
    this.ctrl.onRowsChanged = (): void => {
      this.ds.sync(this.ctrl);
    };
    this.ctrl.onTimelineReset = (): void => {
      this.scrollPos = 0;
      const epoch = this.nextScrollEpoch();
      this.ctrl.programmaticScroll = true;
      this.scrollToIndexAfterLayout(0, 0, epoch);
    };
    this.ctrl.onRestoreAnchor = (): void => {
      const epoch = this.nextScrollEpoch();
      // 定位全程抑制滚动事件误触发分页（对齐 Flutter userScrollDirection 判定），
      // 否则定位中途的 loadMore 会用捕获到的中间行锚点再次回调，把位置顶到前一天
      this.ctrl.programmaticScroll = true;
      const anchor = this.ctrl.restoreAnchorKey;
      if (anchor.length === 0) {
        this.scrollToIndexAfterLayout(0, 0, epoch);
        return;
      }
      this.scrollToAnchorAfterLayout(anchor, 0, epoch);
    };
    this.ds.sync(this.ctrl);
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.ctrl.programmaticScroll = false;
    this.ctrl.onRowsChanged = undefined;
    this.ctrl.onTimelineReset = undefined;
    this.ctrl.onRestoreAnchor = undefined;
  }

  private nextScrollEpoch(): number {
    this.scrollEpoch++;
    return this.scrollEpoch;
  }

  /** 结束程序化滚动状态（仅当本指令链仍是最新一代时生效），留 120ms 宽限吃掉残余滚动事件 */
  private endProgrammaticScroll(epoch: number): void {
    setTimeout((): void => {
      if (!this.disposed && epoch === this.scrollEpoch) {
        this.ctrl.programmaticScroll = false;
      }
    }, 120);
  }

  /**
   * 数据整体刷新（onDataReloaded）后定位到指定下标。
   * scrollToIndex 由系统按真实布局定位，不会因混合行高的像素估算而过冲。
   * epoch 代次保证旧指令链立即失效。
   */
  private scrollToIndexAfterLayout(index: number, attempt: number, epoch: number): void {
    setTimeout((): void => {
      if (this.disposed || epoch !== this.scrollEpoch) {
        return;
      }
      if (index < 0 || index >= this.ds.totalCount()) {
        if (attempt < 10) {
          this.scrollToIndexAfterLayout(index, attempt + 1, epoch);
        } else {
          this.endProgrammaticScroll(epoch);
        }
        return;
      }
      if (this.observedFirst !== index) {
        this.scroller.scrollToIndex(index, false, ScrollAlign.START);
      }
      if (this.observedFirst !== index) {
        if (attempt < 10) {
          this.scrollToIndexAfterLayout(index, attempt + 1, epoch);
        } else {
          this.endProgrammaticScroll(epoch);
        }
      } else {
        this.endProgrammaticScroll(epoch);
      }
    }, 16);
  }

  private scrollToAnchorAfterLayout(anchor: string, attempt: number, epoch: number): void {
    setTimeout((): void => {
      if (this.disposed || epoch !== this.scrollEpoch) {
        return;
      }
      const index = this.ds.indexOfAnchor(anchor);
      // TODO(diag) 跳转整天丢失排查，定位后删除
      console.info(`[TimelineJump] restore attempt=${attempt} anchor=${anchor} index=${index} observedFirst=${this.observedFirst} total=${this.ds.totalCount()}`);
      if (index < 0) {
        if (attempt < 10) {
          this.scrollToAnchorAfterLayout(anchor, attempt + 1, epoch);
        } else {
          this.endProgrammaticScroll(epoch);
        }
        return;
      }
      if (this.observedFirst === index) {
        // 头部增量插入后 maintainVisibleContentPosition 已把目标保持在原位
        this.endProgrammaticScroll(epoch);
        return;
      }
      // 前两拍（~32ms）只观察不滚动：位置保持的 onScrollIndex 上报可能滞后一两帧，
      // 抢跑会把已正确保持的画面拖走（实测像素估算抢跑导致 285→126→131 连续跳动）。
      if (attempt >= 2) {
        // 系统按真实布局定位，目标精确、不过冲；配合反馈环重试即可收敛
        this.scroller.scrollToIndex(index, false, ScrollAlign.START);
      }
      if (attempt < 12) {
        this.scrollToAnchorAfterLayout(anchor, attempt + 1, epoch);
      } else {
        this.endProgrammaticScroll(epoch);
      }
    }, 16);
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
      }, (entry: TimelineEntry): string => entry.key)
    }
    .width('100%')
    .height('100%')
    .cachedCount(6)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .maintainVisibleContentPosition(true)
    .onScrollIndex((first: number, last: number): void => {
      this.observedFirst = first;
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
