import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { AppImage } from '../../../common/components/AppImage';
import { TimelineController } from '../../controllers/TimelineController';
import { TimelineYearItem } from '../../models/PhotoModels';
import { PhotoTimelineApiService } from '../../service/PhotoTimelineApiService';

/** 与照片主页悬浮模式栏（bottom 10 + height 45）对齐的网格底部留白，避免挡住年份卡片最后一行 */
const YEAR_GRID_BOTTOM_PAD: number = 10 + 45 + 12;

/**
 * 照片年视图（对齐 Flutter AppPhotoTimelineYearPage）：
 * 拉取年份统计，双列网格展示封面卡片（年份 + 数量 + 底部黑色渐变遮罩），
 * 点击卡片将时间线切换到该年（ctrl.setYearFilter）并通过 onYearPicked 通知父组件退出年视图。
 */
@ComponentV2
export struct PhotoTimelineYearView {
  @Param ctrl: TimelineController = new TimelineController();
  /** 点击年份卡片后的回调（父组件用于退出年视图） */
  @Param onYearPicked: (year: number) => void = (_year: number): void => {
  };
  @Local isLoading: boolean = true;
  @Local items: TimelineYearItem[] = [];
  @Local isRefreshing: boolean = false;
  private apiService: PhotoTimelineApiService = new PhotoTimelineApiService();

  aboutToAppear(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    this.isLoading = true;
    try {
      const res = await this.apiService.getTimelineYearList();
      if (res.success && res.data !== undefined) {
        this.items = res.data.items;
      } else {
        this.items = [];
      }
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Refresh({ refreshing: this.isRefreshing }) {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .padding({ top: 120, bottom: YEAR_GRID_BOTTOM_PAD })
      } else if (this.items.length === 0) {
        Column() {
          Text(L10n.t('no_photo', '暂无照片'))
            .fontSize(14)
            .fontColor(AppTheme.current().hint)
        }
        .width('100%')
        .padding({ top: 120, bottom: YEAR_GRID_BOTTOM_PAD })
      } else {
        Grid() {
          ForEach(this.items, (item: TimelineYearItem): void => {
            GridItem() {
              YearCard({
                item: item,
                onTap: (): void => {
                  this.ctrl.setYearFilter(item.year);
                  this.onYearPicked(item.year);
                }
              })
            }
          }, (item: TimelineYearItem): string => `${item.year}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: YEAR_GRID_BOTTOM_PAD })
        .scrollBar(BarState.Off)
      }
    }
    .onRefreshing(() => {
      this.isRefreshing = true;
      this.load().finally(() => {
        this.isRefreshing = false;
      });
    })
    .width('100%')
    .height('100%')
  }
}

/** 年份封面卡片（对齐 Flutter _YearCard）：封面图 + 底部渐变 + 年份/数量文案 */
@ComponentV2
struct YearCard {
  @Param item: TimelineYearItem = new TimelineYearItem();
  @Param onTap: () => void = (): void => {
  };
  @Local tinyUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用变化时重新解析封面地址 */
  @Monitor('item', 'item.cover.fullpath')
  onItemChange(): void {
    this.tinyUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const path = this.item.cover.fullpath;
    if (path.length === 0) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(path);
      if (this.item.cover.fullpath === path) {
        this.tinyUrl = url;
      }
    } catch (_e) {
      this.tinyUrl = '';
    }
  }

  private yearText(): string {
    return L10n.t('photo_timeline_year_title', '@year年', L10n.paramsOf('year', `${this.item.year}`));
  }

  private countText(): string {
    return L10n.t('folder_status_total', '共@total项', L10n.paramsOf('total', `${this.item.count}`));
  }

  build() {
    Stack() {
      if (this.tinyUrl.length > 0) {
        AppImage({ url: this.tinyUrl })
      } else {
        Image($rawfile('icons/no_data.png'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }
      // 底部黑色渐变遮罩（对齐 Flutter LinearGradient bottom→top）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [['#00000000', 0.0], ['#AA000000', 1.0]]
        })
      Column() {
        Blank()
        Text(this.yearText())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width('100%')
          .maxLines(1)
        Text(this.countText())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#EBFFFFFF')
          .width('100%')
          .maxLines(1)
          .margin({ top: 6 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.End)
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .aspectRatio(1.2)
    .borderRadius(16)
    .clip(true)
    .onClick(() => {
      this.onTap();
    })
  }
}
