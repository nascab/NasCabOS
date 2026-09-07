import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { TimelineController } from '../../controllers/TimelineController';

/**
 * 照片主页浮动模式条（对齐 Flutter _buildFloatingModeBar）：
 * 全部/按年/今日/收藏 四个芯片，45 高半透明圆角条，距底 10。
 * 独立组件：选中状态在 build 内直接读取 ctrl 状态（@Trace），保证点击后 UI 正确刷新。
 */
@ComponentV2
export struct PhotoModeBar {
  @Param ctrl: TimelineController = new TimelineController();
  /** 是否处于"按年"视图（父组件 @Local 同步） */
  @Param yearMode: boolean = false;
  /** 切换时间线模式（父组件处理年份筛选清理与刷新） */
  @Param onModeSelected: (listType: string, loadTheDay: boolean) => void =
    (_listType: string, _loadTheDay: boolean): void => {
    };
  /** 进入"按年"视图 */
  @Param onYearSelected: () => void = (): void => {
  };

  /** 芯片选中态（对齐 Flutter：isYear 优先，favorite/today 次之，其余为 all） */
  private isChipSelected(mode: number): boolean {
    const isYear = this.yearMode;
    const isFavorite = !isYear && this.ctrl.listType === 'favorite';
    const isToday = !isYear && this.ctrl.loadTheDay;
    if (mode === 1) {
      return isYear;
    }
    if (mode === 2) {
      return isToday;
    }
    if (mode === 3) {
      return isFavorite;
    }
    return !isYear && !isToday && !isFavorite;
  }

  build() {
    Column() {
      Row() {
        this.ModeChip(L10n.t('all', '全部'), 0)
        this.ModeChip(L10n.t('photo_timeline_view_year', '按年'), 1)
        this.ModeChip(L10n.t('photo_timeline_view_today', '今日'), 2)
        this.ModeChip(L10n.t('favorites', '收藏'), 3)
      }
      .width('100%')
      .height(45)
      .padding({ left: 6, right: 6 })
      .borderRadius(22.5)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
      // 触摸穿透：条内非芯片区域可滑动下方列表（对齐 Flutter deferToChild 行为）
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 10 })
    .hitTestBehavior(HitTestMode.None)
  }

  /** 模式芯片（对齐 Flutter _modeChip）：32 高，选中主色背景白字，未选透明背景 */
  @Builder
  ModeChip(label: string, mode: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isChipSelected(mode) ? '#FFFFFF' : AppTheme.current().onSurface)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(16)
      .backgroundColor(this.isChipSelected(mode) ? AppTheme.current().primary : '#00000000')
      .onClick(() => {
        if (mode === 1) {
          this.onYearSelected();
        } else if (mode === 2) {
          this.onModeSelected('timeline', true);
        } else if (mode === 3) {
          this.onModeSelected('favorite', false);
        } else {
          this.onModeSelected('timeline', false);
        }
      })
      .layoutWeight(1)
  }
}
