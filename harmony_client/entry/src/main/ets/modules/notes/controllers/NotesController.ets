import { APIClient } from '../../../core/network/APIClient';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil, SelectItem } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import {
  NotesNotebookInfo, NotesGroup, NotesNote,
  NOTES_ALL_TAG_FILTER, NOTES_PRESET_COLORS
} from '../models/NotesModels';
import {
  NotesApiService, NotesStatePayload, NotesNoteDetailPayload, NotesApiResult
} from '../services/NotesApiServices';

/** 编辑器桥接口（NotesEditorPage 用 webController 实现，对齐 Flutter QuillController 能力面） */
export interface NotesEditorBridge {
  /** 全量装载 delta（重置编辑器内容，期间不回推变更） */
  loadDelta(deltaJson: string): void;
  /** 应用增量 patch（user 来源，计入 pending） */
  applyPatch(patchJson: string): void;
  /** 编辑器命令：bold/italic/underline/strike/clear 等（工具栏由 Web 端承担，此接口预留） */
  cmd(name: string): void;
  /** 在光标处插入图片 embed */
  insertImage(url: string, style: string): void;
  /** 调整当前点击图片尺寸 */
  resizeImage(width: number, height: number): void;
  /** 移除当前点击图片 */
  removeImage(): void;
  /** 原子取出 JS 侧 pending patch（取出后清空） */
  takePending(): Promise<string>;
  /** 保存失败时把 patch 回填到 JS 侧 pending */
  restorePending(patchJson: string): void;
}

function displayNotesTitle(title: string): string {
  const v = title.trim();
  return v.length > 0 ? v : L10n.t('notes_untitled');
}

function displayNotesGroupName(groupId: string, groupName: string): string {
  const gid = groupId.trim();
  const gnameLower = groupName.trim().toLowerCase();
  const gname = groupName.trim();
  if (gid === 'all' || gnameLower === 'all' || gname === '全部') {
    return L10n.t('all');
  }
  return gname;
}

/** 解析 ISO 时间为本地 "yyyy-MM-dd HH:mm"（对齐 Flutter formatNotesTime） */
function formatNotesTime(iso: string): string {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) {
    return '';
  }
  const dt = new Date(t);
  const now = new Date();
  const pad = (n: number): string => `${n < 10 ? '0' : ''}${n}`;
  if (now.getFullYear() === dt.getFullYear() && now.getMonth() === dt.getMonth()
    && now.getDate() === dt.getDate()) {
    return `${L10n.t('notes_today')} ${pad(dt.getHours())}:${pad(dt.getMinutes())}`;
  }
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())} `
    + `${pad(dt.getHours())}:${pad(dt.getMinutes())}`;
}

/** 解析 #RRGGBB 颜色（对齐 Flutter parseNotesHexColor），非法返回 '' */
function parseNotesHexColor(hex: string): string {
  const v = hex.trim();
  if (v.length === 0) {
    return '';
  }
  const normalized = v.startsWith('#') ? v.substring(1) : v;
  if (normalized.length !== 6) {
    return '';
  }
  return `#${normalized.toUpperCase()}`;
}

/** 标签色显示名（对齐 Flutter _tagColorLabel） */
function tagColorLabel(color: string): string {
  if (color === '') {
    return L10n.t('notes_no_tag');
  }
  const map: Record<string, string> = {
    '#EF4444': 'notes_tag_color_red',
    '#F59E0B': 'notes_tag_color_orange',
    '#10B981': 'notes_tag_color_green',
    '#3B82F6': 'notes_tag_color_blue',
    '#8B5CF6': 'notes_tag_color_purple',
    '#EC4899': 'notes_tag_color_pink'
  };
  const key = map[color];
  return key !== undefined ? L10n.t(key) : color;
}

export {
  displayNotesTitle, displayNotesGroupName, formatNotesTime, parseNotesHexColor, tagColorLabel
};

/**
 * 笔记控制器（对齐 Flutter NotesController；@ObservedV2 + @Trace 驱动 V2 刷新）。
 * 全局单例（Flutter Get.put permanent: true 对应实现）。
 */
@ObservedV2
export class NotesController {
  private static instance: NotesController | undefined = undefined;

  static getInstance(): NotesController {
    if (!NotesController.instance) {
      NotesController.instance = new NotesController();
    }
    return NotesController.instance;
  }

  @Trace loadingNotebook: boolean = false;
  @Trace loadingState: boolean = false;
  @Trace loadingNoteDetail: boolean = false;
  @Trace savingNote: boolean = false;
  @Trace notebookSelected: boolean = false;

  @Trace selectedGroupId: string = 'all';
  @Trace selectedNoteId: string = '';
  @Trace selectedNoteIds: string[] = [];
  @Trace showingTrash: boolean = false;
  @Trace keyword: string = '';
  @Trace tagColorFilter: string = NOTES_ALL_TAG_FILTER;
  @Trace statusText: string = '';
  @Trace showSaveFailureWarning: boolean = false;

  @Trace notebook: NotesNotebookInfo | undefined = undefined;
  @Trace groups: NotesGroup[] = [];
  @Trace notes: NotesNote[] = [];
  @Trace currentNote: NotesNote | undefined = undefined;
  /** 编辑器标题输入（Flutter titleController 对应） */
  @Trace titleText: string = '';

  /** 编辑器桥（编辑页挂载后注入） */
  private bridge: NotesEditorBridge | undefined = undefined;
  /** 最近一次装载的编辑器 delta（桥未挂载时缓冲，挂载后补推；对齐 Flutter quillController 常驻语义） */
  private lastLoadDeltaJson: string = '[{"insert":"\\n"}]';

  private searchDebounce: number = -1;
  private saveDebounce: number = -1;
  private lastSavedTitle: string = '';
  private contentRevision: number = 0;
  private saveInFlight: boolean = false;
  private saveCompleter: Promise<void> | undefined = undefined;
  private saveResolve: (() => void) | undefined = undefined;
  private selectionAnchorNoteId: string = '';
  private sessionKey: string = '';
  private sessionSyncInFlight: boolean = false;

  private constructor() {
  }

  // ===== 派生数据 =====

  get visibleNotes(): NotesNote[] {
    const filter = this.tagColorFilter;
    if (filter === NOTES_ALL_TAG_FILTER) {
      return this.notes;
    }
    return this.notes.filter((n: NotesNote): boolean => n.tagColor === filter);
  }

  get selectedNoteCount(): number {
    return this.selectedNoteIds.length;
  }

  get hasBatchSelection(): boolean {
    return this.selectedNoteCount > 1;
  }

  isNoteSelected(noteId: string): boolean {
    return this.selectedNoteIds.indexOf(noteId.trim()) >= 0;
  }

  get presetColors(): string[] {
    return NOTES_PRESET_COLORS;
  }

  /** 服务器版本是否 >= 5（对齐 Flutter ServerVersionUtil.isAtLeast(5)） */
  isServerVersionTooLow(): boolean {
    const ver = APIClient.getInstance().state.serverVersion ?? '';
    const parts = ver.trim().split('.');
    const major = parts.length > 0 ? Number(parts[0]) : 0;
    return !(Number.isFinite(major) && major >= 5);
  }

  private setSelectedNoteIds(ids: string[], anchorId: string | undefined): void {
    const next: string[] = [];
    ids.forEach((rawId: string): void => {
      const id = rawId.trim();
      if (id.length === 0 || next.indexOf(id) >= 0) {
        return;
      }
      next.push(id);
    });
    this.selectedNoteIds = next;
    if (anchorId !== undefined) {
      this.selectionAnchorNoteId = anchorId.trim();
    }
  }

  clearNoteSelection(keepActive: boolean = true): void {
    const activeId = this.selectedNoteId.trim().length > 0
      ? this.selectedNoteId.trim()
      : (this.currentNote !== undefined ? this.currentNote.id : '');
    if (keepActive && activeId.length > 0) {
      this.setSelectedNoteIds([activeId], activeId);
      return;
    }
    this.selectedNoteIds = [];
    this.selectionAnchorNoteId = '';
  }

  setEditorBridge(bridge: NotesEditorBridge | undefined): void {
    this.bridge = bridge;
    if (bridge !== undefined && this.lastLoadDeltaJson.length > 0) {
      // 桥挂载时补推缓冲内容（编辑页打开晚于 selectNote 装载）
      bridge.loadDelta(this.lastLoadDeltaJson);
    }
  }

  // ===== 搜索（对齐 _handleSearchChanged） =====

  onSearchChanged(text: string): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.keyword = text.trim();
      void this.refreshState('');
    }, 260);
  }

  // ===== 编辑器事件（对齐 _handleEditorChanged） =====

  onEditorChanged(): void {
    if (this.currentNote === undefined || this.currentNote.isDeleted) {
      return;
    }
    this.pendingHasContent = true;
    if (this.saveDebounce >= 0) {
      clearTimeout(this.saveDebounce);
    }
    this.saveDebounce = setTimeout((): void => {
      this.saveDebounce = -1;
      void this.saveCurrentNote(false);
    }, 800);
  }

  private get hasPendingSave(): boolean {
    const note = this.currentNote;
    if (note === undefined || note.isDeleted) {
      return false;
    }
    return this.pendingHasContent || this.titleText.trim() !== this.lastSavedTitle;
  }

  /** JS 侧 pending 是否非空（异步探测缓存；由 bridge 提供） */
  private pendingHasContent: boolean = false;

  private resetPendingSaveState(title: string, revision: number): void {
    if (this.saveDebounce >= 0) {
      clearTimeout(this.saveDebounce);
      this.saveDebounce = -1;
    }
    this.lastSavedTitle = title;
    this.contentRevision = revision;
    this.pendingHasContent = false;
    this.showSaveFailureWarning = false;
  }

  get canRetrySave(): boolean {
    const note = this.currentNote;
    return note !== undefined && !note.isDeleted && !this.savingNote;
  }

  async retryFailedSave(): Promise<void> {
    await this.saveCurrentNote(true);
  }

  private async waitForSaveCycle(): Promise<void> {
    const c = this.saveCompleter;
    if (c === undefined) {
      return;
    }
    await c;
  }

  /** 立即冲刷待保存内容（编辑页退出前调用；对齐 Flutter _flushPendingNoteSaves） */
  async flushPendingSaves(): Promise<void> {
    if (this.saveInFlight) {
      await this.waitForSaveCycle();
    }
    if (this.hasPendingSave) {
      await this.saveCurrentNote(true);
      if (this.saveInFlight) {
        await this.waitForSaveCycle();
      }
    }
  }

  // ===== 会话 =====

  private buildSessionKey(): string {
    const serverId = `${APIClient.getInstance().state.serverId ?? ''}`.trim();
    const user = CurrentUserStore.getInstance().current;
    const userId = user !== undefined ? `${user.id}` : '';
    const username = user !== undefined ? user.username.trim() : '';
    return `${serverId}::${userId}::${username}`;
  }

  private resetSessionState(): void {
    this.loadingNotebook = false;
    this.loadingState = false;
    this.loadingNoteDetail = false;
    this.savingNote = false;
    this.notebookSelected = false;
    this.notebook = undefined;
    this.groups = [];
    this.notes = [];
    this.currentNote = undefined;
    this.selectedGroupId = 'all';
    this.selectedNoteId = '';
    this.selectedNoteIds = [];
    this.showingTrash = false;
    this.keyword = '';
    this.tagColorFilter = NOTES_ALL_TAG_FILTER;
    this.statusText = '';
    this.selectionAnchorNoteId = '';
    this.titleText = '';
    this.resetEditor();
  }

  async ensureSessionFresh(): Promise<void> {
    if (this.sessionSyncInFlight) {
      return;
    }
    const user = CurrentUserStore.getInstance().current;
    const token = (APIClient.getInstance().accessToken ?? '').trim();
    const nextSessionKey = (user === undefined || token.length === 0) ? '' : this.buildSessionKey();
    if (nextSessionKey === this.sessionKey) {
      return;
    }
    this.sessionSyncInFlight = true;
    try {
      this.sessionKey = nextSessionKey;
      this.resetSessionState();
      if (nextSessionKey.length === 0) {
        return;
      }
      await this.loadNotebookStatus();
    } finally {
      this.sessionSyncInFlight = false;
    }
  }

  async loadNotebookStatus(): Promise<void> {
    this.loadingNotebook = true;
    const res = await NotesApiService.getNotebookStatus();
    if (!res.success) {
      this.notebookSelected = false;
      this.notebook = undefined;
      this.loadingNotebook = false;
      return;
    }
    const info = res.data as NotesNotebookInfo;
    this.notebook = info;
    this.notebookSelected = info.selected;
    this.loadingNotebook = false;
    if (info.selected) {
      await this.refreshState('');
    }
  }

  /** 选择笔记本（对齐 Flutter pickNotebook；folderPaths 由 FolderPickerSheet 返回） */
  async pickNotebook(folderPaths: string[]): Promise<void> {
    if (folderPaths.length === 0) {
      return;
    }
    const folderPath = folderPaths[0].trim();
    if (folderPath.length === 0) {
      return;
    }
    const res = await NotesApiService.selectNotebook(folderPath);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_open_notebook_failed'));
      return;
    }
    this.notebook = res.data;
    this.notebookSelected = this.notebook !== undefined && this.notebook.selected;
    this.selectedGroupId = 'all';
    this.showingTrash = false;
    await this.refreshState('');
  }

  // ===== 状态加载 =====

  async refreshState(keepNoteId: string): Promise<void> {
    if (!this.notebookSelected) {
      return;
    }
    this.loadingState = true;
    const res = await NotesApiService.getState(
      this.selectedGroupId, this.keyword, this.showingTrash);
    this.loadingState = false;
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_load_failed'));
      return;
    }
    const data = res.data as NotesStatePayload;
    this.notebook = data.notebook;
    this.groups = data.groups;
    this.notes = data.notes;
    const availableIds: string[] = [];
    this.notes.forEach((n: NotesNote): void => {
      availableIds.push(n.id);
    });
    const retainedSelection = this.selectedNoteIds.filter(
      (id: string): boolean => availableIds.indexOf(id) >= 0);
    this.selectedNoteIds = retainedSelection;
    if (this.selectionAnchorNoteId.length > 0
      && availableIds.indexOf(this.selectionAnchorNoteId) < 0) {
      this.selectionAnchorNoteId = retainedSelection.length > 0 ? retainedSelection[0] : '';
    }
    const currentSelectedId = this.selectedNoteId.trim();
    const targetId = (keepNoteId.length > 0 ? keepNoteId
      : (currentSelectedId.length > 0
        ? currentSelectedId
        : (this.currentNote !== undefined ? this.currentNote.id : ''))).trim();
    if (targetId.length > 0) {
      const hit = this.notes.find((n: NotesNote): boolean => n.id === targetId);
      if (hit !== undefined) {
        this.selectedNoteId = hit.id;
        this.currentNote = hit;
      }
    }
    if (this.notes.length === 0) {
      this.selectedNoteId = '';
      this.selectedNoteIds = [];
      this.currentNote = undefined;
      this.selectionAnchorNoteId = '';
      this.resetEditor();
      return;
    }
    const currentId = this.currentNote !== undefined ? this.currentNote.id : '';
    if (currentId === '' || this.notes.find((n: NotesNote): boolean => n.id === currentId) === undefined) {
      this.selectedNoteId = this.notes[0].id;
      await this.selectNote(this.notes[0].id, true, true);
      return;
    }
    this.currentNote = this.notes.find((n: NotesNote): boolean => n.id === currentId);
    this.selectedNoteId = this.currentNote !== undefined ? this.currentNote.id : '';
    if (this.selectedNoteIds.length === 0 && this.selectedNoteId.length > 0) {
      this.setSelectedNoteIds([this.selectedNoteId], this.selectedNoteId);
    }
  }

  // ===== 编辑器内容装载 =====

  /** 默认图片 embed 样式（对齐 Flutter _defaultImageEmbedStyle） */
  static readonly DEFAULT_IMAGE_STYLE: string = 'width: 300px;';

  /** 编辑器插入图片资源（对齐 Flutter _insertEmbedAsset：上传 → 插入 → 强制保存 → 刷新） */
  async insertImageAsset(localUri: string): Promise<void> {
    const note = this.currentNote;
    if (note === undefined || localUri.trim().length === 0) {
      return;
    }
    try {
      const url = await NotesApiService.uploadAsset(note.id, localUri.trim());
      if (this.bridge !== undefined) {
        this.bridge.insertImage(url, NotesController.DEFAULT_IMAGE_STYLE);
      }
      await this.saveCurrentNote(true);
      await this.refreshState(note.id);
    } catch (e) {
      const msg = e instanceof Error ? e.message : `${JSON.stringify(e)}`;
      ToastUtil.show(msg.length > 0 ? msg : L10n.t('upload_failed'));
    }
  }

  private resetEditor(): void {
    this.titleText = '';
    this.resetPendingSaveState('', 0);
    this.lastLoadDeltaJson = '[{"insert":"\\n"}]';
    if (this.bridge !== undefined) {
      this.bridge.loadDelta(this.lastLoadDeltaJson);
    }
  }

  /** 服务器 delta ops → 编辑器展开（assets/ → 服务器 URL） */
  private expandEmbedsForEditor(noteId: string, rawOps: Object[] | undefined): Object[] {
    const ops = rawOps ?? [];
    const out: Object[] = [];
    ops.forEach((item: Object): void => {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        out.push(item);
        return;
      }
      const op = item as Record<string, Object>;
      const insert = op['insert'];
      if (insert !== undefined && insert !== null && typeof insert === 'object'
        && !Array.isArray(insert)) {
        const nextInsert = insert as Record<string, Object>;
        const imageVal = nextInsert['image'];
        if (typeof imageVal === 'string') {
          nextInsert['image'] = NotesApiService.expandEmbedForEditor(noteId, imageVal);
        }
        const videoVal = nextInsert['video'];
        if (typeof videoVal === 'string') {
          nextInsert['video'] = NotesApiService.expandEmbedForEditor(noteId, videoVal);
        }
        op['insert'] = nextInsert as Object;
      }
      out.push(op as Object);
    });
    return out;
  }

  private applyServerNoteDetail(data: NotesNoteDetailPayload): void {
    const note = data.note;
    this.selectedNoteId = note.id;
    this.currentNote = note;
    this.setSelectedNoteIds([note.id], note.id);
    this.titleText = note.title;
    this.resetPendingSaveState(note.title, data.revision);
    this.lastLoadDeltaJson = JSON.stringify(this.expandEmbedsForEditor(note.id, data.delta));
    if (this.bridge !== undefined) {
      this.bridge.loadDelta(this.lastLoadDeltaJson);
    }
    this.replaceLocalNote(note);
  }

  async selectNote(noteId: string, syncSelection: boolean = true,
    updateAnchor: boolean = true): Promise<void> {
    const trimmedId = noteId.trim();
    if (trimmedId.length === 0) {
      return;
    }
    const currentId = this.currentNote !== undefined ? this.currentNote.id : '';
    if (currentId !== trimmedId) {
      await this.flushPendingSaves();
    }
    this.selectedNoteId = trimmedId;
    if (syncSelection) {
      this.setSelectedNoteIds([trimmedId], updateAnchor ? trimmedId : undefined);
    } else if (updateAnchor) {
      this.selectionAnchorNoteId = trimmedId;
    }
    this.loadingNoteDetail = true;
    const res = await NotesApiService.getNoteDetail(trimmedId);
    this.loadingNoteDetail = false;
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_load_failed'));
      return;
    }
    this.applyServerNoteDetail(res.data as NotesNoteDetailPayload);
  }

  /** 列表点击（对齐 Flutter handleNoteTap；移动端无 shift 多选） */
  async handleNoteTap(note: NotesNote): Promise<void> {
    await this.selectNote(note.id);
  }

  // ===== 保存（对齐 saveCurrentNote） =====

  /** 保存前 patch 收敛：assets URL → assets/<name> */
  private normalizeEmbedsForSave(noteId: string, rawOps: Object[]): Object[] {
    const out: Object[] = [];
    rawOps.forEach((item: Object): void => {
      if (item === null || typeof item !== 'object' || Array.isArray(item)) {
        out.push(item);
        return;
      }
      const op = item as Record<string, Object>;
      const insert = op['insert'];
      if (insert !== undefined && insert !== null && typeof insert === 'object'
        && !Array.isArray(insert)) {
        const nextInsert = insert as Record<string, Object>;
        const imageVal = nextInsert['image'];
        if (typeof imageVal === 'string') {
          nextInsert['image'] = NotesApiService.normalizeEmbedForSave(noteId, imageVal);
        }
        const videoVal = nextInsert['video'];
        if (typeof videoVal === 'string') {
          nextInsert['video'] = NotesApiService.normalizeEmbedForSave(noteId, videoVal);
        }
        op['insert'] = nextInsert as Object;
      }
      out.push(op as Object);
    });
    return out;
  }

  async saveCurrentNote(force: boolean): Promise<void> {
    const note = this.currentNote;
    if (note === undefined || note.isDeleted) {
      return;
    }
    if (this.saveInFlight) {
      await this.waitForSaveCycle();
      return;
    }
    if (this.bridge === undefined) {
      return;
    }
    // 原子取出 JS 侧 pending patch（期间新变更继续进入 JS pending，下一轮保存）
    let patchJson = '';
    try {
      patchJson = await this.bridge.takePending();
    } catch (_e) {
      patchJson = '';
    }
    const hasContentChanges = patchJson.length > 0 && patchJson !== '[]';
    this.pendingHasContent = false;
    const titleToSave = this.titleText.trim();
    const titleChanged = titleToSave !== this.lastSavedTitle;
    if (!force && !titleChanged && !hasContentChanges) {
      if (hasContentChanges || patchJson.length > 0) {
        this.bridge.restorePending(patchJson);
        this.pendingHasContent = true;
      }
      return;
    }
    if (!titleChanged && !hasContentChanges) {
      return;
    }
    const patchToSend = hasContentChanges
      ? this.normalizeEmbedsForSave(note.id, JSON.parse(patchJson) as Object[])
      : undefined;
    const revisionToSend = this.contentRevision;
    this.saveInFlight = true;
    this.saveCompleter = new Promise<void>((resolve: () => void): void => {
      this.saveResolve = resolve;
    });
    this.savingNote = true;
    let res: NotesApiResult<Object>;
    try {
      res = await NotesApiService.saveNote(note.id, titleToSave, revisionToSend, patchToSend);
    } finally {
      this.saveInFlight = false;
      if (this.saveResolve !== undefined) {
        this.saveResolve();
        this.saveResolve = undefined;
        this.saveCompleter = undefined;
      }
      this.savingNote = false;
    }
    if (!res.success) {
      if (res.code === 409) {
        const recovered = await this.recoverFromSaveConflict(note.id, titleToSave, patchToSend);
        if (recovered) {
          this.statusText = L10n.t('notes_save_conflict_retried');
          if (this.hasPendingSave) {
            void this.saveCurrentNote(true);
          }
          return;
        }
      }
      if (patchToSend !== undefined && this.bridge !== undefined) {
        this.bridge.restorePending(JSON.stringify(patchToSend));
        this.pendingHasContent = true;
      }
      this.showSaveFailureWarning = true;
      this.statusText = res.message.length > 0 ? res.message : L10n.t('notes_save_failed');
      return;
    }
    this.showSaveFailureWarning = false;
    this.statusText = L10n.t('notes_auto_saved');
    const rec = (res.data ?? {}) as Record<string, Object>;
    const noteRec = (rec['note'] ?? {}) as Record<string, Object>;
    const updated = NotesNoteFromServer(noteRec, note.id);
    this.lastSavedTitle = updated.title;
    const rev = Number(rec['revision'] ?? NaN);
    this.contentRevision = Number.isFinite(rev) ? rev : this.contentRevision;
    this.replaceNoteInListOnly(updated);
    this.sortLocalNotes();
    if (this.hasPendingSave) {
      void this.saveCurrentNote(false);
    }
  }

  /** 保存冲突恢复（对齐 _recoverFromSaveConflict）：拉服务器内容重载，再叠加本地 patch */
  private async recoverFromSaveConflict(noteId: string, localTitle: string,
    localPatch: Object[] | undefined): Promise<boolean> {
    const res = await NotesApiService.getNoteDetail(noteId);
    if (!res.success || this.bridge === undefined) {
      return false;
    }
    const data = res.data as NotesNoteDetailPayload;
    const note = data.note;
    this.selectedNoteId = note.id;
    this.currentNote = note;
    this.titleText = note.title;
    this.resetPendingSaveState(note.title, data.revision);
    this.lastLoadDeltaJson = JSON.stringify(this.expandEmbedsForEditor(note.id, data.delta));
    this.bridge.loadDelta(this.lastLoadDeltaJson);
    if (localPatch !== undefined && localPatch.length > 0) {
      this.bridge.applyPatch(JSON.stringify(localPatch));
    }
    const trimmedLocalTitle = localTitle.trim();
    if (trimmedLocalTitle !== this.titleText.trim()) {
      this.titleText = trimmedLocalTitle;
    }
    return true;
  }

  // ===== 本地列表操作 =====

  private compareLocalNotes(a: NotesNote, b: NotesNote): number {
    const pinDelta = (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0);
    if (pinDelta !== 0) {
      return pinDelta;
    }
    return b.updateTime.localeCompare(a.updateTime);
  }

  private sortLocalNotes(): void {
    this.notes = this.notes.slice().sort((a: NotesNote, b: NotesNote): number =>
      this.compareLocalNotes(a, b));
  }

  private replaceLocalNote(updated: NotesNote): void {
    const idx = this.notes.findIndex((n: NotesNote): boolean => n.id === updated.id);
    if (idx >= 0) {
      const next = this.notes.slice();
      next[idx] = updated;
      this.notes = next;
    }
    if (this.currentNote !== undefined && this.currentNote.id === updated.id) {
      this.currentNote = updated;
    }
    if (this.selectedNoteId === updated.id || this.selectedNoteId.length === 0) {
      this.selectedNoteId = updated.id;
    }
  }

  private replaceNoteInListOnly(updated: NotesNote): void {
    const idx = this.notes.findIndex((n: NotesNote): boolean => n.id === updated.id);
    if (idx >= 0) {
      const next = this.notes.slice();
      next[idx] = updated;
      this.notes = next;
    }
    if (this.selectedNoteId === updated.id || this.selectedNoteId.length === 0) {
      this.selectedNoteId = updated.id;
    }
  }

  private findLocalNote(noteId: string): NotesNote | undefined {
    if (this.currentNote !== undefined && this.currentNote.id === noteId) {
      return this.currentNote;
    }
    return this.notes.find((n: NotesNote): boolean => n.id === noteId);
  }

  // ===== 新建 / 分组管理 =====

  async createNote(): Promise<void> {
    if (this.showingTrash) {
      this.showingTrash = false;
    }
    const groupId = this.selectedGroupId.trim().length === 0 ? 'all' : this.selectedGroupId;
    const res = await NotesApiService.createNote(groupId);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_create_failed'));
      return;
    }
    const note = res.data as NotesNote;
    this.selectedNoteId = note.id;
    this.currentNote = note;
    await this.refreshState(note.id);
    await this.selectNote(note.id);
  }

  async createGroup(): Promise<void> {
    const name = await DialogUtil.showInputDialog(
      L10n.t('notes_new_group'), L10n.t('notes_group_name_input'),
      '', L10n.t('create'), L10n.cancel,
      (value: string): string | undefined => {
        const text = value.trim();
        if (text.length === 0) {
          return L10n.t('notes_group_name_required');
        }
        return undefined;
      });
    if (typeof name !== 'string') {
      return;
    }
    const res = await NotesApiService.createGroup(name.trim());
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_group_create_failed'));
      return;
    }
    await this.refreshState('');
  }

  async renameGroup(group: NotesGroup): Promise<void> {
    const name = await DialogUtil.showInputDialog(
      L10n.t('notes_group_rename'), L10n.t('notes_group_name_new_input'),
      displayNotesGroupName(group.id, group.name),
      L10n.save, L10n.cancel,
      (value: string): string | undefined => {
        const text = value.trim();
        if (text.length === 0) {
          return L10n.t('notes_group_name_required');
        }
        return undefined;
      });
    if (typeof name !== 'string') {
      return;
    }
    const res = await NotesApiService.updateGroup(group.id, name.trim());
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_group_rename_failed'));
      return;
    }
    await this.refreshState('');
  }

  async deleteGroup(group: NotesGroup): Promise<void> {
    const groupName = displayNotesGroupName(group.id, group.name);
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('notes_group_delete'),
      L10n.t('notes_group_delete_confirm', '', new Map<string, string>([['name', groupName]])),
      undefined, L10n.t('delete'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    const res = await NotesApiService.deleteGroup(group.id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_group_delete_failed'));
      return;
    }
    if (this.selectedGroupId === group.id) {
      this.selectedGroupId = 'all';
    }
    await this.refreshState('');
  }

  /** 组排序（桌面端侧栏拖拽用，移动端分组 chip 不涉及；保留对齐） */
  async reorderGroups(orderedCustomGroups: NotesGroup[]): Promise<void> {
    const ids: string[] = [];
    orderedCustomGroups.forEach((g: NotesGroup): void => {
      ids.push(g.id);
    });
    const res = await NotesApiService.reorderGroups(ids);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_group_reorder_failed'));
      return;
    }
    await this.refreshState('');
  }

  async changeGroup(groupId: string, trash: boolean = false): Promise<void> {
    this.selectedGroupId = groupId;
    this.showingTrash = trash;
    this.selectedNoteId = '';
    this.currentNote = undefined;
    this.notes = [];
    this.resetEditor();
    await this.refreshState('');
  }

  // ===== 笔记元数据 / 批量操作 =====

  async togglePinned(note: NotesNote): Promise<void> {
    const current = this.findLocalNote(note.id) ?? note;
    const res = await NotesApiService.updateNoteMeta([current.id], undefined, undefined,
      !current.isPinned);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
      return;
    }
    const updated = NotesNoteClone(current);
    updated.isPinned = !current.isPinned;
    this.replaceLocalNote(updated);
    this.sortLocalNotes();
  }

  async setTagColor(note: NotesNote, color: string): Promise<void> {
    const targets = this.resolveMetaTargets(note);
    if (targets.length === 0) {
      return;
    }
    const ids: string[] = [];
    targets.forEach((n: NotesNote): void => {
      ids.push(n.id);
    });
    const res = await NotesApiService.updateNoteMeta(ids, undefined, color, undefined);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_tag_update_failed'));
      return;
    }
    const updated: NotesNote[] = [];
    targets.forEach((n: NotesNote): void => {
      const c = NotesNoteClone(n);
      c.tagColor = color;
      updated.push(c);
    });
    this.applyLocalNoteUpdates(updated);
  }

  setTagColorFilter(color: string): void {
    this.tagColorFilter = color;
  }

  clearTagColorFilter(): void {
    this.tagColorFilter = NOTES_ALL_TAG_FILTER;
  }

  /** 目标分组选择（对齐 Flutter pickTargetGroup；返回所选组 id，取消返回 ''） */
  async pickTargetGroup(excludedGroupId: string): Promise<string> {
    const excluded = excludedGroupId.trim();
    const targets = this.groups.filter(
      (g: NotesGroup): boolean => excluded.length === 0 || g.id !== excluded);
    if (targets.length === 0) {
      ToastUtil.show(L10n.t('notes_no_group_to_move'));
      return '';
    }
    const items = targets.map((g: NotesGroup): SelectItem =>
      new SelectItem(displayNotesGroupName(g.id, g.name)));
    const idx = await DialogUtil.showSelectDialog(
      L10n.t('notes_group_select'), items, -1);
    if (typeof idx !== 'number' || idx < 0 || idx >= targets.length) {
      return '';
    }
    return targets[idx].id;
  }

  async moveNoteTo(noteId: string, targetGroupId: string): Promise<void> {
    const ok = await this.moveNoteOnce(noteId, targetGroupId);
    if (!ok) {
      return;
    }
    await this.refreshState(noteId);
  }

  private async moveNoteOnce(noteId: string, targetGroupId: string): Promise<boolean> {
    const res = await NotesApiService.moveNote(noteId, targetGroupId);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_move_failed'));
      return false;
    }
    return true;
  }

  async deleteCurrentNote(): Promise<void> {
    const note = this.currentNote;
    if (note === undefined) {
      return;
    }
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('notes_note_delete'),
      L10n.t('notes_note_delete_confirm', '',
        new Map<string, string>([['title', displayNotesTitle(note.title)]])),
      undefined, L10n.t('delete'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    const deleted = await this.deleteNoteOnce(note.id);
    if (!deleted) {
      return;
    }
    await this.refreshState('');
  }

  private async deleteNoteOnce(noteId: string): Promise<boolean> {
    const res = await NotesApiService.deleteNote(noteId);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed'));
      return false;
    }
    return true;
  }

  async restoreNote(note: NotesNote): Promise<void> {
    const res = await NotesApiService.restoreNote(note.id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_restore_failed'));
      return;
    }
    await this.refreshState('');
  }

  async permanentlyDeleteNote(note: NotesNote): Promise<void> {
    const ok = await DialogUtil.showConfirmDialog(
      L10n.t('notes_delete_forever'), L10n.t('notes_delete_forever_confirm'),
      undefined, L10n.t('delete'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    const res = await NotesApiService.permanentlyDeleteNote(note.id);
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed'));
      return;
    }
    await this.refreshState('');
  }

  private resolveMetaTargets(note: NotesNote): NotesNote[] {
    const current = this.findLocalNote(note.id) ?? note;
    if (!(this.hasBatchSelection && this.isNoteSelected(note.id))) {
      return [current];
    }
    const targets: NotesNote[] = [];
    this.selectedNoteIds.forEach((id: string): void => {
      const hit = this.visibleNotes.find((n: NotesNote): boolean => n.id === id);
      if (hit !== undefined) {
        targets.push(this.findLocalNote(hit.id) ?? hit);
      }
    });
    return targets.length === 0 ? [current] : targets;
  }

  private applyLocalNoteUpdates(updatedNotes: NotesNote[]): void {
    if (updatedNotes.length === 0) {
      return;
    }
    const next = this.notes.slice();
    updatedNotes.forEach((u: NotesNote): void => {
      const idx = next.findIndex((n: NotesNote): boolean => n.id === u.id);
      if (idx >= 0) {
        next[idx] = u;
      }
    });
    this.notes = next;
    const current = this.currentNote;
    if (current !== undefined) {
      const hit = updatedNotes.find((n: NotesNote): boolean => n.id === current.id);
      if (hit !== undefined) {
        this.currentNote = hit;
      }
    }
  }

  // ===== 批量（对齐 restoreSelectedNotes/moveSelectedNotes/deleteSelectedNotes） =====

  private batchTargets(): NotesNote[] {
    const pickedIds = this.selectedNoteIds.slice();
    if (pickedIds.length <= 1) {
      return [];
    }
    const selected = this.visibleNotes.filter((n: NotesNote): boolean =>
      pickedIds.indexOf(n.id) >= 0);
    return selected.length <= 1 ? [] : selected;
  }

  async restoreSelectedNotes(): Promise<void> {
    const selected = this.batchTargets();
    if (selected.length === 0) {
      return;
    }
    this.loadingState = true;
    const ids: string[] = [];
    selected.forEach((n: NotesNote): void => {
      ids.push(n.id);
    });
    const res = await NotesApiService.batchRestoreNotes(ids);
    this.loadingState = false;
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_restore_failed'));
      return;
    }
    this.clearNoteSelection(false);
    await this.refreshState('');
  }

  async moveSelectedNotes(): Promise<void> {
    const selected = this.batchTargets();
    if (selected.length === 0) {
      return;
    }
    await this.flushPendingSaves();
    const uniqueGroupIds: string[] = [];
    selected.forEach((n: NotesNote): void => {
      if (uniqueGroupIds.indexOf(n.groupId) < 0) {
        uniqueGroupIds.push(n.groupId);
      }
    });
    const targetId = await this.pickTargetGroup(uniqueGroupIds.length === 1 ? uniqueGroupIds[0] : '');
    if (targetId.length === 0) {
      return;
    }
    const keepNoteId = this.selectedNoteId.trim();
    const movableIds: string[] = [];
    selected.forEach((n: NotesNote): void => {
      if (n.groupId !== targetId) {
        movableIds.push(n.id);
      }
    });
    if (movableIds.length === 0) {
      this.clearNoteSelection();
      return;
    }
    this.loadingState = true;
    const res = await NotesApiService.batchMoveNotes(movableIds, targetId);
    this.loadingState = false;
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('notes_move_failed'));
      return;
    }
    this.clearNoteSelection(false);
    await this.refreshState(keepNoteId);
  }

  async deleteSelectedNotes(): Promise<void> {
    const selected = this.batchTargets();
    if (selected.length === 0) {
      return;
    }
    await this.flushPendingSaves();
    const title = this.showingTrash ? L10n.t('notes_delete_forever') : L10n.t('notes_note_delete');
    const content = this.showingTrash
      ? `${L10n.t('notes_delete_forever_confirm')}\n`
        + `${L10n.t('items_selected', '已选择 @count 项', L10n.paramsOf('count', `${selected.length}`))}`
      : L10n.t('book_delete_confirm_count', '确认删除@count个项目吗？',
        L10n.paramsOf('count', `${selected.length}`));
    const ok = await DialogUtil.showConfirmDialog(title, content,
      undefined, L10n.t('delete'), L10n.cancel);
    if (ok !== true) {
      return;
    }
    const keepNoteId = this.selectedNoteId.trim();
    this.loadingState = true;
    const ids: string[] = [];
    selected.forEach((n: NotesNote): void => {
      ids.push(n.id);
    });
    const res = this.showingTrash
      ? await NotesApiService.batchPermanentlyDeleteNotes(ids)
      : await NotesApiService.batchDeleteNotes(ids);
    this.loadingState = false;
    if (!res.success) {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.t('delete_failed'));
      return;
    }
    this.clearNoteSelection(false);
    await this.refreshState(keepNoteId);
  }

  // ===== 导出（对齐 Flutter exportNote：先强制保存当前笔记，再走服务器导出下载） =====

  /** 返回导出 URL（由视图层执行下载保存），失败返回 '' */
  async prepareExport(note: NotesNote, format: string): Promise<string> {
    const noteId = note.id.trim();
    const normalizedFormat = format.trim().toLowerCase();
    if (noteId.length === 0 || normalizedFormat.length === 0) {
      return '';
    }
    if (!note.isDeleted && this.currentNote !== undefined && this.currentNote.id === noteId) {
      await this.saveCurrentNote(true);
    }
    const label = normalizedFormat === 'pdf' ? 'PDF'
      : (normalizedFormat === 'markdown' ? 'Markdown'
        : (normalizedFormat === 'txt' ? 'TXT' : normalizedFormat.toUpperCase()));
    const fmtParams = new Map<string, string>();
    fmtParams.set('format', label);
    ToastUtil.show(L10n.t('notes_export_started', undefined, fmtParams));
    return NotesApiService.buildExportUrl(noteId, normalizedFormat);
  }

  /** 导出文件名（对齐 Flutter _buildExportFileName） */
  buildExportFileName(note: NotesNote, ext: string): string {
    let base = note.title.trim();
    base = base.replace(/[\u0000-\u001F]/g, '_');
    base = base.replace(/[<>:"/\\|?*]/g, '_');
    base = base.replace(/\s+/g, ' ').trim();
    base = base.replace(/[. ]+$/, '');
    if (base.length === 0) {
      const suffix = note.id.length >= 8 ? note.id.substring(0, 8) : note.id;
      base = suffix.length === 0 ? 'note' : `note_${suffix}`;
    }
    return `${base}.${ext}`;
  }
}

/** 服务器 note 记录 → NotesNote（res.data['note']，id 缺失时沿用本地） */
function NotesNoteFromServer(rec: Record<string, Object>, fallbackId: string): NotesNote {
  const n = NotesNote.fromJson(rec);
  if (n.id.length === 0) {
    n.id = fallbackId;
  }
  return n;
}

/** NotesNote 浅拷贝 */
function NotesNoteClone(src: NotesNote): NotesNote {
  const n = new NotesNote();
  n.id = src.id;
  n.title = src.title;
  n.preview = src.preview;
  n.groupId = src.groupId;
  n.groupName = src.groupName;
  n.tagColor = src.tagColor;
  n.isPinned = src.isPinned;
  n.isDeleted = src.isDeleted;
  n.updateTime = src.updateTime;
  n.createTime = src.createTime;
  n.deletedAt = src.deletedAt;
  n.assetCount = src.assetCount;
  return n;
}
