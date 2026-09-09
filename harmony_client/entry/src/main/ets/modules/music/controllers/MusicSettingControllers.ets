/**
 * 音乐设置与主框架控制器合集（对齐 Flutter）：
 * - MusicSourceController  ← source_setting/controller/music_source_settings_controller.dart
 * - MusicCacheSettingsController ← cache_setting/controller/music_cache_settings_controller.dart
 * - MusicMainController    ← music_main/controller/music_main_controller.dart（页面切换/歌单分组展开）
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { MusicSource } from '../models/MusicModels';
import { MusicListApiService, MusicSourceApiService } from '../services/MusicApiServices';
import { MusicPlayService } from '../service/MusicPlayService';
import { MusicSubListPayload } from './MusicSubListController';

const TAG = 'MusicSettingControllers';

// ===== 音乐来源设置（对齐 MusicSourceSettingsController） =====

@ObservedV2
export class MusicSourceController {
  @Trace sources: MusicSource[] = [];
  @Trace loadingSources: boolean = false;
  @Trace scanning: boolean = false;

  onInit(): void {
    this.fetchSources(false);
  }

  getIntervalHours(source: MusicSource): number {
    const ms = source.scanIntervalMs;
    if (ms <= 0) {
      return 2;
    }
    const hours = Math.round(ms / (3600 * 1000));
    return Math.min(Math.max(hours, 1), 24);
  }

  getIntervalEnabled(source: MusicSource): boolean {
    return source.scanInterval === 1 || source.scanIntervalMs > 0;
  }

  async fetchSources(showLoading: boolean = false): Promise<void> {
    if (this.loadingSources) {
      return;
    }
    this.loadingSources = true;
    try {
      const list = await MusicSourceApiService.listSources();
      this.sources = list;
    } catch (e) {
      hilog.error(0x0000, TAG, 'fetchSources failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loadingSources = false;
    }
  }

  async addSources(paths: string[]): Promise<boolean> {
    const uniq = Array.from(new Set<string>(paths.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0)));
    if (uniq.length === 0) {
      return false;
    }
    DialogUtil.showLoading(L10n.t('loading'));
    try {
      for (const p of uniq) {
        const res = await MusicSourceApiService.addSource(p);
        if (!res.success) {
          DialogUtil.dismissLoading(true);
          ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
          return false;
        }
      }
      await this.fetchSources(false);
      ToastUtil.show(L10n.t('operation_success'));
      return true;
    } finally {
      DialogUtil.dismissLoading(true);
    }
  }

  /** 乐观更新来源选项；失败回滚（对齐 updateSourceOptimistic） */
  async updateSourceOptimistic(source: MusicSource, scanWhenStart: number | undefined = undefined,
    scanWhenChange: number | undefined = undefined, scanInterval: number | undefined = undefined,
    scanIntervalMs: number | undefined = undefined, showType: string | undefined = undefined): Promise<void> {
    const idx = this.sources.findIndex((e: MusicSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const prev = this.sources[idx];
    const next = MusicSource.fromJson(this.sourceToRaw(source));
    if (scanWhenStart !== undefined) {
      next.scanWhenStart = scanWhenStart === 1;
    }
    if (scanWhenChange !== undefined) {
      next.scanWhenChange = scanWhenChange === 1;
    }
    if (scanInterval !== undefined) {
      next.scanInterval = scanInterval;
    }
    if (scanIntervalMs !== undefined) {
      next.scanIntervalMs = scanIntervalMs;
    }
    if (showType !== undefined) {
      next.showType = showType;
    }
    this.sources[idx] = next;

    const payload: Record<string, Object> = {};
    if (scanWhenStart !== undefined) {
      payload['scan_when_start'] = scanWhenStart;
    }
    if (scanWhenChange !== undefined) {
      payload['scan_when_change'] = scanWhenChange;
    }
    if (scanInterval !== undefined) {
      payload['scan_interval'] = scanInterval;
    }
    if (scanIntervalMs !== undefined) {
      payload['scan_interval_ms'] = scanIntervalMs;
    }
    if (showType !== undefined) {
      payload['show_type'] = showType;
    }
    const res = await MusicSourceApiService.updateSource(source.id, payload);
    if (!res.success) {
      this.sources[idx] = prev;
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    if (res.data !== undefined) {
      this.sources[idx] = MusicSource.fromJson(res.data);
    }
  }

  async relocateSource(source: MusicSource, newPath: string): Promise<void> {
    DialogUtil.showLoading(L10n.t('loading'));
    try {
      const res = await MusicSourceApiService.relocateSource(source.id, newPath);
      if (!res.success) {
        DialogUtil.dismissLoading(true);
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      await this.fetchSources(false);
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.t('operation_success'));
    } catch (_e) {
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.operationFailed);
    }
  }

  async deleteSourceOptimistic(source: MusicSource): Promise<void> {
    const idx = this.sources.findIndex((e: MusicSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const removed = this.sources[idx];
    this.sources = this.sources.filter((e: MusicSource): boolean => e.id !== source.id);
    DialogUtil.showLoading(L10n.t('loading'));
    try {
      const res = await MusicSourceApiService.deleteSource(source.id);
      if (!res.success) {
        this.sources.splice(idx, 0, removed);
        DialogUtil.dismissLoading(true);
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.t('operation_success'));
    } catch (_e) {
      this.sources.splice(idx, 0, removed);
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.operationFailed);
    }
  }

  async scanSource(path: string): Promise<void> {
    const p = path.trim();
    if (p.length === 0 || this.scanning) {
      return;
    }
    this.scanning = true;
    DialogUtil.showLoading(L10n.t('loading'));
    try {
      const res = await MusicSourceApiService.scanSource(p);
      if (!res.success) {
        DialogUtil.dismissLoading(true);
        ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
        return;
      }
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.t('operation_success'));
      await this.fetchSources(false);
    } catch (_e) {
      DialogUtil.dismissLoading(true);
      ToastUtil.show(L10n.operationFailed);
    } finally {
      this.scanning = false;
    }
  }

  /** 复制成可序列化 raw（供 fromJson 复制实例） */
  private sourceToRaw(s: MusicSource): Record<string, Object> {
    const r: Record<string, Object> = {
      'id': s.id,
      'path': s.path,
      'exists': s.exists ? 1 : 0,
      'scan_when_start': s.scanWhenStart ? 1 : 0,
      'scan_when_change': s.scanWhenChange ? 1 : 0,
      'is_show': s.isShow ? 1 : 0,
      'show_type': s.showType,
      'scan_interval': s.scanInterval,
      'scan_interval_ms': s.scanIntervalMs,
      'last_scan_time': s.lastScanTime
    };
    return r;
  }
}

// ===== 缓存设置（对齐 MusicCacheSettingsController） =====

@ObservedV2
export class MusicCacheSettingsController {
  @Trace loading: boolean = false;
  @Trace clearing: boolean = false;
  @Trace cachedCount: number = 0;
  @Trace cachedBytes: number = 0;

  get playCtrl(): MusicPlayService {
    return MusicPlayService.getInstance();
  }

  get enabled(): boolean {
    return this.playCtrl.audioCacheEnabled;
  }

  async toggleEnabled(v: boolean): Promise<void> {
    await this.playCtrl.setAudioCacheEnabled(v);
    await this.refreshStats(false);
  }

  async setMaxItems(v: number): Promise<void> {
    await this.playCtrl.setAudioCacheMaxItems(v);
    await this.refreshStats(false);
  }

  async refreshStats(showLoading: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    if (showLoading) {
      this.loading = true;
    }
    try {
      const stats = this.playCtrl.getAudioCacheStats();
      this.cachedCount = stats.count;
      this.cachedBytes = stats.sizeBytes;
    } finally {
      this.loading = false;
    }
  }

  async clearCache(): Promise<void> {
    if (this.clearing) {
      return;
    }
    this.clearing = true;
    try {
      this.playCtrl.clearAudioCache();
      await this.refreshStats(false);
    } finally {
      this.clearing = false;
    }
  }
}

// ===== 主框架（对齐 MusicMainController） =====

export const MUSIC_PAGE_SONGS: string = 'library.songs';
export const MUSIC_PAGE_FAVORITES: string = 'library.favorites';
export const MUSIC_PAGE_ALBUMS: string = 'library.albums';
export const MUSIC_PAGE_ARTISTS: string = 'library.artists';
export const MUSIC_PAGE_PLAYLISTS: string = 'library.playlists';
export const MUSIC_PAGE_COLLECTIONS: string = 'library.collections';
export const MUSIC_PAGE_HISTORY: string = 'settings.history';
export const MUSIC_PAGE_SOURCES: string = 'settings.sources';
export const MUSIC_PAGE_CACHE: string = 'settings.cache';

@ObservedV2
export class MusicMainController {
  @Trace currentPageKey: string = MUSIC_PAGE_SONGS;
  @Trace songCount: number = 0;
  /** 歌单 Overlay 打开状态（对齐 PlayListOverlayController.active） */
  @Trace activePlaylist: MusicPlaylistOverlayState | undefined = undefined;
  /** 子列表 Overlay 打开状态（对齐 MusicSubListOverlayController.active） */
  @Trace activeSubList: MusicSubListPayload | undefined = undefined;

  onInit(): void {
    this.fetchLibraryCounts();
  }

  private async fetchLibraryCounts(): Promise<void> {
    try {
      const res = await MusicListApiService.listCount([]);
      const data = res;
      if (data !== undefined) {
        this.songCount = data.songs;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'fetchLibraryCounts failed: %{public}s', JSON.stringify(e));
    }
  }

  selectPage(key: string): void {
    this.activeSubList = undefined;
    this.currentPageKey = key;
  }

  // ===== 歌单 Overlay =====

  openPlaylist(listId: number, name: string): void {
    if (listId <= 0) {
      return;
    }
    const payload = new MusicPlaylistOverlayState();
    payload.listId = listId;
    payload.name = name;
    this.activePlaylist = payload;
  }

  closePlaylist(): void {
    this.activePlaylist = undefined;
  }

  // ===== 子列表 Overlay =====

  openSubList(keyType: string, name: string, seriesIndexId: number = 0, listId: number = 0,
    listType: string = '', collectionId: number = 0, isFavorite: boolean = false, isHistory: boolean = false): void {
    if (name.trim().length === 0) {
      return;
    }
    this.activeSubList = new MusicSubListPayload(keyType, name, seriesIndexId, listId,
      listType, collectionId, isFavorite, isHistory);
  }

  closeSubList(): void {
    if (this.activeSubList === undefined) {
      return;
    }
    this.activeSubList = undefined;
  }
}

/** 歌单 Overlay 状态（对齐 PlayListOverlayPayload） */
export class MusicPlaylistOverlayState {
  listId: number = 0;
  name: string = '';
}
