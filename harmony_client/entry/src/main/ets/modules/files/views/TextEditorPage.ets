import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { TextEditorPageParam } from '../router/FileRoutes';
import { EditorApiService, EditorOpenResult } from '../service/EditorApiService';

/** 编辑器本地拦截域：主框架 URL 指向该域，onInterceptRequest 映射到 rawfile/editor */
const EDITOR_ORIGIN = 'http://nascab.editor';
const RAW_BASE = 'editor/';
/** 移动端单文件编辑上限（对齐 Flutter 移动端 80KB 限制） */
const MAX_EDITOR_BYTES = 80 * 1024;

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
  return 'application/octet-stream';
}

function isTextMime(mime: string): boolean {
  return mime === 'text/html' || mime === 'text/css' || mime === 'application/javascript';
}

/** 文件扩展名（小写，不含点） */
function extOf(path: string): string {
  const name = path.trim();
  const dot = name.lastIndexOf('.');
  if (dot < 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

/** 扩展名 → editor.html 内置高亮语言标识 */
function languageOf(path: string): string {
  const ext = extOf(path);
  if (ext === 'md' || ext === 'markdown') {
    return 'markdown';
  }
  if (ext === 'json') {
    return 'json';
  }
  if (ext === 'yaml' || ext === 'yml') {
    return 'yaml';
  }
  if (ext === 'xml' || ext === 'html' || ext === 'vue' || ext === 'svelte') {
    return 'xml';
  }
  if (ext === 'css' || ext === 'scss' || ext === 'less') {
    return 'css';
  }
  if (ext === 'py' || ext === 'dart') {
    return 'python';
  }
  if (ext === 'sh' || ext === 'bash' || ext === 'zsh' || ext === 'bat' || ext === 'cmd' || ext === 'ps1') {
    return 'shell';
  }
  if (ext === 'js' || ext === 'jsx' || ext === 'ts' || ext === 'tsx' || ext === 'mjs' || ext === 'cjs') {
    return 'js';
  }
  if (ext === 'c' || ext === 'cc' || ext === 'cpp' || ext === 'h' || ext === 'hpp' || ext === 'java'
    || ext === 'kt' || ext === 'kts' || ext === 'go' || ext === 'rs' || ext === 'swift' || ext === 'php'
    || ext === 'rb' || ext === 'lua' || ext === 'sql' || ext === 'gradle' || ext === 'ets') {
    return 'c';
  }
  return 'plain';
}

function baseNameOf(path: string): string {
  const p = path.trim();
  if (p.length === 0) {
    return '';
  }
  const idx = p.lastIndexOf('/');
  return idx >= 0 ? p.substring(idx + 1) : p;
}

/**
 * 文本编辑器（对齐 Flutter TextEditorPage）：
 * - 打开：EditorApiService.open 读取服务端文本 + 是否可写 + 用户字号
 * - 编辑区：Web 组件加载 rawfile/editor/editor.html（透明 textarea + 语法高亮层），
 *   文本以 base64 注入避免引号/换行转义问题，保存时经 runJavaScript 取回
 * - 保存：POST /api/editor/save，成功提示已保存；不可写时隐藏保存按钮（只读）
 */
@ComponentV2
export struct TextEditorPage {
  @Param param: TextEditorPageParam = new TextEditorPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local ready: boolean = false;
  @Local canWrite: boolean = false;
  @Local saving: boolean = false;
  @Local injected: boolean = false;
  private webController: webview.WebviewController = new webview.WebviewController();
  /** 服务端原文（用于脏检查，保存后同步更新） */
  private initialText: string = '';
  private fontSize: number = 14;

  aboutToAppear(): void {
    void this.loadDoc();
  }

  private titleText(): string {
    const t = this.param.title.trim();
    return t.length > 0 ? t : baseNameOf(this.param.path);
  }

  /** 读取文件内容；超过移动端上限时提示并退出 */
  private async loadDoc(): Promise<void> {
    try {
      const res = await new EditorApiService().open(this.param.path);
      if (!res.success || res.data === undefined) {
        this.loading = false;
        this.errorText = (res.message ?? '').length > 0 ? `${res.message}` : L10n.operationFailed;
        return;
      }
      const data: EditorOpenResult = res.data;
      if (data.size > MAX_EDITOR_BYTES) {
        this.loading = false;
        void DialogUtil.showInfoDialog(L10n.t('tip', '提示'),
          L10n.t('editor_file_too_large', '文件体积过大，无法使用文本编辑器打开'), L10n.ok,
          (): void => {
            this.popPage();
          });
        return;
      }
      this.initialText = data.text;
      this.canWrite = data.canWrite;
      this.fontSize = data.config.fontSize;
      this.ready = true;
      this.loading = false;
    } catch (_e) {
      this.loading = false;
      this.errorText = L10n.networkFailure;
    }
  }

  /** 本地资源拦截：http://nascab.editor/editor/<rest> → rawfile/editor/<rest> */
  private interceptRequest(event: OnInterceptRequestEvent): WebResourceResponse | null {
    const url = event.request.getRequestUrl();
    if (!url.startsWith(EDITOR_ORIGIN)) {
      return null;
    }
    let path = url.substring(EDITOR_ORIGIN.length);
    const q = path.indexOf('?');
    if (q >= 0) {
      path = path.substring(0, q);
    }
    let rest = '';
    if (path === '/editor' || path === '/editor/') {
      rest = 'editor.html';
    } else if (path.startsWith('/editor/')) {
      rest = path.substring('/editor/'.length);
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

  /** 页面加载完成后注入文本（仅一次） */
  private injectContent(): void {
    if (this.injected) {
      return;
    }
    this.injected = true;
    try {
      const b64 = new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(this.initialText));
      const lang = languageOf(this.param.path);
      const dark = AppTheme.isDark() ? 'true' : 'false';
      const readOnly = this.canWrite ? 'false' : 'true';
      const script = `window.editorApi.setContent('${b64}',{language:'${lang}',`
        + `fontSize:${this.fontSize},dark:${dark},readOnly:${readOnly}})`;
      void this.webController.runJavaScript(script);
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    }
  }

  /** 从 Web 侧取回当前编辑内容（失败返回空串） */
  private async currentText(): Promise<string> {
    try {
      const v = await this.webController.runJavaScript('window.editorApi.getText()');
      return v === undefined || v === null ? '' : `${v}`;
    } catch (_e) {
      return '';
    }
  }

  /** 保存到服务端 */
  private async saveDoc(): Promise<void> {
    if (!this.canWrite || this.saving || !this.injected) {
      return;
    }
    this.saving = true;
    const text = await this.currentText();
    try {
      const res = await new EditorApiService().save(this.param.path, text);
      if (res.success && res.data === true) {
        this.initialText = text;
        ToastUtil.show(L10n.t('editor_status_saved', '已保存'));
      } else {
        ToastUtil.show((res.message ?? '').length > 0 ? `${res.message}` : L10n.operationFailed);
      }
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
    }
    this.saving = false;
  }

  /** 返回：有未保存修改时二次确认 */
  private handleBack(): void {
    if (this.saving) {
      return;
    }
    if (!this.injected) {
      this.popPage();
      return;
    }
    void this.currentText().then((text: string): void => {
      if (text === this.initialText) {
        this.popPage();
        return;
      }
      void DialogUtil.showConfirmDialog(L10n.t('discard_changes_title', '放弃修改？'),
        L10n.t('discard_changes_message', '当前修改尚未保存，确定要离开吗？'),
        undefined, L10n.t('discard', '放弃'), L10n.cancel).then((r: boolean | number | string | undefined): void => {
        if (r === true) {
          this.popPage();
        }
      });
    });
  }

  build() {
    PageScaffold({
      title: this.titleText(),
      showBack: true,
      onBack: (): void => {
        this.handleBack();
      },
      customBack: (): boolean => {
        this.handleBack();
        return true;
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.PageBody()
      }
    })
  }

  @Builder
  TitleActions() {
    if (this.ready && this.canWrite) {
      Button(this.saving ? L10n.t('editor_status_saving', '保存中...') : L10n.t('save', '保存'))
        .fontSize(14)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .height(32)
        .padding({ left: 14, right: 14 })
        .enabled(!this.saving)
        .onClick(() => {
          void this.saveDoc();
        })
    } else if (this.ready) {
      Text(L10n.t('editor_status_readonly', '只读'))
        .fontSize(13)
        .fontColor(AppTheme.current().subText)
    }
  }

  @Builder
  PageBody() {
    Stack() {
      if (this.ready) {
        Web({ src: `${EDITOR_ORIGIN}/editor/editor.html`, controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
            return this.interceptRequest(event);
          })
          .onPageEnd((_e: OnPageEndEvent): void => {
            this.injectContent();
          })
          .onErrorReceive((e: OnErrorReceiveEvent): void => {
            if (!e.request.isMainFrame()) {
              return;
            }
            this.errorText = `${e.error.getErrorCode()} ${e.error.getErrorInfo()}`;
          })
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

      // 底部错误提示框（对齐 BookWebReaderPage 样式）
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
