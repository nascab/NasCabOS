import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { VideoSource, parseVideoSource } from '../models/VideoModels';
import { VideoSourceApiService } from '../service/VideoApiServices';

/**
 * 影音来源设置控制器（对齐 Flutter VideoSourceSettingsController）：
 * 列表加载 + 单个/批量添加 + 乐观更新（失败回滚）+ 删除/重定位/扫描/预生成缩略图。
 */
@ObservedV2
export class VideoSourceSettingsController {
  private api: VideoSourceApiService = new VideoSourceApiService();

  @Trace sources: VideoSource[] = [];
  @Trace loadingSources: boolean = false;
  @Trace scanning: boolean = false;

  init(): void {
    void this.fetchSources();
  }

  dispose(): void {
  }

  /** 定时扫描小时数（对齐 Flutter getIntervalHours：ms→小时，缺省 2） */
  getIntervalHours(source: VideoSource): number {
    const ms = source.scanIntervalMs;
    if (ms <= 0) {
      return 2;
    }
    const hours = Math.round(ms / (3600 * 1000));
    return Math.min(Math.max(hours, 1), 24);
  }

  /** 定时扫描是否启用（对齐 Flutter getIntervalEnabled） */
  getIntervalEnabled(source: VideoSource): boolean {
    return source.scanInterval === 1 || source.scanIntervalMs > 0;
  }

  /** 拉取来源列表（对齐 Flutter fetchSources） */
  async fetchSources(showLoading: boolean = false): Promise<void> {
    if (this.loadingSources) {
      return;
    }
    this.loadingSources = true;
    if (showLoading) {
      DialogUtil.showLoading(L10n.loading);
    }
    try {
      this.sources = await this.api.listSources();
    } finally {
      this.loadingSources = false;
      if (showLoading) {
        DialogUtil.dismissLoading();
      }
    }
  }

  /** 添加单个来源（对齐 Flutter addSource：movie/tv + matchNfo 校验） */
  async addSource(path: string, mediaType: string, matchNfo: number): Promise<boolean> {
    const p = path.trim();
    if (p.length === 0) {
      return false;
    }
    if (mediaType !== 'movie' && mediaType !== 'tv') {
      return false;
    }
    if (matchNfo !== 0 && matchNfo !== 1) {
      return false;
    }
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.addSource(p, mediaType, matchNfo);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return false;
      }
      await this.fetchSources();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 批量添加来源（对齐 Flutter addSourcesWithConfig：逐个添加，失败即停） */
  async addSourcesWithConfig(paths: string[], mediaType: string, matchNfo: number): Promise<boolean> {
    const uniq: string[] = [];
    for (const e of paths) {
      const t = e.trim();
      if (t.length > 0 && !uniq.includes(t)) {
        uniq.push(t);
      }
    }
    if (uniq.length === 0) {
      return false;
    }
    DialogUtil.showLoading(L10n.loading);
    try {
      for (const p of uniq) {
        const res = await this.api.addSource(p, mediaType, matchNfo);
        if (!res.success) {
          DialogUtil.dismissLoading();
          ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
          return false;
        }
      }
      await this.fetchSources();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } finally {
      DialogUtil.dismissLoading();
    }
  }

  /** 乐观更新来源开关/间隔（对齐 Flutter updateSourceOptimistic：失败回滚） */
  async updateSourceOptimistic(source: VideoSource,
    scanWhenStart: number | undefined = undefined,
    scanWhenChange: number | undefined = undefined,
    scanInterval: number | undefined = undefined,
    scanIntervalMs: number | undefined = undefined): Promise<void> {
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const prev = this.sources[idx];
    const next = new VideoSource();
    next.id = prev.id;
    next.path = prev.path;
    next.exists = prev.exists;
    next.mediaType = prev.mediaType;
    next.matchNfo = prev.matchNfo;
    next.scanWhenStart = scanWhenStart !== undefined ? scanWhenStart : prev.scanWhenStart;
    next.scanWhenChange = scanWhenChange !== undefined ? scanWhenChange : prev.scanWhenChange;
    next.isShow = prev.isShow;
    next.ctime = prev.ctime;
    next.scanInterval = scanInterval !== undefined ? scanInterval : prev.scanInterval;
    next.scanIntervalMs = scanIntervalMs !== undefined ? scanIntervalMs : prev.scanIntervalMs;
    next.scanIntervalConfig = prev.scanIntervalConfig;
    next.lastScanTime = prev.lastScanTime;
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

    const res = await this.api.updateSource(source.id, payload);
    if (!res.success) {
      this.sources[idx] = prev;
      ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (res.data !== undefined && res.data !== null) {
      this.sources[idx] = parseVideoSource(res.data as Object);
    }
  }

  /** 乐观更新媒体类型（对齐 Flutter updateMediaTypeOptimistic） */
  async updateMediaTypeOptimistic(source: VideoSource, mediaType: string): Promise<void> {
    if (mediaType !== 'movie' && mediaType !== 'tv') {
      return;
    }
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0 || this.sources[idx].mediaType === mediaType) {
      return;
    }
    const prev = this.sources[idx];
    const next = new VideoSource();
    next.id = prev.id;
    next.path = prev.path;
    next.exists = prev.exists;
    next.mediaType = mediaType;
    next.matchNfo = prev.matchNfo;
    next.scanWhenStart = prev.scanWhenStart;
    next.scanWhenChange = prev.scanWhenChange;
    next.isShow = prev.isShow;
    next.ctime = prev.ctime;
    next.scanInterval = prev.scanInterval;
    next.scanIntervalMs = prev.scanIntervalMs;
    next.scanIntervalConfig = prev.scanIntervalConfig;
    next.lastScanTime = prev.lastScanTime;
    this.sources[idx] = next;

    const res = await this.api.updateMediaType(source.id, mediaType);
    if (!res.success) {
      this.sources[idx] = prev;
      ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (res.data !== undefined && res.data !== null) {
      this.sources[idx] = parseVideoSource(res.data as Object);
    }
  }

  /** 乐观更新匹配 NFO（对齐 Flutter updateMatchNfoOptimistic） */
  async updateMatchNfoOptimistic(source: VideoSource, matchNfo: number): Promise<void> {
    if (matchNfo !== 0 && matchNfo !== 1) {
      return;
    }
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0 || this.sources[idx].matchNfo === matchNfo) {
      return;
    }
    const prev = this.sources[idx];
    const next = new VideoSource();
    next.id = prev.id;
    next.path = prev.path;
    next.exists = prev.exists;
    next.mediaType = prev.mediaType;
    next.matchNfo = matchNfo;
    next.scanWhenStart = prev.scanWhenStart;
    next.scanWhenChange = prev.scanWhenChange;
    next.isShow = prev.isShow;
    next.ctime = prev.ctime;
    next.scanInterval = prev.scanInterval;
    next.scanIntervalMs = prev.scanIntervalMs;
    next.scanIntervalConfig = prev.scanIntervalConfig;
    next.lastScanTime = prev.lastScanTime;
    this.sources[idx] = next;

    const res = await this.api.updateMatchNfo(source.id, matchNfo);
    if (!res.success) {
      this.sources[idx] = prev;
      ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      return;
    }
    if (res.data !== undefined && res.data !== null) {
      this.sources[idx] = parseVideoSource(res.data as Object);
    }
  }

  /** 删除来源（乐观删除 + 失败恢复，对齐 Flutter deleteSourceOptimistic） */
  async deleteSourceOptimistic(source: VideoSource): Promise<void> {
    const idx = this.sources.findIndex((e: VideoSource): boolean => e.id === source.id);
    if (idx < 0) {
      return;
    }
    const removed = this.sources[idx];
    const next = this.sources.slice();
    next.splice(idx, 1);
    this.sources = next;

    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.deleteSource(source.id);
      if (!res.success) {
        const restored = this.sources.slice();
        restored.splice(idx, 0, removed);
        this.sources = restored;
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } catch (_e) {
      const restored = this.sources.slice();
      restored.splice(idx, 0, removed);
      this.sources = restored;
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 重定位来源（对齐 Flutter relocateSource） */
  async relocateSource(source: VideoSource, newPath: string): Promise<void> {
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.relocateSource(source.id, newPath);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      await this.fetchSources();
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } catch (_e) {
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    }
  }

  /** 立即扫描（对齐 Flutter scanSource；path 传 'all' 扫描全部） */
  async scanSource(path: string): Promise<void> {
    const p = path.trim();
    if (p.length === 0 || this.scanning) {
      return;
    }
    this.scanning = true;
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.scanSource(p);
      if (!res.success) {
        DialogUtil.dismissLoading();
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
        return;
      }
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      await this.fetchSources();
    } catch (_e) {
      DialogUtil.dismissLoading();
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    } finally {
      this.scanning = false;
      DialogUtil.dismissLoading();
    }
  }

  /** 预生成缩略图（确认弹窗由页面触发，对齐 Flutter preGenerateThumbnails） */
  async preGenerateThumbnails(): Promise<void> {
    DialogUtil.showLoading(L10n.loading);
    try {
      const res = await this.api.preGenerateThumbnails();
      if (res.success) {
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
      } else {
        ToastUtil.show(res.message ?? L10n.t('operation_failed', '操作失败'));
      }
    } catch (_e) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
    } finally {
      DialogUtil.dismissLoading();
    }
  }
}
