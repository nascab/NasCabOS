import { TimelineController } from '../../controllers/TimelineController';
import { TimelineDateItem } from '../../models/PhotoModels';
import { AppTheme } from '../../../core/theme/AppTheme';

class SidebarBucket {
  representativeDate: string = '';
  year: number = 0;
  count: number = 0;
}

/** 侧栏布局计算结果（日期抽稀 + 高度分配） */
class SidebarLayout {
  buckets: SidebarBucket[] = [];
  heights: number[] = [];

  totalHeight(): number {
    let sum = 0;
    for (const h of this.heights) {
      sum += h;
    }
    return sum;
  }
}

/**
 * 时间线右侧快速定位手柄（对齐 Flutter PhotoTimelineSidebar compact 模式）：
 * 滚动时浮现，点击/拖动显示日期并快速跳转。
 */
@ComponentV2
export struct PhotoTimelineSidebar {
  @Param ctrl: TimelineController = new TimelineController();
  @Local layout: SidebarLayout = new SidebarLayout();
  @Local viewportH: number = 0;
  /** 拖动中光标位置与日期（空串表示未激活） */
  @Local cursorTop: number = -1;
  @Local cursorRawDate: string = '';
  private panStartTop: number = 0;

  aboutToAppear(): void {
    this.recompute();
  }

  @Monitor('ctrl.dateList')
  onDateListChange(): void {
    this.recompute();
  }

  private recompute(): void {
    const next = new SidebarLayout();
    const height = this.viewportH;
    // 1. 构建初始 buckets（按日期）
    const buckets: SidebarBucket[] = [];
    for (const d of this.ctrl.dateList) {
      const b = SidebarLayoutHelper.bucketFromDate(d);
      if (b !== undefined) {
        buckets.push(b);
      }
    }
    if (buckets.length === 0 || height <= 0) {
      this.layout = next;
      return;
    }
    // 2. 数量过多时按 count 阈值抽稀
    let working = buckets;
    if (working.length > 1000) {
      const filterRatio = working.length > 2000 ? 0.5 : (working.length > 1500 ? 0.3 : 0.2);
      const counts = working.map((b: SidebarBucket): number => b.count).sort((a: number, b: number): number => a - b);
      const numToFilter = Math.floor(working.length * filterRatio);
      if (numToFilter > 0 && numToFilter < counts.length) {
        const threshold = counts[numToFilter - 1];
        working = working.filter((b: SidebarBucket): boolean => b.count >= threshold);
      }
    }
    // 3. 按权重分配高度
    const minItemHeight = 8.0;
    const maxItems = Math.max(1, Math.floor(height / minItemHeight));
    if (working.length > maxItems) {
      working = SidebarLayoutHelper.mergeBucketsKeepingEnds(working, maxItems, this.ctrl.sortOrder === 'desc');
    }
    const weights = working.map((b: SidebarBucket): number => Math.sqrt(Math.max(0, b.count)) + 1);
    let totalWeight = 0;
    for (const w of weights) {
      totalWeight += w;
    }
    let baseH = minItemHeight;
    if (working.length === 1 && height < minItemHeight) {
      baseH = height;
    }
    const variableH = Math.max(0, height - baseH * working.length);
    const heights: number[] = [];
    for (const w of weights) {
      heights.push(baseH + (totalWeight === 0 ? 0 : variableH * w / totalWeight));
    }
    next.buckets = working;
    next.heights = heights;
    this.layout = next;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.ctrl.isTimelineVisible && this.layout.buckets.length > 0) {
        this.Handle()
      }
    }
    .width('100%')
    .height('100%')
    // 触摸穿透：空白区域不拦截，保证列表任意位置可滑动；手柄自身仍响应点击/拖动
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_o: Area, n: Area): void => {
      const h = Number(n.height);
      if (h > 0 && Math.abs(h - this.viewportH) > 0.5) {
        this.viewportH = h;
        this.recompute();
      }
    })
  }

  @Builder
  Handle() {
    Row({ space: 6 }) {
      if (this.isActive()) {
        Text(this.cursorDate())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.75)])
      } else {
        Column({ space: 2 }) {
          SymbolGlyph($r('sys.symbol.chevron_up'))
            .fontSize(14)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.7)])
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(14)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.7)])
        }
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width(this.isActive() ? 142 : 35)
    .height(40)
    .margin({ top: this.handleTop() })
    .padding({ left: this.isActive() ? 12 : 0, right: this.isActive() ? 12 : 0 })
    .borderRadius({ topLeft: 20, bottomLeft: 20 })
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, this.isDragging() ? 0.95 : 0.86))
    .shadow({ radius: 12, offsetX: 0, offsetY: 4, color: '#1F000000' })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(() => {
      this.showCurrentDate();
    })
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 3 })
      .onActionStart((_e: GestureEvent) => {
        this.panStartTop = this.effectiveTop() + 20;
        this.cursorTop = this.effectiveTop();
        this.updateCursorByPan(0);
      })
      .onActionUpdate((e: GestureEvent) => {
        this.updateCursorByPan(e.offsetY);
      })
      .onActionEnd(() => {
        const date = this.cursorRawDate.trim();
        if (date.length > 0) {
          void this.ctrl.jumpToDate(date);
        }
        this.clearCursor();
      })
      .onActionCancel(() => {
        this.clearCursor();
      }))
  }

  private isDragging(): boolean {
    return this.cursorTop >= 0;
  }

  private isActive(): boolean {
    return this.cursorRawDate.trim().length > 0;
  }

  private cursorDate(): string {
    const date = this.cursorRawDate;
    if (date.length >= 10) {
      return date.substring(0, 10).split('-').join('/');
    }
    return date;
  }

  private updateCursorByPan(offsetY: number): void {
    this.setCursorTop(this.panStartTop + offsetY);
  }

  private setCursorTop(top: number): void {
    const clamped = Math.min(Math.max(top, 0), this.viewportH);
    this.cursorTop = clamped;
    const date = SidebarLayoutHelper.dateForDy(this.layout, clamped);
    if (date !== undefined) {
      this.cursorRawDate = date;
      this.ctrl.keepTimelineVisible();
    }
  }

  private clearCursor(): void {
    this.cursorTop = -1;
    this.cursorRawDate = '';
  }

  /** 当前顶部日期对应的空闲位置 */
  private idleTopForCurrentDate(): number {
    const date = this.ctrl.topDate.trim();
    const layout = this.layout;
    if (date.length === 0 || layout.buckets.length === 0) {
      return this.viewportH / 2;
    }
    let index = -1;
    for (let i = 0; i < layout.buckets.length; i++) {
      if (layout.buckets[i].representativeDate === date) {
        index = i;
        break;
      }
    }
    if (index === -1 && date.length >= 7) {
      const prefix = date.substring(0, 7);
      for (let i = 0; i < layout.buckets.length; i++) {
        if (layout.buckets[i].representativeDate.startsWith(prefix)) {
          index = i;
          break;
        }
      }
    }
    if (index < 0 || index >= layout.heights.length) {
      return this.viewportH / 2;
    }
    let offset = 0;
    for (let i = 0; i < index; i++) {
      offset += layout.heights[i];
    }
    return Math.min(Math.max(offset + layout.heights[index] / 2, 0), this.viewportH);
  }

  private effectiveTop(): number {
    if (this.cursorTop >= 0) {
      return Math.min(Math.max(this.cursorTop, 0), this.viewportH);
    }
    return this.idleTopForCurrentDate();
  }

  private handleTop(): number {
    const total = this.viewportH;
    let top = this.effectiveTop() - 20;
    if (top < 0) {
      top = 0;
    }
    if (total > 40 && top > total - 40) {
      top = total - 40;
    }
    return top;
  }

  private showCurrentDate(): void {
    const date = this.ctrl.topDate.trim();
    if (date.length === 0) {
      return;
    }
    this.cursorTop = this.idleTopForCurrentDate();
    this.cursorRawDate = date;
    this.ctrl.keepTimelineVisible();
  }
}

class SidebarLayoutHelper {
  static bucketFromDate(d: TimelineDateItem): SidebarBucket | undefined {
    const m = d.originalDate.match(/^(\d+)/);
    if (m === null) {
      return undefined;
    }
    const b = new SidebarBucket();
    b.representativeDate = d.originalDate;
    b.year = parseInt(m[1], 10);
    b.count = d.count;
    return b;
  }

  /** 合并 buckets 至目标数量，保留首尾（对齐 _mergeBucketsKeepingEnds） */
  static mergeBucketsKeepingEnds(buckets: SidebarBucket[], targetCount: number, desc: boolean): SidebarBucket[] {
    if (targetCount <= 0) {
      return [];
    }
    if (buckets.length <= targetCount) {
      return buckets;
    }
    const len = buckets.length;
    if (targetCount === 1) {
      let countSum = 0;
      for (const b of buckets) {
        countSum += b.count;
      }
      const repDate = desc ? buckets[0].representativeDate : buckets[len - 1].representativeDate;
      const merged = new SidebarBucket();
      merged.representativeDate = repDate;
      merged.year = SidebarLayoutHelper.extractYear(repDate, buckets[0].year);
      merged.count = countSum;
      return [merged];
    }
    if (targetCount === 2) {
      let firstCount = 0;
      for (let i = 0; i < len - 1; i++) {
        firstCount += buckets[i].count;
      }
      const firstDate = buckets[0].representativeDate;
      const first = new SidebarBucket();
      first.representativeDate = firstDate;
      first.year = SidebarLayoutHelper.extractYear(firstDate, buckets[0].year);
      first.count = firstCount;
      return [first, buckets[len - 1]];
    }
    const merged: SidebarBucket[] = [buckets[0], buckets[len - 1]];
    // 插入中间分桶（顺序：首桶之后依次插入，保持时间顺序）
    const middleCount = targetCount - 2;
    const middleLen = len - 2;
    const middles: SidebarBucket[] = [];
    if (middleLen > 0) {
      for (let i = 0; i < middleCount; i++) {
        let start = 1 + Math.floor(i * middleLen / middleCount);
        let end = 1 + Math.floor((i + 1) * middleLen / middleCount) - 1;
        if (start < 1) {
          start = 1;
        }
        if (end < start) {
          end = start;
        }
        if (end > len - 2) {
          end = len - 2;
        }
        let countSum = 0;
        for (let j = start; j <= end; j++) {
          countSum += buckets[j].count;
        }
        const repDate = buckets[start].representativeDate;
        const b = new SidebarBucket();
        b.representativeDate = repDate;
        b.year = SidebarLayoutHelper.extractYear(repDate, buckets[start].year);
        b.count = countSum;
        middles.push(b);
      }
    }
    return [buckets[0], ...middles, buckets[len - 1]];
  }

  static extractYear(dateStr: string, fallback: number): number {
    const m = dateStr.match(/^(\d+)/);
    if (m === null) {
      return fallback;
    }
    const y = parseInt(m[1], 10);
    return isNaN(y) ? fallback : y;
  }

  /** 由 dy 定位日期（前缀和 + 线性/二分查找） */
  static dateForDy(layout: SidebarLayout, dy: number): string | undefined {
    if (layout.buckets.length === 0 || layout.heights.length === 0) {
      return undefined;
    }
    const clamped = dy < 0 ? 0 : dy;
    const n = layout.heights.length;
    let sum = 0;
    let low = 0;
    let high = n - 1;
    const prefix: number[] = new Array<number>(n);
    for (let i = 0; i < n; i++) {
      sum += layout.heights[i];
      prefix[i] = sum;
    }
    const maxY = prefix[n - 1];
    const target = clamped > maxY ? maxY : clamped;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (target < prefix[mid]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    const idx = Math.min(Math.max(low, 0), layout.buckets.length - 1);
    return layout.buckets[idx].representativeDate;
  }
}
