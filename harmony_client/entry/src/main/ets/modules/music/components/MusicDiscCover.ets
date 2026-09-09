import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { AppImage } from '../../../common/components/AppImage';

/**
 * 旋转唱片封面（对齐 Flutter MusicPlayDiscCover）：
 * 黑胶圆盘背景 + 中央圆形封面；isPlaying 时旋转（默认 18s/圈）。
 * 悬浮条与全屏播放页共用。封面 URL 为异步 AES 构造，内部自管理。
 */
@ComponentV2
export struct MusicDiscCover {
  /** 封面文件路径；空串用默认封面 */
  @Param coverPath: string = '';
  @Param isPlaying: boolean = false;
  /** rawfile 下的唱片背景图（music/icons/player_disc*.png） */
  @Param discAsset: string = 'music/icons/player_disc1.png';
  @Param outerSize: number = 58;
  @Param innerSize: number = 40;
  @Param rotationDuration: number = 18000;
  @Param onTap: () => void = (): void => {
  };

  @Local private coverUrl: string = '';
  @Local private angle: number = 0;
  private timerId: number = -1;
  private coverToken: number = 0;

  aboutToAppear(): void {
    this.resolveCover();
    this.updateTimer();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  @Monitor('coverPath')
  onCoverPathChange(): void {
    this.resolveCover();
  }

  @Monitor('isPlaying')
  onPlayingChange(): void {
    this.updateTimer();
  }

  private resolveCover(): void {
    const p = this.coverPath.trim();
    if (p.length === 0) {
      this.coverUrl = '';
      return;
    }
    const token = ++this.coverToken;
    ApiUrls.getMusicCoverUrl(p, 240).then((url: string): void => {
      if (token !== this.coverToken) {
        return;
      }
      this.coverUrl = url;
    }).catch((_e: Object): void => {
      if (token === this.coverToken) {
        this.coverUrl = '';
      }
    });
  }

  private updateTimer(): void {
    this.stopTimer();
    if (!this.isPlaying) {
      return;
    }
    // rotationDuration 毫秒转一圈；30ms 步进（约 33fps 流畅省电）
    const stepDeg = 360 * 30 / this.rotationDuration;
    this.timerId = setInterval((): void => {
      this.angle = (this.angle + stepDeg) % 360;
    }, 30);
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Stack() {
      Image($rawfile(this.discAsset))
        .width(this.outerSize)
        .height(this.outerSize)
        .objectFit(ImageFit.Cover)
        .rotate({ angle: this.angle })

      Stack() {
        if (this.coverUrl.length > 0) {
          AppImage({ url: this.coverUrl, showLoadingSpin: false })
        } else {
          Image($rawfile('music/icons/default_cover.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
      }
      .width(this.innerSize)
      .height(this.innerSize)
      .borderRadius(this.innerSize / 2)
      .clip(true)
      .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.4))
      .rotate({ angle: this.angle })
    }
    .width(this.outerSize)
    .height(this.outerSize)
    .onClick(() => {
      this.onTap();
    })
  }
}
