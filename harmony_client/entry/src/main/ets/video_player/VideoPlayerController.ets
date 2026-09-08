/**
 * 视频播放器控制器（对齐 Flutter PlayerController 及其 parts 扩展）：
 * 播放初始化流程 / 原画↔转码切换 / 续播与偏好 / 自动保存 / 自动跳过片头片尾 /
 * 音轨字幕切换（VTT 客户端叠层 + 位图烧录转码）/ 循环模式 / 错误恢复。
 * 时间单位统一为毫秒。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../core/localization/L10n';
import { APIClient } from '../core/network/APIClient';
import { PreferencesStore } from '../core/storage/PreferencesStore';
import { ToastUtil } from '../common/ToastUtil';
import { DialogUtil } from '../common/DialogUtil';
import {
  PlayerPlaylistItem, PlayerTrackInfo, PlayerStreamInfo, SubtitleCue,
  PlayerStreamInfo as StreamInfo, DEFAULT_TRANSCODE_QUALITY,
  isBitmapSubtitleCodec, isBitmapSubtitleExt, qualityLabelShort
} from './models/PlayerModels';
import { VideoPlayerApiService } from './service/VideoPlayerApiService';
import { VideoPlayerEngine } from './engine/VideoPlayerEngine';
import { parseWebVtt, findActiveCue } from './subtitle/WebVttParser';
import { asNum, asStr } from '../video/models/VideoModels';
import { WindowStore } from '../common/WindowStore';
import { window } from '@kit.ArkUI';

const TAG = 'PlayerCtrl';
/** P2P 中继下默认转码的大文件阈值（字节，对齐 Flutter 3GB） */
const P2P_RELAY_LARGE_FILE_BYTES = 3 * 1024 * 1024 * 1024;
/** 续播提示阈值：大于 10 秒才提示续播 */
const RESUME_TIP_THRESHOLD_SEC = 10;
/** 转码 seek 防抖 */
const TRANSCODE_SEEK_DEBOUNCE_MS = 300;
/** 播放失败重试上限 */
const MAX_RELOAD_RETRIES = 2;

function generatePlayId(): string {
  const rnd = Math.floor(Math.random() * 0xFFFF).toString(16).padStart(4, '0');
  return `${Date.now().toString(16)}-${rnd}-4${rnd}-a${rnd}-${Date.now().toString(16).slice(-8)}`;
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
  private surfaceId: string = '';
  private playId: string | undefined = undefined;
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
  private speedBeforeBoost: number = 1.0;
  private deviceId: string = '';

  constructor() {
    this.engine.setCallbacks({
      onPrepared: (durationMs: number): void => {
        if (this.sourceDurationSec > 0) {
          this.durationMs = this.sourceDurationSec * 1000;
        } else if (durationMs > 0) {
          this.durationMs = durationMs;
        }
        void this.engine.loadTracks();
      },
      onPlaying: (): void => {
        this.isPlaying = true;
        void this.applyOriginalAudioTrackAfterPlay();
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
        this.videoWidth = width;
        this.videoHeight = height;
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
    const relSec = Math.floor(ms / 1000);
    if (relSec >= this.transcodeBaseSeconds) {
      return Math.max(0, ms);
    }
    return this.transcodeBaseSeconds * 1000 + ms;
  }

  private async initializePlayer(keepPosition: boolean, switchPositionMs: number): Promise<void> {
    const gen = ++this.initGeneration;
    this.clearTranscodeSeekTimer();
    this.isPreparing = true;
    this.isPlaying = false;
    const lastPositionMs = switchPositionMs >= 0 ? switchPositionMs : this.positionMs;
    const originalSeekAfterInitMs =
      this.currentQuality === 'original' && keepPosition ? lastPositionMs : -1;

    if (keepPosition) {
      this.pendingResumePositionMs = -1;
      this.resumeSeekBakedIntoUrlSec = -1;
    }

    // 停止旧转码会话
    const prevPlayId = this.playId;
    this.playId = undefined;
    if (prevPlayId !== undefined && prevPlayId.length > 0) {
      void this.apiService.stopTranscode(prevPlayId);
    }
    // 停掉旧引擎播放（保留实例复用）
    this.engine.stop();
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
    this.videoWidth = 0;
    this.videoHeight = 0;

    if (!keepPosition) {
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
      this.playId = generatePlayId();
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

    const videoUrl = this.currentQuality === 'original'
      ? this.buildOriginalVideoUrl(item, lastPositionMs)
      : this.buildTranscodeVideoUrl(item, keepPosition, lastPositionMs);

    if (this.sourceDurationSec > 0) {
      this.durationMs = this.sourceDurationSec * 1000;
    }

    if (this.isClosedOrGeneration(gen)) {
      this.playId = undefined;
      return;
    }

    this.isPreparing = false;
    this.isInitialized = true;
    this.reloadRetryCount = 0;
    this.isRecoveringFromError = false;

    // 字幕：转码/外挂文本走客户端叠层
    await this.applyClientSubtitleOverlayIfNeeded();

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
      this.engine.open(videoUrl, keepPosition && this.currentQuality !== 'original'
        ? lastPositionMs : -1, true);
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
    this.engine.setSpeed(this.playbackSpeed);
    this.engine.setVolume(this.volume);
    this.isInitialized = true;
    this.isPlaying = true;
    if (shouldShowResumeTip) {
      this.startResumeTip(RESUME_TIP_THRESHOLD_SEC);
    }
    this.resetControlsTimer();
    this.startAutoSave();
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
    return videoUrl;
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
    let subtitlePath = '';
    let burn = false;
    if (this.currentSubtitleTrack.length > 0 && !this.currentIsNoSubtitle) {
      const track = this.findTrackByLabel(this.subtitleTracks, this.currentSubtitleTrack);
      if (track !== undefined) {
        if (track.isExternal) {
          // 文本外挂由客户端 VTT 叠层渲染；位图外挂烧录
          if (isBitmapSubtitleExt(fileExt(track.path))) {
            subtitlePath = track.path;
            burn = true;
          }
        } else if (isBitmapSubtitleCodec(track.codecName)) {
          subtitleIndex = track.mapIndex;
          burn = true;
        }
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
    if (subtitlePath.length > 0) {
      url += `&subtitlePath=${encodeURIComponent(subtitlePath)}`;
    }
    if (burn) {
      url += '&subtitleBurn=true';
    }
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
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
      // 原画：AVPlayer selectTrack
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
    if (this.currentQuality !== 'original') {
      return;
    }
    if (this.originalAudioAppliedGen === this.initGeneration) {
      return;
    }
    this.originalAudioAppliedGen = this.initGeneration;
    if (this.currentAudioTrack.length === 0 || this.currentQuality !== 'original') {
      return;
    }
    const track = this.findTrackByLabel(this.audioTracks, this.currentAudioTrack);
    if (track !== undefined && track.mapIndex > 0) {
      await this.engine.loadTracks();
      await this.engine.selectAudioTrackByOrder(track.mapIndex);
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

  isTextExternalSubtitleLabel(label: string): boolean {
    if (label.length === 0 || this.currentIsNoSubtitle) {
      return false;
    }
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    if (t === undefined || !t.isExternal) {
      return false;
    }
    return !isBitmapSubtitleExt(fileExt(t.path));
  }

  /** 字幕是否需要转码烧录（位图内嵌/位图外挂） */
  private subtitleNeedsBurn(label: string): boolean {
    if (label.length === 0 || label === this.noSubtitleLabel()) {
      return false;
    }
    const t = this.findTrackByLabel(this.subtitleTracks, label);
    if (t === undefined) {
      return false;
    }
    if (t.isExternal) {
      return isBitmapSubtitleExt(fileExt(t.path));
    }
    return isBitmapSubtitleCodec(t.codecName);
  }

  /** 是否使用客户端 VTT 叠层 */
  useClientSubtitleOverlay(): boolean {
    if (this.currentIsNoSubtitle) {
      return false;
    }
    if (this.currentQuality !== 'original') {
      return true;
    }
    // 原画：AVPlayer 不渲染内嵌字幕，文本内嵌也走 VTT；位图需烧录
    return true;
  }

  async setSubtitleTrack(trackLabel: string, force: boolean = false): Promise<void> {
    if (this.currentSubtitleTrack === trackLabel && !force) {
      return;
    }
    const prevNeedsBurn = this.subtitleNeedsBurn(this.currentSubtitleTrack);
    const nextNeedsBurn = this.subtitleNeedsBurn(trackLabel);
    this.currentSubtitleTrack = trackLabel;
    this.savePreference();

    // 位图字幕在原画模式下无法渲染 → 自动切转码烧录
    if (nextNeedsBurn && this.currentQuality === 'original') {
      this.currentQuality = DEFAULT_TRANSCODE_QUALITY;
      await this.initializePlayer(true, this.absolutePlaybackPositionMs());
      return;
    }
    // 从烧录切回非烧录且当前是转码 → 重建会话去掉烧录
    if (prevNeedsBurn && !nextNeedsBurn && this.currentQuality !== 'original') {
      await this.initializePlayer(true, this.absolutePlaybackPositionMs());
      await this.loadWebSubtitleIfNeeded(true);
      return;
    }
    if (this.currentIsNoSubtitle) {
      this.webClearSubtitle();
      return;
    }
    await this.loadWebSubtitleIfNeeded(true);
  }

  /** 打开/切换后应用客户端字幕叠层 */
  private async applyClientSubtitleOverlayIfNeeded(): Promise<void> {
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
      return;
    }
    this.webSubtitleLoading = true;
    this.webSubtitleCacheKey = key;
    try {
      const body = await this.apiService.getSubtitleVtt(item.path, idx,
        track.isExternal ? track.path : '');
      if (body === undefined) {
        this.webSubtitleCues = [];
        this.webActiveSubtitleText = '';
        return;
      }
      this.webSubtitleCues = parseWebVtt(body);
      this.webUpdateActiveCue();
    } catch (_e) {
      this.webSubtitleCues = [];
      this.webActiveSubtitleText = '';
    } finally {
      this.webSubtitleLoading = false;
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
    if (this.isPlaying) {
      this.engine.pause();
    } else {
      this.engine.play();
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
    // 单曲循环/列表播放完成检测
    if (this.durationMs > 0 && this.positionMs >= this.durationMs - 1000 && !this.isPlaying) {
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
        this.isRecoveringFromError = true;
        this.isInitialized = false;
        this.reloadRetryCount++;
        await sleepMs(300);
        this.isRecoveringFromError = false;
        if (this.isClosingPlayer) {
          return;
        }
        await this.initializePlayer(true, this.positionMs);
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

  attachSurface(surfaceId: string): void {
    this.surfaceId = surfaceId;
    this.engine.setSurface(surfaceId);
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
    this.webClearSubtitle();
    this.restoreOrientation();
    this.engine.release();
  }
}

function fileExt(p: string): string {
  const dot = p.lastIndexOf('.');
  return dot >= 0 ? p.substring(dot) : '';
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
