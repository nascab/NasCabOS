import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { TextEditorPageParam } from '../router/FileRoutes';
import { EditorApiService, EditorOpenResult } from '../service/EditorApiService';

/** 编辑器单文件编辑上限（对齐 Flutter 移动端 80KB 限制） */
const MAX_EDITOR_BYTES = 80 * 1024;

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

  /** UTF-8 文本转 base64（空文本返回空串，规避运行时 encodeInto 对空值返回 undefined） */
  private encodeBase64(text: string): string {
    if (text.length === 0) {
      return '';
    }
    const bytes = new util.TextEncoder().encodeInto(text);
    if (bytes === undefined) {
      return '';
    }
    return new util.Base64Helper().encodeToStringSync(bytes);
  }

  /** 页面加载完成后注入文本（注入成功才算完成，失败允许下次 onPageEnd 重试） */
  private injectContent(): void {
    if (this.injected) {
      return;
    }
    try {
      // 空内容时 encodeInto 返回 undefined，Base64Helper 也无法编码空数组，直接给空串
      const b64 = this.encodeBase64(this.initialText ?? '');
      const lang = languageOf(this.param.path);
      const dark = AppTheme.isDark() ? 'true' : 'false';
      const readOnly = this.canWrite ? 'false' : 'true';
      const script = `window.editorApi.setContent('${b64}',{language:'${lang}',`
        + `fontSize:${this.fontSize},dark:${dark},readOnly:${readOnly}})`;
      this.webController.runJavaScript(script)
        .then((): void => {
          this.injected = true;
        })
        .catch((e: Object): void => {
          hilog.error(0x0000, 'TextEditorPage', 'inject failed: %{public}s', `${e}`);
          this.errorText = L10n.operationFailed;
          ToastUtil.show(L10n.operationFailed);
        });
    } catch (e) {
      hilog.error(0x0000, 'TextEditorPage', 'inject throw: %{public}s', `${e}`);
      this.errorText = L10n.operationFailed;
      ToastUtil.show(L10n.operationFailed);
    }
  }

  /** 从 Web 侧取回当前编辑内容（失败返回空串） */
  private async currentText(): Promise<string> {
    try {
      // 用 base64 传输：runJavaScript 会把字符串结果再包一层引号并转义，
      // 直接取 getText() 会导致保存后多出引号/转义符（如引号、"\/"）。
      const raw = await this.webController.runJavaScript('window.editorApi.getTextB64()');
      return this.decodeBase64JsResult(`${raw}`);
    } catch (_e) {
      return '';
    }
  }

  /** 还原 JS 返回的 base64（兼容 runJavaScript 额外包裹的引号） */
  private decodeBase64JsResult(raw: string): string {
    let b64 = raw.trim();
    if (b64.startsWith('"') && b64.endsWith('"') && b64.length >= 2) {
      b64 = b64.substring(1, b64.length - 1);
    }
    if (b64.length === 0 || b64 === 'undefined' || b64 === 'null') {
      return '';
    }
    try {
      const bytes = new util.Base64Helper().decodeSync(b64);
      return new util.TextDecoder('utf-8').decodeToString(bytes);
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
        // 直接加载 HAP 内 rawfile（单文件自包含，无需本地域拦截，避免伪域走真实 DNS 失败）
        Web({ src: $rawfile('editor/editor.html'), controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
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
