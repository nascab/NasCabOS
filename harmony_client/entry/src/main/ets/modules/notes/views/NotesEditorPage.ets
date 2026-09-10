import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { picker } from '@kit.CoreFileKit';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { ThemeManager } from '../../../core/theme/ThemeManager';
import { AppEventBus } from '../../../common/AppEventBus';
import { WindowStore } from '../../../common/WindowStore';
import { NavUtil } from '../../../common/NavUtil';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { EmptyState } from '../../../common/components/EmptyState';
import { ZoomableImage } from '../../../common/components/ZoomableImage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  NotesController, displayNotesTitle
} from '../controllers/NotesController';
import { NotesEditorBridge } from '../controllers/NotesController';
import { NotesNote } from '../models/NotesModels';
import { NotesActionItem, showNotesActionSheet, showNotesImageResizeSheet } from '../components/NotesActionSheet';
import { NotesFileUtils } from '../services/NotesFileUtils';
import { NotesEditorPageParam } from '../router/NotesRoutes';

const TAG = 'NotesEditorPage';
/** 编辑器本地拦截域：主框架 URL 指向该域，onInterceptRequest 映射到 rawfile/notes_editor */
const EDITOR_ORIGIN = 'http://nascab.notes';
const RAW_BASE = 'notes_editor/';

// ===== 全屏图片查看（对齐 Flutter ImageTapWrapper，供图片菜单 zoom 使用） =====

class NotesZoomParams extends DialogParamsBase {
  url: string = '';
}

@ComponentV2
struct NotesZoomViewer {
  @Param params: NotesZoomParams = new NotesZoomParams();

  build() {
    Stack() {
      ZoomableImage({
        url: this.params.url,
        idlePanDirection: PanDirection.All,
        onSingleTap: (_x: number, _y: number): void => {
          this.params.onResult(undefined);
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E6000000')
  }
}

const notesZoomBuilder: WrappedBuilder<[NotesZoomParams]> = wrapBuilder(NotesZoomBuilderFn);

@Builder
function NotesZoomBuilderFn(params: NotesZoomParams) {
  NotesZoomViewer({ params: params })
}

function showNotesZoomViewer(url: string): void {
  const p = new NotesZoomParams();
  p.url = url;
  DialogUtil.openCustom(p, notesZoomBuilder, true);
}

// ===== Web 桥 =====

/** JS → 原生回调集合（javaScriptProxy 注册对象；方法名与 index.html 协议一致） */
class NotesWebProxy {
  onEditorReady: () => void = (): void => {
  };
  onDeltaChanged: (patchJson: string) => void = (_patchJson: string): void => {
  };
  onImageClicked: (infoJson: string) => void = (_infoJson: string): void => {
  };
  onPickImage: () => void = (): void => {
  };
}

/** 解包 runJavaScript 的字符串返回（内核可能 JSON 引号包裹） */
function unwrapJsString(v: string): string {
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    try {
      const parsed = JSON.parse(v) as Object;
      if (typeof parsed === 'string') {
        return parsed as string;
      }
    } catch (_e) {
      // 非引号包裹原样返回
    }
  }
  return v;
}

/** 原生 → JS 桥（实现 NotesEditorBridge；对齐 Flutter QuillController 能力面） */
class NotesWebBridge implements NotesEditorBridge {
  private ctrl: webview.WebviewController;

  constructor(ctrl: webview.WebviewController) {
    this.ctrl = ctrl;
  }

  private run(script: string): void {
    try {
      this.ctrl.runJavaScript(script);
    } catch (e) {
      hilog.error(0x0000, TAG, 'runJavaScript failed: %{public}s', `${JSON.stringify(e)}`);
    }
  }

  loadDelta(deltaJson: string): void {
    this.run(`window.__notes.load(${JSON.stringify(deltaJson)})`);
  }

  applyPatch(patchJson: string): void {
    this.run(`window.__notes.applyPatch(${JSON.stringify(patchJson)})`);
  }

  cmd(_name: string): void {
    // 工具栏由 Web 端承担（index.html），预留
  }

  insertImage(url: string, style: string): void {
    this.run(`window.__notes.insertImage(${JSON.stringify(url)}, ${JSON.stringify(style)})`);
  }

  resizeImage(width: number, height: number): void {
    const parts: string[] = [];
    if (width > 0) {
      parts.push(`width: ${width}px;`);
    }
    if (height > 0) {
      parts.push(`height: ${height}px;`);
    }
    if (parts.length === 0) {
      return;
    }
    this.run(`window.__notes.resizeImage(${JSON.stringify(parts.join(' '))})`);
  }

  removeImage(): void {
    this.run('window.__notes.removeImage()');
  }

  /** 原子取出 JS 侧 pending patch（取出后 JS 清空；对齐 _pendingChangeDelta 语义） */
  takePending(): Promise<string> {
    return new Promise<string>((resolve: (v: string) => void) => {
      try {
        this.ctrl.runJavaScript('window.__notes.takePending()')
          .then((v: string): void => resolve(unwrapJsString(v)))
          .catch((): void => resolve('[]'));
      } catch (_e) {
        resolve('[]');
      }
    });
  }

  restorePending(patchJson: string): void {
    this.run(`window.__notes.restorePending(${JSON.stringify(patchJson)})`);
  }

  /** 主题热更新（index.html setTheme：dark + primary） */
  runSetTheme(darkFlag: string, primaryColor: string): void {
    this.run(`window.__notes.setTheme(${JSON.stringify(darkFlag)}, ${JSON.stringify(primaryColor)})`);
  }
}

/** 从 style 串解析 width/height px 值（无则 0） */
function parseStyleSize(style: string): [number, number] {
  let w = 0;
  let h = 0;
  const wMatch = /width\s*:\s*([\d.]+)px/i.exec(style);
  const hMatch = /height\s*:\s*([\d.]+)px/i.exec(style);
  if (wMatch !== null) {
    w = Number(wMatch[1]);
  }
  if (hMatch !== null) {
    h = Number(hMatch[1]);
  }
  return [Number.isFinite(w) ? w : 0, Number.isFinite(h) ? h : 0];
}

/**
 * 笔记编辑页（对齐 Flutter _NotesMobileEditorPage + NotesEditorPane）：
 * AppBar（标题 + 保存中 spinner + 菜单）+ 标题输入（置顶按钮）+ 保存失败警告 +
 * 细进度条 + Quill 富文本编辑器（Web + Quill.js，rawfile 静态资源本地拦截）。
 */
@ComponentV2
export struct NotesEditorPage {
  @Param param: NotesEditorPageParam = new NotesEditorPageParam();
  @Param popPage: () => void = (): void => {
  };
  @Local ctrl: NotesController = NotesController.getInstance();
  /** 主题变化刷新计数（AppTheme.current() 非响应式，依赖它触发整页重渲染） */
  @Local themeTick: number = 0;
  /** 状态栏高度（vp）：全屏布局后顶栏用它避让 */
  @Local statusBarHeight: number = 0;
  /** 编辑器加载地址（本地拦截域 + 主题/占位/本地化查询参数） */
  @Local startUrl: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  private proxy: NotesWebProxy = new NotesWebProxy();
  private bridge: NotesWebBridge | undefined = undefined;
  /** 图片菜单当前点击的图片信息 */
  private clickedSrc: string = '';
  private clickedStyle: string = '';
  /** 全屏布局重试定时器（纠正 push 转场对窗口布局写入的回滚） */
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
    this.applyStatusBar();
    this.pushThemeToWeb();
  };

  aboutToAppear(): void {
    this.bridge = new NotesWebBridge(this.webController);
    this.proxy.onEditorReady = (): void => {
      this.ctrl.setEditorBridge(this.bridge);
      this.pushThemeToWeb();
    };
    this.proxy.onDeltaChanged = (_patchJson: string): void => {
      // pending 由 JS 侧累积、保存时 takePending 原子取走；此处仅触发保存调度
      this.ctrl.onEditorChanged();
    };
    this.proxy.onImageClicked = (infoJson: string): void => {
      this.handleImageClicked(infoJson);
    };
    this.proxy.onPickImage = (): void => {
      void this.pickAndInsertImage();
    };
    this.applyStatusBar();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    // 沉浸全屏布局（对齐主页面）
    this.setFullScreen(true);
    this.fetchSafeAreas();
    this.buildStartUrl();
  }

  /** 组装编辑器 URL（主题/占位符/更多面板文案以查询参数传入 Web） */
  private buildStartUrl(): void {
    const p = AppTheme.current();
    const qp = new Map<string, string>();
    qp.set('dark', AppTheme.isDark() ? '1' : '0');
    qp.set('primary', p.primary);
    qp.set('placeholder', L10n.t('notes_editor_placeholder'));
    qp.set('l_undo', L10n.t('notes_toolbar_undo'));
    qp.set('l_redo', L10n.t('notes_toolbar_redo'));
    qp.set('l_clear', L10n.t('notes_toolbar_clear'));
    qp.set('l_quote', L10n.t('notes_toolbar_quote'));
    qp.set('l_code', L10n.t('notes_toolbar_code'));
    qp.set('l_bullet', L10n.t('notes_toolbar_list_bullet'));
    qp.set('l_number', L10n.t('notes_toolbar_list_number'));
    qp.set('l_check', L10n.t('notes_toolbar_list_check'));
    qp.set('l_image', L10n.t('file_type_image'));
    const pairs: string[] = [];
    qp.forEach((v: string, k: string): void => {
      pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
    });
    this.startUrl = `${EDITOR_ORIGIN}/index.html?${pairs.join('&')}`;
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    this.ctrl.setEditorBridge(undefined);
    this.applyStatusBar();
  }

  /** 全屏布局开关（窗口主窗口同步单例，写顺序=调用顺序） */
  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w !== undefined) {
      w.setWindowLayoutFullScreen(full);
    }
  }

  private fetchSafeAreas(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = Math.min(Math.max(px2vp(top.topRect.height), 0), 140);
  }

  private static setStatusBar(ctx: Context, contentColor: string, bgColor: string): void {
    try {
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowSystemBarProperties({
          statusBarContentColor: contentColor,
          statusBarColor: bgColor
        });
      });
    } catch (_e) {
      // 状态栏设置失败不阻塞页面
    }
  }

  private applyStatusBar(): void {
    const p = AppTheme.current();
    NotesEditorPage.setStatusBar(getContext(this), p.appBarFg, p.appBarBg);
  }

  private scheduleFullScreenRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.setFullScreen(true);
    }, 120);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private pushThemeToWeb(): void {
    if (this.bridge === undefined) {
      return;
    }
    const p = AppTheme.current();
    this.bridge.runSetTheme(AppTheme.isDark() ? '1' : '0', p.primary);
  }

  // ===== 菜单（对齐 _NotesMobileEditorPage PopupMenuButton） =====

  private async showEditorMenu(): Promise<void> {
    const note = this.ctrl.currentNote;
    if (note === undefined) {
      return;
    }
    const items: NotesActionItem[] = [];
    if (this.ctrl.showingTrash) {
      items.push(new NotesActionItem('restore', L10n.t('notes_restore')));
      items.push(new NotesActionItem('permanent_delete', L10n.t('notes_delete_forever'), true));
    } else {
      items.push(new NotesActionItem('export_pdf', L10n.t('notes_export_pdf')));
      items.push(new NotesActionItem('export_markdown', L10n.t('notes_export_markdown')));
      items.push(new NotesActionItem('export_txt', L10n.t('notes_export_txt')));
      items.push(new NotesActionItem('delete', L10n.t('delete'), true));
    }
    const key = await showNotesActionSheet(displayNotesTitle(note.title), items);
    if (key.length === 0) {
      return;
    }
    if (key === 'delete') {
      await this.ctrl.deleteCurrentNote();
      this.popPage();
      return;
    }
    if (key === 'restore') {
      await this.ctrl.restoreNote(note);
      this.popPage();
      return;
    }
    if (key === 'permanent_delete') {
      await this.ctrl.permanentlyDeleteNote(note);
      this.popPage();
      return;
    }
    if (key === 'export_pdf' || key === 'export_markdown' || key === 'export_txt') {
      await this.exportNoteAs(note, key === 'export_pdf' ? 'pdf'
        : (key === 'export_markdown' ? 'markdown' : 'txt'));
    }
  }

  /** 导出笔记（先强制保存当前笔记，再下载另存） */
  private async exportNoteAs(note: NotesNote, format: string): Promise<void> {
    const url = await this.ctrl.prepareExport(note, format);
    if (url.length === 0) {
      return;
    }
    await NotesFileUtils.exportNote(url, this.ctrl.buildExportFileName(note,
      NotesFileUtils.exportExt(format)));
  }

  // ===== 编辑器图片交互（对齐 NotesQuillImageEmbedBuilder 菜单） =====

  private handleImageClicked(infoJson: string): void {
    try {
      const info = JSON.parse(infoJson) as Record<string, Object>;
      this.clickedSrc = typeof info['src'] === 'string' ? info['src'] as string : '';
      this.clickedStyle = typeof info['style'] === 'string' ? info['style'] as string : '';
    } catch (_e) {
      return;
    }
    if (this.clickedSrc.length === 0) {
      return;
    }
    void this.showImageMenu();
  }

  private async showImageMenu(): Promise<void> {
    const items: NotesActionItem[] = [
      new NotesActionItem('resize', L10n.t('resize')),
      new NotesActionItem('copy', L10n.t('copy')),
      new NotesActionItem('remove', L10n.t('remove')),
      new NotesActionItem('save', L10n.t('save')),
      new NotesActionItem('zoom', L10n.t('zoom'))
    ];
    const key = await showNotesActionSheet(L10n.t('file_type_image'), items);
    if (key.length === 0) {
      return;
    }
    if (key === 'resize') {
      const size = parseStyleSize(this.clickedStyle);
      const next = await showNotesImageResizeSheet(size[0], size[1]);
      if (next !== null && this.bridge !== undefined) {
        this.bridge.resizeImage(next[0], next[1]);
        this.ctrl.onEditorChanged();
      }
      return;
    }
    if (key === 'copy') {
      await NotesFileUtils.copyImageToClipboard(this.clickedSrc);
      return;
    }
    if (key === 'remove') {
      if (this.bridge !== undefined) {
        this.bridge.removeImage();
        this.ctrl.onEditorChanged();
      }
      return;
    }
    if (key === 'save') {
      const downloadUrl = NotesFileUtils.buildImageDownloadUrl(this.clickedSrc);
      if (downloadUrl.length === 0 || !downloadUrl.startsWith('http')) {
        return;
      }
      await NotesFileUtils.exportNote(downloadUrl,
        NotesFileUtils.imageFileNameFromUrl(downloadUrl));
      return;
    }
    if (key === 'zoom') {
      showNotesZoomViewer(this.clickedSrc);
    }
  }

  /** 相册选图并上传插入（对齐 Flutter insertImageFromPicker） */
  private async pickAndInsertImage(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const opts = new picker.PhotoSelectOptions();
      opts.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      opts.maxSelectNumber = 1;
      const result: picker.PhotoSelectResult = await photoPicker.select(opts);
      const uris = result.photoUris ?? [];
      if (uris.length === 0) {
        return;
      }
      await this.ctrl.insertImageAsset(uris[0]);
    } catch (_e) {
      // 用户取消选择
    }
  }

  // ===== 渲染 =====

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.Header()
          this.Body()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().pageBg)
        .opacity(this.themeTick >= 0 ? 1 : 1)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onShown((): void => {
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
      this.fetchSafeAreas();
      this.applyStatusBar();
    })
    .onHidden((): void => {
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      void this.flushAndPop();
      return true;
    })
  }

  /** 退出前冲刷待保存内容（编辑器桥随 Web 销毁，必须先落盘） */
  private async flushAndPop(): Promise<void> {
    await this.ctrl.flushPendingSaves();
    this.popPage();
  }

  /** 顶栏（对齐 Flutter AppBar：标题 + 保存中 spinner + 菜单） */
  @Builder
  Header() {
    Row() {
      BorderedIconButton({
        icon: $r('sys.symbol.arrow_left'),
        strokeColor: AppTheme.withAlpha(this.palette().appBarFg, 0.35),
        iconColor: this.palette().appBarFg,
        onTap: (): void => {
          void this.flushAndPop();
        }
      })
      Text(this.ctrl.currentNote !== undefined
        ? displayNotesTitle(this.ctrl.currentNote.title) : L10n.t('app_note', '笔记'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().appBarFg)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })
      if (this.ctrl.savingNote) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.palette().appBarFg)
          .margin({ right: 12 })
      }
      if (this.ctrl.currentNote !== undefined) {
        SymbolGlyph($r('sys.symbol.ellipsis_circle'))
          .fontSize(20)
          .fontColor([this.palette().appBarFg])
          .onClick((): void => {
            void this.showEditorMenu();
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 10, right: 12 })
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.palette().appBarBg)
  }

  /** 主体（对齐 NotesEditorPane） */
  @Builder
  Body() {
    if (this.ctrl.currentNote === undefined) {
      Column() {
        EmptyState({
          message: this.ctrl.showingTrash
            ? L10n.t('notes_select_deleted_note')
            : L10n.t('notes_select_or_create_note'),
          imagePath: $rawfile('icons/nodata_note.png')
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.TitleBar(this.ctrl.currentNote)
        if (this.ctrl.showSaveFailureWarning) {
          this.SaveFailureWarning()
        }
        // 细进度条（对齐 LinearProgressIndicator minHeight 1）
        if (this.ctrl.savingNote || this.ctrl.loadingNoteDetail) {
          Progress({ value: 40, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(1.5)
            .color(this.palette().primary)
        }
        this.EditorWeb()
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  /** 标题行（对齐 pane 顶部标题输入 + 置顶按钮） */
  @Builder
  TitleBar(note: NotesNote) {
    Row() {
      TextInput({
        text: this.ctrl.titleText,
        placeholder: L10n.t('notes_untitled')
      })
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)
        .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.3))
        .placeholderFont({ size: 26, weight: FontWeight.Bold })
        .backgroundColor(Color.Transparent)
        .border({ width: { bottom: 1 }, color: { bottom: this.palette().divider } })
        .padding({ bottom: 8 })
        .height(52)
        .layoutWeight(1)
        .onChange((v: string): void => {
          this.ctrl.titleText = v;
          this.ctrl.onEditorChanged();
        })
      if (!this.ctrl.showingTrash) {
        SymbolGlyph($r('sys.symbol.pin_fill'))
          .fontSize(18)
          .fontColor([note.isPinned ? this.palette().primary : this.palette().hint])
          .padding(8)
          .onClick((): void => {
            void this.ctrl.togglePinned(note);
          })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 12, top: 14, bottom: 10 })
    .backgroundColor(this.palette().surfaceBg)
  }

  /** 保存失败警告（对齐 pane 失败卡片） */
  @Builder
  SaveFailureWarning() {
    Column() {
      Row() {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(18)
          .fontColor([this.palette().error])
        Text(L10n.t('notes_save_connection_lost'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().error)
          .lineHeight(20)
          .layoutWeight(1)
          .margin({ left: 10 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row() {
        Button(this.ctrl.savingNote ? L10n.t('editor_status_saving')
          : L10n.t('notes_manual_save'))
          .fontSize(14)
          .fontColor(this.palette().buttonText)
          .backgroundColor(this.palette().buttonBg)
          .height(36)
          .enabled(this.ctrl.savingNote || !this.ctrl.canRetrySave ? false : true)
          .onClick((): void => {
            void this.ctrl.retryFailedSave();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(AppTheme.withAlpha(this.palette().error, 0.12))
    .border({ width: 1, color: AppTheme.withAlpha(this.palette().error, 0.25) })
    .margin({ left: 18, right: 18, bottom: 10 })
  }

  /** Web 富文本编辑器（工具栏内置于 index.html） */
  @Builder
  EditorWeb() {
    Web({ src: this.startUrl, controller: this.webController })
      .width('100%')
      .layoutWeight(1)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .zoomAccess(false)
      .backgroundColor(this.palette().surfaceBg)
      .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse | null => {
        return this.interceptRequest(event);
      })
      .javaScriptProxy({
        object: this.proxy,
        name: 'NativeBridge',
        methodList: ['onEditorReady', 'onDeltaChanged', 'onImageClicked', 'onPickImage'],
        controller: this.webController
      })
  }

  /**
   * 本地资源拦截：http://nascab.notes/<rest> → rawfile/notes_editor/<rest>；
   * 其余（服务器图片等）放行走网络。
   */
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
    let rest = path === '/' || path === '' ? 'index.html' : path.substring(1);
    if (rest.length === 0 || rest.includes('..')) {
      return null;
    }
    const resp = new WebResourceResponse();
    resp.setResponseData($rawfile(RAW_BASE + rest));
    resp.setResponseMimeType(mimeOf(rest));
    if (rest.endsWith('.html') || rest.endsWith('.js') || rest.endsWith('.css')) {
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
  if (lower.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.woff2')) {
    return 'font/woff2';
  }
  return 'application/octet-stream';
}
