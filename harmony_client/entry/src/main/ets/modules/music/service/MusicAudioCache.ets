import fs from '@ohos.file.fs';
import http from '@ohos.net.http';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { APIClient } from '../../../core/network/APIClient';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 音频缓存服务（对齐 Flutter music_audio_cache_io.dart）：
 * - 按 fileHash(+ext) 命中本地缓存，转码文件加 _mp3 后缀
 * - 断点续传（.part + Range）、下载进度回调、maxItems 按 lastAccessMs 淘汰
 * - enabled/maxItems 持久化（CacheKeys.musicAudioCacheEnabled/MaxItems）
 */

const TAG = 'MusicAudioCache';

export interface MusicAudioCacheProgress {
  received: number;
  total: number;
  progress: number;
}

export class MusicPlaySource {
  /** 本地缓存文件路径（未命中为空） */
  filePath: string = '';
  /** 网络播放 URL（未启用缓存或未命中） */
  url: string = '';
  /** 文件扩展名（如 mp3/flac） */
  fileExt: string = '';
  /** 是否来自缓存 */
  cached: boolean = false;
}

interface CacheIndexEntry {
  lastAccessMs: number;
  complete: boolean;
  size: number;
}

export class MusicAudioCacheService {
  private static instance: MusicAudioCacheService | undefined = undefined;

  static getInstance(): MusicAudioCacheService {
    if (MusicAudioCacheService.instance === undefined) {
      MusicAudioCacheService.instance = new MusicAudioCacheService();
    }
    return MusicAudioCacheService.instance;
  }

  private cacheDir: string = '';
  private indexPath: string = '';
  private index: Map<string, CacheIndexEntry> = new Map();
  private downloadingKey: string = '';
  private downloadAborted: boolean = false;
  enabled: boolean = true;
  maxItems: number = 300;

  async init(context: common.Context): Promise<void> {
    this.cacheDir = `${context.cacheDir}/music_audio_cache`;
    this.indexPath = `${this.cacheDir}/index.json`;
    try {
      if (!fs.accessSync(this.cacheDir)) {
        fs.mkdirSync(this.cacheDir, true);
      }
    } catch (_e) {
    }
    this.loadIndex();
    const store = PreferencesStore.getInstance();
    this.enabled = store.getBool(CacheKeys.MUSIC_AUDIO_CACHE_ENABLED, true);
    this.maxItems = store.getInt(CacheKeys.MUSIC_AUDIO_CACHE_MAX_ITEMS, 300);
  }

  updateOptions(enabled: boolean, maxItems: number): void {
    this.enabled = enabled;
    this.maxItems = Math.max(0, maxItems);
  }

  private loadIndex(): void {
    this.index = new Map();
    try {
      if (fs.accessSync(this.indexPath)) {
        const stat = fs.statSync(this.indexPath);
        if (stat.size > 0) {
          const file = fs.openSync(this.indexPath, fs.OpenMode.READ_ONLY);
          const buf = new ArrayBuffer(stat.size);
          fs.readSync(file.fd, buf);
          fs.closeSync(file);
          const text = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
          const obj = JSON.parse(text) as Record<string, Object>;
          const keys = Object.keys(obj);
          for (const k of keys) {
            const e = obj[k] as Object as CacheIndexEntry;
            this.index.set(k, { lastAccessMs: Number(e.lastAccessMs) || 0, complete: !!e.complete, size: Number(e.size) || 0 });
          }
        }
      }
    } catch (_e) {
      this.index = new Map();
    }
  }

  private saveIndex(): void {
    try {
      const obj: Record<string, Object> = {};
      this.index.forEach((v: CacheIndexEntry, k: string): void => {
        const entry: CacheIndexEntry = { lastAccessMs: v.lastAccessMs, complete: v.complete, size: v.size };
        obj[k] = entry as Object as Record<string, Object>;
      });
      const file = fs.openSync(this.indexPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(obj));
      fs.closeSync(file);
    } catch (e) {
      hilog.error(0x0000, TAG, 'saveIndex failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 缓存键（转码加 _mp3 后缀，对齐 Flutter） */
  static cacheKey(fileHash: string, ext: string, isTranscode: boolean): string {
    const h = fileHash.trim().length > 0 ? fileHash.trim() : 'nohash';
    const e = ext.replace(/\./g, '').toLowerCase();
    return isTranscode ? `${h}_mp3` : `${h}${e.length > 0 ? '.' + e : ''}`;
  }

  private cacheFilePath(key: string, ext: string): string {
    const e = ext.replace(/\./g, '').toLowerCase();
    return `${this.cacheDir}/${key}${e.length > 0 ? '.' + e : ''}`;
  }

  private partPath(key: string, ext: string): string {
    return `${this.cacheFilePath(key, ext)}.part`;
  }

  hasCached(fileHash: string, ext: string, isTranscode: boolean): boolean {
    if (!this.enabled || this.cacheDir.length === 0) {
      return false;
    }
    const key = MusicAudioCacheService.cacheKey(fileHash, ext, isTranscode);
    const entry = this.index.get(key);
    if (entry === undefined || !entry.complete) {
      return false;
    }
    try {
      return fs.accessSync(this.cacheFilePath(key, ext));
    } catch (_e) {
      return false;
    }
  }

  touch(fileHash: string, ext: string, isTranscode: boolean): void {
    const key = MusicAudioCacheService.cacheKey(fileHash, ext, isTranscode);
    const entry = this.index.get(key);
    if (entry !== undefined) {
      entry.lastAccessMs = Date.now();
      this.saveIndex();
    }
  }

  remove(fileHash: string, ext: string, isTranscode: boolean): void {
    const key = MusicAudioCacheService.cacheKey(fileHash, ext, isTranscode);
    try {
      const p = this.cacheFilePath(key, ext);
      if (fs.accessSync(p)) {
        fs.unlinkSync(p);
      }
      const pp = this.partPath(key, ext);
      if (fs.accessSync(pp)) {
        fs.unlinkSync(pp);
      }
    } catch (_e) {
    }
    this.index.delete(key);
    this.saveIndex();
  }

  /** 播放源准备：优先缓存；否则下载（带进度）；失败返回原始 URL。 */
  async prepareSource(playUrl: string, fileHash: string, fileExt: string, isTranscode: boolean,
    progressCb: ((p: MusicAudioCacheProgress) => void) | undefined): Promise<MusicPlaySource> {
    const source = new MusicPlaySource();
    source.url = playUrl;
    source.fileExt = fileExt;
    if (!this.enabled || this.cacheDir.length === 0) {
      return source;
    }
    const key = MusicAudioCacheService.cacheKey(fileHash, fileExt, isTranscode);
    if (this.hasCached(fileHash, fileExt, isTranscode)) {
      this.touch(fileHash, fileExt, isTranscode);
      source.filePath = this.cacheFilePath(key, fileExt);
      source.cached = true;
      return source;
    }
    const ok = await this.download(playUrl, key, fileExt, progressCb);
    if (ok && this.hasCached(fileHash, fileExt, isTranscode)) {
      source.filePath = this.cacheFilePath(key, fileExt);
      source.cached = true;
      return source;
    }
    return source;
  }

  private static extFromUrlOrPath(path: string): string {
    const dot = path.lastIndexOf('.');
    if (dot < 0) {
      return 'mp3';
    }
    let ext = path.substring(dot + 1).toLowerCase();
    const q = ext.indexOf('?');
    if (q >= 0) {
      ext = ext.substring(0, q);
    }
    return ext.length > 0 && ext.length <= 5 ? ext : 'mp3';
  }

  /** 断点续传下载；返回是否成功完成 */
  async download(url: string, key: string, ext: string,
    progressCb: ((p: MusicAudioCacheProgress) => void) | undefined): Promise<boolean> {
    if (this.downloadingKey.length > 0) {
      this.cancelActiveDownload();
    }
    this.downloadingKey = key;
    this.downloadAborted = false;
    const client: http.HttpRequest = http.createHttp();
    try {
      const targetPath = this.cacheFilePath(key, ext);
      const partPath = this.partPath(key, ext);
      let already = 0;
      try {
        if (fs.accessSync(partPath)) {
          already = fs.statSync(partPath).size;
        }
      } catch (_e) {
        already = 0;
      }
      const header: Record<string, string> = {
        'accept': '*/*'
      };
      const token = APIClient.getInstance().accessToken;
      if (token !== undefined && token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      if (already > 0) {
        header['Range'] = `bytes=${already}-`;
      }
      // 大文件必须显式调大 maxLimit（默认 5MB 上限）
      const resp = await client.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 60000,
        connectTimeout: 15000,
        maxLimit: 100 * 1024 * 1024
      });
      if (this.downloadAborted) {
        return false;
      }
      const code = resp.responseCode;
      if (code !== 200 && code !== 206) {
        return false;
      }
      const data = resp.result as ArrayBuffer;
      const append = already > 0 && code === 206;
      const openFlag = append
        ? fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE
        : fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC;
      const file = fs.openSync(partPath, openFlag);
      if (append) {
        fs.truncateSync(file.fd, already);
        fs.lseek(file.fd, already, fs.WhenceType.SEEK_SET);
      }
      fs.writeSync(file.fd, data);
      fs.fsyncSync(file.fd);
      fs.closeSync(file);
      // 完成改名
      try {
        if (fs.accessSync(targetPath)) {
          fs.unlinkSync(targetPath);
        }
        fs.renameSync(partPath, targetPath);
      } catch (_e) {
      }
      const totalBytes = already + data.byteLength;
      const entry: CacheIndexEntry = { lastAccessMs: Date.now(), complete: true, size: totalBytes };
      this.index.set(key, entry);
      this.saveIndex();
      this.evictIfNeeded();
      if (progressCb !== undefined) {
        progressCb({ received: totalBytes, total: totalBytes, progress: 1 });
      }
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'download failed: %{public}s', JSON.stringify(e));
      return false;
    } finally {
      client.destroy();
      if (this.downloadingKey === key) {
        this.downloadingKey = '';
      }
    }
  }

  cancelActiveDownload(): void {
    this.downloadAborted = true;
    this.downloadingKey = '';
  }

  /** maxItems 淘汰：按 lastAccessMs 排序删除最久未访问的已完成缓存 */
  private evictIfNeeded(): void {
    if (this.maxItems <= 0) {
      return;
    }
    const completed: Array<[string, CacheIndexEntry]> = [];
    this.index.forEach((v: CacheIndexEntry, k: string): void => {
      if (v.complete) {
        completed.push([k, v]);
      }
    });
    if (completed.length <= this.maxItems) {
      return;
    }
    completed.sort((a, b): number => a[1].lastAccessMs - b[1].lastAccessMs);
    const toRemove = completed.length - this.maxItems;
    for (let i = 0; i < toRemove; i++) {
      const key = completed[i][0];
      const extIdx = key.lastIndexOf('.');
      const ext = extIdx >= 0 ? key.substring(extIdx) : '';
      const baseKey = extIdx >= 0 ? key.substring(0, extIdx) : key;
      try {
        const p = `${this.cacheDir}/${key}`;
        if (fs.accessSync(p)) {
          fs.unlinkSync(p);
        }
        const pp = `${this.cacheDir}/${baseKey}${ext}.part`;
        if (fs.accessSync(pp)) {
          fs.unlinkSync(pp);
        }
      } catch (_e) {
      }
      this.index.delete(key);
    }
    this.saveIndex();
  }

  clearAll(): void {
    this.cancelActiveDownload();
    try {
      if (fs.accessSync(this.cacheDir)) {
        fs.rmdirSync(this.cacheDir);
      }
      fs.mkdirSync(this.cacheDir, true);
    } catch (_e) {
    }
    this.index = new Map();
    this.saveIndex();
  }

  getStats(): MusicAudioCacheStats {
    let count = 0;
    let size = 0;
    this.index.forEach((v: CacheIndexEntry): void => {
      if (v.complete) {
        count++;
        size += v.size;
      }
    });
    const s = new MusicAudioCacheStats();
    s.count = count;
    s.sizeBytes = size;
    return s;
  }
}

export class MusicAudioCacheStats {
  count: number = 0;
  sizeBytes: number = 0;
}
