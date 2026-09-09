import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WindowStore } from '../../../common/WindowStore';
import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';

const TAG = 'BookLocalCache';

/** 缓存条目（对齐 Flutter BookCacheEntry） */
export class BookCacheEntry {
  fileHash: string = '';
  filePath: string = '';
  sizeBytes: number = 0;
  modifiedAt: number = 0;
}

/**
 * 图书本地缓存服务（对齐 Flutter BookLocalCacheService）：
 * 目录 <cacheDir>/book_cache/<fileHash>/<净化文件名>；
 * 下载写 .nascab_tmp 完成后改名；inflight 去重；下载进度可观察。
 */
@ObservedV2
export class BookLocalCacheService {
  private static instance: BookLocalCacheService | undefined = undefined;

  static getInstance(): BookLocalCacheService {
    if (BookLocalCacheService.instance === undefined) {
      BookLocalCacheService.instance = new BookLocalCacheService();
    }
    return BookLocalCacheService.instance;
  }

  /** 已缓存 fileHash 集合（整体替换触发刷新） */
  @Trace cachedFileHashes: Set<string> = new Set<string>();
  /** 下载进度（0~1，整体替换触发刷新） */
  @Trace downloadProgress: Map<string, number> = new Map<string, number>();

  private rootDir: string = '';
  private inflight: Map<string, Promise<boolean>> = new Map<string, Promise<boolean>>();

  private constructor() {
    this.initDir();
  }

  private initDir(): void {
    const ctx = WindowStore.appContext;
    if (ctx === undefined) {
      return;
    }
    try {
      this.rootDir = `${ctx.cacheDir}/book_cache`;
      if (!fs.accessSync(this.rootDir)) {
        fs.mkdirSync(this.rootDir, true);
      }
      this.refreshCachedHashes();
    } catch (e) {
      hilog.error(0x0000, TAG, 'initDir failed: %{public}s', JSON.stringify(e));
      this.rootDir = '';
    }
  }

  isCached(fileHash: string): boolean {
    const h = fileHash.trim();
    if (h.length === 0) {
      return false;
    }
    if (this.cachedFileHashes.has(h)) {
      return true;
    }
    return this.cachedFilePathOf(h) !== undefined;
  }

  progressOf(fileHash: string): number {
    const v = this.downloadProgress.get(fileHash.trim());
    return v !== undefined ? v : 0;
  }

  /** 已缓存文件的本地路径（未缓存返回 undefined） */
  cachedFilePathOf(fileHash: string): string | undefined {
    const h = fileHash.trim();
    const dir = `${this.rootDir}/${h}`;
    if (h.length === 0 || this.rootDir.length === 0 || !fs.accessSync(dir)) {
      return undefined;
    }
    try {
      const names = fs.listFileSync(dir);
      for (const n of names) {
        if (n.endsWith('.nascab_tmp')) {
          continue;
        }
        return `${dir}/${n}`;
      }
    } catch (_e) {
    }
    return undefined;
  }

  /** 重新扫描缓存目录（启动/删除后调用） */
  refreshCachedHashes(): void {
    const next = new Set<string>(this.cachedFileHashes);
    if (this.rootDir.length > 0 && fs.accessSync(this.rootDir)) {
      try {
        const names = fs.listFileSync(this.rootDir);
        for (const n of names) {
          if (this.cachedFilePathOf(n) !== undefined) {
            next.add(n);
          }
        }
      } catch (_e) {
      }
    }
    this.cachedFileHashes = next;
  }

  /** 确保已缓存（去重 inflight；已缓存直接返回 true） */
  async ensureCached(fileHash: string, filename: string, filePath: string): Promise<boolean> {
    const h = fileHash.trim();
    if (h.length === 0) {
      return false;
    }
    if (this.isCached(h)) {
      return true;
    }
    const running = this.inflight.get(h);
    if (running !== undefined) {
      return running;
    }
    const task = this.downloadAndCache(h, filename, filePath);
    this.inflight.set(h, task);
    try {
      return await task;
    } finally {
      this.inflight.delete(h);
    }
  }

  private async downloadAndCache(fileHash: string, filename: string, filePath: string): Promise<boolean> {
    if (this.rootDir.length === 0) {
      this.initDir();
      if (this.rootDir.length === 0) {
        return false;
      }
    }
    const url = await ApiUrls.getRawFileUrl(filePath);
    if (url.length === 0) {
      return false;
    }
    const hashDir = `${this.rootDir}/${fileHash}`;
    const safeName = BookLocalCacheService.sanitizeFilename(
      filename.trim().length > 0 ? filename.trim() : fileHash);
    const targetPath = `${hashDir}/${safeName}`;
    const tmpPath = `${hashDir}/${safeName}.nascab_tmp`;
    try {
      if (!fs.accessSync(hashDir)) {
        fs.mkdirSync(hashDir, true);
      }
      const ok = await BookLocalCacheService.downloadToFile(url, tmpPath, fileHash, this);
      if (!ok) {
        return false;
      }
      try {
        if (fs.accessSync(targetPath)) {
          fs.unlinkSync(targetPath);
        }
        fs.renameSync(tmpPath, targetPath);
      } catch (_e) {
      }
      const next = new Set<string>(this.cachedFileHashes);
      next.add(fileHash);
      this.cachedFileHashes = next;
      return true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'downloadAndCache failed: %{public}s', JSON.stringify(e));
      try {
        if (fs.accessSync(tmpPath)) {
          fs.unlinkSync(tmpPath);
        }
      } catch (_e) {
      }
      return false;
    } finally {
      const prog = new Map<string, number>(this.downloadProgress);
      prog.delete(fileHash);
      this.downloadProgress = prog;
    }
  }

  /** 流式下载落盘（dataReceive 分块写文件 + dataReceiveProgress 实时进度） */
  private static async downloadToFile(url: string, targetPath: string,
    fileHash: string, svc: BookLocalCacheService): Promise<boolean> {
    const client = http.createHttp();
    let file: fs.File | undefined = undefined;
    let finished = false;
    const finishWrite = (): void => {
      if (file !== undefined) {
        try {
          fs.fsyncSync(file.fd);
          fs.closeSync(file);
        } catch (_e) {
        }
        file = undefined;
      }
    };
    try {
      const header: Record<string, string> = { 'accept': '*/*' };
      const token = APIClient.getInstance().accessToken;
      if (token !== undefined && token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }
      file = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      client.on('dataReceive', (chunk: ArrayBuffer): void => {
        if (file !== undefined && chunk.byteLength > 0) {
          try {
            fs.writeSync(file.fd, chunk);
          } catch (_e) {
          }
        }
      });
      client.on('dataEnd', (): void => {
        finished = true;
      });
      client.on('dataReceiveProgress', (data: http.DataReceiveProgressInfo): void => {
        const total = data.totalSize;
        const p = total > 0 ? Math.min(1, data.receiveSize / total) : 0;
        const prog = new Map<string, number>(svc.downloadProgress);
        prog.set(fileHash, p);
        svc.downloadProgress = prog;
      });
      // 大文件必须显式调大 maxLimit（默认 5MB 上限）
      const code = await client.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: header,
        readTimeout: 120000,
        connectTimeout: 15000,
        maxLimit: 100 * 1024 * 1024
      });
      if (code !== 200 && code !== 206) {
        return false;
      }
      // dataEnd 与 requestInStream resolve 的时序不保证，轮询等待收尾
      for (let i = 0; i < 100 && !finished; i++) {
        await BookLocalCacheService.sleep(50);
      }
      finishWrite();
      if (!finished) {
        return false;
      }
      const st = fs.statSync(targetPath);
      return st.size > 0;
    } catch (e) {
      hilog.error(0x0000, TAG, 'download failed: %{public}s', JSON.stringify(e));
      return false;
    } finally {
      finishWrite();
      try {
        client.destroy();
      } catch (_e) {
      }
      if (!finished) {
        try {
          if (fs.accessSync(targetPath)) {
            fs.unlinkSync(targetPath);
          }
        } catch (_e) {
        }
      }
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  /** 删除单项缓存 */
  deleteCache(fileHash: string): void {
    const h = fileHash.trim();
    if (h.length === 0 || this.rootDir.length === 0) {
      return;
    }
    const dir = `${this.rootDir}/${h}`;
    try {
      if (fs.accessSync(dir)) {
        fs.rmdirSync(dir);
      }
    } catch (_e) {
    }
    const next = new Set<string>(this.cachedFileHashes);
    next.delete(h);
    this.cachedFileHashes = next;
  }

  /** 清空全部缓存 */
  clearAllCaches(): void {
    if (this.rootDir.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(this.rootDir)) {
        fs.rmdirSync(this.rootDir);
      }
      fs.mkdirSync(this.rootDir, true);
    } catch (_e) {
    }
    this.cachedFileHashes = new Set<string>();
    this.downloadProgress = new Map<string, number>();
  }

  /** 列出全部缓存条目（按修改时间倒序） */
  listCacheEntries(): BookCacheEntry[] {
    const out: BookCacheEntry[] = [];
    if (this.rootDir.length === 0 || !fs.accessSync(this.rootDir)) {
      return out;
    }
    try {
      const hashes = fs.listFileSync(this.rootDir);
      for (const h of hashes) {
        const dir = `${this.rootDir}/${h}`;
        try {
          const names = fs.listFileSync(dir);
          for (const n of names) {
            if (n.endsWith('.nascab_tmp')) {
              continue;
            }
            const p = `${dir}/${n}`;
            const st = fs.statSync(p);
            const e = new BookCacheEntry();
            e.fileHash = h;
            e.filePath = p;
            e.sizeBytes = st.size;
            e.modifiedAt = st.mtime;
            out.push(e);
            break;
          }
        } catch (_e) {
        }
      }
    } catch (_e) {
    }
    out.sort((a: BookCacheEntry, b: BookCacheEntry): number => b.modifiedAt - a.modifiedAt);
    return out;
  }

  /** 文件名净化（对齐 Flutter sanitizeFilename）：非法字符替换、保留名前缀、限 180 字符 */
  static sanitizeFilename(name: string): string {
    let s = name.replace(/[\x00-\x1f<>:"/\\|?*]/g, '_').trim();
    if (s.length === 0) {
      s = 'book';
    }
    const upper = s.toUpperCase();
    const reserved = ['CON', 'PRN', 'AUX', 'NUL',
      'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'];
    if (reserved.includes(upper)) {
      s = `_${s}`;
    }
    if (s.length > 180) {
      s = s.substring(0, 180);
    }
    return s;
  }
}
