import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { PageScaffold } from '../../../common/PageScaffold';
import { BookWebReaderParam } from '../router/BookRoutes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BookWebReader';
/** 阅读器本地拦截域：主框架 URL 指向该域，onInterceptRequest 映射到 rawfile/book_reader */
const READER_ORIGIN = 'http://nascab.reader';
const RAW_BASE = 'book_reader/';

function basenameOf(path: string): string {
  const p = path.trim();
  if (p.length === 0) {
    return '';
  }
  const idx = p.lastIndexOf('/');
  return idx >= 0 ? p.substring(idx + 1) : p;
}

function mimeOf(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return 'text/html';
  }
  if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
    return 'application/javascript';
  }
  if (lower.endsWith('.css')) {
    return 'text/css';
  }
  if (lower.endsWith('.json')) {
    return 'application/json';
  }
  if (lower.endsWith('.txt')) {
    return 'text/plain';
  }
  if (lower.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.woff2')) {
    return 'font/woff2';
  }
  if (lower.endsWith('.woff')) {
    return 'font/woff';
  }
  if (lower.endsWith('.ttf')) {
    return 'font/ttf';
  }
  if (lower.endsWith('.otf')) {
    return 'font/otf';
  }
  if (lower.endsWith('.wasm')) {
    return 'application/wasm';
  }
  // bcmap / pfb / 其他二进制资源（对齐 Flutter LocalWebAssetServer 兜底）
  return 'application/octet-stream';
}

function isTextMime(mime: string): boolean {
  return mime === 'text/html' || mime === 'text/css' || mime === 'text/plain'
    || mime === 'application/javascript' || mime === 'application/json'
    || mime === 'image/svg+xml';
}

/** 电子书文件 MIME（reader.js 按 filename 参数判格式，MIME 仅供内核参考） */
function bookMimeOf(name: string): string {
  const lower = name.toLowerCase();
  if (lower.endsWith('.epub')) {
    return 'application/epub+zip';
  }
  if (lower.endsWith('.mobi') || lower.endsWith('.prc')) {
    return 'application/x-mobipocket-ebook';
  }
  if (lower.endsWith('.azw3') || lower.endsWith('.azw') || lower.endsWith('.kfx')) {
    return 'application/vnd.amazon.ebook';
  }
  if (lower.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (lower.endsWith('.fb2') || lower.endsWith('.xml')) {
    return 'application/xml';
  }
  return 'application/octet-stream';
}

/**
 * Web 阅读器（对齐 Flutter BookWebReaderPage，epub/mobi/azw3 等）：
 * Web 组件加载 foliate reader.html（rawfile/book_reader 静态资源经 onInterceptRequest 本地映射，
 * 主框架域 http://nascab.reader 使相对路径与 CSP 'self' 一致），携带
 * url（rawFile + scoped token）/lang/file_hash/filename/accessToken/apiBase 查询参数，
 * 阅读器 JS 直连服务器上报进度（/api/book/history、/api/book/preference，Bearer scoped token）。
 * 顶部 2px 加载进度条 + 底部错误提示框（对齐 Flutter 版式）。
 */
@ComponentV2
export struct BookWebReaderPage {
  @Param param: BookWebReaderParam = new BookWebReaderParam();
  @Param popPage: () => void = (): void => {
  };
  @Local startUrl: string = '';
  @Local loading: boolean = true;
  @Local progress: number = 0;
  @Local errorText: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  /** 本地文件 serve 打开的 fd 集合（aboutToDisappear 统一关闭） */
  private servedFds: Set<number> = new Set();

  aboutToAppear(): void {
    void this.buildStartUrl();
  }

  aboutToDisappear(): void {
    this.servedFds.forEach((fd: number): void => {
      try {
        fs.closeSync(fd);
      } catch (_e) {
        // 忽略关闭失败
      }
    });
    this.servedFds.clear();
  }

  /** 为一次本地文件请求打开独立 fd（内核按 fd 读取，避免共享偏移竞态） */
  private openServeFd(): number {
    if (this.param.localPath.length === 0) {
      return -1;
    }
    try {
      const f: fs.File = fs.openSync(this.param.localPath, fs.OpenMode.READ_ONLY);
      this.servedFds.add(f.fd);
      return f.fd;
    } catch (_e) {
      return -1;
    }
  }

  /** 组装阅读器 URL（对齐 Flutter book_item_card 打开逻辑的查询参数集合） */
  private async buildStartUrl(): Promise<void> {
    const scopedToken = this.param.url.trim();
    let filename = this.param.filename.trim();
    if (filename.length === 0) {
      filename = basenameOf(this.param.filePath);
    }
    try {
      // 对齐 Flutter app 端：本地缓存文件优先（经 /local/ 拦截器 fd 供页），无缓存回退服务器 URL
      const bookUrl = this.param.localPath.length > 0
        ? `${READER_ORIGIN}/local/${encodeURIComponent(basenameOf(this.param.localPath))}`
        : await ApiUrls.getRawFileUrl(this.param.filePath, true, 'download',
          scopedToken.length > 0 ? scopedToken : undefined);
      const apiBase = APIClient.getInstance().state.baseUrl.trim();
      const lang = L10n.localeHttpTag;
      let url = `${READER_ORIGIN}/reader/reader.html?url=${encodeURIComponent(bookUrl)}`
        + `&lang=${encodeURIComponent(lang)}`
        + `&file_hash=${encodeURIComponent(this.param.fileHash.trim())}`
        + `&filename=${encodeURIComponent(filename)}`;
      if (scopedToken.length > 0) {
        url += `&accessToken=${encodeURIComponent(scopedToken)}`;
      }
      if (apiBase.length > 0) {
        url += `&apiBase=${encodeURIComponent(apiBase)}`;
      }
      this.startUrl = url;
    } catch (e) {
      hilog.error(0x0000, TAG, 'buildStartUrl failed: %{public}s', JSON.stringify(e));
      this.loading = false;
      this.errorText = L10n.networkFailure;
    }
  }

  /**
   * 本地资源拦截：https://nascab.reader/reader/<rest> → rawfile/book_reader/<rest>；
   * 其余（服务器文件与 API）放行走网络。$rawfile Resource 直接作为响应数据，无内存拷贝。
   */
  private interceptRequest(event: OnInterceptRequestEvent): WebResourceResponse | null {
    const url = event.request.getRequestUrl();
    if (!url.startsWith(READER_ORIGIN)) {
      return null;
    }
    let path = url.substring(READER_ORIGIN.length);
    const q = path.indexOf('?');
    if (q >= 0) {
      path = path.substring(0, q);
    }
    let rest = '';
    if (path === '/reader' || path === '/reader/') {
      rest = 'reader.html';
    } else if (path.startsWith('/reader/')) {
      rest = path.substring('/reader/'.length);
    } else if (path.startsWith('/local/')) {
      // 本地缓存图书文件：fd 直供（对齐 Flutter LocalWebAssetServer 本地 serve）
      return this.serveLocalFile();
    } else {
      return null;
    }
    if (rest.length === 0 || rest.includes('..')) {
      return null;
    }
    const mime = mimeOf(rest);
    const resp = new WebResourceResponse();
    resp.setResponseData($rawfile(RAW_BASE + rest));
    resp.setResponseMimeType(mime);
    if (isTextMime(mime)) {
      resp.setResponseEncoding('utf-8');
    }
    resp.setResponseCode(200);
    resp.setReasonMessage('OK');
    resp.setResponseIsReady(true);
    const headers: Header[] = [];
    headers.push({ headerKey: 'Cache-Control', headerValue: 'no-store' });
    resp.setResponseHeader(headers);
    return resp;
  }

  /** 本地缓存图书文件响应（fd 方式，内核读取后自行消费，fd 在页面销毁时统一关闭） */
  private serveLocalFile(): WebResourceResponse {
    const resp = new WebResourceResponse();
    const fd = this.openServeFd();
    if (fd >= 0) {
      resp.setResponseData(fd);
    }
    resp.setResponseMimeType(bookMimeOf(this.param.localPath));
    resp.setResponseCode(fd >= 0 ? 200 : 404);
    resp.setReasonMessage(fd >= 0 ? 'OK' : 'Not Found');
    resp.setResponseIsReady(true);
    return resp;
  }

  build() {
    PageScaffold({
      title: this.param.title,
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageBody()
      }
    })
  }

  @Builder
  PageBody() {
    Stack() {
      if (this.startUrl.length > 0) {
        Web({ src: this.startUrl, controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
            return this.interceptRequest(event);
          })
          .onPageBegin((_e: OnPageBeginEvent): void => {
            this.loading = true;
            this.errorText = '';
          })
          .onPageEnd((_e: OnPageEndEvent): void => {
            this.loading = false;
          })
          .onProgressChange((e: OnProgressChangeEvent): void => {
            this.progress = e.newProgress;
          })
          .onErrorReceive((e: OnErrorReceiveEvent): void => {
            if (!e.request.isMainFrame()) {
              return;
            }
            this.loading = false;
            this.errorText = `${e.error.getErrorCode()} ${e.error.getErrorInfo()}`;
          })

        // 顶部 2px 加载进度条（对齐 Flutter LinearProgressIndicator）
        if (this.loading) {
          Row() {
            Progress({ value: this.progress > 0 && this.progress < 100 ? this.progress : 8, total: 100,
              type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color(AppTheme.current().primary)
              .backgroundColor(AppTheme.current().surfaceBg)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .hitTestBehavior(HitTestMode.None)
        }

        // 底部错误提示框（对齐 Flutter errorContainer 样式）
        if (this.errorText.length > 0) {
          Row() {
            Text(this.errorText)
              .fontSize(12)
              .fontColor(AppTheme.current().buttonText)
              .maxLines(5)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(AppTheme.current().error)
          .borderRadius(12)
          .margin({ left: 12, right: 12, bottom: 12 })
          .justifyContent(FlexAlign.Center)
        }
      } else if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    .alignContent(Alignment.TopStart)
  }
}
