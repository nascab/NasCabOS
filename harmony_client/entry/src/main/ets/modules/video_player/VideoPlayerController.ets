/**
 * 视频播放器控制器（对齐 Flutter PlayerController 及其 parts 扩展）：
 * 播放初始化流程 / 原画↔转码切换 / 续播与偏好 / 自动保存 / 自动跳过片头片尾 /
 * 音轨字幕切换（内嵌/外挂字幕 mpv 原生渲染，失败回退 VTT 叠层；内嵌位图转码烧录）/ 循环模式 / 错误恢复。
 * 时间单位统一为毫秒。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { L10n } from '../../core/localization/L10n';
import { APIClient } from '../../core/network/APIClient';
import { ApiUrls } from '../../core/network/ApiUrls';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import {
  PlayerPlaylistItem, PlayerTrackInfo, PlayerStreamInfo, SubtitleCue,
  PlayerStreamInfo as StreamInfo, DEFAULT_TRANSCODE_QUALITY,
  isBitmapSubtitleCodec, isBitmapSubtitleExt, qualityLabelShort
} from './models/PlayerModels';
import { VideoPlayerApiService } from './service/VideoPlayerApiService';
import { VideoPlayerEngine } from './engine/VideoPlayerEngine';
import { parseWebVtt, findActiveCue } from './subtitle/WebVttParser';
import { decodeSubtitleText } from './subtitle/SubtitleEncoding';
import { asNum, asStr } from '../video/models/VideoModels';
import { WindowStore } from '../../common/WindowStore';
import { window } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { Player } from '@mpv-ohos/mpv-arkts';
import { LocalPlaybackProxy } from '../../p2p/LocalPlaybackProxy';

const TAG = 'PlayerCtrl';
/** P2P 中继下默认转码的大文件阈值（字节，对齐 Flutter 3GB） */
const P2P_RELAY_LARGE_FILE_BYTES = 3 * 1024 * 1024 * 1024;
/** 续播提示阈值：大于 10 秒才提示续播 */
const RESUME_TIP_THRESHOLD_SEC = 10;
/** 转码 seek 防抖 */
const TRANSCODE_SEEK_DEBOUNCE_MS = 300;
/** 播放失败重试上限 */
const MAX_RELOAD_RETRIES = 2;
/** 字幕 VTT 请求失败后的重试间隔（服务端首次提取可能超过单次请求时长） */
const SUBTITLE_VTT_RETRY_INTERVAL_MS = 3000;
/** 字幕 VTT 重试次数上限 */
const SUBTITLE_VTT_MAX_RETRIES = 6;

/**
 * 服务端 TranscodeWorker 用 UUID 校验 playId
 * （^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$），
 * 必须是标准 UUID，否则转码进程直接退出。
 */
function generatePlayId(): string {
  return util.generateRandomUUID(true);
}

/** 画质解析：'4k_20m' → { width: 3840, bitrate: '20000k' } */
function parseQuality(q: string): [number, string] {
  let width = 0;
  let bitrate = '';
  const parts = q.split('_');
  if (parts.length >= 2) {
    const res = parts[0].toLowerCase();
    const br = parts[1].toLowerCase();
    if (res === '4k') {
      width = 3840;
    } else if (res === '1080p') {
      width = 1920;
    } else if (res === '720p') {
      width = 1280;
    } else if (res === '480p') {
      width = 854;
    }
    const m = /^(\d+)(m|k)$/.exec(br);
    if (m !== null) {
      const n = parseInt(m[1], 10);
      if (n > 0) {
        bitrate = m[2] === 'm' ? `${n * 1000}k` : `${n}k`;
      }
    }
  }
  return [width, bitrate];
}

@ObservedV2
export class VideoPlayerController {
  // ===== 播放列表 =====
  playlist: PlayerPlaylistItem[] = [];
  @Trace currentIndex: number = 0;
  /** path 是 http url（加密空间）时为 true */
  @Trace isUrlSource: boolean = false;
  /** info 请求是否忽略查找外挂字幕 */
  ignoreFindSub: number = 1;

  // ===== 播放状态 =====
  @Trace isInitialized: boolean = false;
  @Trace isPreparing: boolean = false;
  @Trace isPlaying: boolean = false;
  @Trace positionMs: number = 0;
  @Trace durationMs: number = 0;
  @Trace bufferedMs: number = 0;
  @Trace videoWidth: number = 0;
  @Trace videoHeight: number = 0;
  @Trace playbackSpeed: number = 1.0;
  @Trace volume: number = 1.0;
  @Trace isLandscape: boolean = false;
  @Trace isLocked: boolean = false;
  @Trace showLockedIcon: boolean = false;
  @Trace isLooping: boolean = false;
  @Trace loopMode: string = 'sequence';
  @Trace showControls: boolean = true;
  /** 长按加速中（对齐 Flutter isCtrlSpeedBoost，移动端为长按手势） */
  @Trace isCtrlSpeedBoost: boolean = false;
  /** 续播提示倒计时（0 不显示） */
  @Trace resumeTipCountdown: number = 0;

  // ===== 轨道 =====
  videoTracks: PlayerTrackInfo[] = [];
  audioTracks: PlayerTrackInfo[] = [];
  @Trace audioTrackLabels: string[] = [];
  @Trace currentAudioTrack: string = '';
  subtitleTracks: PlayerTrackInfo[] = [];
  @Trace subtitleTrackLabels: string[] = [];
  @Trace currentSubtitleTrack: string = '';
  /** 客户端字幕叠层（转码/原画外挂文本字幕） */
  webSubtitleCues: SubtitleCue[] = [];
  @Trace webActiveSubtitleText: string = '';

  // ===== 画质 =====
  @Trace currentQuality: string = 'original';

  // ===== 内部状态 =====
  private engine: VideoPlayerEngine = new VideoPlayerEngine();
  private apiService = new VideoPlayerApiService();
  private playId: string | undefined = undefined;
  /** 切换前待停止的转码会话：等新地址打开后再停，避免旧 demuxer 大量 404 */
  private stalePlayId: string | undefined = undefined;
  /** 转码播放位置日志去重（每 5s 一条） */
  private lastTranscodePosBucket: number = -1;
  private transcodeBaseSeconds: number = 0;
  private pendingTranscodeSeekMs: number = -1;
  private transcodeSeekTimer: number = -1;
  private hideTimer: number = -1;
  private autoSaveTimer: number = -1;
  private resumeTipTimer: number = -1;
  private lockIconTimer: number = -1;
  private singleLoopCooldown: boolean = false;
  private singleLoopCooldownTimer: number = -1;
  private initGeneration: number = 0;
  private isClosingPlayer: boolean = false;
  private reloadRetryCount: number = 0;
  private isRecoveringFromError: boolean = false;
  private isPlaybackErrorDialogOpen: boolean = false;
  private autoSwitchedToTranscode: boolean = false;
  private pendingResumePositionMs: number = -1;
  private resumeSeekBakedIntoUrlSec: number = -1;
  private sourceDurationSec: number = 0;
  private sourceFileSizeBytes: number = 0;
  private openSkipStartSec: number = 0;
  private openSkipEndSec: number = 0;
  private didApplyResumeForCurrentSource: boolean = false;
  private skipIntroConsumed: boolean = false;
  private skipOutroConsumed: boolean = false;
  private skipOutroSuppressedByResume: boolean = false;
  private webSubtitleCacheKey: string = '';
  private webSubtitleLoading: boolean = false;
  private webSubtitleQueuedKey: string = '';
  private webSubtitleRetryTimer: number = -1;
  private webSubtitleRetryCount: number = 0;
  /** mpv 原生内嵌字幕选轨失败后的回退标记（按 label），切轨/重建会话时重置 */
  private nativeSubtitleFallbackLabel: string = '';
  private speedBeforeBoost: number = 1.0;
  private deviceId: string = '';
  /** 应用缓存目录（页面注入，用于外挂字幕解码后的 UTF-8 本地文件） */
  private cacheDir: string = '';

  constructor() {
    this.engine.setCallbacks({
      onPrepared: (durationMs: number): void => {
        if (this.sourceDurationSec > 0) {
          this.durationMs = this.sourceDurationSec * 1000;
        } else if (durationMs > 0) {
          // 转码流从 seek 起点截断，mpv 上报的是剩余时长；叠加起始偏移换算为绝对时长，
          // 否则绝对进度会立刻超过时长，误触发“播放完成”导致停播重建。
          this.durationMs = this.currentQuality !== 'original' && this.transcodeBaseSeconds > 0
            ? this.transcodeBaseSeconds * 1000 + durationMs
            : durationMs;
        }
        void this.engine.loadTracks();
      },
      onPlaying: (): void => {
        this.isPlaying = true;
        void this.applyOriginalAudioTrackAfterPlay();
        void this.applySubtitleTrackAfterPlay();
      },
      onPaused: (): void => {
        this.isPlaying = false;
      },
      onCompleted: (): void => {
        this.isPlaying = false;
        this.handlePlaybackComplete();
      },
      onError: (message: string): void => {
        hilog.error(0x0000, TAG, 'engine error: %{public}s', message);
        void this.handlePlaybackFailure();
      },
      onTimeUpdate: (positionMs: number): void => {
        this.onEnginePosition(positionMs);
      },
      onBuffered: (bufferedMs: number): void => {
        this.bufferedMs = this.transcodeTimelinePosition(bufferedMs);
      },
      onVideoSize: (width: number, height: number): void => {
        if (width > 0 && height > 0) {
          this.videoWidth = width;
          this.videoHeight = height;
        }
      }
    });
  }

  // ================================ 打开播放列表 ================================

  async openPlaylist(items: PlayerPlaylistItem[], initialIndex: number): Promise<void> {
    this.playlist = items;
    const len = items.length;
    let idx = initialIndex;
    if (idx < 0) {
      idx = 0;
    }
    if (idx > len - 1) {
      idx = Math.max(0, len - 1);
    }
    this.currentIndex = idx;
    this.reloadRetryCount = 0;
    this.isRecoveringFromError = false;
    this.isPlaybackErrorDialogOpen = false;
    this.autoSwitchedToTranscode = false;
    this.isClosingPlayer = false;
    this.loopMode = PreferencesStore.getInstance().getString('video_player_loop_mode') ?? 'sequence';
    this.isLooping = this.loopMode === 'single';
    this.deviceId = PreferencesStore.getInstance().getString('video_player_device_id') ?? '';
    if (this.deviceId.length === 0) {
      this.deviceId = generatePlayId();
      void PreferencesStore.getInstance().setString('video_player_device_id', this.deviceId);
    }
    if (this.playlist.length === 0) {
      return;
    }
    await this.initializePlayer(false, -1);
  }

  currentPlaylistItem(): PlayerPlaylistItem | undefined {
    if (this.playlist.length === 0 || this.currentIndex < 0 || this.currentIndex >= this.playlist.length) {
      return undefined;
    }
    return this.playlist[this.currentIndex];
  }

  /** 当前片源路径（internalPath 优先，信息接口/搜索字幕用） */
  currentSourcePathForInfo(): string {
    const item = this.currentPlaylistItem();
    if (item === undefined) {
      return '';
    }
    return item.internalPath.trim().length > 0 ? item.internalPath : item.path;
  }

  /** 页面注入应用缓存目录（getContext(this).cacheDir），用于外挂字幕 UTF-8 本地缓存 */
  setCacheDir(dir: string): void {
    this.cacheDir = dir;
  }

  // ================================ 初始化播放器 ================================

  private isHttpUrl(v: string): boolean {
    const s = v.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  /** 转码时间轴上的绝对进度（base + 相对偏移） */
  private transcodeTimelinePosition(ms: number): number {
    if (this.currentQuality === 'original' || this.transcodeBaseSeconds <= 0) {
      return Math.max(0, ms);
    }
    // mpv 上报的 time-pos 始终相对当前打开的转码流（从 0 开始），直接叠加起点偏移即可。
    // 不再沿用 Flutter/Media3 的“超过 base 视为绝对时间”启发式：那会让进度在
    // 播放到 base 秒时突然回退，并影响完播判定。
    return this.transcodeBaseSeconds * 1000 + ms;
  }

  private async initializePlayer(keepPosition: boolean, switchPositionMs: number,
    reusePlayId: boolean = false): Promise<void> {
    const gen = ++this.initGeneration;
    this.nativeSubtitleFallbackLabel = '';
    this.clearTranscodeSeekTimer();
    this.lastTranscodePosBucket = -1;
    this.isPreparing = true;
    this.isPlaying = false;
    hilog.info(0x0000, TAG, 'initializePlayer quality=%{public}s keepPosition=%{public}s switchMs=%{public}d reusePlayId=%{public}s',
      this.currentQuality, String(keepPosition), switchPositionMs, String(reusePlayId));
    const lastPositionMs = switchPositionMs >= 0 ? switchPositionMs : this.positionMs;
    const originalSeekAfterInitMs =
      this.currentQuality === 'original' && keepPosition ? lastPositionMs : -1;

    if (keepPosition) {
      this.pendingResumePositionMs = -1;
      this.resumeSeekBakedIntoUrlSec = -1;
    }

    // 旧转码会话先记下来，等新地址成功打开后再停止：
    // 若在 open 之前就 /stop，服务端会删掉旧输出目录，仍在运行的旧 demuxer 会持续 404 重试。
    const prevPlayId = this.playId;
    this.playId = undefined;
    const willReuseTranscode = reusePlayId && prevPlayId !== undefined && prevPlayId.length > 0;
    if (prevPlayId !== undefined && prevPlayId.length > 0 && !willReuseTranscode) {
      this.stalePlayId = prevPlayId;
    }
    // 停掉旧引擎播放（保留实例复用）。必须 await：否则 stop 内部的 reset 会在 open 之后执行，
    // 把刚写入的新地址复位掉，导致切换画质后卡住不播。
    await this.engine.stop();
    this.isInitialized = false;

    const item = this.currentPlaylistItem();
    if (item === undefined) {
      this.isUrlSource = false;
      this.isPreparing = false;
      return;
    }
    let path = item.path;
    let isUrl = this.isHttpUrl(path);
    this.isUrlSource = isUrl;

    if (!keepPosition) {
      // 仅在切换片源时清空画面尺寸；会话重建（切音轨/字幕/画质）必须保留，
      // 否则页面 letterbox 会退化为整页尺寸，画面被拉伸铺满屏幕。
      this.videoWidth = 0;
      this.videoHeight = 0;
      this.reloadRetryCount = 0;
      this.isRecoveringFromError = false;
      this.isPlaybackErrorDialogOpen = false;
      this.autoSwitchedToTranscode = false;
      this.resumeSeekBakedIntoUrlSec = -1;
      this.resetAutoSkipState(true);
      this.webClearSubtitle();
    }

    if (isUrl && this.currentQuality !== 'original') {
      this.currentQuality = 'original';
    }

    if (this.currentQuality !== 'original') {
      if (willReuseTranscode && prevPlayId !== undefined) {
        // 加载超时重试：沿用同一转码会话，避免服务端重新转码、用户反复看到同一片段
        this.playId = prevPlayId;
        hilog.info(0x0000, TAG, 'reuse transcode session playId=%{public}s', prevPlayId);
      } else {
        this.playId = generatePlayId();
      }
    }

    if (!keepPosition && !isUrl) {
      await this.fetchStreamInfo(item);
      if (this.isClosedOrGeneration(gen)) {
        return;
      }
      const item2 = this.currentPlaylistItem();
      if (item2 === undefined) {
        return;
      }
      path = item2.path;
      isUrl = this.isHttpUrl(path);
      this.isUrlSource = isUrl;
      // P2P 中继下大文件默认转码
      const api = APIClient.getInstance();
      if (this.currentQuality === 'original' && api.isP2pMode &&
        this.sourceFileSizeBytes > P2P_RELAY_LARGE_FILE_BYTES) {
        this.currentQuality = DEFAULT_TRANSCODE_QUALITY;
        this.playId = generatePlayId();
      }
    }

    // P2P 模式下 p2p.local 是虚拟域名，mpv/ffmpeg 无法解析，
    // 起播前确保本地代理已就绪，播放地址会改写到 127.0.0.1:<port>
    if (APIClient.getInstance().isP2pMode) {
      await LocalPlaybackProxy.getInstance().start();
    }

    const videoUrl = this.currentQuality === 'original'
      ? this.buildOriginalVideoUrl(item, lastPositionMs)
      : this.buildTranscodeVideoUrl(item, keepPosition, lastPositionMs);
    hilog.info(0x0000, TAG, 'open url=%{public}s', maskUrl(videoUrl));

    if (this.sourceDurationSec > 0) {
      this.durationMs = this.sourceDurationSec * 1000;
    }

    if (this.isClosedOrGeneration(gen)) {
      this.playId = undefined;
      return;
    }

    this.isPreparing = false;
    this.isInitialized = true;
    // 注意：此处不再重置 reloadRetryCount，否则 handlePlaybackFailure 的自增会被清零，
    // 造成「超时 → 重建会话 → 超时」无限循环（reloadRetryCount 仅在切片源时重置）。
    this.isRecoveringFromError = false;

    if (this.currentQuality !== 'original') {
      this.positionMs = keepPosition ? lastPositionMs : this.transcodeBaseSeconds * 1000;
    }

    if (!keepPosition) {
      // 应用服务端偏好（音轨/字幕/进度）
      if (this.pendingPreference !== undefined) {
        this.applyPreference(this.pendingPreference);
      }
    }

    let shouldShowResumeTip = false;
    if (!keepPosition) {
      if (this.resumeSeekBakedIntoUrlSec > RESUME_TIP_THRESHOLD_SEC) {
        this.markResumeApplied(this.resumeSeekBakedIntoUrlSec * 1000);
        shouldShowResumeTip = true;
      } else if (this.pendingResumePositionMs > RESUME_TIP_THRESHOLD_SEC * 1000) {
        let targetMs = this.pendingResumePositionMs;
        const capMs = this.resumePositionCapMs();
        if (targetMs > capMs) {
          targetMs = capMs;
        }
        this.pendingResumePositionMs = -1;
        if (Math.floor(targetMs / 1000) > RESUME_TIP_THRESHOLD_SEC) {
          this.markResumeApplied(targetMs);
          shouldShowResumeTip = true;
          this.engine.open(videoUrl, targetMs, true);
          this.positionMs = targetMs;
          if (this.currentQuality !== 'original') {
            this.transcodeBaseSeconds = Math.floor(targetMs / 1000);
          }
          this.finishInit(gen, shouldShowResumeTip);
          return;
        }
      }
    }

    if (originalSeekAfterInitMs > 0) {
      const capMs = this.resumePositionCapMs();
      const targetMs = originalSeekAfterInitMs > capMs ? capMs : originalSeekAfterInitMs;
      this.engine.open(videoUrl, targetMs, true);
      this.positionMs = targetMs;
    } else {
      // 转码地址已通过 URL 的 seek 参数完成定位，不能再按绝对进度 seek（对齐 Flutter：
      // 转码 keepPosition 时 startPosition 恒为 0）；否则会对已截断的转码流越界 seek 导致卡住。
      this.engine.open(videoUrl, -1, true);
    }

    this.finishInit(gen, shouldShowResumeTip);
  }

  /** 恢复播放位置上限（不超过当前时长；时长未知时不限制） */
  private resumePositionCapMs(): number {
    return this.durationMs > 0 ? this.durationMs : Number.MAX_SAFE_INTEGER;
  }

  private finishInit(gen: number, shouldShowResumeTip: boolean): void {
    if (this.isClosedOrGeneration(gen)) {
      return;
    }
    // 新地址已经发起打开，此时再停止上一个转码会话（避免旧 demuxer 立刻 404 重试）
    this.stopStaleTranscode();
    this.engine.setSpeed(this.playbackSpeed);
    this.engine.setVolume(this.volume);
    this.isInitialized = true;
    this.isPlaying = true;
    // 字幕叠层在起播后再异步加载：未命中缓存时服务端要现提取（ffmpeg），
    // 若在 engine.open 之前 await，会一直卡到提取完成才起播（原画同样受影响）。
    void this.applyClientSubtitleOverlayIfNeeded();
    if (shouldShowResumeTip) {
      this.startResumeTip(RESUME_TIP_THRESHOLD_SEC);
    }
    this.resetControlsTimer();
    this.startAutoSave();
  }

  /** 停止切换前遗留的转码会话（新地址已发起打开后再调用） */
  private stopStaleTranscode(): void {
    const stale = this.stalePlayId;
    this.stalePlayId = undefined;
    if (stale === undefined || stale.length === 0 || stale === this.playId) {
      return;
    }
    const startedAt = Date.now();
    this.apiService.stopTranscode(stale)
      .then((): void => {
        hilog.info(0x0000, TAG, 'stopTranscode done playId=%{public}s cost=%{public}d ms',
          stale, Date.now() - startedAt);
      })
      .catch((): void => {
        hilog.warn(0x0000, TAG, 'stopTranscode failed playId=%{public}s', stale);
      });
  }

  private isClosedOrGeneration(gen: number): boolean {
    return this.isClosingPlayer || gen !== this.initGeneration;
  }

  private pendingPreference: Record<string, Object> | undefined = undefined;

  // ================================ URL 构建 ================================

  private buildOriginalVideoUrl(item: PlayerPlaylistItem, _lastPositionMs: number): string {
    this.transcodeBaseSeconds = 0;
    this.pendingTranscodeSeekMs = -1;
    const path = item.path;
    const internalPath = item.internalPath.trim();
    if (this.isHttpUrl(path)) {
      return path;
    }
    const api = APIClient.getInstance();
    const token = api.accessToken ?? '';
    let videoUrl = `${api.baseUrl}/api/videoPlayer/rawFile?raw=1&path=${encodeURIComponent(path)}`;
    if (internalPath.length > 0) {
      videoUrl += `&internalPath=${encodeURIComponent(internalPath)}`;
    }
    if (token.length > 0) {
      videoUrl += `&accessToken=${encodeURIComponent(token)}`;
    }
    return this.resolvePlaybackUrl(videoUrl);
  }

  private buildTranscodeVideoUrl(item: PlayerPlaylistItem, keepPosition: boolean,
    lastPositionMs: number): string {
    let seekSeconds = keepPosition ? Math.floor(lastPositionMs / 1000) : 0;
    if (seekSeconds === 0 && !keepPosition && this.pendingResumePositionMs > RESUME_TIP_THRESHOLD_SEC * 1000) {
      let sec = Math.floor(this.pendingResumePositionMs / 1000);
      if (this.sourceDurationSec > 0) {
        sec = Math.min(sec, Math.max(0, this.sourceDurationSec - 1));
      }
      if (sec > RESUME_TIP_THRESHOLD_SEC) {
        seekSeconds = sec;
        this.resumeSeekBakedIntoUrlSec = sec;
        this.pendingResumePositionMs = -1;
      }
    }
    this.transcodeBaseSeconds = seekSeconds;

    const quality = parseQuality(this.currentQuality);
    const width = quality[0];
    const bitrate = quality[1];

    let audioIndex = -1;
    if (this.currentAudioTrack.length > 0) {
      const track = this.findTrackByLabel(this.audioTracks, this.currentAudioTrack);
      if (track !== undefined) {
        audioIndex = track.mapIndex;
      }
    }

    let subtitleIndex = -1;
    let burn = false;
    if (this.currentSubtitleTrack.length > 0 && !this.currentIsNoSubtitle) {
      const track = this.findTrackByLabel(this.subtitleTracks, this.currentSubtitleTrack);
      // 外挂字幕（含位图）由客户端 raw 直链交给 mpv 原生渲染，转码流不再烧录
      if (track !== undefined && !track.isExternal && isBitmapSubtitleCodec(track.codecName)) {
        subtitleIndex = track.mapIndex;
        burn = true;
      }
    }

    const api = APIClient.getInstance();
    const token = api.accessToken ?? '';
    let url = `${api.baseUrl}/api/videoPlayer/transcode?playId=${this.playId}` +
      `&filePath=${encodeURIComponent(item.path)}&seek=${seekSeconds}`;
    if (item.internalPath.trim().length > 0) {
      url += `&internalPath=${encodeURIComponent(item.internalPath.trim())}`;
    }
    if (this.deviceId.length > 0) {
      url += `&device_id=${encodeURIComponent(this.deviceId)}`;
    }
    if (width > 0) {
      url += `&width=${width}`;
    }
    if (bitrate.length > 0) {
      url += `&bitrate=${bitrate}`;
    }
    if (audioIndex >= 0) {
      url += `&audioIndex=${audioIndex}`;
    }
    if (subtitleIndex >= 0) {
      url += `&subtitleIndex=${subtitleIndex}`;
    }
    if (burn) {
      url += '&subtitleBurn=true';
    }
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    // 不追加 `#.m3u8` 伪后缀：mpv/ffmpeg 会按 m3u8 内容自动识别 HLS，
    // 而 URL fragment 可能被 mpv 当作本地片段语法解析，导致转码流打开失败。
    return this.resolvePlaybackUrl(url);
  }

  /**
   * P2P 模式下把 `p2p.local` 地址改写到本地代理 `127.0.0.1:<port>`：
   * mpv/ffmpeg 走系统 DNS，无法解析该虚拟域名，必须由本地代理转发到 P2P 通道。
   * （转码 m3u8 里的分片地址由服务端按请求 Host 生成，因此同样指向本地代理）
   */
  private resolvePlaybackUrl(url: string): string {
    return LocalPlaybackProxy.getInstance().resolveP2pProxyUrl(url);
  }

  // ================================ 流信息 ================================

  private async fetchStreamInfo(item: PlayerPlaylistItem): Promise<void> {
    const filePath = item.path;
    const internalPath = item.internalPath.trim();
    if (this.isHttpUrl(filePath)) {
      return;
    }
    const noSubLabel = this.noSubtitleLabel();
    const res = await this.apiService.getStreamInfo(filePath, internalPath, this.ignoreFindSub);
    if (!res.success || res.data === undefined) {
      return;
    }
    const info: PlayerStreamInfo = PlayerStreamInfo.fromData(res.data);
    this.sourceDurationSec = info.durationSec;
    this.sourceFileSizeBytes = info.sizeBytes;
    this.openSkipStartSec = info.openSkip.startSec;
    this.openSkipEndSec = info.openSkip.endSec;
    this.resetAutoSkipState(false);

    this.videoTracks = info.videoTracks;
    this.audioTracks = info.audioTracks;
    this.audioTrackLabels = info.audioTracks.map((t: PlayerTrackInfo): string => t.label);
    this.subtitleTracks = [];
    this.subtitleTrackLabels = [noSubLabel];
    // 外挂字幕排在内嵌字幕前（对齐 Flutter：插到 index 1 起始位置）
    const external = info.externalSubtitleTracks;
    const inner = info.innerSubtitleTracks;
    for (let i = 0; i < external.length; i++) {
      this.subtitleTracks.push(external[i]);
      this.subtitleTrackLabels.push(external[i].label);
    }
    for (let i = 0; i < inner.length; i++) {
      this.subtitleTracks.push(inner[i]);
      this.subtitleTrackLabels.push(inner[i].label);
    }
    this.currentSubtitleTrack = noSubLabel;
    if (this.audioTrackLabels.length > 0) {
      this.currentAudioTrack = this.audioTrackLabels[0];
    }
    if (this.subtitleTrackLabels.length > 1) {
      this.currentSubtitleTrack = this.subtitleTrackLabels[1];
    }
    this.pendingPreference = info.preference;
    if (info.preference !== undefined) {
      this.applyPreference(info.preference);
    }
  }

  private findTrackByLabel(tracks: PlayerTrackInfo[], label: string): PlayerTrackInfo | undefined {
    for (const t of tracks) {
      if (t.label === label) {
        return t;
      }
    }
    return undefined;
  }

  // ================================ 偏好 / 进度 ================================

  private applyPreference(pref: Record<string, Object>): void {
    const audioLabel = asStr(pref['audio_label']).trim();
    if (audioLabel.length > 0 && this.findTrackByLabel(this.audioTracks, audioLabel) !== undefined) {
      this.currentAudioTrack = audioLabel;
    }
    const subtitleLabel = asStr(pref['subtitle_label']).trim();
    if (subtitleLabel.length > 0 &&
      this.findTrackByLabel(this.subtitleTracks, subtitleLabel) !== undefined) {
      this.currentSubtitleTrack = subtitleLabel;
    }
    const resumeSec = Math.round(asNum(pref['playback_position']));
    if (resumeSec > RESUME_TIP_THRESHOLD_SEC) {
      if (this.resumeSeekBakedIntoUrlSec !== resumeSec) {
        this.pendingResumePositionMs = resumeSec * 1000;
      }
    }
  }

  async saveProgress(): Promise<void> {
    const item = this.currentPlaylistItem();
    if (item === undefined || this.isHttpUrl(item.path)) {
      return;
    }
    try {
      await this.apiService.savePreference(item.path, item.internalPath,
        Math.floor(this.positionMs / 1000), this.currentSubtitleTrack, this.currentAudioTrack);
    } catch (_e) {
      // 保存失败忽略
    }
  }

  savePreference(): void {
    void this.saveProgress();
  }

  // ================================ 音轨 ================================

  async setAudioTrack(trackLabel: string, force: boolean = false): Promise<void> {
    if (this.currentAudioTrack === trackLabel && !force) {
      return;
    }
    this.currentAudioTrack = trackLabel;
    this.savePreference();
    if (this.currentQuality === 'original') {
      // 原画：mpv 通过 aid 切换音轨
      const track = this.findTrackByLabel(this.audioTracks, trackLabel);
      if (track === undefined) {
        return;
      }
      const ok = await this.engine.selectAudioTrackByOrder(track.mapIndex);
      if (!ok) {
        // 引擎切换失败（如不支持），回退重建会话
        await this.initializePlayer(true, this.absolutePlaybackPositionMs());
      }
    } else {
      // 转码：重启会话应用新音轨
      await this.initializePlayer(true, this.positionMs);
    }
  }

  /** 原画播放开始后应用音轨（对齐 _applyOriginalTracksAfterPlay） */
  private originalAudioAppliedGen: number = -1;

  private async applyOriginalAudioTrackAfterPlay(): Promise<void> {
    // 同字幕：playing 事件可能早于流信息到达，此时不消耗 applied 标记
    if (this.currentQuality !== 'original' || this.audioTracks.length === 0 ||
      this.currentAudioTrack.length === 0) {
      return;
    }
    if (this.originalAudioAppliedGen === this.initGeneration) {
      return;
    }
    this.originalAudioAppliedGen = this.initGeneration;
    const track = this.findTrackByLabel(this.audioTracks, this.currentAudioTrack);
    // 即使目标是第一条也要显式下发：mpv 打开文件时会按容器里的 default 标记自动选轨，
    // 多音轨视频可能默认选中第二条，而 UI 默认勾选第一条，不下发就会出现勾选与实际播放不一致。
    if (track !== undefined && this.audioTracks.length > 1) {
      await this.engine.loadTracks();
      let ok = await this.engine.selectAudioTrackByOrder(track.mapIndex);
      // mpv 的 tracks 属性可能晚于 playing 事件到达，短暂等待后重试
      for (let i = 0; i < 10 && !ok; i++) {
        await sleepMs(100);
        ok = await this.engine.selectAudioTrackByOrder(track.mapIndex);
      }
    }
  }

  // ================================ 字幕 ================================

  noSubtitleLabel(): string {
    return L10n.t('player_no_subtitle', '无字幕');
  }

  get currentIsNoSubtitle(): boolean {
    return this.currentSubtitleTrack === this.noSubtitleLabel();
  }

  checkSubtitleIsExternal(label: string): boolean {
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    return t !== undefined && t.isExternal;
  }

  /** 是否为内嵌位图字幕（转码时由服务端烧录进画面，切换必须重建会话） */
  private subtitleIsEmbeddedBitmap(label: string): boolean {
    if (label.length === 0 || label === this.noSubtitleLabel()) {
      return false;
    }
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    return t !== undefined && !t.isExternal && isBitmapSubtitleCodec(t.codecName);
  }

  /** 原画内嵌字幕（文本/位图）交给 mpv 原生渲染 */
  private shouldUseNativeEmbeddedSubtitle(label: string): boolean {
    if (this.currentQuality !== 'original' || label.length === 0 ||
      label === this.noSubtitleLabel()) {
      return false;
    }
    // 原生选轨失败过一次时，本次会话回退到客户端叠层
    if (this.nativeSubtitleFallbackLabel === label) {
      return false;
    }
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    return t !== undefined && !t.isExternal;
  }

  /** 外挂字幕（文本/位图）直接拉 raw 源文件交给 mpv 原生渲染，原画/转码都适用 */
  private shouldUseNativeExternalSubtitle(label: string): boolean {
    if (label.length === 0 || label === this.noSubtitleLabel()) {
      return false;
    }
    // 原生挂载失败过一次时，本次会话回退到客户端叠层（仅文本字幕可回退）
    if (this.nativeSubtitleFallbackLabel === label) {
      return false;
    }
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    return t !== undefined && t.isExternal;
  }

  /** 是否为外挂位图字幕（无法转 VTT，原生挂载失败后没有叠层可回退） */
  private isExternalBitmapSubtitle(label: string): boolean {
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    return t !== undefined && t.isExternal && isBitmapSubtitleExt(fileExt(t.path));
  }

  /** 是否使用客户端 VTT 叠层 */
  useClientSubtitleOverlay(): boolean {
    if (this.currentIsNoSubtitle) {
      return false;
    }
    // 外挂字幕与内嵌字幕都优先交给 mpv 原生渲染，不再叠加客户端字幕
    if (this.shouldUseNativeExternalSubtitle(this.currentSubtitleTrack) ||
      this.shouldUseNativeEmbeddedSubtitle(this.currentSubtitleTrack)) {
      return false;
    }
    // 仅原生渲染失败回退时使用 VTT 叠层
    return true;
  }

  async setSubtitleTrack(trackLabel: string, force: boolean = false): Promise<void> {
    if (this.currentSubtitleTrack === trackLabel && !force) {
      return;
    }
    const prevBitmap = this.subtitleIsEmbeddedBitmap(this.currentSubtitleTrack);
    const nextBitmap = this.subtitleIsEmbeddedBitmap(trackLabel);
    hilog.info(0x0000, TAG,
      'setSubtitleTrack label=%{public}s prevBitmap=%{public}s nextBitmap=%{public}s quality=%{public}s',
      trackLabel, String(prevBitmap), String(nextBitmap), this.currentQuality);
    this.currentSubtitleTrack = trackLabel;
    // 切轨时重新尝试原生挂载，上一次的失败回退只对那一次会话有效
    this.nativeSubtitleFallbackLabel = '';
    this.cancelWebSubtitleRetry();
    this.webSubtitleRetryCount = 0;
    this.savePreference();

    // 转码流中已烧录的内嵌位图无法实时移除，切到任何其他字幕都要重建会话
    if (this.currentQuality !== 'original' && prevBitmap) {
      await this.initializePlayer(true, this.absolutePlaybackPositionMs());
      return;
    }

    // 外挂字幕：独立文件，文本先由客户端解码为 UTF-8 再交给 mpv，原画与转码都无需服务端转换
    if (this.shouldUseNativeExternalSubtitle(trackLabel)) {
      this.webClearSubtitle();
      const ok = await this.attachNativeExternalSubtitle(trackLabel);
      if (!ok) {
        hilog.warn(0x0000, TAG, 'native external subtitle failed label=%{public}s', trackLabel);
        this.nativeSubtitleFallbackLabel = trackLabel;
        // 挂载失败时关闭 mpv 可能残留的上一条字幕，避免与叠层重复
        this.engine.disableSubtitle();
        // 文本外挂可回退客户端叠层；位图外挂无法转 VTT，只能放弃
        if (!this.isExternalBitmapSubtitle(trackLabel)) {
          void this.loadWebSubtitleIfNeeded(true);
        }
      }
      return;
    }

    if (this.currentQuality === 'original') {
      // 原画：内嵌字幕（文本/位图）交给 mpv 原生渲染，无需转码
      if (this.shouldUseNativeEmbeddedSubtitle(trackLabel)) {
        this.webClearSubtitle();
        const ok = await this.attachNativeEmbeddedSubtitle(trackLabel);
        if (!ok) {
          if (nextBitmap) {
            // 内嵌位图 mpv 确实挂不上时才回退转码烧录
            hilog.warn(0x0000, TAG, 'native bitmap subtitle failed, fallback to transcode');
            this.currentQuality = DEFAULT_TRANSCODE_QUALITY;
            await this.initializePlayer(true, this.absolutePlaybackPositionMs());
          } else {
            hilog.warn(0x0000, TAG, 'native inner subtitle failed, fallback to overlay label=%{public}s',
              trackLabel);
            this.nativeSubtitleFallbackLabel = trackLabel;
            this.engine.disableSubtitle();
            // 不阻塞字幕菜单：回退叠层，加载完成后自动显示
            void this.loadWebSubtitleIfNeeded(true);
          }
        }
        return;
      }
      this.engine.disableSubtitle();
      if (this.currentIsNoSubtitle) {
        this.webClearSubtitle();
        return;
      }
      // 不阻塞字幕菜单：未命中缓存时服务端提取可能较久，加载完成后叠层会自动显示
      void this.loadWebSubtitleIfNeeded(true);
      return;
    }

    // 转码：切到内嵌位图需要重建会话（由服务端烧录进转码流）
    if (nextBitmap) {
      await this.initializePlayer(true, this.absolutePlaybackPositionMs());
      return;
    }
    // 转码 + 内嵌文本/无字幕：关闭可能残留的外挂原生字幕，改由 VTT 叠层绘制
    this.engine.disableSubtitle();
    if (this.currentIsNoSubtitle) {
      this.webClearSubtitle();
      return;
    }
    void this.loadWebSubtitleIfNeeded(true);
  }

  /**
   * 用 mpv 原生渲染内嵌字幕（原画，文本/位图通用）：按 mapIndex 选轨。
   * 返回 false 表示 mpv 无法选中该字幕。
   */
  private async attachNativeEmbeddedSubtitle(label: string): Promise<boolean> {
    const track = this.findTrackByLabel(this.subtitleTracks, label);
    if (track === undefined || track.isExternal) {
      return false;
    }
    await this.engine.loadTracks();
    let ok = await this.engine.selectSubtitleTrackByOrder(track.mapIndex);
    // mpv 的 tracks 属性可能晚于 playing 事件到达，短暂等待后重试
    for (let i = 0; i < 10 && !ok; i++) {
      await sleepMs(100);
      ok = await this.engine.selectSubtitleTrackByOrder(track.mapIndex);
    }
    hilog.info(0x0000, TAG, 'attach inner native subtitle idx=%{public}d ok=%{public}s',
      track.mapIndex, String(ok));
    return ok;
  }

  /**
   * 用 mpv 原生渲染外挂字幕（文本/位图通用）。
   * 文本字幕的编码由客户端识别（GBK/Big5/UTF-16 等）并转成 UTF-8 写入本地缓存文件，
   * 再以 file:// 交给 mpv：libmpv/libass 只按 UTF-8 解析，直接给原文件会乱码。
   * 返回 false 表示 mpv 无法挂载该字幕。
   */
  private async attachNativeExternalSubtitle(label: string): Promise<boolean> {
    const track = this.findTrackByLabel(this.subtitleTracks, label);
    if (track === undefined || !track.isExternal) {
      return false;
    }
    let subtitleUrl = '';
    if (isBitmapSubtitleExt(fileExt(track.path))) {
      // 位图字幕（sup/sub+idx）无编码问题，直接交给 mpv 解析
      subtitleUrl = this.resolvePlaybackUrl(await ApiUrls.getRawFileUrl(track.path, true));
    } else {
      const bytes = await this.apiService.getExternalSubtitleBytes(track.path);
      if (bytes === undefined) {
        hilog.warn(0x0000, TAG, 'download external subtitle failed label=%{public}s', track.label);
        return false;
      }
      const text = decodeSubtitleText(bytes);
      if (text === undefined || text.length === 0) {
        hilog.warn(0x0000, TAG, 'decode external subtitle failed label=%{public}s bytes=%{public}d',
          track.label, bytes.length);
        return false;
      }
      const localPath = this.writeUtf8SubtitleCache(track.path, text);
      if (localPath.length === 0) {
        return false;
      }
      subtitleUrl = `file://${localPath}`;
    }
    if (subtitleUrl.length === 0) {
      return false;
    }
    hilog.info(0x0000, TAG, 'attach external subtitle label=%{public}s url=%{public}s',
      track.label, subtitleUrl);
    return this.engine.loadExternalSubtitle(subtitleUrl, track.label, track.language);
  }

  /** 把解码后的 UTF-8 字幕写入本地缓存，返回文件路径；失败返回 '' */
  private writeUtf8SubtitleCache(sourcePath: string, text: string): string {
    if (this.cacheDir.length === 0) {
      hilog.warn(0x0000, TAG, 'cacheDir not injected, skip subtitle cache');
      return '';
    }
    const dir = `${this.cacheDir}/player_subtitles`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const outPath = `${dir}/${subtitleCacheName(sourcePath, fileExt(sourcePath).toLowerCase())}`;
      const file = fs.openSync(outPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        // 字符串默认 UTF-8 写入，正是 mpv/libass 需要的编码
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
      return outPath;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'write subtitle cache failed: %{public}s', JSON.stringify(e));
      return '';
    }
  }

  /** 字幕恢复标记（mpv 每次加载新文件会重置 sid，需在播放开始后重新挂载） */
  private subtitleAppliedGen: number = -1;

  private async applySubtitleTrackAfterPlay(): Promise<void> {
    // 引擎的 playing 事件可能早于流信息/偏好恢复到达（此时字幕列表为空）。
    // 这种情况下不能消耗 applied 标记，否则真正起播后就再也不会恢复字幕。
    if (this.subtitleTracks.length === 0 || this.currentSubtitleTrack.length === 0) {
      return;
    }
    if (this.subtitleAppliedGen === this.initGeneration) {
      return;
    }
    this.subtitleAppliedGen = this.initGeneration;

    // 外挂字幕：独立文件，原画/转码都直接交给 mpv 原生渲染
    if (this.shouldUseNativeExternalSubtitle(this.currentSubtitleTrack)) {
      this.webClearSubtitle();
      const ok = await this.attachNativeExternalSubtitle(this.currentSubtitleTrack);
      if (!ok) {
        hilog.warn(0x0000, TAG, 'restore native external subtitle failed label=%{public}s',
          this.currentSubtitleTrack);
        this.nativeSubtitleFallbackLabel = this.currentSubtitleTrack;
        this.engine.disableSubtitle();
        if (!this.isExternalBitmapSubtitle(this.currentSubtitleTrack)) {
          void this.loadWebSubtitleIfNeeded(true);
        }
      }
      return;
    }

    if (this.currentQuality !== 'original') {
      // 内嵌位图字幕已烧录进转码画面，关闭 mpv 原生字幕避免重复显示
      this.engine.disableSubtitle();
      return;
    }
    if (this.shouldUseNativeEmbeddedSubtitle(this.currentSubtitleTrack)) {
      // 原画内嵌字幕：文本与位图统一交给 mpv 原生渲染
      this.webClearSubtitle();
      const ok = await this.attachNativeEmbeddedSubtitle(this.currentSubtitleTrack);
      if (!ok) {
        // 原生选轨失败时回退客户端叠层，避免该字幕完全不显示
        hilog.warn(0x0000, TAG, 'restore native inner subtitle failed, fallback to overlay label=%{public}s',
          this.currentSubtitleTrack);
        this.nativeSubtitleFallbackLabel = this.currentSubtitleTrack;
        this.engine.disableSubtitle();
        void this.loadWebSubtitleIfNeeded(true);
      }
      return;
    }
    this.engine.disableSubtitle();
  }

  /** 打开/切换后应用客户端字幕叠层 */
  private async applyClientSubtitleOverlayIfNeeded(): Promise<void> {
    if (this.currentQuality !== 'original' &&
      !this.shouldUseNativeExternalSubtitle(this.currentSubtitleTrack)) {
      // 转码：内嵌位图已烧录、内嵌文本不在转码流中，关闭 mpv 原生字幕；
      // 外挂字幕是独立文件，转码下同样由 mpv 原生渲染，不能关闭
      this.engine.disableSubtitle();
    }
    if (!this.useClientSubtitleOverlay()) {
      this.webClearSubtitle();
      return;
    }
    if (this.currentIsNoSubtitle) {
      this.webClearSubtitle();
      return;
    }
    if (this.currentSubtitleTrack.length === 0) {
      this.webClearSubtitle();
      return;
    }
    const track = this.findTrackByLabel(this.subtitleTracks, this.currentSubtitleTrack);
    if (track === undefined) {
      this.webClearSubtitle();
      return;
    }
    if (track.isExternal) {
      if (isBitmapSubtitleExt(fileExt(track.path))) {
        this.webClearSubtitle();
        return;
      }
    } else if (isBitmapSubtitleCodec(track.codecName)) {
      this.webClearSubtitle();
      return;
    }
    await this.loadWebSubtitleIfNeeded(true);
  }

  webClearSubtitle(): void {
    this.webSubtitleCues = [];
    this.webActiveSubtitleText = '';
    this.webSubtitleCacheKey = '';
    this.webSubtitleQueuedKey = '';
    this.cancelWebSubtitleRetry();
    this.webSubtitleRetryCount = 0;
  }

  private cancelWebSubtitleRetry(): void {
    if (this.webSubtitleRetryTimer >= 0) {
      clearTimeout(this.webSubtitleRetryTimer);
      this.webSubtitleRetryTimer = -1;
    }
  }

  /**
   * 服务端首次提取字幕可能超过单次请求时长（请求超时或 504），但 worker 会继续生成并落缓存，
   * 因此定时重试，命中缓存后字幕即可自动出现，无需退出重进。
   */
  private scheduleWebSubtitleRetry(): void {
    if (this.webSubtitleRetryTimer >= 0 ||
      this.webSubtitleRetryCount >= SUBTITLE_VTT_MAX_RETRIES) {
      return;
    }
    this.webSubtitleRetryTimer = setTimeout(() => {
      this.webSubtitleRetryTimer = -1;
      if (this.currentIsNoSubtitle || this.webSubtitleCues.length > 0) {
        return;
      }
      if (this.webSubtitleLoading) {
        this.scheduleWebSubtitleRetry();
        return;
      }
      this.webSubtitleRetryCount += 1;
      void this.loadWebSubtitleIfNeeded(true);
    }, SUBTITLE_VTT_RETRY_INTERVAL_MS);
  }

  webUpdateActiveCue(): void {
    if (!this.useClientSubtitleOverlay() || this.currentIsNoSubtitle || this.webSubtitleCues.length === 0) {
      if (this.webActiveSubtitleText.length > 0) {
        this.webActiveSubtitleText = '';
      }
      return;
    }
    const cue = findActiveCue(this.webSubtitleCues, this.positionMs);
    const text = cue !== undefined ? cue.text : '';
    if (this.webActiveSubtitleText !== text) {
      this.webActiveSubtitleText = text;
    }
  }

  async loadWebSubtitleIfNeeded(force: boolean): Promise<void> {
    if (!this.useClientSubtitleOverlay() || this.currentIsNoSubtitle) {
      this.webClearSubtitle();
      return;
    }
    const item = this.currentPlaylistItem();
    if (item === undefined || item.path.trim().length === 0) {
      this.webClearSubtitle();
      return;
    }
    const track = this.findTrackByLabel(this.subtitleTracks, this.currentSubtitleTrack);
    if (track === undefined) {
      this.webClearSubtitle();
      return;
    }
    if (track.isExternal && isBitmapSubtitleExt(fileExt(track.path))) {
      this.webClearSubtitle();
      return;
    }
    if (!track.isExternal && isBitmapSubtitleCodec(track.codecName)) {
      this.webClearSubtitle();
      return;
    }
    const idx = track.mapIndex;
    const key = track.isExternal ? `ext:${track.path}#${idx}` : `emb:${item.path}#${idx}`;
    if (!force && key === this.webSubtitleCacheKey && this.webSubtitleCues.length > 0) {
      this.webUpdateActiveCue();
      return;
    }
    if (this.webSubtitleLoading) {
      // 已有请求在途：记下最新要加载的字幕，等当前请求结束后再补一次，
      // 否则切字幕会被静默丢弃（未命中缓存时服务端提取较慢，很容易撞上）。
      if (key !== this.webSubtitleCacheKey) {
        this.webSubtitleQueuedKey = key;
        this.webSubtitleCacheKey = key;
      }
      return;
    }
    this.webSubtitleLoading = true;
    this.webSubtitleCacheKey = key;
    try {
      const body = await this.apiService.getSubtitleVtt(item.path, idx,
        track.isExternal ? track.path : '');
      if (this.webSubtitleCacheKey !== key) {
        return;
      }
      if (body === undefined) {
        this.webSubtitleCues = [];
        this.webActiveSubtitleText = '';
        this.scheduleWebSubtitleRetry();
        return;
      }
      this.webSubtitleCues = parseWebVtt(body);
      this.webSubtitleRetryCount = 0;
      this.cancelWebSubtitleRetry();
      this.webUpdateActiveCue();
    } catch (_e) {
      if (this.webSubtitleCacheKey !== key) {
        return;
      }
      this.webSubtitleCues = [];
      this.webActiveSubtitleText = '';
      this.scheduleWebSubtitleRetry();
    } finally {
      this.webSubtitleLoading = false;
      const queued = this.webSubtitleQueuedKey;
      if (queued.length > 0) {
        this.webSubtitleQueuedKey = '';
        void this.loadWebSubtitleIfNeeded(true);
      }
    }
  }

  /** 添加并选中服务器字幕文件（搜索/上传/服务器选择后调用） */
  async addAndSelectExternalSubtitle(subtitlePath: string, filename: string,
    source: string = ''): Promise<void> {
    const p = subtitlePath.trim();
    const name = filename.trim().length > 0 ? filename.trim() : baseName(p);
    if (p.length === 0 || name.length === 0) {
      return;
    }
    let exists = false;
    for (const t of this.subtitleTracks) {
      if (t.isExternal && t.path.trim() === p) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      const t = new PlayerTrackInfo();
      t.index = -1;
      t.mapIndex = 0;
      t.isExternal = true;
      t.path = p;
      t.filename = name;
      t.label = name;
      t.source = source;
      t.codecName = fileExt(name).toLowerCase();
      this.subtitleTracks.unshift(t);
      // 显示列表：0 是无字幕，外挂字幕从 1 开始
      this.subtitleTrackLabels.splice(1, 0, name);
    }
    await this.setSubtitleTrack(name, true);
  }

  async deleteExternalSubtitle(subtitlePath: string): Promise<void> {
    const videoPath = this.currentSourcePathForInfo();
    if (videoPath.length === 0 || subtitlePath.trim().length === 0) {
      return;
    }
    const sub = subtitlePath.trim();
    let extLabel = '';
    for (const t of this.subtitleTracks) {
      if (t.isExternal && t.path.trim() === sub) {
        extLabel = t.label.trim();
        break;
      }
    }
    const deletingSelected = extLabel.length > 0 && this.currentSubtitleTrack === extLabel;

    const res = await this.apiService.deleteExternalSubtitle(videoPath, sub);
    if (!res.success) {
      ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (deletingSelected) {
      await this.setSubtitleTrack(this.noSubtitleLabel(), true);
    }
    this.subtitleTracks = this.subtitleTracks.filter(
      (t: PlayerTrackInfo): boolean => !(t.isExternal && t.path.trim() === sub));
    this.subtitleTrackLabels = [this.noSubtitleLabel()];
    for (const t of this.subtitleTracks) {
      this.subtitleTrackLabels.push(t.label);
    }
    ToastUtil.show(L10n.t('player_subtitle_delete_success', '字幕已删除'));
  }

  // ================================ 播放控制 ================================

  togglePlay(): void {
    if (!this.isInitialized) {
      this.resetControlsTimer();
      return;
    }
    // 直接用乐观状态切换：mpv 的 pause 属性变更事件在 HLS/转码流下并不可靠，
    // 若等回调再更新，图标不会切换，且再次点击仍会走 pause 分支导致无法继续播放。
    if (this.isPlaying) {
      this.engine.pause();
      this.isPlaying = false;
    } else {
      this.engine.play();
      this.isPlaying = true;
    }
    this.resetControlsTimer();
  }

  playPrev(): void {
    if (this.currentIndex > 0) {
      this.currentIndex--;
      void this.initializePlayer(false, -1);
    }
  }

  playNext(): void {
    if (this.currentIndex < this.playlist.length - 1) {
      this.currentIndex++;
      void this.initializePlayer(false, -1);
    }
  }

  playAt(index: number): void {
    if (index < 0 || index >= this.playlist.length) {
      return;
    }
    if (this.currentIndex === index) {
      return;
    }
    this.currentIndex = index;
    void this.initializePlayer(false, -1);
  }

  rewind(seconds: number = 10): void {
    const newPos = this.positionMs - seconds * 1000;
    this.seekTo(newPos < 0 ? 0 : newPos);
  }

  fastForward(seconds: number = 30): void {
    const newPos = this.positionMs + seconds * 1000;
    this.seekTo(newPos > this.durationMs ? this.durationMs : newPos);
  }

  seekTo(posMs: number): void {
    const clamped = Math.min(Math.max(posMs, 0), this.durationMs > 0 ? this.durationMs : posMs);
    if (this.currentQuality !== 'original') {
      // 转码：debounce 后重建会话
      this.pendingTranscodeSeekMs = clamped;
      this.positionMs = clamped;
      this.clearTranscodeSeekTimer();
      this.transcodeSeekTimer = setTimeout((): void => {
        const target = this.pendingTranscodeSeekMs;
        this.pendingTranscodeSeekMs = -1;
        if (this.isClosingPlayer || target < 0) {
          return;
        }
        void this.initializePlayer(true, target);
      }, TRANSCODE_SEEK_DEBOUNCE_MS);
      this.resetControlsTimer();
      return;
    }
    this.positionMs = clamped;
    this.engine.seekTo(clamped);
    this.resetControlsTimer();
  }

  private clearTranscodeSeekTimer(): void {
    if (this.transcodeSeekTimer >= 0) {
      clearTimeout(this.transcodeSeekTimer);
      this.transcodeSeekTimer = -1;
    }
  }

  setSpeed(speed: number): void {
    this.engine.setSpeed(speed);
    this.playbackSpeed = speed;
  }

  /** 长按加速 2x，松开恢复（对齐 setCtrlSpeedBoost） */
  setCtrlSpeedBoost(held: boolean): void {
    if (held) {
      if (!this.isCtrlSpeedBoost) {
        this.speedBeforeBoost = this.playbackSpeed;
        this.setSpeed(2.0);
        this.isCtrlSpeedBoost = true;
      }
    } else {
      if (this.isCtrlSpeedBoost) {
        this.setSpeed(this.speedBeforeBoost);
        this.isCtrlSpeedBoost = false;
      }
    }
  }

  setVolume(vol: number): void {
    const v = Math.min(Math.max(vol, 0.0), 1.0);
    this.engine.setVolume(v);
    this.volume = v;
  }

  async setLoopMode(mode: string): Promise<void> {
    this.loopMode = mode;
    this.isLooping = mode === 'single';
    void PreferencesStore.getInstance().setString('video_player_loop_mode', mode);
  }

  changeQuality(quality: string): void {
    if (this.currentQuality === quality) {
      return;
    }
    const switchPos = this.absolutePlaybackPositionMs();
    this.currentQuality = quality;
    this.positionMs = switchPos;
    // 用户主动切换画质属于新的播放意图，重置失败重试计数
    this.reloadRetryCount = 0;
    void this.initializePlayer(true, switchPos);
  }

  /** 当前绝对播放进度（画质切换采样用） */
  absolutePlaybackPositionMs(): number {
    if (this.currentQuality !== 'original') {
      return this.transcodeTimelinePosition(this.engine.getCurrentPosition());
    }
    const enginePos = this.engine.getCurrentPosition();
    if (enginePos > 0) {
      return enginePos;
    }
    return this.positionMs;
  }

  qualityLabel(quality: string): string {
    return qualityLabelShort(quality, L10n.t('player_quality_original', '原画'),
      L10n.t('player_quality', '画质'));
  }

  // ================================ 引擎位置/完成 ================================

  private onEnginePosition(enginePosMs: number): void {
    if (this.isClosingPlayer || !this.isInitialized) {
      return;
    }
    // 播放位置已经推进说明本次加载确实成功，清零失败重试计数：
    // 否则一次加载超时会把计数永久留在高位，之后任何偶发错误都会直接弹「播放出错」。
    if (enginePosMs > 0 && this.reloadRetryCount !== 0) {
      this.reloadRetryCount = 0;
    }
    if (this.currentQuality !== 'original') {
      // 转码流每推进 5s 打一条日志，便于确认播放是否真的在推进（HLS 事件可能稀疏）
      const bucket = Math.floor(enginePosMs / 5000);
      if (bucket !== this.lastTranscodePosBucket) {
        this.lastTranscodePosBucket = bucket;
        hilog.info(0x0000, TAG, 'transcode pos=%{public}d ms', Math.round(enginePosMs));
      }
    }
    const pendingSeek = this.pendingTranscodeSeekMs;
    if (this.currentQuality !== 'original') {
      if (pendingSeek >= 0) {
        this.positionMs = pendingSeek;
        return;
      }
      if (!this.isInitialized) {
        return;
      }
      this.positionMs = this.transcodeTimelinePosition(Math.max(0, enginePosMs));
      if (this.sourceDurationSec > 0) {
        this.durationMs = this.sourceDurationSec * 1000;
      }
    } else {
      this.positionMs = Math.max(0, enginePosMs);
      if (this.sourceDurationSec > 0) {
        this.durationMs = this.sourceDurationSec * 1000;
      }
    }
    this.webUpdateActiveCue();
    this.handleAutoSkip();
    // 单曲循环/列表播放完成检测（需已真正出画，避免起播/重建阶段的误判）
    if (!this.isPlaying && enginePosMs > 0 && this.durationMs > 0 &&
      this.positionMs >= this.durationMs - 1000) {
      if (this.singleLoopCooldown) {
        return;
      }
      this.handlePlaybackComplete();
    }
  }

  private handlePlaybackComplete(): void {
    if (this.isClosingPlayer) {
      return;
    }
    const mode = this.loopMode;
    if (mode === 'single') {
      this.singleLoopCooldownTimer = setTimeout((): void => {
        this.singleLoopCooldown = false;
        this.singleLoopCooldownTimer = -1;
      }, 1500);
      this.singleLoopCooldown = true;
      this.seekTo(0);
      this.engine.play();
      return;
    }
    if (mode === 'shuffle') {
      if (this.playlist.length <= 1) {
        return;
      }
      let next = Math.floor(Math.random() * this.playlist.length);
      if (next === this.currentIndex) {
        next = (next + 1) % this.playlist.length;
      }
      this.playAt(next);
      return;
    }
    if (mode === 'all') {
      if (this.playlist.length === 0) {
        return;
      }
      if (this.currentIndex >= this.playlist.length - 1) {
        this.playAt(0);
        return;
      }
      this.playNext();
      return;
    }
    this.playNext();
  }

  // ================================ 自动跳过片头片尾 ================================

  private resetAutoSkipState(clearSegments: boolean): void {
    if (clearSegments) {
      this.openSkipStartSec = 0;
      this.openSkipEndSec = 0;
    }
    this.didApplyResumeForCurrentSource = false;
    this.skipIntroConsumed = false;
    this.skipOutroConsumed = false;
    this.skipOutroSuppressedByResume = false;
  }

  private markResumeApplied(targetMs: number): void {
    this.didApplyResumeForCurrentSource = true;
    this.skipIntroConsumed = true;
    if (this.openSkipEndSec <= 0 || this.durationMs <= 0) {
      return;
    }
    const outroStartMs = this.durationMs - this.openSkipEndSec * 1000;
    if (outroStartMs <= 0) {
      return;
    }
    if (targetMs >= outroStartMs) {
      this.skipOutroSuppressedByResume = true;
      this.skipOutroConsumed = true;
    }
  }

  private handleAutoSkip(): void {
    if (this.isClosingPlayer || !this.isInitialized || !this.isPlaying) {
      return;
    }
    const totalMs = this.durationMs;
    if (totalMs <= 0) {
      return;
    }
    if (!this.skipIntroConsumed && !this.didApplyResumeForCurrentSource) {
      const startSec = this.openSkipStartSec;
      if (startSec > 0) {
        const introTargetMs = startSec * 1000;
        if (introTargetMs >= totalMs) {
          this.skipIntroConsumed = true;
        } else if (this.positionMs < introTargetMs) {
          this.skipIntroConsumed = true;
          if (introTargetMs > this.positionMs + 500) {
            ToastUtil.show(L10n.t('player_skip_opening', '已跳过片头'));
            this.seekTo(introTargetMs);
          }
          return;
        } else {
          this.skipIntroConsumed = true;
        }
      }
    }
    if (this.skipOutroConsumed || this.skipOutroSuppressedByResume) {
      return;
    }
    const endSec = this.openSkipEndSec;
    if (endSec <= 0) {
      return;
    }
    const outroStartMs = totalMs - endSec * 1000;
    if (outroStartMs <= 0) {
      return;
    }
    if (this.positionMs >= outroStartMs) {
      this.skipOutroConsumed = true;
      ToastUtil.show(L10n.t('player_skip_ending', '已跳过片尾'));
      this.handlePlaybackComplete();
    }
  }

  // ================================ 错误恢复 ================================

  private async handlePlaybackFailure(): Promise<void> {
    if (this.isClosingPlayer || this.isRecoveringFromError) {
      return;
    }
    hilog.warn(0x0000, TAG, 'playback failure quality=%{public}s retry=%{public}d positionMs=%{public}d enginePos=%{public}d playId=%{public}s',
      this.currentQuality, this.reloadRetryCount, Math.round(this.positionMs),
      this.engine.getCurrentPosition(), String(this.playId));
    // 原画直链失败 → 自动切转码（对齐 TV/Android 行为）
    if (this.currentQuality === 'original') {
      if (!this.autoSwitchedToTranscode) {
        this.autoSwitchedToTranscode = true;
        this.isRecoveringFromError = true;
        this.isInitialized = false;
        this.reloadRetryCount = 0;
        this.currentQuality = DEFAULT_TRANSCODE_QUALITY;
        await sleepMs(300);
        this.isRecoveringFromError = false;
        if (this.isClosingPlayer) {
          return;
        }
        await this.initializePlayer(true, this.positionMs);
        return;
      }
    } else {
      if (this.reloadRetryCount < MAX_RELOAD_RETRIES) {
        // 首次失败：沿用同一转码会话重开（服务端分片继续产出，不会重新转码）；
        // 再次失败才换新 playId 重建会话。
        const reusePlayId = this.reloadRetryCount === 0 && this.playId !== undefined;
        this.isRecoveringFromError = true;
        this.isInitialized = false;
        this.reloadRetryCount++;
        await sleepMs(300);
        this.isRecoveringFromError = false;
        if (this.isClosingPlayer) {
          return;
        }
        await this.initializePlayer(true, this.positionMs, reusePlayId);
        return;
      }
    }
    if (this.isPlaybackErrorDialogOpen) {
      return;
    }
    this.isPlaybackErrorDialogOpen = true;
    if (this.currentQuality === 'original') {
      DialogUtil.showConfirmThreeButtonsDialog(
        L10n.t('player_playback_error', '播放出错'),
        L10n.t('player_if_retry', '是否重试？'),
        (): void => {
          this.isPlaybackErrorDialogOpen = false;
          this.reloadRetryCount = 0;
          this.currentQuality = DEFAULT_TRANSCODE_QUALITY;
          void this.initializePlayer(true, this.positionMs);
        },
        (): void => {
          this.isPlaybackErrorDialogOpen = false;
          this.reloadRetryCount = 0;
          void this.initializePlayer(true, this.positionMs);
        },
        L10n.t('cancel', '取消'),
        L10n.t('player_test_transcode', '尝试转码'),
        L10n.t('retry', '重试')
      );
      return;
    }
    DialogUtil.showConfirmDialog(
      L10n.t('player_playback_error', '播放出错'),
      L10n.t('player_if_retry', '是否重试？'),
      (): void => {
        this.isPlaybackErrorDialogOpen = false;
        this.reloadRetryCount = 0;
        void this.initializePlayer(true, this.positionMs);
      },
      L10n.t('retry', '重试'),
      L10n.t('cancel', '取消')
    );
  }

  // ================================ 控制栏显隐 / 锁定 ================================

  handlePlayerTap(): void {
    if (this.isLocked) {
      this.showLockedIcon = true;
      this.lockIconTimer = setTimeout((): void => {
        this.showLockedIcon = false;
        this.lockIconTimer = -1;
      }, 3000);
      ToastUtil.show(L10n.t('player_screen_locked', '屏幕已锁定'));
      return;
    }
    this.toggleControls();
  }

  lockScreen(): void {
    if (this.isLocked) {
      return;
    }
    this.isLocked = true;
    this.showControls = false;
    this.showLockedIcon = false;
    this.clearHideTimer();
    ToastUtil.show(L10n.t('player_screen_locked', '屏幕已锁定'));
  }

  unlockScreen(): void {
    if (!this.isLocked) {
      return;
    }
    this.isLocked = false;
    this.showLockedIcon = false;
    this.showControls = true;
    this.resetControlsTimer();
  }

  toggleControls(): void {
    if (this.isLocked) {
      return;
    }
    this.showControls = !this.showControls;
    if (this.showControls) {
      this.resetControlsTimer();
    } else {
      this.clearHideTimer();
    }
  }

  /** 唤出控制栏并重置自动隐藏计时（已显示或被锁定时不做任何事） */
  revealControls(): void {
    if (this.isLocked || this.showControls) {
      return;
    }
    this.showControls = true;
    this.resetControlsTimer();
  }

  resetControlsTimer(): void {
    if (this.isLocked) {
      return;
    }
    this.clearHideTimer();
    this.hideTimer = setTimeout((): void => {
      if (this.isLocked) {
        return;
      }
      if (this.isPlaying) {
        this.showControls = false;
      }
    }, 3000);
  }

  private clearHideTimer(): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  // ================================ 横竖屏 ================================

  async toggleOrientation(): Promise<void> {
    const next = !this.isLandscape;
    this.isLandscape = next;
    this.setPreferredOrientation(next);
  }

  private setPreferredOrientation(landscape: boolean): void {
    try {
      windowOrientationSet(landscape);
    } catch (e) {
      hilog.error(0x0000, TAG, 'setPreferredOrientation failed: %{public}s', JSON.stringify(e));
    }
  }

  restoreOrientation(): void {
    if (this.lockIconTimer >= 0) {
      clearTimeout(this.lockIconTimer);
      this.lockIconTimer = -1;
    }
    this.showLockedIcon = false;
    this.isLocked = false;
    this.isLandscape = false;
    this.setPreferredOrientation(false);
  }

  async prepareExitIfLandscape(): Promise<void> {
    if (!this.isLandscape) {
      return;
    }
    this.restoreOrientation();
    await sleepMs(120);
  }

  // ================================ 续播提示 ================================

  startResumeTip(seconds: number): void {
    if (this.resumeTipTimer >= 0) {
      clearInterval(this.resumeTipTimer);
      this.resumeTipTimer = -1;
    }
    this.resumeTipCountdown = seconds;
    this.resumeTipTimer = setInterval((): void => {
      if (this.resumeTipCountdown <= 1) {
        this.cancelResumeTip();
        return;
      }
      this.resumeTipCountdown--;
    }, 1000);
  }

  cancelResumeTip(): void {
    if (this.resumeTipTimer >= 0) {
      clearInterval(this.resumeTipTimer);
      this.resumeTipTimer = -1;
    }
    this.resumeTipCountdown = 0;
  }

  onResumeTipTap(): void {
    this.seekTo(0);
    this.cancelResumeTip();
  }

  // ================================ 自动保存 ================================

  startAutoSave(): void {
    if (this.autoSaveTimer >= 0) {
      clearInterval(this.autoSaveTimer);
      this.autoSaveTimer = -1;
    }
    this.autoSaveTimer = setInterval((): void => {
      if (this.isPlaying && this.isInitialized) {
        void this.saveProgress();
      }
    }, 30000);
  }

  stopAutoSave(): void {
    if (this.autoSaveTimer >= 0) {
      clearInterval(this.autoSaveTimer);
      this.autoSaveTimer = -1;
    }
  }

  // ================================ 引擎挂载 / 关闭 ================================

  /** mpv 播放器实例（页面 PlayerSurface 绑定渲染 surface 用） */
  getMpvPlayer(): Player {
    return this.engine.getPlayer();
  }

  /** 横向滑动进度预览（页面手势层用） */
  positionForScrub(dxVp: number, pageWidthVp: number): number {
    if (pageWidthVp < 1 || this.durationMs <= 0) {
      return this.positionMs;
    }
    const deltaMs = Math.round(dxVp / pageWidthVp * this.durationMs);
    return Math.min(Math.max(this.positionMs + deltaMs, 0), this.durationMs);
  }

  /** 关闭播放器：保存进度并释放资源 */
  async close(): Promise<void> {
    if (this.isClosingPlayer) {
      return;
    }
    this.isClosingPlayer = true;
    this.initGeneration++;
    this.isInitialized = false;
    this.isPlaying = false;
    this.isPreparing = false;
    this.cancelResumeTip();
    this.clearHideTimer();
    this.clearTranscodeSeekTimer();
    if (this.singleLoopCooldownTimer >= 0) {
      clearTimeout(this.singleLoopCooldownTimer);
      this.singleLoopCooldownTimer = -1;
    }
    this.stopAutoSave();
    await this.saveProgress();
    if (this.playId !== undefined && this.playId.length > 0) {
      const pid = this.playId;
      this.playId = undefined;
      try {
        await this.apiService.stopTranscode(pid);
      } catch (_e) {
        // 忽略
      }
    }
    if (this.stalePlayId !== undefined && this.stalePlayId.length > 0) {
      const stale = this.stalePlayId;
      this.stalePlayId = undefined;
      try {
        await this.apiService.stopTranscode(stale);
      } catch (_e) {
        // 忽略
      }
    }
    this.webClearSubtitle();
    this.restoreOrientation();
    this.engine.release();
  }
}

function fileExt(p: string): string {
  const dot = p.lastIndexOf('.');
  return dot >= 0 ? p.substring(dot) : '';
}

/** 外挂字幕 UTF-8 缓存文件名：源路径 FNV-1a 哈希 + 原扩展名（mpv 按扩展名识别字幕格式） */
function subtitleCacheName(sourcePath: string, ext: string): string {
  let h = 2166136261;
  for (let i = 0; i < sourcePath.length; i++) {
    h ^= sourcePath.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return `${(h >>> 0).toString(16)}${ext.length > 0 ? ext : '.srt'}`;
}

/** 日志脱敏：隐藏访问令牌 */
function maskUrl(url: string): string {
  return url.replace(/((?:accessToken|token)=)[^&]*/g, '$1***');
}

function baseName(p: string): string {
  const normalized = p.replace(/\\/g, '/');
  const slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}

function sleepMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

/** 横竖屏设置（通过 WindowStore 主窗口） */
function windowOrientationSet(landscape: boolean): void {
  const w = WindowStoreHolder.get();
  if (w === undefined) {
    return;
  }
  w.setPreferredOrientation(landscape ? window.Orientation.AUTO_ROTATION_LANDSCAPE_RESTRICTED
    : window.Orientation.PORTRAIT);
}

class WindowStoreHolder {
  static get(): window.Window | undefined {
    return WindowStore.getMainWindow();
  }
}
