import { HomeViewModel } from '../HomeViewModel';
import { AppIconMap } from '../AppIconMap';

/** 图标单元在窗口中的像素矩形（vp），用于拖拽触点命中 */
interface ItemRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * 应用图标网格：对应 Flutter AppAppsGrid（LongPressDraggable + DragTarget 排序 + 点击打开）。
 *
 * 不使用 Grid editMode：官方 FAQ（faqs-arkui-1506）已确认其长按拖拽与子节点 onClick 冲突，
 * 且只提供“可拖拽/可点击二选一”的 HitTestMode 方案，无法满足桌面图标“点按打开、长按拖动”
 * 的共存需求。这里改为 onTouch 手动长按识别（500ms + touchSlop）+ 自绘浮动图标 +
 * 触点命中实时重排，松手一次性 vm.reorderApp 落盘，行为与 Flutter 一致。
 */
@ComponentV2
export struct HomeAppsGrid {
  @Require @Param vm: HomeViewModel;
  @Param onTapApp: (app: string) => void = (_app: string) => {
  };
  @Local crossCount: number = 4;
  /** 拖拽进行中的视觉顺序；null 时直接展示 vm 数据 */
  @Local dragOrder: string[] | null = null;
  /** 当前被拖拽的应用 id（空串=未拖拽），同时驱动原位半透明与浮动图标 */
  @Local dragApp: string = '';
  @Local dragX: number = 0;
  @Local dragY: number = 0;

  private readonly minItemWidth: number = 75;
  private readonly spacing: number = 10;
  /** Flutter kLongPressTimeout */
  private readonly longPressMs: number = 500;
  /** 系统统一拖拽的移动门槛（vp），超过即视为滑动/滚动，不进入拖拽 */
  private readonly touchSlopVp: number = 10;

  private itemRects: Map<string, ItemRect> = new Map();
  private gridX: number = 0;
  private gridY: number = 0;
  private longPressTimer: number = -1;
  private downWx: number = 0;
  private downWy: number = 0;
  private startIndex: number = -1;
  /** 拖拽抬手后的当次点击抑制（避免长按松手误打开应用） */
  private suppressTap: boolean = false;

  private activeApps(): string[] {
    return this.dragOrder !== null ? this.dragOrder : this.vm.filteredApps();
  }

  private updateCrossCount(width: number): void {
    const count = Math.floor((width + this.spacing) / (this.minItemWidth + this.spacing));
    const next = count > 0 ? count : 1;
    if (next !== this.crossCount) {
      this.crossCount = next;
    }
  }

  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.crossCount; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private clearTimer(): void {
    if (this.longPressTimer >= 0) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
    }
  }

  /** 长按达阈值：进入拖拽态，快照当前顺序 */
  private beginDrag(app: string, index: number, wx: number, wy: number): void {
    this.dragOrder = this.vm.filteredApps().slice();
    this.startIndex = index;
    this.dragApp = app;
    this.dragX = wx - this.gridX;
    this.dragY = wy - this.gridY;
  }

  /** 拖拽中：触点落在哪个图标单元内 */
  private hitIndex(wx: number, wy: number): number {
    const apps = this.activeApps();
    for (let i = 0; i < apps.length; i++) {
      const r = this.itemRects.get(apps[i]);
      if (r !== undefined && wx >= r.x && wx <= r.x + r.w && wy >= r.y && wy <= r.y + r.h) {
        return i;
      }
    }
    return -1;
  }

  /** 拖拽中：仅改本地视觉数组（不触网），其他图标实时让位 */
  private moveVisual(from: number, to: number): void {
    if (this.dragOrder === null || from === to) {
      return;
    }
    const next = this.dragOrder.slice();
    const item = next.splice(from, 1)[0];
    if (item === undefined) {
      return;
    }
    next.splice(to, 0, item);
    this.dragOrder = next;
  }

  /** 松手：一次性把最终位置同步给 vm（落本地+上报），退出拖拽态 */
  private finishDrag(): void {
    const order = this.dragOrder;
    const app = this.dragApp;
    const start = this.startIndex;
    const finalIndex = order !== null && app.length > 0 ? order.indexOf(app) : -1;
    this.dragOrder = null;
    this.dragApp = '';
    this.startIndex = -1;
    if (start >= 0 && finalIndex >= 0 && finalIndex !== start) {
      this.vm.reorderApp(start, finalIndex);
    }
    this.suppressTap = true;
    setTimeout((): void => {
      this.suppressTap = false;
    }, 300);
  }

  private cancelDrag(): void {
    this.clearTimer();
    this.dragOrder = null;
    this.dragApp = '';
    this.startIndex = -1;
  }

  private onTouchItem(app: string, index: number, e: TouchEvent): void {
    if (e.type === TouchType.Down) {
      if (this.dragApp.length > 0) {
        return;
      }
      const t = e.touches[0];
      if (t === undefined) {
        return;
      }
      this.downWx = t.windowX;
      this.downWy = t.windowY;
      this.startIndex = index;
      this.suppressTap = false;
      this.clearTimer();
      this.longPressTimer = setTimeout((): void => {
        this.longPressTimer = -1;
        this.beginDrag(app, index, this.downWx, this.downWy);
      }, this.longPressMs);
    } else if (e.type === TouchType.Move) {
      const t = e.touches[0];
      if (t === undefined) {
        return;
      }
      if (this.dragApp.length > 0) {
        this.dragX = t.windowX - this.gridX;
        this.dragY = t.windowY - this.gridY;
        const to = this.hitIndex(t.windowX, t.windowY);
        if (to >= 0) {
          const from = this.activeApps().indexOf(this.dragApp);
          if (from >= 0) {
            this.moveVisual(from, to);
          }
        }
      } else if (this.longPressTimer >= 0) {
        // 长按达成前移动超过 slop：让出手势，交给 Grid 滚动/页面滑动
        if (Math.abs(t.windowX - this.downWx) > this.touchSlopVp
          || Math.abs(t.windowY - this.downWy) > this.touchSlopVp) {
          this.clearTimer();
        }
      }
    } else if (e.type === TouchType.Up) {
      this.clearTimer();
      if (this.dragApp.length > 0) {
        this.finishDrag();
      }
    } else if (e.type === TouchType.Cancel) {
      this.cancelDrag();
    }
  }

  /** 图标内容（普通单元与拖拽浮体共用，对齐 Flutter _appIconContent） */
  @Builder
  AppIconContent(app: string) {
    Column() {
      Image(AppIconMap.getIcon(app))
        .width(60)
        .height(60)
        .interpolation(ImageInterpolation.High)
        .draggable(false)
      Text(this.vm.getAppDisplayName(app))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        // Text 为默认可拖拽组件，关闭系统文本拖拽以免抢占触摸
        .draggable(false)
        // 轻微文字阴影（仅作用于文字笔画，提升壁纸上的可读性）
        .textShadow({ radius: 2, color: 'rgba(0,0,0,0.35)', offsetX: 0, offsetY: 1 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
    }
    .width(76)
    .justifyContent(FlexAlign.Center)
  }

  /** 拖拽浮体：放大 1.1 + 阴影（对齐 Flutter feedback scale:1.1） */
  @Builder
  DragGhost() {
    Column() {
      this.AppIconContent(this.dragApp)
    }
    .position({ x: this.dragX, y: this.dragY })
    .translate({ x: '-50%', y: '-50%' })
    .scale({ x: 1.1, y: 1.1 })
    .shadow({ radius: 16, color: 'rgba(0,0,0,0.45)', offsetX: 0, offsetY: 6 })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      Grid() {
        ForEach(this.activeApps(), (app: string, index: number) => {
          GridItem() {
            Column() {
              this.AppIconContent(app)
            }
            .width('100%')
            .aspectRatio(0.86)
            .justifyContent(FlexAlign.Center)
            // 对齐 Flutter childWhenDragging：被拖项原位半透明
            .opacity(this.dragApp === app ? 0.3 : 1)
            .animation({ duration: 180, curve: Curve.EaseOut })
            .onClick((): void => {
              if (!this.suppressTap && this.dragApp.length === 0) {
                this.onTapApp(app);
              }
            })
            .onTouch((e: TouchEvent): void => {
              this.onTouchItem(app, index, e);
            })
            .onAreaChange((_old: Area, n: Area): void => {
              this.itemRects.set(app, {
                x: Number(n.globalPosition.x),
                y: Number(n.globalPosition.y),
                w: Number(n.width),
                h: Number(n.height)
              });
            })
          }
        }, (app: string): string => app)
      }
      .columnsTemplate(this.columnsTemplate())
      .columnsGap(this.spacing)
      .rowsGap(this.spacing)
      .width('100%')
      .height('100%')
      .padding({ left: 10, right: 10, bottom: 10 })
      .scrollBar(BarState.Off)
      // 拖拽中禁止网格滚动，避免垂直滑动与重排相互干扰
      .enableScrollInteraction(this.dragApp.length === 0)
      // 依赖 localeVersion：切换语言后触发应用名刷新
      .opacity(this.vm.localeVersion >= 0 ? 1 : 1)
      .onAreaChange((_old: Area, n: Area): void => {
        this.gridX = Number(n.globalPosition.x);
        this.gridY = Number(n.globalPosition.y);
        this.updateCrossCount(Number(n.width));
      })

      if (this.dragApp.length > 0) {
        this.DragGhost()
      }
    }
    .width('100%')
    .layoutWeight(1)
    .clip(true)
  }
}
