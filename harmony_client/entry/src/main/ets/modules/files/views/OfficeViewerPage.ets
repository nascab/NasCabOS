import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { OfficeViewerPageParam } from '../router/FileRoutes';

const TAG = 'OfficeViewer';
/** 预览器本地拦截域：主框架 URL 指向该域，onInterceptRequest 映射 rawfile/viewer 与本地文件 */
const VIEWER_ORIGIN = 'http://nascab.viewer';
const RAW_BASE = 'viewer/';
const LOCAL_FILE_PATH = '/local/file';

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
  return 'application/octet-stream';
}

function isTextMime(mime: string): boolean {
  return mime === 'text/html' || mime === 'text/css' || mime === 'application/javascript'
    || mime === 'application/json';
}

function officeMimeOf(path: string): string {
  const lower = path.toLowerCase();
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
}

/**
 * Office 预览页（对齐 Flutter _openOfficeFromItem）：
 * Web 组件加载 js-preview 的 docx.html / excel.html（rawfile/viewer 静态资源经拦截器本地映射），
 * fileUrl 指向同源 /local/file，由拦截器以本地缓存文件 fd 直接供页（无跨域）。
 */
@ComponentV2
export struct OfficeViewerPage {
  @Param param: OfficeViewerPageParam = new OfficeViewerPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local startUrl: string = '';
  @Local loading: boolean = true;
  @Local progress: number = 0;
  @Local errorText: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const page = this.param.officeType === 'xlsx' ? 'excel.html' : 'docx.html';
    const fileUrl = `${VIEWER_ORIGIN}${LOCAL_FILE_PATH}`;
    this.startUrl = `${VIEWER_ORIGIN}/viewer/${page}?fileUrl=${encodeURIComponent(fileUrl)}`;
    if (this.param.localPath.trim().length === 0) {
      this.loading = false;
      this.errorText = L10n.networkFailure;
    }
  }

  /**
   * 本地资源拦截：/viewer/<rest> → rawfile/viewer/<rest>；/local/file → 本地缓存文件 fd。
   */
  private interceptRequest(event: OnInterceptRequestEvent): WebResourceResponse | null {
    const url = event.request.getRequestUrl();
    if (!url.startsWith(VIEWER_ORIGIN)) {
      return null;
    }
    let path = url.substring(VIEWER_ORIGIN.length);
    const q = path.indexOf('?');
    if (q >= 0) {
      path = path.substring(0, q);
    }
    if (path === LOCAL_FILE_PATH) {
      return this.serveLocalFile();
    }
    let rest = '';
    if (path === '/viewer' || path === '/viewer/') {
      rest = 'docx.html';
    } else if (path.startsWith('/viewer/')) {
      rest = path.substring('/viewer/'.length);
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

  /**
   * 本地缓存 Office 文件响应（fd 直供）。
   * 注意：setResponseData(number) 的 fd 所有权移交 Web 内核，本页不可再 close。
   */
  private serveLocalFile(): WebResourceResponse {
    const resp = new WebResourceResponse();
    let fd = -1;
    let file: fs.File | undefined = undefined;
    const localPath = this.param.localPath.trim();
    if (localPath.length > 0) {
      try {
        file = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
        fd = file.fd;
      } catch (e) {
        hilog.error(0x0000, TAG, 'open local file failed: %{public}s', JSON.stringify(e));
        file = undefined;
      }
    }
    if (file !== undefined && fd >= 0) {
      try {
        resp.setResponseData(fd);
      } catch (_e) {
        try {
          fs.closeSync(file);
        } catch (_c) {
        }
        fd = -1;
      }
    }
    resp.setResponseMimeType(officeMimeOf(localPath));
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
      if (this.startUrl.length > 0 && this.param.localPath.trim().length > 0) {
        Web({ src: this.startUrl, controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
            return this.interceptRequest(event);
          })
          .onPageBegin((_e: OnPageBeginEvent): void => {
            this.loading = true;
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

        // 顶部 2px 加载进度条
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    .alignContent(Alignment.TopStart)
  }
}
