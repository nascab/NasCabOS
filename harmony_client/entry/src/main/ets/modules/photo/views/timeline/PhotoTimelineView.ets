import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { BorderedIconButton } from '../../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../../common/components/SearchInputBar';
import { EmptyState } from '../../../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../../../common/components/OptionPickSheet';
import { TimelineController, TimelineRowItem, TimelineViewport } from '../../controllers/TimelineController';
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
    // 差量更新：只对“最长公共前缀/后缀”之间的差异区间下发 DELETE + ADD。
    // 不能做全量替换（先删除全部再插入全部）：那样会连带删除 List 的
    // maintainVisibleContentPosition 锚点项，删除照片后列表会沿用旧像素偏移，
    // 落在完全不同的日期上（表现为“自动跳转到一个中间位置的日期”）。
    // 删除照片只影响所在日期的行，其余行的 key 与内容都不变，因此差异区间很小，
    // 可见区域的锚点行保持不变，画面无需滚动。全程只使用 onDatasetChange
    // （ArkUI 约束：同一 listener 一旦用过 onDatasetChange，就不能再混用
    // onDataReloaded 等其他通知接口，否则运行时崩溃 401）。
    const oldLen = this.entries.length;
    const nextLen = next.length;
    let prefix = 0;
    while (prefix < oldLen && prefix < nextLen
      && this.sameEntry(this.entries[prefix], next[prefix])) {
      prefix++;
    }
    let suffix = 0;
    while (suffix < oldLen - prefix && suffix < nextLen - prefix
      && this.sameEntry(this.entries[oldLen - 1 - suffix], next[nextLen - 1 - suffix])) {
      suffix++;
    }
    const removed = oldLen - prefix - suffix;
    const added = nextLen - prefix - suffix;
    if (removed === 0 && added === 0) {
      return;
    }
    this.entries = next;
    const ops: DataOperation[] = [];
    if (removed > 0) {
      ops.push({ type: DataOperationType.DELETE, index: prefix, count: removed });
    }
    // 单次批量插入区间，避免逐条 onDataAdd 触发上百次增量布局（实测可阻塞主线程近 0.9s）
    if (added > 0) {
      ops.push({ type: DataOperationType.ADD, index: prefix, count: added });
    }
    this.notifyDatasetChange(ops);
  }

  /** 条目渲染语义是否完全相同：key 相同，照片行还要求照片序列一致（行内移位需重建） */
  private sameEntry(a: TimelineEntry, b: TimelineEntry): boolean {
    if (a.kind !== b.kind || a.key !== b.key) {
      return false;
    }
    if (a.kind !== 1) {
      return true;
    }
    return this.sameRow(a.row, b.row);
  }

  private sameRow(a: TimelineRowItem, b: TimelineRowItem): boolean {
    if (a.isHeader || b.isHeader) {
      return a.isHeader === b.isHeader && a.date === b.date;
    }
    if (a.photos.length !== b.photos.length) {
      return false;
    }
    for (let i = 0; i < a.photos.length; i++) {
      if (a.photos[i].id !== b.photos[i].id) {
        return false;
      }
    }
    return true;
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

  // ---- 多选拖选（长按 + 滑动框选，边缘自动滚动）----
  /** 列表窗口位置与高度（拖选命中测试用） */
  private listLeft: number = 0;
  private listTop: number = 0;
  private listHeight: number = 0;
  /** 当前手指窗口坐标（拖选命中测试用） */
  private fingerX: number = 0;
  private fingerY: number = 0;
  /** 拖选进行中 */
  private dragging: boolean = false;
  private autoScrollTimer: number = -1;
  /** 长按检测：按住不动 380ms 进入拖选；手指移动超过阈值即取消（把滚动让给列表） */
  private pressTimer: number = -1;
  private pressStartX: number = 0;
  private pressStartY: number = 0;
  /** 本次触摸已处理过长按（计时器与 LongPressGesture 双通道去重） */
  private pressHandled: boolean = false;
  /** 拖选期间锁定列表手势滚动（只允许程序化的边缘自动滚动，避免双重位移） */
  @Local scrollLocked: boolean = false;

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
    this.cancelPressTimer();
    this.stopAutoScroll();
    this.dragging = false;
    this.ctrl.endSelectionDrag();
    this.ctrl.programmaticScroll = false;
    this.ctrl.onRowsChanged = undefined;
    this.ctrl.onTimelineReset = undefined;
    this.ctrl.onRestoreAnchor = undefined;
  }

  private nextScrollEpoch(): number {
    this.scrollEpoch++;
    return this.scrollEpoch;
  }

  /** 拖选命中测试所需的列表视口几何（列表窗口位置 + 当前滚动偏移 + 顶部哨兵高度） */
  private viewport(): TimelineViewport {
    const vp = new TimelineViewport();
    vp.left = this.listLeft;
    vp.top = this.listTop;
    vp.scrollY = this.scroller.currentOffset().yOffset;
    // 顶部 loading 哨兵与 ListContent 中插入条件保持一致（高度 56 + 1vp 行间距）
    vp.topSentinel = (this.ctrl.isLoadingUp && !this.ctrl.programmaticScroll) ? 57 : 0;
    return vp;
  }

  /** 按下：启动长按检测（手指移动超过阈值或双指落下时取消，把滚动交还给列表） */
  private handleTouchDown(): void {
    this.cancelPressTimer();
    this.pressStartX = this.fingerX;
    this.pressStartY = this.fingerY;
    this.pressTimer = setTimeout((): void => {
      this.pressTimer = -1;
      this.handleLongPress();
    }, 380);
  }

  private cancelPressTimer(): void {
    if (this.pressTimer >= 0) {
      clearTimeout(this.pressTimer);
      this.pressTimer = -1;
    }
  }

  /** 长按：多选模式开始拖选；非多选模式先进入多选选中该张，同一根手指继续框选 */
  private handleLongPress(): void {
    if (this.pressHandled) {
      return;
    }
    this.pressHandled = true;
    const vp = this.viewport();
    if (!this.ctrl.isMultiSelectMode) {
      const id = this.ctrl.photoIdAtWindowPoint(this.fingerX, this.fingerY, vp);
      if (id < 0) {
        return;
      }
      this.ctrl.toggleSelection(id);
      this.dragging = this.ctrl.beginSelectionDrag(this.fingerX, this.fingerY, vp, true);
    } else {
      this.dragging = this.ctrl.beginSelectionDrag(this.fingerX, this.fingerY, vp, false);
    }
    if (this.dragging) {
      // 锁定列表手势滚动：拖选期间内容只由边缘自动滚动移动，避免“框选 + 惯性滚动”双重位移
      this.scrollLocked = true;
      this.ensureAutoScroll();
    }
  }

  private handleDragMove(): void {
    if (!this.dragging) {
      return;
    }
    this.ctrl.updateSelectionDrag(this.fingerX, this.fingerY, this.viewport());
    this.ensureAutoScroll();
  }

  private endDragSelect(): void {
    this.stopAutoScroll();
    if (!this.dragging) {
      return;
    }
    this.dragging = false;
    this.scrollLocked = false;
    this.ctrl.endSelectionDrag();
  }

  /** 手指进入列表上下边缘区域时，启动连续滚动，让框选能自然延伸到屏幕外 */
  private ensureAutoScroll(): void {
    if (!this.dragging) {
      this.stopAutoScroll();
      return;
    }
    if (this.autoScrollTimer >= 0 || this.autoScrollStep() === 0) {
      return;
    }
    this.autoScrollTimer = setTimeout((): void => this.autoScrollTick(), 16);
  }

  /** 单次自动滚动距离（vp，正数向下滚）：越靠近边缘滚得越快 */
  private autoScrollStep(): number {
    if (!this.dragging || this.listHeight <= 0) {
      return 0;
    }
    const zone = 72;
    const topEdge = this.listTop + zone;
    const bottomEdge = this.listTop + this.listHeight - zone;
    if (this.fingerY < topEdge) {
      const ratio = Math.min(1, (topEdge - this.fingerY) / zone);
      return -Math.max(3, Math.round(16 * ratio));
    }
    if (this.fingerY > bottomEdge) {
      const ratio = Math.min(1, (this.fingerY - bottomEdge) / zone);
      return Math.max(3, Math.round(16 * ratio));
    }
    return 0;
  }

  private autoScrollTick(): void {
    this.autoScrollTimer = -1;
    if (!this.dragging) {
      return;
    }
    const step = this.autoScrollStep();
    if (step === 0) {
      return;
    }
    this.scroller.scrollBy(0, step);
    // 滚动后手指下方的照片已变化，重新按“起点→当前点”矩形更新选中
    this.ctrl.updateSelectionDrag(this.fingerX, this.fingerY, this.viewport());
    this.autoScrollTimer = setTimeout((): void => this.autoScrollTick(), 16);
  }

  private stopAutoScroll(): void {
    if (this.autoScrollTimer >= 0) {
      clearTimeout(this.autoScrollTimer);
      this.autoScrollTimer = -1;
    }
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
    .onAreaChange((_o: Area, n: Area): void => {
      this.listLeft = Number(n.globalPosition.x);
      this.listTop = Number(n.globalPosition.y);
      this.listHeight = Number(n.height);
    })
    .onTouch((e: TouchEvent): void => {
      // 抬手/取消必须先处理：不依赖 touches[0] 是否仍然存在，避免拖选状态与滚动锁卡死
      if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.cancelPressTimer();
        this.endDragSelect();
        return;
      }
      const t = e.touches[0];
      if (t === undefined) {
        return;
      }
      this.fingerX = t.windowX;
      this.fingerY = t.windowY;
      if (e.type === TouchType.Down) {
        this.pressHandled = false;
        this.pressStartX = this.fingerX;
        this.pressStartY = this.fingerY;
        // 双指（缩放手势）不进入长按拖选
        if (e.touches.length > 1) {
          this.cancelPressTimer();
          return;
        }
        this.handleTouchDown();
        return;
      }
      if (e.type === TouchType.Move) {
        if (this.dragging) {
          this.handleDragMove();
          return;
        }
        // 移动超过 10vp 即判定为滑动，取消长按：多选模式下列表滑动与平时完全一致
        const dx = this.fingerX - this.pressStartX;
        const dy = this.fingerY - this.pressStartY;
        if (dx * dx + dy * dy >= 100) {
          this.cancelPressTimer();
        }
        return;
      }
      if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.cancelPressTimer();
        this.endDragSelect();
      }
    })
    .enableScrollInteraction(!this.scrollLocked)
    .gesture(
      // 长按手势只负责“消费本次点击并赢得手势竞争”：
      // 手指按住不动 380ms 即识别，使内置滚动与照片点击都失败，避免松手时误触打开大图。
      // 拖选的移动跟踪与自动滚动在 onTouch 中处理（不依赖手势，滚动时单元格被回收也不会中断）。
      LongPressGesture({ fingers: 1, duration: 380 })
        .onAction((e: GestureEvent): void => {
          if (e.fingerList.length !== 1) {
            return;
          }
          this.cancelPressTimer();
          this.handleLongPress();
        }))
    .parallelGesture(PinchGesture({ fingers: 2 })
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
