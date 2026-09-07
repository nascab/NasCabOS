import { AppTheme } from '../../core/theme/AppTheme';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoUtils, buildVideoHomeMeta, videoMediaTypeText } from '../utils/VideoItemUtils';
import { VideoItemActions } from './VideoItemViews';
import { VideoDetailPageParam } from '../router/VideoRoutes';

/**
 * 视频推荐卡片（对齐 Flutter VideoItemRecommend）：
 * 背景大图 + 底部渐变 + 标题/元信息 + 评分/类型角标。
 */
@ComponentV2
export struct VideoItemRecommend {
  @Param item: VideoHomeItemBean = new VideoHomeItemBean();
  @Param imageWidth: number = 330;
  @Param imageHeight: number = 192;
  @Param imageRadius: number = 16;
  @Local imageUrl: string = '';

  aboutToAppear(): void {
    VideoUtils.getFanartUrl(this.item).then((url: string) => {
      this.imageUrl = url;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
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
      // 底部渐变遮罩（对齐 bottom→top 三段渐变）
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 0,
          colors: [['#C7000000', 0], ['#26000000', 0.5], ['#00000000', 1]]
        })
        .hitTestBehavior(HitTestMode.None)
      // 标题/元信息 + 底部角标行
      Column({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.item.nfoName.length > 0 ? this.item.nfoName : this.item.filename)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (buildVideoHomeMeta(this.item).length > 0) {
            Text(buildVideoHomeMeta(this.item))
              .fontSize(11)
              .fontColor('#E5FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (this.item.nfoYear > 0) {
            Text(`${this.item.nfoYear}`)
              .fontSize(11)
              .fontColor('#E5FFFFFF')
              .maxLines(1)
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        Row() {
          if (this.item.nfoScore > 0) {
            Text(this.item.nfoScore.toFixed(1))
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#EBE5B527')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(6)
              .backgroundColor('#8C000000')
              .border({ width: 1, color: '#52E5B527' })
          }
          Blank()
          if (videoMediaTypeText(this.item.mediaType).trim().length > 0) {
            Text(videoMediaTypeText(this.item.mediaType))
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(6)
              .backgroundColor('#8C000000')
              .border({ width: 1, color: '#52FFFFFF' })
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 10 })
      .hitTestBehavior(HitTestMode.None)
    }
    .width(this.imageWidth)
    .height(this.imageHeight)
    .borderRadius(this.imageRadius)
    .clip(true)
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.08) })
    .onClick(() => {
      const param = new VideoDetailPageParam();
      param.indexId = this.item.id;
      NavUtil.push(AppRouter.VIDEO_DETAIL, param);
    })
    .gesture(LongPressGesture()
      .onAction(() => {
        VideoItemActions.showActionSheet(this.item);
      }))
  }
}
