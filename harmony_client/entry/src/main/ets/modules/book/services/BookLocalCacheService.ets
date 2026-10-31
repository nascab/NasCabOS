import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WindowStore } from '../../../common/WindowStore';
import { HeaderMap } from '../../../common/HeaderMap';
import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { P2PService } from '../../../p2p/P2PService';
import { P2pRtcChannel } from '../../../p2p/P2pProtocol';

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
    // P2P 模式下 p2p.local 为虚拟域名，HTTP 栈无法解析（CURLcode 6 / Failed to resolve host），
    // 必须改走 RTC download 通道（对齐 Flutter BookLocalCacheService 的 p2p 分支）
    const p2p = APIClient.getInstance().isP2pMode;
    const url = await ApiUrls.getRawFileUrl(filePath, true, p2p ? 'download' : 'file', undefined, true);
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
      const ok = p2p
        ? await BookLocalCacheService.downloadP2pToFile(url, tmpPath, fileHash, this)
        : await BookLocalCacheService.downloadToFile(url, tmpPath, fileHash, this);
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
      // 空文件（如新建的 0 字节 txt）也是合法内容：只要请求正常结束即视为缓存成功
      return true;
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

  /**
   * P2P 模式下载落盘：p2p.local 是虚拟域名（系统 HTTP 栈无法解析），
   * 改走 RTC download 通道流式写文件（对齐 Flutter BookLocalCacheService p2p 分支）。
   * url 为 getRawFileUrl 结果，去掉 p2p.local 前缀后作为通道请求路径。
   */
  private static async downloadP2pToFile(url: string, targetPath: string,
    fileHash: string, svc: BookLocalCacheService): Promise<boolean> {
    const p2pPath = url.startsWith(NetworkConfig.P2P_BASE_URL)
      ? url.substring(NetworkConfig.P2P_BASE_URL.length) : url;
    let file: fs.File | undefined = undefined;
    let finished = false;
    let status = 0;
    let total = 0;
    let loaded = 0;
    let errText = '';
    let failed = false;
    let failedMessage = '';
    const decoder: util.TextDecoder = new util.TextDecoder();
    const headers: HeaderMap = new HeaderMap();
    const token = (APIClient.getInstance().accessToken ?? '').trim();
    if (token.length > 0) {
      headers.set('Authorization', `Bearer ${token}`);
    }
    try {
      file = fs.openSync(targetPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await new Promise<void>((resolve, reject) => {
        P2PService.getInstance().sendOnChannelStream(
          P2pRtcChannel.DOWNLOAD, 'GET', p2pPath, headers, new Uint8Array(0), 600000,
          {
            onBegin: (s: number, h: HeaderMap): void => {
              status = s;
              const raw: string | undefined = h.get('content-length') ?? h.get('Content-Length');
              if (raw !== undefined) {
                const n: number = Number.parseInt(raw, 10);
                total = Number.isFinite(n) && n > 0 ? n : 0;
              }
            },
            onChunk: (data: Uint8Array): void => {
              if (status >= 200 && status < 300) {
                if (file !== undefined) {
                  fs.writeSync(file.fd, data.buffer as ArrayBuffer);
                }
                loaded += data.byteLength;
                const prog = new Map<string, number>(svc.downloadProgress);
                prog.set(fileHash, total > 0 ? Math.min(1, loaded / total) : 0);
                svc.downloadProgress = prog;
              } else if (errText.length < 4096) {
                errText += decoder.decodeToString(data);
              }
            },
            onEnd: (): void => {
              finished = true;
              resolve();
            },
            onError: (e: Error): void => {
              reject(e);
            }
          }
        ).catch((e: Error): void => {
          reject(e);
        });
      });
    } catch (e) {
      failed = true;
      failedMessage = (e as Error).message;
    } finally {
      if (file !== undefined) {
        try {
          fs.fsyncSync(file.fd);
          fs.closeSync(file);
        } catch (_e) {
        }
        file = undefined;
      }
    }
    if (failed) {
      hilog.error(0x0000, TAG, 'p2p download failed: %{public}s', failedMessage);
    }
    if (failed || status < 200 || status >= 300 || !finished) {
      try {
        if (fs.accessSync(targetPath)) {
          fs.unlinkSync(targetPath);
        }
      } catch (_e) {
      }
      return false;
    }
    // 空文件（0 字节）同样视为成功，交由阅读器/编辑器呈现空内容
    return true;
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
