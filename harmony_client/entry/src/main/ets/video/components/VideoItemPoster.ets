import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { VideoHomeItemBean } from '../models/VideoModels';
import {
  buildVideoHomeMeta, shortTypeLabel, videoMediaTypeText
} from '../utils/VideoItemUtils';
import { VideoItemActions, VideoActionSheetOptions } from './VideoItemViews';
import { VideoCoverImage } from './VideoCoverImage';
import { VideoDetailPageParam } from '../router/VideoRoutes';

/**
 * 视频海报卡片（对齐 Flutter AppVideoItemPoster，移动端版式）：
 * 2:3 封面 + 收藏角标 + 更多按钮（操作弹层）+ 进度条 + 标题/副标题。
 * 桌面端右键菜单在鸿蒙端统一为长按弹出操作弹层。
 */
@ComponentV2
export struct VideoItemPoster {
  @Param item: VideoHomeItemBean = new VideoHomeItemBean();
  /** 播放进度 0~1；<=0 不显示（对齐 Flutter progress 可空参数） */
  @Param progress: number = 0;
  @Param currentAlbumId: number = 0;
  @Param onDeleted: (item: VideoHomeItemBean) => void = (_item: VideoHomeItemBean): void => {
  };
  @Param onFavoriteChanged: (isFav: boolean) => void = (_isFav: boolean): void => {
  };
  @Param onRemovedFromCurrentAlbum: () => void = (): void => {
  };

  private openDetail(): void {
    const param = new VideoDetailPageParam();
    param.indexId = this.item.id;
    NavUtil.push(AppRouter.VIDEO_DETAIL, param);
  }

  private showActions(): void {
    const options = new VideoActionSheetOptions();
    options.onDeleted = (): void => {
      this.onDeleted(this.item);
    };
    options.onFavoriteChanged = this.onFavoriteChanged;
    options.onRemovedFromCurrentAlbum = this.onRemovedFromCurrentAlbum;
    VideoItemActions.showActionSheet(this.item, this.currentAlbumId, options);
  }

  @Builder
  FavoriteBadge() {
    Column() {
      SymbolGlyph($r('sys.symbol.heart_fill'))
        .fontSize(15)
        .fontColor([AppTheme.current().error])
    }
    .padding(6)
    .borderRadius(999)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.12) })
  }

  @Builder
  MoreBadge() {
    Column() {
      SymbolGlyph($r('sys.symbol.more'))
        .fontSize(15)
        .fontColor([AppTheme.current().onSurface])
    }
    .padding(6)
    .borderRadius(999)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.55))
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.12) })
  }

  @Builder
  ProgressBar() {
    Column() {
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .height(5)
          .width('100%')
          .borderRadius(99)
          .backgroundColor(AppTheme.withAlpha('#000000', 0.35))
        Row()
          .height(5)
          .width(`${Math.min(Math.max(this.progress, 0), 1) * 100}%`)
          .borderRadius(99)
          .backgroundColor(AppTheme.current().primary)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 8, right: 8 })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column() {
      Stack() {
        VideoCoverImage({
          item: this.item,
          mode: 'poster',
          imageRadius: 12,
          rating: this.item.nfoScore,
          typeText: shortTypeLabel(videoMediaTypeText(this.item.mediaType)),
          showBadges: true,
          badgeShortLabel: true
        })
        if (this.item.isFavorite) {
          Column() {
            this.FavoriteBadge()
          }
          .position({ x: 6, y: 6 })
        }
        Column() {
          this.MoreBadge()
        }
        .position({ x: '100%', y: 6 })
        .markAnchor({ x: '100%' })
        .onClick(() => {
          this.showActions();
        })
        if (this.progress > 0) {
          Column() {
            this.ProgressBar()
          }
          .width('100%')
          .position({ x: 0, y: 0 })
        }
      }
      .width('100%')
      .aspectRatio(2 / 3)

      Text(this.item.nfoName.length > 0 ? this.item.nfoName : this.item.filename)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 6 })

      if (this.item.nfoYear > 0 || buildVideoHomeMeta(this.item).length > 0) {
        Text(this.posterSubtitle())
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 2 })
      }
    }
    .onClick(() => {
      this.openDetail();
    })
    .gesture(LongPressGesture()
      .onAction(() => {
        this.showActions();
      }))
  }

  private posterSubtitle(): string {
    const parts: string[] = [];
    if (this.item.nfoYear > 0) {
      parts.push(`${this.item.nfoYear}`);
    }
    const meta = buildVideoHomeMeta(this.item);
    if (meta.length > 0) {
      parts.push(meta);
    }
    return parts.join(' · ');
  }
}

/** 海报卡片操作弹层回调集合（供列表页透传） */
export class VideoPosterActionOptions {
  onDeleted: (() => void) | undefined = undefined;
  onFavoriteChanged: ((isFav: boolean) => void) | undefined = undefined;
  onRemovedFromCurrentAlbum: (() => void) | undefined = undefined;
}

void VideoPosterActionOptions;
void L10n;
