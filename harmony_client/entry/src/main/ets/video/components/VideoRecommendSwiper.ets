import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoDetailPageParam } from '../router/VideoRoutes';
import { buildVideoHomeMeta, videoMediaTypeText, VideoUtils } from '../utils/VideoItemUtils';

/**
 * 首页推荐轮播（对齐 Flutter _AppVideoRecommendSwiper）：
 * 全宽背景大图 + 底部信息（推荐标签/评分/标题/年份·元信息/类型胶囊）+
 * 顶部暗色渐变（承载返回/设置按钮）+ 底部指示条；5 秒自动轮播。
 */
@ComponentV2
export struct VideoRecommendSwiper {
  @Param items: VideoHomeItemBean[] = [];
  /** 背景图缓存（index → url） */
  @Local imageUrls: string[] = [];
  @Local index: number = 0;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.loadImages();
    this.startTimer();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private loadImages(): void {
    const urls: string[] = new Array(this.items.length).fill('');
    this.imageUrls = urls;
    for (let i = 0; i < this.items.length; i++) {
      const capture = i;
      VideoUtils.getFanartUrl(this.items[capture]).then((url: string) => {
        if (capture < this.imageUrls.length) {
          const next = this.imageUrls.slice();
          next[capture] = url;
          this.imageUrls = next;
        }
      });
    }
  }

  private startTimer(): void {
    this.stopTimer();
    if (this.items.length <= 1) {
      return;
    }
    this.timerId = setInterval((): void => {
      const next = (this.index + 1) % this.items.length;
      this.index = next;
    }, 5000);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Swiper() {
        ForEach(this.items, (item: VideoHomeItemBean, i: number) => {
          this.SwiperItem(item, i)
        }, (item: VideoHomeItemBean) => `${item.id}`)
      }
      .index(this.index)
      .autoPlay(false)
      .loop(true)
      .duration(420)
      .curve(Curve.EaseOut)
      .indicator(false)
      .width('100%')
      .height('100%')
      .onChange((i: number) => {
        this.index = i;
        this.startTimer();
      })

      // 顶部暗色渐变（承载返回/设置浮动按钮的可读性）
      Column()
        .width('100%')
        .height(64)
        .linearGradient({
          angle: 180,
          colors: [['#9E000000', 0], ['#00000000', 1]]
        })
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None)

      // 底部信息
      Column({ space: 6 }) {
        Row({ space: 10 }) {
          Text(L10n.t('video_home_recommend', '为你推荐'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E6FFFFFF')
          if (this.currentItem().nfoScore > 0) {
            Text(this.currentItem().nfoScore.toFixed(1))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F2E5B527')
          }
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        Text(this.currentItem().nfoName.length > 0
          ? this.currentItem().nfoName : this.currentItem().filename)
          .fontSize(22)
          .fontWeight(FontWeight.Bolder)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.subtitle().length > 0) {
          Text(this.subtitle())
            .fontSize(13)
            .fontColor('#BFFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        if (this.typeText().trim().length > 0) {
          Row() {
            Text(this.typeText().trim())
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F2FFFFFF')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor('#73000000')
          }
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 26 })
      .hitTestBehavior(HitTestMode.None)

      // 指示条
      if (this.items.length > 1) {
        Row({ space: 6 }) {
          ForEach(this.items, (_dotItem: VideoHomeItemBean, i: number) => {
            Column()
              .width(this.index === i ? 14 : 6)
              .height(6)
              .borderRadius(99)
              .backgroundColor(this.index === i ? '#F2FFFFFF' : '#73FFFFFF')
          }, (_dotItem: VideoHomeItemBean, i: number) => `dot_${i}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: '100%' })
        .markAnchor({ y: '100%' })
        .translate({ y: -10 })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }

  private currentItem(): VideoHomeItemBean {
    if (this.items.length === 0) {
      return new VideoHomeItemBean();
    }
    const i = this.index % this.items.length;
    return this.items[i];
  }

  private subtitle(): string {
    const item = this.currentItem();
    const sub = item.nfoYear > 0 ? `${item.nfoYear}` : '';
    const meta = buildVideoHomeMeta(item);
    return [sub, meta].filter((e: string) => e.length > 0).join(' · ');
  }

  private typeText(): string {
    return videoMediaTypeText(this.currentItem().mediaType);
  }

  @Builder
  SwiperItem(item: VideoHomeItemBean, i: number) {
    Stack() {
      if (i < this.imageUrls.length && this.imageUrls[i].length > 0) {
        Image(this.imageUrls[i])
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.12))
      }
      // 底部渐变压暗
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 0,
          colors: [['#DB000000', 0], ['#2E000000', 0.5], ['#00000000', 1]]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      const param = new VideoDetailPageParam();
      param.indexId = item.id;
      NavUtil.push(AppRouter.VIDEO_DETAIL, param);
    })
  }
}
