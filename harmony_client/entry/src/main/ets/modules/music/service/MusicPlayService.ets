/**
 * 音乐全局播放服务（对齐 Flutter MusicPlayServiceController + _MusicAudioHandler）：
 * - 队列/循环（顺序/列表/单曲/随机）/音量静音/唱片样式
 * - 歌词：详情接口获取 + 无歌词时自动搜索匹配写入
 * - AVSession：锁屏/控制中心媒体控制，元数据与播放状态同步
 * - 长时任务：后台连续播放（AUDIO_PLAYBACK）
 * - 缓存：MusicAudioCacheService 断点续传下载，失败回退网络 URL
 */

import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import wantAgent from '@ohos.app.ability.wantAgent';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { WindowStore } from '../../../common/WindowStore';
import { MusicAudioCacheProgress, MusicAudioCacheService, MusicAudioCacheStats, MusicPlaySource } from './MusicAudioCache';
import { MusicPlayerEngine } from './MusicPlayerEngine';
import { MusicListApiService, MusicListQuery } from '../services/MusicApiServices';
import { LyricSearchItem, MusicApiResult, MusicListItem, MusicListPagedResult } from '../models/MusicModels';

const TAG = 'MusicPlayService';

export enum MusicLoopMode {
  sequence = 0,
  listLoop = 1,
  singleLoop = 2,
  shuffle = 3
}

/** 分页队列加载（对齐 Flutter MusicPlaylistPaging） */
export interface MusicPlaylistPaging {
  hasMore: () => boolean;
  loadMore: () => Promise<MusicListItem[]>;
}

export type MusicProgressListener = (positionMs: number, durationMs: number, bufferedMs: number) => void;

/** LRC 解析行（供全屏歌词使用） */
export interface LyricLine {
  timeMs: number;
  text: string;
}

/** LRC 歌词解析（[mm:ss.xx] 多时间标签支持） */
export function parseLrc(lrcText: string): LyricLine[] {
  const out: LyricLine[] = [];
  const lines = lrcText.split('\n');
  for (const raw of lines) {
    const line = raw.trim();
    if (line.length === 0) {
      continue;
    }
    const times: number[] = [];
    const re = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
    let m = re.exec(line);
    while (m !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      let frac = 0;
      if (m[3] !== undefined) {
        const digits = m[3].length;
        const v = parseInt(m[3], 10);
        frac = digits === 1 ? v * 100 : digits === 2 ? v * 10 : v;
      }
      times.push(min * 60000 + sec * 1000 + frac);
      m = re.exec(line);
    }
    if (times.length === 0) {
      continue;
    }
    const text = line.replace(re, '').trim();
    for (const t of times) {
      out.push({ timeMs: t, text: text });
    }
  }
  out.sort((a: LyricLine, b: LyricLine): number => a.timeMs - b.timeMs);
  return out;
}

@ObservedV2
export class MusicPlayService {
  private static instance: MusicPlayService | undefined = undefined;

  static getInstance(): MusicPlayService {
    if (MusicPlayService.instance === undefined) {
      MusicPlayService.instance = new MusicPlayService();
    }
    return MusicPlayService.instance;
  }

  /** 唱片样式资源（rawfile/music/icons） */
  static readonly discAssets: string[] = [
    'music/icons/player_disc1.png',
    'music/icons/player_disc2.png',
    'music/icons/player_disc3.png'
  ];

  // ===== 可观察状态 =====
  @Trace playlist: MusicListItem[] = [];
  @Trace currentIndex: number = 0;
  @Trace isPlaying: boolean = false;
  @Trace positionMs: number = 0;
  @Trace durationMs: number = 0;
  @Trace bufferedMs: number = 0;
  @Trace volume: number = 1.0;
  @Trace loopMode: MusicLoopMode = MusicLoopMode.sequence;
  @Trace isReady: boolean = false;
  @Trace discStyleIndex: number = 0;
  @Trace currentLyrics: string = '';

  @Trace audioCacheEnabled: boolean = true;
  @Trace audioCacheMaxItems: number = 300;
  @Trace isDownloading: boolean = false;
  @Trace downloadProgress: number = 0;
  @Trace downloadReceivedBytes: number = 0;
  @Trace downloadTotalBytes: number = 0;
  @Trace downloadingFileHash: string = '';

  // ===== 内部状态 =====
  private engine: MusicPlayerEngine = new MusicPlayerEngine();
  private volumeBeforeMute: number = 1.0;
  private isCompleted: boolean = false;
  private desiredPlaying: boolean = false;
  private isSkippingTrack: boolean = false;
  private suppressCompletedUntilMs: number = 0;
  private isOpeningTrack: boolean = false;
  private initPromise: Promise<void> | undefined;
  private progressListeners: MusicProgressListener[] = [];
  private posTimer: number = -1;
  private stallTimer: number = -1;
  private paging: MusicPlaylistPaging | undefined = undefined;
  private pagingToken: number = 0;
  private pagingLoading: boolean = false;
  private shuffleHistory: number[] = [];
  private rebuildToken: number = 0;
  private detailFetchToken: number = 0;
  private detailCache: Map<string, MusicListItem> = new Map();
  private lyricsCache: Map<string, string> = new Map();
  private autoLyricTried: Set<string> = new Set();
  private lastRecoveryMs: number = 0;
  private lastPlaylistAccessToken: string = '';

  // ===== AVSession / 后台任务 =====
  private session: avSession.AVSession | undefined = undefined;
  private lastSyncPlaying: boolean | undefined = undefined;
  private lastSyncState: string = '';
  private lastSyncIndex: number = -1;
  private lastPositionSyncMs: number = 0;
  private bgTaskStarted: boolean = false;
  private syncedDurationKey: string = '';

  private constructor() {
  }

  /** 懒初始化（首次播放时调用）：AVSession + 偏好加载 + 进度轮询 */
  private async ensureInit(): Promise<void> {
    if (this.initPromise !== undefined) {
      try {
        await this.initPromise;
      } catch (_e) {
        this.initPromise = undefined;
        await this.ensureInit();
      }
      return;
    }
    const future = this.doInit();
    this.initPromise = future;
    try {
      await future;
    } catch (e) {
      this.initPromise = undefined;
      hilog.error(0x0000, TAG, 'init failed: %{public}s', JSON.stringify(e));
    }
  }

  private async doInit(): Promise<void> {
    const cache = MusicAudioCacheService.getInstance();
    await cache.init(WindowStore.appContext!);
    cache.updateOptions(this.audioCacheEnabled, this.audioCacheMaxItems);
    this.audioCacheEnabled = cache.enabled;
    this.audioCacheMaxItems = cache.maxItems;
    this.engine.setCallbacks({
      onPrepared: (durationMs: number): void => {
        if (durationMs > 0 && durationMs !== this.durationMs) {
          this.durationMs = durationMs;
          this.syncMediaItem(this.currentIndex, true);
        }
      },
      onPlaying: (): void => {
        this.isPlaying = true;
        this.startBgTask();
        this.syncPlaybackState('playing');
      },
      onPaused: (): void => {
        this.isPlaying = false;
        this.syncPlaybackState('paused');
      },
      onCompleted: (): void => {
        // 由轮询的 completed 判定统一处理（对齐 Flutter）
      },
      onError: (_message: string): void => {
        this.attemptRecovery();
      },
      onBuffered: (bufferedMs: number): void => {
        this.bufferedMs = bufferedMs;
      },
      onBufferingChange: (_buffering: boolean): void => {
        this.scheduleStallRecoveryIfNeeded();
      }
    });
    this.loadPrefs();
    await this.setupSession();
    this.startPositionPolling();
    this.isReady = true;
  }

  private loadPrefs(): void {
    const store = PreferencesStore.getInstance();
    this.discStyleIndex = Math.min(Math.max(store.getInt(CacheKeys.MUSIC_DISC_STYLE_INDEX, 0), 0),
      MusicPlayService.discAssets.length - 1);
    const loop = store.getInt(CacheKeys.MUSIC_LOOP_MODE_INDEX, 0);
    if (loop >= 0 && loop <= 3) {
      this.loopMode = loop as MusicLoopMode;
    }
    const volPercent = store.getInt(CacheKeys.MUSIC_VOLUME, 100);
    this.volume = Math.min(Math.max(volPercent / 100, 0), 1);
    const beforeMute = store.getInt(CacheKeys.MUSIC_VOLUME_BEFORE_MUTE, 100) / 100;
    if (beforeMute > 0.01) {
      this.volumeBeforeMute = Math.min(Math.max(beforeMute, 0), 1);
    }
    this.engine.setVolume(this.volume);
  }

  // ================= AVSession =================

  private async setupSession(): Promise<void> {
    const ctx = WindowStore.appContext;
    if (ctx === undefined) {
      return;
    }
    try {
      if (this.session === undefined) {
        this.session = await avSession.createAVSession(ctx, 'nascab_music', 'audio');
        this.session.on('play', (): void => {
          this.play();
        });
        this.session.on('pause', (): void => {
          this.pause();
        });
        this.session.on('playNext', (): void => {
          this.playNext(true);
        });
        this.session.on('playPrevious', (): void => {
          this.playPrevious(true);
        });
        this.session.on('seek', (time: number): void => {
          this.seekTo(time);
        });
        this.session.on('stop', (): void => {
          this.stop();
        });
        await this.session.activate();
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'setupSession failed: %{public}s', JSON.stringify(e));
    }
  }

  private playbackStateEnum(): avSession.PlaybackState {
    if (this.isCompleted) {
      return avSession.PlaybackState.PLAYBACK_STATE_STOP;
    }
    if (this.isDownloading) {
      return avSession.PlaybackState.PLAYBACK_STATE_BUFFERING;
    }
    return this.isPlaying
      ? avSession.PlaybackState.PLAYBACK_STATE_PLAY
      : avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
  }

  private loopModeEnum(): avSession.LoopMode {
    switch (this.loopMode) {
      case MusicLoopMode.singleLoop:
        return avSession.LoopMode.LOOP_MODE_SINGLE;
      case MusicLoopMode.listLoop:
        return avSession.LoopMode.LOOP_MODE_LIST;
      case MusicLoopMode.shuffle:
        return avSession.LoopMode.LOOP_MODE_SHUFFLE;
      default:
        return avSession.LoopMode.LOOP_MODE_SEQUENCE;
    }
  }

  private async syncMediaItem(index: number, forceUpdate: boolean = false): Promise<void> {
    const s = this.session;
    if (s === undefined) {
      return;
    }
    if (index < 0 || index >= this.playlist.length) {
      return;
    }
    const item = this.playlist[index];
    const durationKey = `${index}:${item.displayTitle}:${item.artist}:${this.durationMs}`;
    if (!forceUpdate && durationKey === this.syncedDurationKey) {
      return;
    }
    this.syncedDurationKey = durationKey;
    try {
      const playUrl = await this.buildPlayUrl(item);
      const coverUrl = await this.buildCoverUrl(item);
      const meta: avSession.AVMetadata = {
        assetId: playUrl,
        title: item.displayTitle,
        duration: this.durationMs
      };
      const artist = item.artist.trim();
      if (artist.length > 0) {
        meta.artist = artist;
      }
      const album = item.album.trim();
      if (album.length > 0) {
        meta.album = album;
      }
      if (coverUrl.length > 0) {
        meta.mediaImage = coverUrl;
      }
      await s.setAVMetadata(meta);
    } catch (e) {
      hilog.error(0x0000, TAG, 'syncMediaItem failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 播放状态同步（对齐 Flutter _syncPlaybackState：关键变化立即更新，位置 1s 节流） */
  private syncPlaybackState(stateKey: string): void {
    const s = this.session;
    if (s === undefined) {
      return;
    }
    const playing = this.isPlaying;
    const index = this.currentIndex;
    const playingChanged = this.lastSyncPlaying !== playing;
    const stateChanged = this.lastSyncState !== stateKey;
    const indexChanged = this.lastSyncIndex !== index;
    const criticalChanged = playingChanged || stateChanged || indexChanged;
    const now = Date.now();
    const shouldUpdatePosition = now - this.lastPositionSyncMs >= 1000;
    if (!(criticalChanged || shouldUpdatePosition)) {
      return;
    }
    this.lastSyncPlaying = playing;
    this.lastSyncState = stateKey;
    this.lastSyncIndex = index;
    this.lastPositionSyncMs = now;
    const ps: avSession.AVPlaybackState = {
      state: this.playbackStateEnum(),
      speed: 1.0,
      loopMode: this.loopModeEnum(),
      position: { elapsedTime: Math.max(0, this.positionMs), updateTime: Date.now() },
      bufferedTime: Math.max(0, this.bufferedMs)
    };
    s.setAVPlaybackState(ps).catch((e: Object): void => {
      hilog.error(0x0000, TAG, 'setAVPlaybackState failed: %{public}s', JSON.stringify(e));
    });
  }

  // ================= 后台长时任务 =================

  private async startBgTask(): Promise<void> {
    if (this.bgTaskStarted || WindowStore.appContext === undefined) {
      return;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: WindowStore.appContext.abilityInfo.bundleName,
          abilityName: WindowStore.appContext.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(WindowStore.appContext,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      this.bgTaskStarted = true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'startBgTask failed: %{public}s', JSON.stringify(e));
    }
  }

  private async stopBgTask(): Promise<void> {
    if (!this.bgTaskStarted || WindowStore.appContext === undefined) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(WindowStore.appContext);
    } catch (e) {
      hilog.error(0x0000, TAG, 'stopBgTask failed: %{public}s', JSON.stringify(e));
    }
    this.bgTaskStarted = false;
  }

  // ================= 队列操作 =================

  private resolvePlayablePath(item: MusicListItem): string {
    return item.resolvePlayablePath();
  }

  private isPlayableItem(item: MusicListItem): boolean {
    return this.resolvePlayablePath(item).trim().length > 0;
  }

  private filterPlayable(items: MusicListItem[]): MusicListItem[] {
    return items.filter((e: MusicListItem): boolean => this.isPlayableItem(e));
  }

  private buildPaging(query: MusicListQuery): MusicPlaylistPaging {
    let page = query.page;
    const pageSize = query.pageSize;
    let more = false;
    return {
      hasMore: (): boolean => more,
      loadMore: (): Promise<MusicListItem[]> => {
        if (!more) {
          return Promise.resolve([]);
        }
        const q: MusicListQuery = {
          page: page + 1, pageSize: pageSize, listType: query.listType, listId: query.listId,
          seriesIndexId: query.seriesIndexId, collectionId: query.collectionId,
          isFavorite: query.isFavorite, isHistory: query.isHistory, search: query.search,
          artists: query.artists, albums: query.albums, genres: query.genres,
          sourceList: query.sourceList, sortBy: query.sortBy, sortOrder: query.sortOrder
        };
        return MusicListApiService.listPaged(q).then((res: MusicApiResult<MusicListPagedResult>): MusicListItem[] => {
          if (!res.success || res.data === undefined) {
            return [];
          }
          page = res.data.pagination.page;
          more = res.data.pagination.hasNextPage;
          return res.data.items;
        });
      }
    };
  }

  async playFromList(items: MusicListItem[], startItem: MusicListItem, autoPlay: boolean = true,
    query: MusicListQuery | undefined = undefined): Promise<void> {
    const playable = this.filterPlayable(items);
    if (playable.length === 0) {
      await this.handleNoPlayableItems();
      return;
    }
    const startPath = this.resolvePlayablePath(startItem).trim();
    let startInOriginal = startItem.id > 0
      ? items.findIndex((e: MusicListItem): boolean => e.id === startItem.id)
      : (startPath.length > 0
        ? items.findIndex((e: MusicListItem): boolean => this.resolvePlayablePath(e).trim() === startPath)
        : -1);
    let resolvedStart = -1;
    if (startInOriginal >= 0 && startInOriginal < items.length) {
      for (let i = startInOriginal; i < items.length; i++) {
        if (this.isPlayableItem(items[i])) {
          resolvedStart = i;
          break;
        }
      }
      if (resolvedStart < 0) {
        resolvedStart = items.findIndex((e: MusicListItem): boolean => this.isPlayableItem(e));
      }
    } else {
      resolvedStart = items.findIndex((e: MusicListItem): boolean => this.isPlayableItem(e));
    }
    const resolvedItem = resolvedStart >= 0 ? items[resolvedStart] : undefined;
    const resolvedPath = resolvedItem === undefined ? '' : this.resolvePlayablePath(resolvedItem).trim();
    let idx = 0;
    if (resolvedItem !== undefined) {
      idx = resolvedItem.id > 0
        ? playable.findIndex((e: MusicListItem): boolean => e.id === resolvedItem.id)
        : (resolvedPath.length > 0
          ? playable.findIndex((e: MusicListItem): boolean => this.resolvePlayablePath(e).trim() === resolvedPath)
          : -1);
      if (idx < 0) {
        idx = 0;
      }
    }
    await this.setPlaylist(playable, idx, autoPlay,
      query !== undefined ? this.buildPaging(query) : undefined);
  }

  async setPlaylist(items: MusicListItem[], startIndex: number = 0, autoPlay: boolean = true,
    paging: MusicPlaylistPaging | undefined = undefined): Promise<void> {
    const playable = this.filterPlayable(items);
    if (playable.length === 0) {
      await this.handleNoPlayableItems();
      return;
    }
    await this.ensureInit();
    this.paging = paging;
    this.pagingToken++;
    this.pagingLoading = false;
    this.shuffleHistory = [];
    this.playlist = playable;
    const safeIndex = Math.min(Math.max(startIndex, 0), playable.length - 1);
    this.currentIndex = safeIndex;
    this.syncedDurationKey = '';
    await this.refreshDetailForIndex(safeIndex);
    if (autoPlay) {
      await this.openTrack(safeIndex, true, 0);
    } else {
      await this.openTrack(safeIndex, false, 0);
    }
    this.maybePrefetchNextPage(safeIndex);
  }

  async playAt(index: number): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    await this.ensureInit();
    this.desiredPlaying = true;
    await this.ensurePlaylistUpToDate();
    const safeIndex = Math.min(Math.max(index, 0), this.playlist.length - 1);
    const prev = this.currentIndex;
    this.currentIndex = safeIndex;
    this.syncedDurationKey = '';
    this.syncMediaItem(safeIndex);
    this.syncPlaybackState('index');
    await this.refreshDetailForIndex(safeIndex);
    await this.openTrack(safeIndex, true, 0);
    this.handleIndexChangeForPaging(prev, safeIndex);
    this.maybePrefetchNextPage(safeIndex);
  }

  async play(): Promise<void> {
    await this.ensureInit();
    this.desiredPlaying = true;
    if (this.playlist.length === 0) {
      return;
    }
    if (this.isCompleted) {
      this.engine.seekTo(0);
      this.isCompleted = false;
      this.positionMs = 0;
    }
    this.engine.play();
    this.syncPlaybackState('play');
  }

  async pause(): Promise<void> {
    await this.ensureInit();
    this.desiredPlaying = false;
    this.engine.pause();
    this.syncPlaybackState('pause');
  }

  async resume(): Promise<void> {
    this.desiredPlaying = true;
    await this.play();
  }

  async stop(): Promise<void> {
    await this.ensureInit();
    this.desiredPlaying = false;
    this.engine.pause();
    this.engine.seekTo(0);
    this.positionMs = 0;
    this.isCompleted = false;
    this.syncPlaybackState('stop');
    await this.stopBgTask();
  }

  async playNext(forcePlay: boolean = false): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    await this.ensureInit();
    this.suppressCompletedUntilMs = Date.now() + 4000;
    this.isSkippingTrack = true;
    try {
      const wasPlaying = forcePlay || this.engine.isPlaying();
      this.desiredPlaying = wasPlaying;
      const prev = this.currentIndex;
      const next = this.resolveNextIndex(true);
      if (next === undefined) {
        return;
      }
      if (this.loopMode === MusicLoopMode.shuffle) {
        this.shuffleHistory.push(prev);
      }
      this.currentIndex = next;
      this.syncedDurationKey = '';
      this.syncMediaItem(next);
      this.syncPlaybackState('index');
      await this.refreshDetailForIndex(next);
      await this.openTrack(next, wasPlaying, 0);
      this.handleIndexChangeForPaging(prev, next);
      this.maybePrefetchNextPage(next);
    } finally {
      this.isSkippingTrack = false;
      this.syncPlaybackState('skip');
    }
  }

  async playPrevious(forcePlay: boolean = false): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    await this.ensureInit();
    this.suppressCompletedUntilMs = Date.now() + 4000;
    this.isSkippingTrack = true;
    try {
      const wasPlaying = forcePlay || this.engine.isPlaying();
      this.desiredPlaying = wasPlaying;
      const prev = this.currentIndex;
      const next = this.resolveNextIndex(false);
      if (next === undefined) {
        return;
      }
      this.currentIndex = next;
      this.syncedDurationKey = '';
      this.syncMediaItem(next);
      this.syncPlaybackState('index');
      await this.refreshDetailForIndex(next);
      await this.openTrack(next, wasPlaying, 0);
      this.handleIndexChangeForPaging(prev, next);
      this.maybePrefetchNextPage(next);
    } finally {
      this.isSkippingTrack = false;
      this.syncPlaybackState('skip');
    }
  }

  seekTo(ms: number): void {
    const d = this.durationMs;
    const safe = d <= 0 ? Math.max(0, ms) : Math.min(Math.max(0, ms), d);
    this.engine.seekTo(safe);
    this.positionMs = safe;
    this.syncPlaybackState('seek');
  }

  async setVolume(value: number): Promise<void> {
    const next = Math.min(Math.max(value, 0), 1);
    this.volume = next;
    this.engine.setVolume(next);
    const store = PreferencesStore.getInstance();
    await store.setInt(CacheKeys.MUSIC_VOLUME, Math.round(next * 100));
    if (next > 0.01) {
      this.volumeBeforeMute = next;
      await store.setInt(CacheKeys.MUSIC_VOLUME_BEFORE_MUTE, Math.round(next * 100));
    }
  }

  async toggleMute(): Promise<void> {
    if (this.volume > 0.01) {
      this.volumeBeforeMute = this.volume;
      await PreferencesStore.getInstance().setInt(CacheKeys.MUSIC_VOLUME_BEFORE_MUTE,
        Math.round(this.volume * 100));
      await this.setVolume(0);
      return;
    }
    const restore = this.volumeBeforeMute > 0.01 ? this.volumeBeforeMute : 1.0;
    await this.setVolume(restore);
  }

  async setLoopMode(mode: MusicLoopMode): Promise<void> {
    if (this.loopMode === mode) {
      return;
    }
    this.loopMode = mode;
    await PreferencesStore.getInstance().setInt(CacheKeys.MUSIC_LOOP_MODE_INDEX, mode as number);
    this.applyLoopModeToEngine();
    this.syncPlaybackState('loop');
  }

  async nextDiscStyle(): Promise<void> {
    const max = MusicPlayService.discAssets.length;
    this.discStyleIndex = max <= 0 ? 0 : (this.discStyleIndex + 1) % max;
    await PreferencesStore.getInstance().setInt(CacheKeys.MUSIC_DISC_STYLE_INDEX, this.discStyleIndex);
  }

  get discAsset(): string {
    const assets = MusicPlayService.discAssets;
    const idx = Math.min(Math.max(this.discStyleIndex, 0), assets.length - 1);
    return assets[idx];
  }

  // ===== 音频缓存设置（对齐 Flutter setAudioCacheEnabled 等，缓存设置页用） =====

  async setAudioCacheEnabled(v: boolean): Promise<void> {
    this.audioCacheEnabled = v;
    MusicAudioCacheService.getInstance().updateOptions(this.audioCacheEnabled, this.audioCacheMaxItems);
    await PreferencesStore.getInstance().setBool(CacheKeys.MUSIC_AUDIO_CACHE_ENABLED, v);
  }

  async setAudioCacheMaxItems(v: number): Promise<void> {
    this.audioCacheMaxItems = v;
    MusicAudioCacheService.getInstance().updateOptions(this.audioCacheEnabled, this.audioCacheMaxItems);
    await PreferencesStore.getInstance().setInt(CacheKeys.MUSIC_AUDIO_CACHE_MAX_ITEMS, v);
  }

  getAudioCacheStats(): MusicAudioCacheStats {
    return MusicAudioCacheService.getInstance().getStats();
  }

  clearAudioCache(): void {
    MusicAudioCacheService.getInstance().clearAll();
  }

  addProgressListener(listener: MusicProgressListener): void {
    if (this.progressListeners.indexOf(listener) < 0) {
      this.progressListeners.push(listener);
    }
  }

  removeProgressListener(listener: MusicProgressListener): void {
    const i = this.progressListeners.indexOf(listener);
    if (i >= 0) {
      this.progressListeners.splice(i, 1);
    }
  }

  get currentDiscUri(): string {
    return `resource://RAWFILE_${this.discAsset}`;
  }

  // ================= 内部：打开曲目 =================

  private applyLoopModeToEngine(): void {
    this.engine.setLooping(this.loopMode === MusicLoopMode.singleLoop);
  }

  private resolveNextIndex(forward: boolean): number | undefined {
    if (this.playlist.length === 0) {
      return undefined;
    }
    const idx = Math.min(Math.max(this.currentIndex, 0), this.playlist.length - 1);
    const mode = this.loopMode;
    if (mode === MusicLoopMode.shuffle) {
      if (!forward && this.shuffleHistory.length > 0) {
        return Math.min(Math.max(this.shuffleHistory.pop() ?? idx, 0), this.playlist.length - 1);
      }
      if (this.playlist.length <= 1) {
        return idx;
      }
      let next = idx;
      let guard = 0;
      while (next === idx && guard++ < 10) {
        next = Math.floor(Math.random() * this.playlist.length);
      }
      return next;
    }
    if (forward) {
      if (idx < this.playlist.length - 1) {
        return idx + 1;
      }
      return mode === MusicLoopMode.listLoop ? 0 : undefined;
    } else {
      if (idx > 0) {
        return idx - 1;
      }
      return mode === MusicLoopMode.listLoop ? this.playlist.length - 1 : undefined;
    }
  }

  private async handleNoPlayableItems(): Promise<void> {
    this.playlist = [];
    this.currentIndex = 0;
    this.currentLyrics = '';
    this.positionMs = 0;
    this.durationMs = 0;
    this.bufferedMs = 0;
    this.paging = undefined;
    this.pagingToken++;
    this.pagingLoading = false;
    this.shuffleHistory = [];
    this.desiredPlaying = false;
    await this.engine.release();
    this.isPlaying = false;
    this.syncedDurationKey = '';
    this.syncPlaybackState('empty');
    await this.stopBgTask();
  }

  private resolveExt(item: MusicListItem): string {
    const e = item.ext.trim();
    if (e.length > 0) {
      return e;
    }
    const name = item.filename.trim();
    const dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1);
    }
    return 'dat';
  }

  private preferTranscodeByExt(ext: string): boolean {
    const e = ext.trim().toLowerCase();
    return e === 'ape' || e === 'wma';
  }

  private async buildPlayUrl(item: MusicListItem): Promise<string> {
    const path = this.resolvePlayablePath(item);
    return ApiUrls.getRawFileUrl(path, true, 'download');
  }

  private async buildTranscodeUrl(item: MusicListItem): Promise<string> {
    return ApiUrls.getMusicTranscodeUrl(this.resolvePlayablePath(item), true, 'download');
  }

  private async buildCoverUrl(item: MusicListItem): Promise<string> {
    const api = APIClient.getInstance();
    if (api.isP2pMode || item.hasInnerCover !== 1) {
      return '';
    }
    return ApiUrls.getMusicCoverUrl(item.coverFilePath(), 500);
  }

  private onCacheProgress(token: number, hash: string, p: MusicAudioCacheProgress): void {
    if (token !== this.rebuildToken) {
      return;
    }
    if (p.progress >= 1) {
      this.isDownloading = false;
      this.downloadingFileHash = '';
      return;
    }
    this.isDownloading = true;
    this.downloadingFileHash = hash;
    this.downloadReceivedBytes = p.received;
    this.downloadTotalBytes = p.total;
    this.downloadProgress = p.progress;
  }

  /** 打开曲目（缓存 → 本地 fd；失败回退 URL；原格式失败转码重试） */
  private async openTrack(index: number, autoPlay: boolean, initialPositionMs: number = 0): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    const safeIndex = Math.min(Math.max(index, 0), this.playlist.length - 1);
    const token = ++this.rebuildToken;
    this.isOpeningTrack = true;
    this.suppressCompletedUntilMs = Date.now() + 4000;
    this.syncPlaybackState('opening');
    try {
      await this.engine.release();
      if (token !== this.rebuildToken) {
        return;
      }
      const item = this.playlist[safeIndex];
      const ext = this.resolveExt(item);
      const hash = item.fileHash.trim();
      const preferTranscode = this.preferTranscodeByExt(ext);
      const cache = MusicAudioCacheService.getInstance();
      const cacheEnabled = cache.enabled && hash.length > 0;

      const openOnce = async (transcode: boolean): Promise<boolean> => {
        const cacheHash = MusicAudioCacheService.cacheKey(hash, transcode ? 'mp3' : ext, transcode);
        let source: MusicPlaySource;
        try {
          const url = transcode ? await this.buildTranscodeUrl(item) : await this.buildPlayUrl(item);
          source = await cache.prepareSource(url, cacheHash, transcode ? 'mp3' : ext, transcode,
            (p: MusicAudioCacheProgress): void => this.onCacheProgress(token, hash, p));
        } catch (_e) {
          const url = transcode ? await this.buildTranscodeUrl(item) : await this.buildPlayUrl(item);
          source = new MusicPlaySource();
          source.url = url;
          source.fileExt = transcode ? 'mp3' : ext;
        }
        if (token !== this.rebuildToken) {
          return false;
        }
        if (source.filePath.trim().length === 0 && source.url.trim().length === 0) {
          return false;
        }
        this.lastPlaylistAccessToken = APIClient.getInstance().accessToken ?? '';
        await this.engine.open(source, initialPositionMs, autoPlay);
        this.applyLoopModeToEngine();
        this.engine.setVolume(this.volume);
        return true;
      };

      let opened = false;
      try {
        opened = await openOnce(preferTranscode);
      } catch (_e) {
        opened = false;
      }
      if (!opened && token === this.rebuildToken) {
        if (cacheEnabled && preferTranscode === false) {
          // 原格式失败 → 转码重试
          try {
            opened = await openOnce(true);
          } catch (_e) {
            opened = false;
          }
        }
      }
      if (!opened || token !== this.rebuildToken) {
        this.isOpeningTrack = false;
        this.syncPlaybackState('open_failed');
        return;
      }

      this.isCompleted = false;
      this.positionMs = initialPositionMs;
      this.syncMediaItem(safeIndex);
      this.syncPlaybackState('opened');
      this.isOpeningTrack = false;
      if (autoPlay) {
        this.desiredPlaying = true;
        this.engine.play();
      }
    } finally {
      if (token === this.rebuildToken) {
        this.isOpeningTrack = false;
        this.syncPlaybackState('open_done');
      }
    }
  }

  // ================= 内部：详情 / 歌词 =================

  private async refreshDetailForIndex(index: number): Promise<void> {
    if (index < 0 || index >= this.playlist.length) {
      return;
    }
    const existing = this.playlist[index];
    const filePath = this.resolvePlayablePath(existing).trim();
    if (filePath.length === 0) {
      if (index === this.currentIndex) {
        this.currentLyrics = '';
      }
      return;
    }
    const indexId = !existing.isSeries && existing.id > 0 ? existing.id : 0;
    if (indexId > 0) {
      MusicListApiService.refreshHistoryByIndexId(indexId);
    } else {
      MusicListApiService.refreshHistoryByFilePath(filePath);
    }
    const cachedDetail = this.detailCache.get(filePath);
    const cachedLyrics = this.lyricsCache.get(filePath);
    if (cachedDetail !== undefined || cachedLyrics !== undefined) {
      if (cachedDetail !== undefined) {
        const fromFile = existing.isFromFile || existing.showType.trim().toLowerCase() === 'file_browser';
        const merged = cachedDetail;
        merged.isFavorite = existing.isFavorite;
        if (fromFile) {
          merged.id = 0;
          merged.showType = existing.showType;
          merged.isFromFile = true;
        } else {
          merged.isFromFile = existing.isFromFile;
        }
        this.playlist[index] = merged;
        this.syncMediaItem(index);
      }
      if (index === this.currentIndex) {
        const lyricText = (cachedLyrics ?? '').trim();
        this.currentLyrics = lyricText;
        if (lyricText.length === 0) {
          this.tryAutoSetLyricIfNoLyric(filePath, this.playlist[index]);
        }
      }
      return;
    }
    const token = ++this.detailFetchToken;
    const res = await MusicListApiService.getDetail(filePath);
    if (token !== this.detailFetchToken) {
      return;
    }
    if (!res.success || res.data === undefined) {
      if (index === this.currentIndex) {
        this.currentLyrics = '';
      }
      return;
    }
    const detail = res.data.item;
    const lyrics = res.data.lyrics.trim();
    if (detail.filename.trim().length > 0) {
      const fromFile = existing.isFromFile || existing.showType.trim().toLowerCase() === 'file_browser';
      detail.isFavorite = existing.isFavorite;
      if (fromFile) {
        detail.id = 0;
        detail.showType = existing.showType;
        detail.isFromFile = true;
      } else {
        detail.isFromFile = existing.isFromFile;
      }
      this.playlist[index] = detail;
      this.detailCache.set(filePath, detail);
      this.syncMediaItem(index);
    }
    this.lyricsCache.set(filePath, lyrics);
    if (index === this.currentIndex) {
      this.currentLyrics = lyrics;
      if (lyrics.length === 0) {
        this.tryAutoSetLyricIfNoLyric(filePath, this.playlist[index]);
      }
    }
  }

  applyLyricOverride(musicPath: string, lyricText: string): void {
    const p = musicPath.trim();
    if (p.length === 0) {
      return;
    }
    const next = lyricText.trim();
    this.lyricsCache.set(p, next);
    const idx = this.currentIndex;
    if (idx < 0 || idx >= this.playlist.length) {
      return;
    }
    const currentPath = this.resolvePlayablePath(this.playlist[idx]).trim();
    if (currentPath === p) {
      this.currentLyrics = next;
    }
  }

  private async maybeAutoSetLyricForCurrent(): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    const idx = this.currentIndex;
    if (idx < 0 || idx >= this.playlist.length) {
      return;
    }
    const filePath = this.resolvePlayablePath(this.playlist[idx]).trim();
    if (filePath.length === 0) {
      return;
    }
    const cached = this.lyricsCache.get(filePath) ?? '';
    if (cached.trim().length > 0) {
      return;
    }
    if (this.durationMs <= 0) {
      return;
    }
    this.tryAutoSetLyricIfNoLyric(filePath, this.playlist[idx]);
  }

  private async tryAutoSetLyricIfNoLyric(filePath: string, item: MusicListItem): Promise<void> {
    const p = filePath.trim();
    if (p.length === 0 || this.autoLyricTried.has(p)) {
      return;
    }
    const cached = (this.lyricsCache.get(p) ?? '').trim();
    if (cached.length > 0) {
      return;
    }
    const expectedMs = this.durationMs > 0 ? this.durationMs : Math.max(0, item.duration) * 1000;
    if (expectedMs <= 0) {
      return;
    }
    const keyword = this.buildLyricSearchKeyword(item, p);
    if (keyword.length === 0) {
      return;
    }
    this.autoLyricTried.add(p);
    const results = await MusicListApiService.searchLyric(keyword);
    if (results.length === 0) {
      return;
    }
    const stemNorm = normalizeForContains(fileStem(p));
    const matched = results.filter((it: LyricSearchItem): boolean => {
      return isHighLyricMatch(it, stemNorm, expectedMs);
    });
    if (matched.length === 0) {
      return;
    }
    const chosen = matched[0];
    const lrc = chosen.lrc.trim();
    if (lrc.length === 0) {
      return;
    }
    const ok = await MusicListApiService.setLyric(p, lrc);
    if (!ok) {
      return;
    }
    this.applyLyricOverride(p, lrc);
  }

  private buildLyricSearchKeyword(item: MusicListItem, filePath: string): string {
    const rawTitle = item.title.trim();
    const rawArtist = item.artist.trim();
    const fallbackTitle = fileStem(item.filename.trim().length > 0 ? item.filename : filePath);
    const title = (rawTitle.length > 0 ? rawTitle : fallbackTitle).trim();
    if (title.length === 0) {
      return '';
    }
    if (rawArtist.length > 0) {
      return `${title} ${rawArtist}`;
    }
    return title;
  }

  // ================= 内部：分页队列 =================

  private maybePrefetchNextPage(index: number): void {
    const mode = this.loopMode;
    if (mode !== MusicLoopMode.sequence && mode !== MusicLoopMode.listLoop) {
      return;
    }
    const paging = this.paging;
    if (paging === undefined || this.pagingLoading || !paging.hasMore()) {
      return;
    }
    if (this.playlist.length === 0 || index !== this.playlist.length - 1) {
      return;
    }
    this.loadMoreAndAppendInPlace(index);
  }

  private handleIndexChangeForPaging(prevIndex: number, nextIndex: number): void {
    if (this.loopMode !== MusicLoopMode.listLoop) {
      return;
    }
    const paging = this.paging;
    if (paging === undefined || this.pagingLoading || !paging.hasMore()) {
      return;
    }
    if (this.playlist.length === 0) {
      return;
    }
    const last = this.playlist.length - 1;
    if (prevIndex !== last || nextIndex !== 0) {
      return;
    }
    const startIndexAfterAppend = this.playlist.length;
    this.loadMoreAndRebuild(startIndexAfterAppend, 0, false, this.engine.isPlaying());
  }

  private async loadMoreAndAppendInPlace(currentIndex: number): Promise<void> {
    const paging = this.paging;
    if (paging === undefined) {
      return;
    }
    const token = ++this.pagingToken;
    this.pagingLoading = true;
    try {
      const more = await paging.loadMore();
      if (token !== this.pagingToken || more.length === 0) {
        return;
      }
      const existing = new Set<string>();
      for (const e of this.playlist) {
        existing.add(this.resolvePlayablePath(e).trim());
      }
      for (const e of more) {
        if (e.isSeries) {
          continue;
        }
        const p = this.resolvePlayablePath(e).trim();
        if (p.length > 0 && !existing.has(p)) {
          this.playlist.push(e);
          existing.add(p);
        }
      }
    } catch (_e) {
    } finally {
      if (token === this.pagingToken) {
        this.pagingLoading = false;
      }
      this.maybePrefetchNextPage(currentIndex);
    }
  }

  private async loadMoreAndRebuild(startIndexAfterAppend: number, initialPositionMs: number,
    autoPlay: boolean, resumeIfWasPlaying: boolean): Promise<void> {
    const paging = this.paging;
    if (paging === undefined) {
      return;
    }
    const token = ++this.pagingToken;
    this.pagingLoading = true;
    try {
      const more = await paging.loadMore();
      if (token !== this.pagingToken || more.length === 0) {
        return;
      }
      const existing = new Set<string>();
      for (const e of this.playlist) {
        existing.add(this.resolvePlayablePath(e).trim());
      }
      const oldLen = this.playlist.length;
      for (const e of more) {
        if (e.isSeries) {
          continue;
        }
        const p = this.resolvePlayablePath(e).trim();
        if (p.length > 0 && !existing.has(p)) {
          this.playlist.push(e);
          existing.add(p);
        }
      }
      const safeIndex = Math.min(Math.max(startIndexAfterAppend, 0), this.playlist.length - 1);
      this.currentIndex = safeIndex;
      await this.openTrack(safeIndex, autoPlay, initialPositionMs);
      await this.refreshDetailForIndex(safeIndex);
      if (!autoPlay && resumeIfWasPlaying) {
        this.engine.play();
      }
      if (!autoPlay && safeIndex === 0 && oldLen > 0) {
        this.syncedDurationKey = '';
        this.syncMediaItem(0);
      }
    } catch (_e) {
    } finally {
      if (token === this.pagingToken) {
        this.pagingLoading = false;
      }
    }
  }

  private async ensurePlaylistUpToDate(force: boolean = false): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    const token = APIClient.getInstance().accessToken ?? '';
    const last = this.lastPlaylistAccessToken;
    if (!force && token === last) {
      return;
    }
    const idx = Math.min(Math.max(this.currentIndex, 0), this.playlist.length - 1);
    const keepPos = this.positionMs;
    const wasDesired = this.desiredPlaying;
    await this.openTrack(idx, false, keepPos);
    if (wasDesired) {
      this.engine.play();
    }
  }

  // ================= 内部：恢复 / 完成 =================

  private async attemptRecovery(): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    const now = Date.now();
    if (now - this.lastRecoveryMs < 2000) {
      return;
    }
    this.lastRecoveryMs = now;
    await APIClient.getInstance().refreshAuthToken();
    await this.ensurePlaylistUpToDate(true);
  }

  private scheduleStallRecoveryIfNeeded(): void {
    const stalling = this.engine.isBuffering();
    if (!stalling || !this.desiredPlaying) {
      this.clearStallTimer();
      return;
    }
    if (this.stallTimer >= 0) {
      return;
    }
    this.stallTimer = setTimeout((): void => {
      this.stallTimer = -1;
      const stillStalling = this.engine.isBuffering();
      if (!stillStalling || !this.desiredPlaying) {
        return;
      }
      this.attemptRecovery();
    }, 12000) as number;
  }

  private clearStallTimer(): void {
    if (this.stallTimer >= 0) {
      clearTimeout(this.stallTimer);
      this.stallTimer = -1;
    }
  }

  private async handleTrackCompleted(): Promise<void> {
    if (this.playlist.length === 0) {
      return;
    }
    const idx = Math.min(Math.max(this.currentIndex, 0), this.playlist.length - 1);
    const mode = this.loopMode;
    if (mode === MusicLoopMode.singleLoop) {
      return;
    }
    if (mode === MusicLoopMode.shuffle) {
      const next = this.resolveNextIndex(true);
      if (next === undefined) {
        return;
      }
      this.shuffleHistory.push(idx);
      await this.playAt(next);
      return;
    }
    if (idx === this.playlist.length - 1) {
      const paging = this.paging;
      const canLoadMore = paging !== undefined && !this.pagingLoading && paging.hasMore();
      if (mode === MusicLoopMode.sequence) {
        if (canLoadMore) {
          await this.loadMoreAndRebuild(this.playlist.length, 0, true, false);
          return;
        }
        this.desiredPlaying = false;
        await this.stop();
        this.isCompleted = true;
        this.syncPlaybackState('completed');
        return;
      }
      if (mode === MusicLoopMode.listLoop) {
        if (canLoadMore) {
          await this.loadMoreAndRebuild(this.playlist.length, 0, true, false);
          return;
        }
        await this.playAt(0);
        return;
      }
    }
    const next = idx + 1;
    if (next >= 0 && next < this.playlist.length) {
      await this.playAt(next);
    }
  }

  // ================= 内部：进度轮询 =================

  private startPositionPolling(): void {
    this.stopPositionPolling();
    this.posTimer = setInterval((): void => {
      this.syncFromPlayer();
    }, 500) as number;
  }

  private stopPositionPolling(): void {
    if (this.posTimer >= 0) {
      clearInterval(this.posTimer);
      this.posTimer = -1;
    }
  }

  private syncFromPlayer(): void {
    const hasEngineSource = this.playlist.length > 0;
    if (!hasEngineSource) {
      if (this.isPlaying) {
        this.isPlaying = false;
      }
      this.syncPlaybackState('idle');
      return;
    }
    const d = this.engine.getDuration();
    const prevDuration = this.durationMs;
    if (prevDuration !== d) {
      this.durationMs = d;
      if (d > 0) {
        this.syncMediaItem(this.currentIndex, true);
        if (prevDuration <= 0) {
          setTimeout((): void => {
            if (this.durationMs > 0 && this.currentIndex >= 0 && this.currentIndex < this.playlist.length) {
              this.syncMediaItem(this.currentIndex, true);
            }
          }, 1800);
        }
      }
      this.maybeAutoSetLyricForCurrent();
    }
    this.positionMs = this.engine.getCurrentPosition();
    this.bufferedMs = this.engine.getBuffered();
    const playing = this.engine.isPlaying();
    let completed = false;
    if (d > 0) {
      const posMs = this.positionMs;
      if (posMs >= d - 500 && !playing && !this.engine.isBuffering() && this.desiredPlaying) {
        completed = true;
      }
    }
    if (completed && !this.isCompleted) {
      const suppress = this.isSkippingTrack || Date.now() < this.suppressCompletedUntilMs;
      if (suppress) {
        this.isPlaying = false;
        this.syncPlaybackState('suppress');
        return;
      }
      this.isCompleted = true;
      this.isPlaying = false;
      this.syncPlaybackState('completed');
      this.handleTrackCompleted();
      return;
    }
    if (!completed) {
      this.isCompleted = false;
      this.suppressCompletedUntilMs = 0;
    }
    this.isPlaying = playing;
    this.scheduleStallRecoveryIfNeeded();
    this.syncPlaybackState('tick');
    this.notifyProgress();
  }

  private notifyProgress(): void {
    const listeners = this.progressListeners;
    for (const l of listeners) {
      l(this.positionMs, this.durationMs, this.bufferedMs);
    }
  }

  /** 播放当前曲目详情（供全屏页属性面板等） */
  get currentItem(): MusicListItem | undefined {
    if (this.currentIndex < 0 || this.currentIndex >= this.playlist.length) {
      return undefined;
    }
    return this.playlist[this.currentIndex];
  }
}

function fileStem(pathOrFile: string): string {
  const input = pathOrFile.trim();
  if (input.length === 0) {
    return '';
  }
  const slash = input.lastIndexOf('/');
  const backSlash = input.lastIndexOf('\\');
  const sep = slash > backSlash ? slash : backSlash;
  const name = sep >= 0 ? input.substring(sep + 1) : input;
  const dot = name.lastIndexOf('.');
  if (dot <= 0) {
    return name;
  }
  return name.substring(0, dot);
}

function normalizeForContains(input: string): string {
  const s = input.trim().toLowerCase();
  if (s.length === 0) {
    return '';
  }
  return s.replace(/[^a-z0-9\u4e00-\u9fff]+/g, '');
}

function isHighLyricMatch(candidate: LyricSearchItem, fileStemNormalized: string, expectedDurationMs: number): boolean {
  const titleNorm = normalizeForContains(candidate.title);
  if (titleNorm.length === 0) {
    return false;
  }
  const durationMatch = candidate.durationMs > 0 &&
    Math.abs(candidate.durationMs - expectedDurationMs) <= 5000;
  const nameMatch = titleNorm.length > 0 && fileStemNormalized.length > 0 &&
    fileStemNormalized.includes(titleNorm);
  return durationMatch && nameMatch;
}
