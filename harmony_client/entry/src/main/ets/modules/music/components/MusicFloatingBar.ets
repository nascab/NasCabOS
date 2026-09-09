import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { MusicPlayService } from '../service/MusicPlayService';
import { MusicListItem } from '../models/MusicModels';
import { MusicDiscCover } from './MusicDiscCover';

/**
 * 音乐悬浮播放条（对齐 Flutter AppMusicPlayCtrlFloatingBar）：
 * 唱片 + 标题/歌手 + 上一首/播放暂停/下一首/播放队列；点击主体打开全屏播放页。
 * 服务未就绪或队列为空时不显示。
 */
@ComponentV2
export struct MusicFloatingBar {
  @Param onOpenFullscreen: () => void = (): void => {
  };
  @Param onOpenPlaylist: () => void = (): void => {
  };

  private svc: MusicPlayService = MusicPlayService.getInstance();

  build() {
    if (this.svc.isReady && this.svc.playlist.length > 0) {
      this.BarContent()
    }
  }

  @Builder
  private BarContent() {
    Row() {
      MusicDiscCover({
        coverPath: this.CoverPath(),
        isPlaying: this.svc.isPlaying,
        discAsset: this.svc.discAsset,
        outerSize: 44,
        innerSize: 30,
        // 唱片组件自带 onTap 会拦截点击冒泡，需显式接通打开全屏播放页
        onTap: (): void => {
          this.onOpenFullscreen();
        }
      })

      Column() {
        Text(this.TitleText())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.SubtitleText())
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })

      this.IconButton($r('sys.symbol.backward_end_fill'), L10n.t('music_prev_track'), (): void => {
        this.svc.playPrevious(false);
      })
      // 播放/暂停按钮内联（@Builder 按值传参不随状态刷新，必须直接读 this.svc.isPlaying）；
      // sys.symbol 无 pause_circle，暂停用实心圆底 + 反色图标与 play_circle_fill 对齐
      Column() {
        if (this.svc.isPlaying) {
          Column() {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(14)
              .fontColor([AppTheme.current().surfaceBg])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(AppTheme.current().onSurface)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          SymbolGlyph($r('sys.symbol.play_circle_fill'))
            .fontSize(30)
            .fontColor([AppTheme.current().onSurface])
        }
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        if (this.svc.isPlaying) {
          void this.svc.pause();
        } else {
          void this.svc.play();
        }
      })
      this.IconButton($r('sys.symbol.forward_end_fill'), L10n.t('music_next_track'), (): void => {
        this.svc.playNext(false);
      })
      this.IconButton($r('sys.symbol.music_note_list'), L10n.t('player_playlist'), (): void => {
        this.onOpenPlaylist();
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 10, right: 8, top: 8, bottom: 8 })
    .borderRadius(16)
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.10) })
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.92))
    .shadow({ radius: 14, color: 'rgba(0,0,0,0.18)', offsetY: 6 })
    .onClick(() => {
      this.onOpenFullscreen();
    })
  }

  private CoverPath(): string {
    const item = this.svc.currentItem;
    return item !== undefined ? item.coverFilePath() : '';
  }

  private TitleText(): string {
    const item = this.svc.currentItem;
    if (item === undefined) {
      return '';
    }
    const downloading = this.svc.isDownloading &&
      this.svc.downloadingFileHash.trim().length > 0 &&
      this.svc.downloadingFileHash.trim() === item.fileHash.trim();
    if (downloading) {
      const pct = Math.round(Math.min(Math.max(this.svc.downloadProgress, 0), 1) * 100);
      return `${pct}% ${item.displayTitle}`;
    }
    return item.displayTitle;
  }

  private SubtitleText(): string {
    const item = this.svc.currentItem;
    if (item === undefined) {
      return '-';
    }
    const a = item.artist.trim();
    return a.length > 0 ? a : '-';
  }

  @Builder
  private IconButton(icon: Resource, tip: string, onTap: () => void, iconSize: number = 22) {
    Column() {
      // SymbolGlyph 无障碍语义由外部 Row 处理；占位保持布局一致
      SymbolGlyph(icon)
        .fontSize(iconSize)
        .fontColor([AppTheme.current().onSurface])
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      onTap();
    })
  }
}
