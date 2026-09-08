import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { APIClient } from '../../core/network/APIClient';
import { AppTheme } from '../../core/theme/AppTheme';
import { L10n } from '../../core/localization/L10n';

/**
 * 统一图片加载器（对齐 Flutter CustomExtendedImage 能力）：
 * Bearer header 下载 → 磁盘缓存（cacheDir/app_images）→ 内存 LRU（按字节上限）→ PixelMap；
 * 同 URL 请求去重（inflight 复用），失败抛错由组件呈现占位/重试。
 */

/** 内存缓存条目（按字节上限淘汰最旧） */
class MemoryEntry {
  pixelMap: PixelMap;
  bytes: number;

  constructor(pixelMap: PixelMap) {
    this.pixelMap = pixelMap;
    this.bytes = pixelMap.getPixelBytesNumber();
  }
}

export class AppImageLoader {
  /** 内存上限 96MB（移动端设备预算） */
  private static readonly memoryMaxBytes: number = 96 * 1024 * 1024;
  private static readonly memoryCache: Map<string, MemoryEntry> = new Map();
  private static readonly inflight: Map<string, Promise<PixelMap>> = new Map();
  private static cacheDir: string = '';

  /** tiny 缩略图退避重试配置（对齐 Flutter _kTiny404MaxRetries） */
  static readonly TINY_MAX_RETRIES: number = 5;
  static readonly TINY_INITIAL_DELAY_MS: number = 500;

  /** 是否 tiny 缩略图接口 URL（对齐 Flutter _isTinyUrl：服务端可能异步生成中返回 404/202） */
  static isTinyUrl(url: string): boolean {
    return url.includes('/api/file/tiny');
  }

  /** 是否可重试的 tiny 生成中错误（对齐 Flutter _isTinyPendingError） */
  static isTinyPendingError(url: string, error: Object): boolean {
    if (!AppImageLoader.isTinyUrl(url)) {
      return false;
    }
    const s = `${error}`;
    return s.includes('image_http_404') || s.includes('image_http_202');
  }

  /** 由 AppImage 组件注入应用缓存目录（getContext(this).cacheDir） */
  static initCacheDir(dir: string): void {
    if (AppImageLoader.cacheDir.length > 0 || dir.length === 0) {
      return;
    }
    AppImageLoader.cacheDir = `${dir}/app_images`;
    try {
      if (!fs.accessSync(AppImageLoader.cacheDir)) {
        fs.mkdirSync(AppImageLoader.cacheDir, true);
      }
      // 清理历史污染文件（早期版本 sha256 返回 Promise，所有 URL 共用同一个缓存文件）
      const poisoned = `${AppImageLoader.cacheDir}/[object Promise]`;
      if (fs.accessSync(poisoned)) {
        fs.unlinkSync(poisoned);
      }
    } catch (_e) {
      // 目录创建失败时禁用磁盘缓存（仅内存）
      AppImageLoader.cacheDir = '';
    }
  }

  /** 主入口：内存 → 磁盘 → 网络（带 Bearer header），同 URL 去重 */
  static load(url: string): Promise<PixelMap> {
    const entry = AppImageLoader.memoryCache.get(url);
    if (entry) {
      // LRU touch：移到末尾
      AppImageLoader.memoryCache.delete(url);
      AppImageLoader.memoryCache.set(url, entry);
      return Promise.resolve(entry.pixelMap);
    }
    const running = AppImageLoader.inflight.get(url);
    if (running) {
      return running;
    }
    const task = AppImageLoader.doLoad(url);
    AppImageLoader.inflight.set(url, task);
    task.then((pm: PixelMap): void => {
      AppImageLoader.inflight.delete(url);
      AppImageLoader.cachePut(url, pm);
    }).catch((_e: Object): void => {
      AppImageLoader.inflight.delete(url);
    });
    return task;
  }

  private static async doLoad(url: string): Promise<PixelMap> {
    let buffer: ArrayBuffer | undefined = await AppImageLoader.readDisk(url);
    if (!buffer || buffer.byteLength === 0) {
      buffer = await AppImageLoader.download(url);
      AppImageLoader.writeDisk(url, buffer);
    }
    return AppImageLoader.decode(buffer);
  }

  private static async download(url: string): Promise<ArrayBuffer> {
    const token = (APIClient.getInstance().state.accessToken ?? '').trim();
    const headers: Record<string, string> = {};
    if (token.length > 0) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    const req = http.createHttp();
    try {
      const resp = await req.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 60000,
        // 原图常超过默认 5MB 响应上限（超限直接报错），放宽到模块最大值 100MB
        maxLimit: 100 * 1024 * 1024,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        remoteValidation: 'skip',
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error(`image_http_${resp.responseCode}`);
      }
      return resp.result as ArrayBuffer;
    } finally {
      req.destroy();
    }
  }

  private static diskPath(url: string): string {
    return `${AppImageLoader.cacheDir}/${AppImageLoader.hashKey(url)}_${url.length}`;
  }

  /** 同步 64 位双种子 FNV-1a 哈希（碰撞概率可忽略）。不能用 async crypto：Promise 插值会令所有 URL 共用一个文件名 */
  private static hashKey(input: string): string {
    let h1 = 0x811c9dc5;
    let h2 = 0x01000193;
    for (let i = 0; i < input.length; i++) {
      const c = input.charCodeAt(i);
      h1 = Math.imul((h1 ^ c) >>> 0, 0x01000193) >>> 0;
      h2 = Math.imul((h2 ^ ((c << 3) | (c >>> 29))) >>> 0, 0x85ebca6b) >>> 0;
    }
    return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0');
  }

  private static async readDisk(url: string): Promise<ArrayBuffer | undefined> {
    if (AppImageLoader.cacheDir.length === 0) {
      return undefined;
    }
    try {
      const path = AppImageLoader.diskPath(url);
      if (!fs.accessSync(path)) {
        return undefined;
      }
      const stat = fs.statSync(path);
      if (stat.size <= 0) {
        return undefined;
      }
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        return buf;
      } finally {
        fs.closeSync(file);
      }
    } catch (_e) {
      return undefined;
    }
  }

  private static writeDisk(url: string, buffer: ArrayBuffer): void {
    if (AppImageLoader.cacheDir.length === 0 || buffer.byteLength === 0) {
      return;
    }
    try {
      const path = AppImageLoader.diskPath(url);
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
    } catch (_e) {
      // 磁盘缓存写失败静默忽略
    }
  }

  /** 解码：超过 2560px 的长边按比例缩小，控制内存 */
  private static async decode(buffer: ArrayBuffer): Promise<PixelMap> {
    const source = image.createImageSource(buffer);
    const info = await source.getImageInfo();
    const maxEdge = Math.max(info.size.width, info.size.height);
    const options: image.DecodingOptions = {};
    if (maxEdge > 2560) {
      const scale = 2560 / maxEdge;
      options.desiredSize = {
        width: Math.round(info.size.width * scale),
        height: Math.round(info.size.height * scale)
      };
    }
    const pixelMap = await source.createPixelMap(options);
    source.release();
    return pixelMap;
  }

  private static cachePut(url: string, pixelMap: PixelMap): void {
    const entry = new MemoryEntry(pixelMap);
    AppImageLoader.memoryCache.delete(url);
    AppImageLoader.memoryCache.set(url, entry);
    let total = 0;
    AppImageLoader.memoryCache.forEach((e: MemoryEntry): void => {
      total += e.bytes;
    });
    while (total > AppImageLoader.memoryMaxBytes && AppImageLoader.memoryCache.size > 1) {
      const oldest = AppImageLoader.memoryCache.keys().next();
      if (oldest.done === true) {
        break;
      }
      const old = AppImageLoader.memoryCache.get(oldest.value);
      AppImageLoader.memoryCache.delete(oldest.value);
      total -= old ? old.bytes : 0;
    }
  }
}

/**
 * 统一图片组件（对齐 Flutter CustomExtendedImage）：
 * - 网络图：AppImageLoader 加载（Bearer header + 磁盘/内存缓存 + 去重）
 * - 本地图（file:// 或沙箱路径）：直接 Image 显示
 * - 加载中占位（灰块 + 可选转圈）、失败占位（点击重试）
 * 尺寸由调用方约束；圆角由 imageRadius 处理。
 */
@ComponentV2
export struct AppImage {
  @Param url: string = '';
  @Param objectFit: ImageFit = ImageFit.Cover;
  @Param imageRadius: number = 0;
  /** 加载中是否显示转圈（小缩略图场景可关） */
  @Param showLoadingSpin: boolean = true;
  @Local pixelMap: PixelMap | undefined = undefined;
  @Local failed: boolean = false;
  private loadSeq: number = 0;
  /** tiny 404/202 退避重试计数与定时器（对齐 Flutter _tiny404RetryCount/_tiny404RetryTimer） */
  private retryCount: number = 0;
  private retryTimer: number = -1;

  aboutToAppear(): void {
    AppImageLoader.initCacheDir(getContext(this).cacheDir);
    void this.reload();
  }

  /** 组件销毁时取消挂起的重试定时器（对齐 Flutter dispose cancel） */
  aboutToDisappear(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  /** 组件复用时 url 变化重新加载（重置重试计数，对齐 Flutter didUpdateWidget） */
  @Monitor('url')
  onUrlChange(): void {
    this.retryCount = 0;
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    void this.reload();
  }

  private isLocal(target: string): boolean {
    return target.length > 0 && !target.startsWith('http://') && !target.startsWith('https://');
  }

  /** tiny 生成中的指数退避重试：delay = 500ms × 2^count，最多 5 次 */
  private scheduleRetry(): void {
    if (this.retryTimer >= 0 || this.retryCount >= AppImageLoader.TINY_MAX_RETRIES) {
      return;
    }
    const delay = AppImageLoader.TINY_INITIAL_DELAY_MS * (1 << this.retryCount);
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.retryCount++;
      void this.reload();
    }, delay);
  }

  private async reload(): Promise<void> {
    const seq = ++this.loadSeq;
    const target = this.url.trim();
    if (target.length === 0 || this.isLocal(target)) {
      this.pixelMap = undefined;
      this.failed = false;
      return;
    }
    try {
      const pm = await AppImageLoader.load(target);
      if (seq !== this.loadSeq) {
        return;
      }
      this.pixelMap = pm;
      this.failed = false;
      this.retryCount = 0;
    } catch (e) {
      if (seq !== this.loadSeq) {
        return;
      }
      if (AppImageLoader.isTinyPendingError(target, e as Object)) {
        // 缩略图服务端生成中：保持加载占位，指数退避重试，重试耗尽才显示失败
        if (this.retryCount < AppImageLoader.TINY_MAX_RETRIES) {
          this.pixelMap = undefined;
          this.failed = false;
          this.scheduleRetry();
          return;
        }
      }
      this.pixelMap = undefined;
      this.failed = true;
    }
  }

  build() {
    Stack() {
      if (this.isLocal(this.url)) {
        Image(this.url)
          .objectFit(this.objectFit)
          .draggable(false)
      } else if (this.pixelMap) {
        Image(this.pixelMap)
          .objectFit(this.objectFit)
          .draggable(false)
      } else if (this.failed) {
        // 失败占位：点击重试
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(18)
            .fontColor([AppTheme.withAlpha('#FFFFFF', 0.4)])
          Text(L10n.t('tap_to_retry', '点击重试'))
            .fontSize(11)
            .fontColor(AppTheme.withAlpha('#FFFFFF', 0.4))
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
        .onClick(() => {
          void this.reload();
        })
      } else {
        // 加载中占位
        Column() {
          if (this.showLoadingSpin) {
            LoadingProgress()
              .width(26)
              .height(26)
              .color(AppTheme.withAlpha('#FFFFFF', 0.35))
          }
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
    .borderRadius(this.imageRadius)
    .clip(true)
  }
}
