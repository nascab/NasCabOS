import { AppTheme } from '../../core/theme/AppTheme';
import { VideoAlbumPreviewItem, VideoHomeItemBean } from '../models/VideoModels';
import { VideoUtils } from '../utils/VideoItemUtils';
import { AppImage } from '../../common/components/AppImage';

/** 预览条单元图（异步加载海报缩略 URL） */
@ComponentV2
export struct VideoAlbumPreviewImage {
  @Param fullpath: string = '';
  @Param firstFilePath: string = '';
  @Local imageUrl: string = '';

  aboutToAppear(): void {
    const item = new VideoHomeItemBean();
    item.firstFilePath = this.firstFilePath;
    item.fullPath = this.fullpath;
    VideoUtils.getPosterUrl(item, 500).then((url: string) => {
      this.imageUrl = url;
    });
  }

  build() {
    Stack() {
      if (this.imageUrl.length > 0) {
        AppImage({ url: this.imageUrl, objectFit: ImageFit.Cover })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
      }
    }
    .width('100%')
    .height('100%')
  }
}

/**
 * 通用相册卡片（对齐 Flutter AppVideoAlbumCard）：
 * 预览条（最多 4 张海报）+ 底部渐变 + 标题行 + 左上信息角标 + 右上更多角标。
 * 自建相册/智能相册/照片合集列表与相册主页共用。
 */
@ComponentV2
export struct VideoAlbumCard {
  @Param title: string = '';
  @Param titleIcon: Resource = $r('sys.symbol.video');
  /** 左上角信息角标图标（不传则不显示） */
  @Param showTopLeftIcon: boolean = false;
  @Param topLeftIcon: Resource = $r('sys.symbol.info_circle');
  @Param onTopLeftTap: () => void = (): void => {
  };
  @Param previews: VideoAlbumPreviewItem[] = [];
  @Param onTap: () => void = (): void => {
  };
  @Param onMore: () => void = (): void => {
  };

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 预览条：最多 4 张，1px 间隔；空时显示占位图标
      if (this.previews.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.video'))
            .fontSize(46)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.6)])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
      } else {
        Row({ space: 1 }) {
          ForEach(this.previews.slice(0, 4), (pv: VideoAlbumPreviewItem) => {
            VideoAlbumPreviewImage({ fullpath: pv.fullpath, firstFilePath: pv.firstFilePath })
              .layoutWeight(1)
              .height('100%')
          }, (pv: VideoAlbumPreviewItem, idx: number) => `${idx}_${pv.fullpath}_${pv.firstFilePath}`)
        }
        .width('100%')
        .height('100%')
      }

      // 底部渐变遮罩
      Column()
        .width('100%')
        .height(64)
        .linearGradient({
          angle: 0,
          colors: [['#CC000000', 0], ['#00000000', 1]]
        })
        .hitTestBehavior(HitTestMode.None)

      // 标题行
      Row({ space: 6 }) {
        SymbolGlyph(this.titleIcon)
          .fontSize(16)
          .fontColor(['#FFFFFF'])
        Text(this.title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 10 })
      .hitTestBehavior(HitTestMode.None)

      // 左上信息角标
      if (this.showTopLeftIcon) {
        Column() {
          SymbolGlyph(this.topLeftIcon)
            .fontSize(18)
            .fontColor(['#FFFFFF'])
        }
        .padding(6)
        .borderRadius(18)
        .backgroundColor('#4D000000')
        .position({ x: 6, y: 6 })
        .onClick(() => {
          this.onTopLeftTap();
        })
      }

      // 右上更多角标
      Column() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(18)
          .fontColor(['#FFFFFF'])
      }
      .padding(6)
      .borderRadius(18)
      .backgroundColor('#4D000000')
      .position({ x: '100%', y: 6 })
      .markAnchor({ x: '100%' })
      .onClick(() => {
        this.onMore();
      })
    }
    .width('100%')
    .height('100%')
    .borderRadius(14)
    .clip(true)
    .onClick(() => {
      this.onTap();
    })
  }
}

export function videoAlbumPreviewFrom(fullpath: string, firstFilePath: string): VideoAlbumPreviewItem {
  const pv = new VideoAlbumPreviewItem();
  pv.fullpath = fullpath;
  pv.firstFilePath = firstFilePath;
  return pv;
}
