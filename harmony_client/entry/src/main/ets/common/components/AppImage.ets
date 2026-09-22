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
  /** 是否仍驻留内存缓存；被淘汰但仍有组件展示时为 false */
  cached: boolean = true;
  /** 展示中组件的引用计数（缓存自身不计）；归零且已淘汰时释放 native 内存 */
  refs: number = 0;

  constructor(pixelMap: PixelMap) {
    this.pixelMap = pixelMap;
    this.bytes = pixelMap.getPixelBytesNumber();
  }
}

/** 进行中的下载任务：等待者计数（组件）+ 取消令牌（最后一个等待者离开时中断网络） */
class InflightRequest {
  promise: Promise<PixelMap> = new Promise<PixelMap>((): void => {
  });
  waiters: number = 0;
  cancelled: boolean = false;
  /** 当前实际占用的 http 请求，取消时 destroy 立即中断 */
  httpReq?: http.HttpRequest;
}

export class AppImageLoader {
  /** 内存上限 96MB（移动端设备预算） */
  private static readonly memoryMaxBytes: number = 96 * 1024 * 1024;
  /**
   * 全部已知条目：既包含驻留缓存的，也包含已被淘汰但仍被组件展示的。
   * 淘汰的 PixelMap 不能立即 release（正在显示会黑屏/异常），引用计数归零才释放 native 内存。
   */
  private static readonly entries: Map<string, MemoryEntry> = new Map();
  private static cachedBytes: number = 0;
  private static readonly inflight: Map<string, InflightRequest> = new Map();
  /** 下载+解码并发上限，防止快速滚动/日期跳转时瞬时并发打满连接与内存导致缩略图失败 */
  private static readonly maxJobs: number = 6;
  private static activeJobs: number = 0;
  private static waitQueue: (() => void)[] = [];
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

  /** 组件展示用加载（计入等待者）：内存 → 磁盘 → 网络（带 Bearer header），同 URL 去重 */
  static load(url: string): Promise<PixelMap> {
    const hit = AppImageLoader.entries.get(url);
    if (hit !== undefined) {
      // LRU touch：驻留缓存的条目移到末尾；已被淘汰但仍被持有的保持原位
      if (hit.cached) {
        AppImageLoader.entries.delete(url);
        AppImageLoader.entries.set(url, hit);
      }
      return Promise.resolve(hit.pixelMap);
    }
    let req = AppImageLoader.inflight.get(url);
    if (req !== undefined) {
      req.waiters++;
      return req.promise;
    }
    req = AppImageLoader.startInflight(url, 1);
    return req.promise;
  }

  /**
   * 预取（不占用等待者名额）：仅用于相邻页/全景探测等“加载完进缓存即可”的场景。
   * 组件随后若需要应继续调用 load 等待同一 promise。
   */
  static prefetch(url: string): void {
    if (AppImageLoader.entries.has(url) || AppImageLoader.inflight.has(url)) {
      return;
    }
    AppImageLoader.startInflight(url, 0);
  }

  /** 非组件等待者（全景探测等）拿到结果后释放名额，绝不中断下载 */
  static detach(url: string): void {
    const req = AppImageLoader.inflight.get(url);
    if (req !== undefined && req.waiters > 0) {
      req.waiters--;
    }
  }

  /**
   * 组件放弃某个 URL（页面销毁/切走）：等待者归零且任务仍在进行时中断网络请求，
   * 防止整页销毁后队列里的数百个源文件继续下载（图片浏览器返回时间轴后的请求风暴）。
   * 已被其他组件共享的任务不会被中断。
   */
  static cancelLoad(url: string): void {
    if (url.length === 0) {
      return;
    }
    const req = AppImageLoader.inflight.get(url);
    if (req === undefined) {
      return;
    }
    req.waiters--;
    if (req.waiters > 0) {
      return;
    }
    req.cancelled = true;
    AppImageLoader.inflight.delete(url);
    if (req.httpReq !== undefined) {
      try {
        req.httpReq.destroy();
      } catch (_e) {
        // 请求可能已结束
      }
    }
  }

  private static startInflight(url: string, waiters: number): InflightRequest {
    const req = new InflightRequest();
    req.waiters = waiters;
    const promise = AppImageLoader.doLoad(url, req)
      .then((pm: PixelMap): PixelMap => {
        AppImageLoader.inflight.delete(url);
        if (!req.cancelled) {
          AppImageLoader.store(url, pm);
        }
        return pm;
      })
      .catch((e: Object): never => {
        AppImageLoader.inflight.delete(url);
        throw e instanceof Error ? e : new Error(`${e}`);
      });
    req.promise = promise;
    AppImageLoader.inflight.set(url, req);
    return req;
  }

  /** 组件开始展示某 URL 的 PixelMap 时持有引用 */
  static retain(url: string): void {
    const e = AppImageLoader.entries.get(url);
    if (e !== undefined) {
      e.refs++;
    }
  }

  /** 组件停止展示时释放引用；缓存已淘汰且无人持有时立即回收 native 内存 */
  static release(url: string): void {
    if (url.length === 0) {
      return;
    }
    const e = AppImageLoader.entries.get(url);
    if (e === undefined) {
      return;
    }
    e.refs--;
    if (e.refs <= 0 && !e.cached) {
      try {
        e.pixelMap.release();
      } catch (_err) {
        // 已释放则忽略
      }
      AppImageLoader.entries.delete(url);
    }
  }

  private static async acquireJob(): Promise<void> {
    if (AppImageLoader.activeJobs < AppImageLoader.maxJobs) {
      AppImageLoader.activeJobs++;
      return;
    }
    await new Promise<void>((resolve): void => {
      AppImageLoader.waitQueue.push(resolve);
    });
    AppImageLoader.activeJobs++;
  }

  private static releaseJob(): void {
    AppImageLoader.activeJobs--;
    const next = AppImageLoader.waitQueue.shift();
    if (next !== undefined) {
      next();
    }
  }

  private static store(url: string, pixelMap: PixelMap): void {
    const entry = new MemoryEntry(pixelMap);
    AppImageLoader.entries.set(url, entry);
    AppImageLoader.cachedBytes += entry.bytes;
    while (AppImageLoader.cachedBytes > AppImageLoader.memoryMaxBytes) {
      if (!AppImageLoader.evictOldest()) {
        break;
      }
    }
  }

  /** 淘汰最旧的驻留条目；返回是否找到可淘汰项 */
  private static evictOldest(): boolean {
    const iter = AppImageLoader.entries.keys();
    let result = iter.next();
    while (!result.done) {
      const key = result.value;
      const victim = AppImageLoader.entries.get(key);
      if (victim !== undefined && victim.cached) {
        victim.cached = false;
        AppImageLoader.cachedBytes -= victim.bytes;
        if (victim.refs <= 0) {
          try {
            victim.pixelMap.release();
          } catch (_err) {
            // 已释放则忽略
          }
          AppImageLoader.entries.delete(key);
        }
        return true;
      }
      result = iter.next();
    }
    return false;
  }

  private static async doLoad(url: string, req: InflightRequest): Promise<PixelMap> {
    await AppImageLoader.acquireJob();
    try {
      if (req.cancelled) {
        throw new Error('image_cancelled');
      }
      let buffer: ArrayBuffer | undefined = await AppImageLoader.readDisk(url);
      if (!buffer || buffer.byteLength === 0) {
        buffer = await AppImageLoader.download(url, req);
        if (req.cancelled) {
          // 网络已中断/放弃：不落盘、不解码
          throw new Error('image_cancelled');
        }
        AppImageLoader.writeDisk(url, buffer);
      }
      if (req.cancelled) {
        throw new Error('image_cancelled');
      }
      return await AppImageLoader.decode(buffer);
    } finally {
      AppImageLoader.releaseJob();
    }
  }

  private static async download(url: string, req: InflightRequest): Promise<ArrayBuffer> {
    const token = (APIClient.getInstance().state.accessToken ?? '').trim();
    const headers: Record<string, string> = {};
    if (token.length > 0) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    const httpReq = http.createHttp();
    req.httpReq = httpReq;
    try {
      const resp = await httpReq.request(url, {
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
      httpReq.destroy();
      req.httpReq = undefined;
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

  /** 解码：超过 2560px 的长边按比例缩小，控制内存；异常时确保释放 ImageSource */
  private static async decode(buffer: ArrayBuffer): Promise<PixelMap> {
    const source = image.createImageSource(buffer);
    try {
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
      return await source.createPixelMap(options);
    } finally {
      source.release();
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
  /** 加载结果回调（成功 true / 失败 false）：用于主图失败切换备选图等场景 */
  @Param onLoaded: (ok: boolean) => void = (_ok: boolean): void => {
  };
  @Local pixelMap: PixelMap | undefined = undefined;
  @Local failed: boolean = false;
  private loadSeq: number = 0;
  /** tiny 404/202 退避重试计数与定时器（对齐 Flutter _tiny404RetryCount/_tiny404RetryTimer） */
  private retryCount: number = 0;
  private retryTimer: number = -1;
  /** 当前组件持有展示权的图片 URL（与 AppImageLoader 引用计数配对） */
  private heldUrl: string = '';

  aboutToAppear(): void {
    AppImageLoader.initCacheDir(getContext(this).cacheDir);
    void this.reload();
  }

  /** 组件销毁时取消挂起的重试定时器并释放持有的 PixelMap 引用（对齐 Flutter dispose cancel） */
  aboutToDisappear(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    this.releaseHeld();
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

  private releaseHeld(): void {
    if (this.heldUrl.length > 0) {
      AppImageLoader.release(this.heldUrl);
      this.heldUrl = '';
    }
  }

  private async reload(): Promise<void> {
    const seq = ++this.loadSeq;
    const target = this.url.trim();
    if (target.length === 0 || this.isLocal(target)) {
      this.releaseHeld();
      this.pixelMap = undefined;
      this.failed = false;
      return;
    }
    try {
      const pm = await AppImageLoader.load(target);
      if (seq !== this.loadSeq) {
        return;
      }
      // 先持有新图、再释放旧图，保证缓存条目引用始终平衡
      AppImageLoader.retain(target);
      const previous = this.heldUrl;
      this.heldUrl = target;
      this.pixelMap = pm;
      this.failed = false;
      this.retryCount = 0;
      if (previous.length > 0 && previous !== target) {
        AppImageLoader.release(previous);
      }
      this.onLoaded(true);
    } catch (e) {
      if (seq !== this.loadSeq) {
        return;
      }
      if (AppImageLoader.isTinyPendingError(target, e as Object)) {
        // 缩略图服务端生成中：释放旧图、保持加载占位，指数退避重试，重试耗尽才显示失败
        if (this.retryCount < AppImageLoader.TINY_MAX_RETRIES) {
          this.releaseHeld();
          this.pixelMap = undefined;
          this.failed = false;
          this.scheduleRetry();
          return;
        }
      }
      this.releaseHeld();
      this.pixelMap = undefined;
      this.failed = true;
      this.onLoaded(false);
    }
  }

  build() {
    Stack() {
      if (this.isLocal(this.url)) {
        Image(this.url)
          .objectFit(this.objectFit)
          .draggable(false)
          .width('100%')
          .height('100%')
      } else if (this.pixelMap) {
        Image(this.pixelMap)
          .objectFit(this.objectFit)
          .draggable(false)
          .width('100%')
          .height('100%')
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
