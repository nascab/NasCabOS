/**
 * 音乐播放内核（AVPlayer 音频，对齐 Flutter music_player_adapter 契约）：
 * - 播放源：本地文件（fdSrc）或网络 URL
 * - 能力：play/pause/seekTo/setVolume/setLooping（单曲循环 loop=-1）/dispose
 * - 回调：onPrepared/onPlaying/onPaused/onCompleted/onError/onTimeUpdate/onBuffered
 * - 单位：毫秒
 */

import media from '@ohos.multimedia.media';
import audio from '@ohos.multimedia.audio';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MusicPlaySource } from './MusicAudioCache';

const TAG = 'MusicPlayerEngine';

export interface MusicEngineCallbacks {
  onPrepared?: (durationMs: number) => void;
  onPlaying?: () => void;
  onPaused?: () => void;
  onCompleted?: () => void;
  onError?: (message: string) => void;
  onTimeUpdate?: (positionMs: number) => void;
  onBuffered?: (bufferedMs: number) => void;
  /** 正在缓冲标志（对齐 Flutter isBuffering，用于播放状态同步） */
  onBufferingChange?: (buffering: boolean) => void;
}

export class MusicPlayerEngine {
  private avPlayer: media.AVPlayer | null = null;
  private cb: MusicEngineCallbacks = {};
  private localFd: number = -1;
  private prepared: boolean = false;
  private durationMs: number = 0;
  private released: boolean = false;
  private lastVolume: number = 1.0;
  private lastLooping: boolean = false;
  private buffering: boolean = false;
  private playing: boolean = false;
  /** prepared 前暂存的 seek */
  private pendingSeekMs: number = -1;
  private autoPlay: boolean = true;

  setCallbacks(cb: MusicEngineCallbacks): void {
    this.cb = cb;
  }

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
          player.prepare().catch((e: Object): void => {
            this.notifyError(`prepare failed: ${JSON.stringify(e)}`);
          });
          break;
        case 'prepared':
          this.prepared = true;
          this.durationMs = player.duration > 0 ? player.duration : 0;
          try {
            player.setVolume(this.lastVolume);
            player.loop = this.lastLooping;
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
            this.play();
          }
          break;
        case 'playing':
          this.playing = true;
          this.setBuffering(false);
          this.cb.onPlaying?.();
          break;
        case 'paused':
          this.playing = false;
          this.cb.onPaused?.();
          break;
        case 'completed':
          this.playing = false;
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

    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (this.released) {
        return;
      }
      if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        const buf = this.durationMs > 0 ? Math.min(value, this.durationMs) : value;
        this.cb.onBuffered?.(buf);
        this.setBuffering(this.playing && this.durationMs > 0 && buf < this.durationMs * 0.98);
      } else if (infoType === media.BufferingInfoType.BUFFERING_PERCENT) {
        const buf = this.durationMs > 0 ? Math.min(Math.round(value / 100 * this.durationMs), this.durationMs) : 0;
        this.cb.onBuffered?.(buf);
      } else if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.setBuffering(true);
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.setBuffering(false);
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

  private setBuffering(v: boolean): void {
    if (this.buffering !== v) {
      this.buffering = v;
      this.cb.onBufferingChange?.(v);
    }
  }

  private notifyError(message: string): void {
    hilog.error(0x0000, TAG, 'engine error: %{public}s', message);
    this.cb.onError?.(message);
  }

  private closeLocalFd(): void {
    if (this.localFd >= 0) {
      try {
        fs.closeSync(this.localFd);
      } catch (_e) {
      }
      this.localFd = -1;
    }
  }

  /** 打开播放源（本地文件优先）；startMs>0 时 prepared 后先 seek */
  async open(source: MusicPlaySource, startMs: number = 0, autoPlay: boolean = true): Promise<void> {
    this.released = false;
    await this.ensureCreated();
    const player = this.avPlayer;
    if (player === null) {
      this.notifyError('avPlayer is null');
      return;
    }
    this.prepared = false;
    this.durationMs = 0;
    this.playing = false;
    this.setBuffering(false);
    this.pendingSeekMs = startMs > 0 ? startMs : -1;
    this.autoPlay = autoPlay;
    // 空闲态才能换源
    if (player.state !== 'idle' && player.state !== 'initialized') {
      player.reset();
      this.closeLocalFd();
    }
    if (source.filePath.trim().length > 0) {
      try {
        const stat = fs.statSync(source.filePath);
        const fd = fs.openSync(source.filePath, fs.OpenMode.READ_ONLY).fd;
        this.localFd = fd;
        player.fdSrc = { fd: fd, offset: 0, length: stat.size };
      } catch (e) {
        this.notifyError(`open local file failed: ${JSON.stringify(e)}`);
      }
    } else {
      player.url = source.url;
    }
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
    return this.playing;
  }

  isBuffering(): boolean {
    return this.buffering;
  }

  isPrepared(): boolean {
    return this.prepared;
  }

  seekTo(ms: number): void {
    if (this.avPlayer === null) {
      return;
    }
    if (!this.prepared) {
      this.pendingSeekMs = Math.max(0, ms);
      return;
    }
    this.doSeek(ms);
  }

  private doSeek(ms: number): void {
    const player = this.avPlayer;
    if (player === null) {
      return;
    }
    player.seek(Math.max(0, ms), media.SeekMode.SEEK_PREV_SYNC);
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

  getBuffered(): number {
    return 0;
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

  /** 单曲循环（对齐 Flutter setLooping） */
  setLooping(looping: boolean): void {
    this.lastLooping = looping;
    if (this.avPlayer !== null && this.prepared) {
      try {
        this.avPlayer.loop = looping;
      } catch (_e) {
        // 忽略设置失败
      }
    }
  }

  /** 释放播放器（切歌/退出时调用） */
  async release(): Promise<void> {
    this.released = true;
    this.playing = false;
    this.prepared = false;
    const player = this.avPlayer;
    this.avPlayer = null;
    if (player !== null) {
      try {
        player.reset();
      } catch (_e) {
      }
      try {
        await player.release();
      } catch (_e) {
      }
    }
    this.closeLocalFd();
  }
}
