import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'LivePhotoInlinePlayer';

/**
 * Live Photo 页内循环播放器（对齐 Flutter LivePhotoInlinePlayer）：
 * 不跳转页面，覆盖在当前图片上自动播放且循环；点击画面回调 onClose 停止；
 * 视频按宽高比居中（aspect fit），加载中转圈、失败白字提示。
 * 独立轻量实现（AVPlayer + XComponent），不复用视频模块内部类。
 */
@ComponentV2
export struct LivePhotoInlinePlayer {
  @Param videoUrl: string = '';
  @Param onClose: () => void = (): void => {
  };

  @Local playerState: string = 'idle';
  @Local errorText: string = '';
  @Local videoWidth: number = 0;
  @Local videoHeight: number = 0;
  @Local surfaceW: number = 0;
  @Local surfaceH: number = 0;
  private avPlayer: media.AVPlayer | null = null;
  private surfaceId: string = '';
  private xcController: XComponentController = new XComponentController();
  /** 每次播放组件实例唯一的 surface 标识，快速反复播放时避免 XComponent id 冲突 */
  private surfaceViewId: string = `nascab_livephoto_surface_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  private released: boolean = false;
  /** 是否已向播放器设置 url（surfaceId 就绪后只配置一次，消除 surface/player 竞态） */
  private configured: boolean = false;

  aboutToAppear(): void {
    this.released = false;
    void this.setupPlayer();
  }

  aboutToDisappear(): void {
    this.releasePlayer();
  }

  private async setupPlayer(): Promise<void> {
    try {
      const player = await media.createAVPlayer();
      if (this.released) {
        player.release().catch((_e: Object): void => {
        });
        return;
      }
      this.avPlayer = player;
      player.loop = true;
      player.on('stateChange', (state: media.AVPlayerState): void => {
        if (this.released) {
          return;
        }
        this.playerState = state;
        if (state === 'initialized') {
          // surfaceId 必须在 initialized 状态设置；url 已被推迟到 surface 就绪后再赋值，
          // 因此这里一定可以设置，避免 5400102（surfaceID 只能在 initialized 状态设置）
          if (this.surfaceId.length === 0) {
            this.fail('surface not ready');
            return;
          }
          player.surfaceId = this.surfaceId;
          player.prepare().catch((e: Object): void => {
            this.fail(`prepare failed: ${JSON.stringify(e)}`);
          });
        } else if (state === 'prepared') {
          player.play().catch((e: Object): void => {
            this.fail(`play failed: ${JSON.stringify(e)}`);
          });
        }
      });
      player.on('videoSizeChange', (width: number, height: number): void => {
        if (!this.released) {
          this.videoWidth = width;
          this.videoHeight = height;
        }
      });
      player.on('error', (err: BusinessError): void => {
        this.fail(`${err.code}: ${err.message}`);
      });
      // surfaceId 可能在 createAVPlayer 期间已就绪（XComponent onLoad 先返回）
      this.configureUrlIfReady();
    } catch (e) {
      this.fail(`create failed: ${JSON.stringify(e)}`);
    }
  }

  /** surfaceId 与播放器都就绪后才设置 url（驱动 idle→initialized），两者只配一次 */
  private configureUrlIfReady(): void {
    if (this.configured || this.released) {
      return;
    }
    if (this.surfaceId.length === 0 || this.avPlayer === null) {
      return;
    }
    this.configured = true;
    this.avPlayer.url = this.videoUrl;
  }

  private fail(msg: string): void {
    if (this.released) {
      return;
    }
    hilog.error(0x0000, TAG, '%{public}s', msg);
    this.errorText = msg;
  }

  private releasePlayer(): void {
    this.released = true;
    const player = this.avPlayer;
    this.avPlayer = null;
    if (player !== null) {
      try {
        if (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared') {
          player.stop().catch((_e: Object): void => {
          });
        }
        player.release().catch((_e: Object): void => {
        });
      } catch (_e) {
        // 释放失败忽略
      }
    }
  }

  /** aspect fit 尺寸（未知时占满容器） */
  private fitWidth(): number {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      return this.surfaceW;
    }
    return Math.min(this.surfaceW / this.videoWidth, this.surfaceH / this.videoHeight) * this.videoWidth;
  }

  private fitHeight(): number {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      return this.surfaceH;
    }
    return Math.min(this.surfaceW / this.videoWidth, this.surfaceH / this.videoHeight) * this.videoHeight;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({ id: this.surfaceViewId, type: 'surface', controller: this.xcController })
        .width(this.fitWidth())
        .height(this.fitHeight())
        .onLoad((): void => {
          try {
            this.surfaceId = this.xcController.getXComponentSurfaceId();
            // surface 就绪后再驱动播放器配置（url→initialized→setSurface→prepare→play），
            // 绝不在 initialized 之外的状态写 surfaceId
            this.configureUrlIfReady();
          } catch (e) {
            hilog.error(0x0000, TAG, 'getSurfaceId failed: %{public}s', JSON.stringify(e));
          }
        })

      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .padding({ left: 16, right: 16 })
      } else if (this.playerState !== 'prepared' && this.playerState !== 'playing'
        && this.playerState !== 'paused' && this.playerState !== 'completed') {
        LoadingProgress()
          .width(32)
          .height(32)
          .color('#FFFFFF')
      }

      // 点击画面停止播放
      Column()
        .width('100%')
        .height('100%')
        .onClick((): void => {
          this.onClose();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .onAreaChange((_o: Area, n: Area): void => {
      this.surfaceW = Number(n.width);
      this.surfaceH = Number(n.height);
    })
  }
}
