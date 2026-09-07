import { AppTheme } from '../../core/theme/AppTheme';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoUtils } from '../utils/VideoItemUtils';

/**
 * 视频封面图（对齐 Flutter VideoItemCoverImage / CustomExtendedImage）：
 * 异步解析海报或背景 URL，底部渐变遮罩 + 评分/类型角标（对齐 _BadgeRow/_Pill）。
 */
@ComponentV2
export struct VideoCoverImage {
  @Param item: VideoHomeItemBean = new VideoHomeItemBean();
  /** poster：2:3 海报；fanart：背景大图 */
  @Param mode: string = 'poster';
  @Param imageRadius: number = 12;
  @Param rating: number = 0;
  @Param typeText: string = '';
  @Param showBadges: boolean = true;
  @Param badgeShortLabel: boolean = false;
  @Local imageUrl: string = '';

  aboutToAppear(): void {
    const task = this.mode === 'fanart'
      ? VideoUtils.getFanartUrl(this.item)
      : VideoUtils.getPosterUrl(this.item, 500);
    task.then((url: string) => {
      this.imageUrl = url;
    });
  }

  private ratingText(): string {
    const rating = Number(this.rating);
    if (Number.isInteger(rating)) {
      return `${rating}`;
    }
    return rating.toFixed(1);
  }

  @Builder
  Pill(text: string, fg: string) {
    Text(text)
      .fontSize(11)
      .fontWeight(FontWeight.Bold)
      .fontColor(fg)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(12)
      .backgroundColor('#8C000000')
      .border({ width: 1, color: AppTheme.withAlpha(fg, 0.32) })
  }

  build() {
    Stack() {
      if (this.imageUrl.length > 0) {
        Image(this.imageUrl)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
      }
      // 底部渐变遮罩（对齐 LinearGradient bottom→top：黑色在底部向上淡出）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 0,
          colors: [['#C7000000', 0], ['#00000000', 0.55]]
        })
        .hitTestBehavior(HitTestMode.None)
      if (this.showBadges) {
        Row() {
          if (this.rating > 0) {
            this.Pill(this.ratingText(), '#E5B527')
          }
          Blank()
          if (this.typeText.trim().length > 0) {
            this.Pill(this.typeText.trim(), '#FFFFFF')
          }
        }
        .padding({ left: 8, right: 8, bottom: 8 })
        .width('100%')
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.imageRadius)
    .clip(true)
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.08) })
  }
}
