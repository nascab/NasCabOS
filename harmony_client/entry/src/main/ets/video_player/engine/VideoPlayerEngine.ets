/**
 * 播放内核封装（基于 GSYVideoPlayer 鸿蒙版的系统 AVPlayer 内核模式）：
 * - 对齐 GSY AvPlayerControl 的状态机（idle→initialized→prepared→playing/paused/completed）
 * - 扩展 Flutter 播放器所需能力：倍速 / 音量 / 音轨切换 / 缓冲回调 / 非强制播放的 seek
 * - 时间单位：毫秒（AVPlayer 原生单位），position/duration/seek 均为 ms
 */

import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import { hiAppEvent } from '@kit.PerformanceAnalysisKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'VideoPlayerEngine';

/** 引擎状态回调（控制器订阅） */
export interface EngineCallbacks {
  onPrepared?: (durationMs: number) => void;
  onPlaying?: () => void;
  onPaused?: () => void;
  onCompleted?: () => void;
  onError?: (message: string) => void;
  onTimeUpdate?: (positionMs: number) => void;
  onBuffered?: (bufferedMs: number) => void;
  onVideoSize?: (width: number, height: number) => void;
}

/** 倍速 → AVPlayer PlaybackSpeed 枚举映射（对齐 Flutter 速度选项） */
function playbackSpeedEnum(speed: number): media.PlaybackSpeed {
  if (speed <= 0.5) {
    return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
  } else if (speed <= 0.75) {
    return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
  } else if (speed <= 1.0) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  } else if (speed <= 1.25) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
  } else if (speed <= 1.5) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
  } else if (speed <= 1.75) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
  } else if (speed <= 2.0) {
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }
  return media.PlaybackSpeed.SPEED_FORWARD_3_00_X;
}

export class VideoPlayerEngine {
  private avPlayer: media.AVPlayer | null = null;
  private cb: EngineCallbacks = {};
  private surfaceId: string = '';
  private pendingUrl: string = '';
  private pendingSeekMs: number = -1;
  private autoPlay: boolean = true;
  private prepared: boolean = false;
  private lastSpeed: number = 1.0;
  private lastVolume: number = 1.0;
  private durationMs: number = 0;
  private released: boolean = false;
  /** 音轨（getTracks 中 track_type=audio 的数组索引，按容器顺序） */
  private audioTrackIndexes: number[] = [];
  /** surface 未就绪时暂存的 open 请求 */
  private pendingOpenUrl: string = '';
  private pendingOpenStartMs: number = -1;
  private pendingOpenAutoPlay: boolean = true;

  setCallbacks(cb: EngineCallbacks): void {
    this.cb = cb;
  }

  /** 设置渲染 surface id（XComponent onLoad 后调用，需在 open 之前） */
  setSurface(surfaceId: string): void {
    this.surfaceId = surfaceId;
    // surface 晚于 open 到达时，补启动暂存的播放请求
    if (surfaceId.trim().length > 0 && this.pendingOpenUrl.length > 0) {
      const url = this.pendingOpenUrl;
      const startMs = this.pendingOpenStartMs;
      const autoPlay = this.pendingOpenAutoPlay;
      this.pendingOpenUrl = '';
      void this.open(url, startMs, autoPlay);
    }
  }

  /** 创建并绑定 AVPlayer 事件（首次使用时调用） */
  async ensureCreated(): Promise<void> {
    if (this.avPlayer !== null) {
      return;
    }
    const player = await media.createAVPlayer();
    this.avPlayer = player;
    this.bindState(player);
  }

  private bindState(player: media.AVPlayer): void {
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (this.released) {
        return;
      }
      switch (state) {
        case 'initialized':
          if (this.surfaceId.trim().length > 0) {
            player.surfaceId = this.surfaceId;
          }
          player.prepare().catch((e: Object): void => {
            this.notifyError(`prepare failed: ${JSON.stringify(e)}`);
          });
          break;
        case 'prepared':
          this.prepared = true;
          this.durationMs = player.duration > 0 ? player.duration : 0;
          try {
            player.setSpeed(playbackSpeedEnum(this.lastSpeed));
            player.setVolume(this.lastVolume);
          } catch (_e) {
            // 忽略设置失败
          }
          this.cb.onPrepared?.(this.durationMs);
          if (this.pendingSeekMs > 0) {
            const target = this.pendingSeekMs;
            this.pendingSeekMs = -1;
            this.doSeek(target);
          }
          if (this.autoPlay) {
            player.play().catch((e: Object): void => {
              this.notifyError(`play failed: ${JSON.stringify(e)}`);
            });
          }
          break;
        case 'playing':
          this.cb.onPlaying?.();
          break;
        case 'paused':
          this.cb.onPaused?.();
          break;
        case 'completed':
          this.cb.onCompleted?.();
          break;
        default:
          break;
      }
    });

    player.on('timeUpdate', (time: number) => {
      if (!this.released) {
        this.cb.onTimeUpdate?.(time);
      }
    });

    player.on('videoSizeChange', (width: number, height: number) => {
      if (!this.released) {
        this.cb.onVideoSize?.(width, height);
      }
    });
    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (!this.released && this.durationMs > 0) {
        if (infoType === media.BufferingInfoType.CACHED_DURATION) {
          this.cb.onBuffered?.(Math.min(value, this.durationMs));
        } else if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
          this.cb.onBuffered?.(Math.min(Math.round(value / 100 * this.durationMs), this.durationMs));
        }
      }
    });

    player.on('durationUpdate', (duration: number) => {
      if (!this.released) {
        this.durationMs = duration;
        this.cb.onPrepared?.(duration);
      }
    });

    player.on('error', (err: BusinessError) => {
      if (!this.released) {
        this.notifyError(`${err.code}: ${err.message}`);
      }
    });

    player.on('audioInterrupt', (event: audio.InterruptEvent) => {
      if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        player.pause().catch((): void => {
        });
      }
    });
  }

  private notifyError(message: string): void {
    hilog.error(0x0000, TAG, 'engine error: %{public}s', message);
    this.cb.onError?.(message);
  }

  /** 打开播放地址；startMs>=0 时在 prepared 后先 seek 再播 */
  async open(url: string, startMs: number = -1, autoPlay: boolean = true): Promise<void> {
    if (this.surfaceId.trim().length === 0) {
      // surface 尚未就绪（XComponent onLoad 未回调），暂存等 setSurface 后再启动
      this.pendingOpenUrl = url;
      this.pendingOpenStartMs = startMs;
      this.pendingOpenAutoPlay = autoPlay;
      return;
    }
    this.pendingOpenUrl = '';
    await this.ensureCreated();
    this.prepared = false;
    this.durationMs = 0;
    this.pendingSeekMs = startMs;
    this.autoPlay = autoPlay;
    const player = this.avPlayer;
    if (player === null) {
      this.notifyError('avPlayer is null');
      return;
    }
    // idle/reset 状态才允许设置 url
    if (player.state !== 'idle' && player.state !== 'initialized') {
      player.reset();
    }
    this.pendingUrl = url;
    player.url = url;
  }

  play(): void {
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    if (player.state === 'paused' || player.state === 'prepared') {
      player.play().catch((e: Object): void => {
        this.notifyError(`play failed: ${JSON.stringify(e)}`);
      });
    }
  }

  pause(): void {
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    if (player.state === 'playing') {
      player.pause().catch((): void => {
      });
    }
  }

  isPlaying(): boolean {
    return this.avPlayer !== null && this.avPlayer.state === 'playing';
  }

  isPrepared(): boolean {
    return this.prepared;
  }

  /** seek（不强制恢复播放；转码模式下由控制器 debounce 后重建会话） */
  seekTo(ms: number): void {
    if (this.avPlayer === null) {
      return;
    }
    if (!this.prepared) {
      this.pendingSeekMs = ms;
      return;
    }
    this.doSeek(ms);
  }

  private doSeek(ms: number): void {
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    const safe = Math.max(0, ms);
    player.seek(safe, media.SeekMode.SEEK_PREV_SYNC);
  }

  getCurrentPosition(): number {
    if (this.avPlayer === null) {
      return 0;
    }
    return this.avPlayer.currentTime;
  }

  getDuration(): number {
    return this.durationMs;
  }

  setSpeed(speed: number): void {
    this.lastSpeed = speed;
    if (this.avPlayer !== null && this.prepared) {
      try {
        this.avPlayer.setSpeed(playbackSpeedEnum(speed));
      } catch (_e) {
        // 忽略设置失败
      }
    }
  }

  setVolume(volume: number): void {
    this.lastVolume = Math.min(Math.max(volume, 0.0), 1.0);
    if (this.avPlayer !== null && this.prepared) {
      try {
        this.avPlayer.setVolume(this.lastVolume);
      } catch (_e) {
        // 忽略设置失败
      }
    }
  }

  /** 音轨数量（容器内 audio 流数量） */
  getAudioTrackCount(): number {
    return this.audioTrackIndexes.length;
  }

  /** prepared 后调用：读取轨道列表 */
  async loadTracks(): Promise<void> {
    const player = this.avPlayer;
    if (player === null || !this.prepared) {
      return;
    }
    try {
      const tracks: media.MediaDescription[] = await player.getTrackDescription();
      this.audioTrackIndexes = [];
      for (let i = 0; i < tracks.length; i++) {
        const typeVal: Object = tracks[i]['track_type'];
        if (Number(typeVal) === media.MediaType.MEDIA_TYPE_AUD) {
          this.audioTrackIndexes.push(i);
        }
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'loadTracks failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 按同类序号（mapIndex，从 0 开始）切换音轨；返回是否成功 */
  async selectAudioTrackByOrder(orderIndex: number): Promise<boolean> {
    const player = this.avPlayer;
    if (player === null || !this.prepared) {
      return false;
    }
    if (orderIndex < 0 || orderIndex >= this.audioTrackIndexes.length) {
      return false;
    }
    if (this.audioTrackIndexes.length <= 1) {
      return false;
    }
    try {
      player.selectTrack(this.audioTrackIndexes[orderIndex]);
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'selectTrack failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  /** 停止并复位（保留实例，可再次 open 复用） */
  stop(): void {
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    if (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared') {
      player.stop().then((): void => {
        player.reset();
        this.prepared = false;
        this.durationMs = 0;
      }).catch((): void => {
      });
    }
  }

  /** 彻底释放 */
  release(): void {
    this.released = true;
    this.prepared = false;
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    this.avPlayer = null;
    try {
      player.off('stateChange');
      player.off('timeUpdate');
      player.off('videoSizeChange');
      player.off('bufferingUpdate');
      player.off('durationUpdate');
      player.off('error');
      player.off('audioInterrupt');
    } catch (_e) {
      // 忽略注销失败
    }
    if (player.state !== 'released') {
      player.release().catch((): void => {
      });
    }
  }
}
