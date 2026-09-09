import { AppImage } from '../../../common/components/AppImage';

/**
 * 全屏播放页带唱针大唱片（对齐 Flutter MusicPlayCtrlFullScreenDiscWithNeedle）：
 * 磨砂圆盘底座 + 旋转黑胶（18s/圈）+ 唱针（播放时小幅摆动，暂停时归位）。
 * 封面 URL 由调用方解析后传入。
 */
@ComponentV2
export struct MusicDiscWithNeedle {
  @Param isPlaying: boolean = false;
  @Param coverUrl: string = '';
  @Param discAsset: string = 'music/icons/player_disc1.png';
  /** 正方形可用边长（含唱针悬出空间，对齐 Flutter size） */
  @Param boxSize: number = 320;
  @Param onTap: () => void = (): void => {
  };

  @Local private angle: number = 0;
  /** 唱针角度（度），基础 -24.06°（-0.42rad） */
  @Local private needleDeg: number = -24.06;
  private rotateTimer: number = -1;
  private needleTimer: number = -1;

  aboutToAppear(): void {
    this.syncAnim();
  }

  aboutToDisappear(): void {
    this.stopRotate();
    this.stopNeedle();
  }

  @Monitor('isPlaying')
  onPlayingChange(): void {
    this.syncAnim();
  }

  private syncAnim(): void {
    if (this.isPlaying) {
      this.startRotate();
      this.startNeedle();
    } else {
      this.stopRotate();
      this.stopNeedle();
      // 暂停时唱针归位（对齐 Flutter animateTo 0.5）
      this.needleDeg = -24.06;
    }
  }

  private startRotate(): void {
    if (this.rotateTimer >= 0) {
      return;
    }
    const stepDeg = 360 * 30 / 18000;
    this.rotateTimer = setInterval((): void => {
      this.angle = (this.angle + stepDeg) % 360;
    }, 30);
  }

  private stopRotate(): void {
    if (this.rotateTimer >= 0) {
      clearInterval(this.rotateTimer);
      this.rotateTimer = -1;
    }
  }

  private startNeedle(): void {
    if (this.needleTimer >= 0) {
      return;
    }
    // 三角波摆动：-0.44rad ~ -0.40rad，周期 1800ms（对齐 Flutter repeat(reverse)）
    const start = Date.now();
    this.needleTimer = setInterval((): void => {
      const t = ((Date.now() - start) % 1800) / 1800;
      const tri = t < 0.5 ? t * 2 : (1 - t) * 2;
      this.needleDeg = -24.06 + (tri * 2 - 1) * 1.146;
    }, 30);
  }

  private stopNeedle(): void {
    if (this.needleTimer >= 0) {
      clearInterval(this.needleTimer);
      this.needleTimer = -1;
    }
  }

  build() {
    Stack() {
      // 磨砂圆盘底座（disc 外扩 10）
      Column()
        .width(this.discSize() + 20)
        .height(this.discSize() + 20)
        .borderRadius((this.discSize() + 20) / 2)
        .backgroundColor('#14FFFFFF')
        .border({ width: 1, color: '#1AFFFFFF' })
        .position({ x: this.discLeft() - 10, y: 0 })

      // 旋转黑胶 + 中央封面
      Stack() {
        Image($rawfile(this.discAsset))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)

        Stack() {
          if (this.coverUrl.trim().length > 0) {
            AppImage({ url: this.coverUrl, showLoadingSpin: false })
          } else {
            Image($rawfile('music/icons/default_cover.jpg'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          }
        }
        .width(this.innerSize())
        .height(this.innerSize())
        .borderRadius(this.innerSize() / 2)
        .clip(true)
        .border({ width: 3, color: '#3DFFFFFF' })
        .padding(3)
        .backgroundColor('#59101010')
      }
      .width(this.discSize())
      .height(this.discSize())
      .rotate({ angle: this.angle })
      .position({ x: this.discLeft(), y: 10 })

      // 唱针（绕自身 27.5%/24.7% 处旋转，顶部悬出）
      Image($rawfile('music/icons/player_disc_bar.png'))
        .width(this.needleSize())
        .height(this.needleSize())
        .objectFit(ImageFit.Contain)
        .align(Alignment.TopStart)
        .rotate({
          angle: this.needleDeg,
          centerX: this.needleSize() * 0.275,
          centerY: this.needleSize() * 0.247
        })
        .position({ x: this.boxSize * 0.18, y: -this.boxSize * 0.2 })
    }
    .width(this.boxSize)
    .height(this.boxSize)
    .alignContent(Alignment.TopStart)
    .onClick(() => {
      this.onTap();
    })
  }

  private discSize(): number {
    return this.boxSize * 0.9;
  }

  private discLeft(): number {
    return (this.boxSize - this.discSize()) / 2;
  }

  private innerSize(): number {
    return Math.min(this.discSize() * 0.42 * 1.3, this.discSize() * 0.62);
  }

  private needleSize(): number {
    return this.boxSize * 0.42;
  }
}
