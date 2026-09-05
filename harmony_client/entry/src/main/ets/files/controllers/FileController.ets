import { APIClient } from '../../core/network/APIClient';
import { APIResponse } from '../../core/network/APIResponse';
import { PreferencesStore } from '../../core/storage/PreferencesStore';
import { L10n } from '../../core/localization/L10n';
import { ToastUtil } from '../../common/ToastUtil';
import { DialogUtil } from '../../common/DialogUtil';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { FileApiService } from '../service/FileApiService';
import { FileWatcherService, FileChangeData } from '../service/FileWatcherService';
import { FileClipboard } from './FileClipboard';
import {
  FileItem, FileModelAccess, FileSuffixes, fileItemIsDotHidden
} from '../models/FileModels';

/** 文件操作确认内容 */
function l10nParams(entries: string[][]): Map<string, string> {
  const map = new Map<string, string>();
  for (const e of entries) {
    map.set(e[0], e[1]);
  }
  return map;
}

/** 涉及页面级 UI（选择目标目录弹层等）的钩子，由页面注入实现 */
export interface FileUiHook {
  /** 打开“添加自定义根路径”表单弹层 */
  showAddCustomPath: () => void;
  /** 打开目标文件夹选择弹层，返回所选路径（取消返回空数组） */
  pickTargetFolder: () => Promise<string[]>;
}

/**
 * 文件浏览器控制器（对齐 Flutter FileController + AppFileController 移动端扩展 + parts/*）：
 * 目录列表/面包屑/搜索(本地+防抖全局)/排序/筛选/多选/操作(新建/删除/重命名/复制移动)/
 * 收藏与最近/剪贴板/WS 实时刷新/索引配置。
 */
@ObservedV2
export class FileController {
  // ===== 目录与列表状态 =====
  @Trace currentPath: string = '';
  @Trace currentSourceType: string = '';
  @Trace items: FileItem[] = [];
  @Trace loading: boolean = false;
  @Trace segments: FileItem[] = [];
  @Trace sep: string = '/';
  // ===== 多选状态 =====
  @Trace selected: string[] = [];
  @Trace isMultiSelectMode: boolean = false;
  // ===== 排序/视图/筛选/搜索 =====
  @Trace sortMode: string = 'name_asc';
  @Trace searchQuery: string = '';
  @Trace filterType: string = 'all'; // all/dir/image/video/audio/document/archive/file
  @Trace searchScope: string = 'current'; // current/global/subtree
  @Trace globalSearchItems: FileItem[] = [];
  @Trace globalSearchLoading: boolean = false;
  @Trace viewMode: string = 'grid'; // grid/large_grid/list
  @Trace showHidden: boolean = false;
  @Trace onlyShowDir: boolean = false;
  // ===== 服务器根目录（含自定义路径） =====
  @Trace serverRoots: FileItem[] = [];
  // ===== 当前模块：normal/favorites/recent =====
  @Trace currentModule: string = 'normal';
  // ===== 索引配置（AppFileController） =====
  @Trace indexEnabled: boolean = false;
  @Trace indexIntervalHours: number = 72;
  @Trace indexConfigLoading: boolean = false;
  @Trace indexConfigSaving: boolean = false;

  private readonly autoLoadRoot: boolean;
  private readonly listApiPath: string;
  private readonly searchApiPath: string;
  private readonly showRootCustomPathEntry: boolean;

  private readonly api: FileApiService = FileApiService.getInstance();
  private fileWatcher: FileWatcherService | undefined = undefined;
  private globalSearchTimer: number = -1;
  /** 并发 listDirectory 时只采纳最后一次请求结果 */
  private listDirectorySeq: number = 0;

  /** 页面注入的 UI 钩子 */
  uiHook: FileUiHook | undefined = undefined;

  constructor(autoLoadRoot: boolean = true, listApiPath: string = '/api/file/list',
    searchApiPath: string = '/api/file/search', showRootCustomPathEntry: boolean = true) {
    this.autoLoadRoot = autoLoadRoot;
    this.listApiPath = listApiPath;
    this.searchApiPath = searchApiPath;
    this.showRootCustomPathEntry = showRootCustomPathEntry;
  }

  // ==================== lifecycle ====================

  init(): void {
    this.fileWatcher = new FileWatcherService(
      (data: FileChangeData): void => this.handleFileChange(data),
      (_e: Object): void => {
      });
    void this.loadSortMode();
    void this.loadViewMode();
    void this.loadShowHidden();
    if (this.autoLoadRoot) {
      void this.listDirectory('', 'normal', this.currentSourceType);
    }
  }

  close(): void {
    this.fileWatcher?.disconnect();
    if (this.globalSearchTimer >= 0) {
      clearTimeout(this.globalSearchTimer);
      this.globalSearchTimer = -1;
    }
  }

  private handleFileChange(data: FileChangeData): void {
    const changeDir = data.changeDir ?? '';
    if (changeDir.length > 0 && this.currentPath.length > 0 && changeDir !== this.currentPath) {
      return;
    }
    const removed = data.removed ?? [];
    const added = data.added ?? [];
    let changed = false;
    if (removed.length > 0) {
      this.items = this.items.filter((it: FileItem) => !removed.includes(FileModelAccess.path(it)));
      changed = true;
    }
    if (added.length > 0) {
      for (const item of added) {
        const idx = this.items.findIndex((e: FileItem) => FileModelAccess.path(e) === FileModelAccess.path(item));
        if (idx >= 0) {
          this.items.splice(idx, 1, item);
        } else {
          this.items.push(item);
        }
      }
      changed = true;
    }
    if (changed) {
      this.applySort();
    }
  }

  // ==================== directory ====================

  get clipboard(): FileClipboard {
    return FileClipboard.getInstance();
  }

  /** 设置搜索关键字（仅影响本地展示列表；非当前目录范围时触发防抖全局搜索） */
  setSearchQuery(q: string): void {
    this.searchQuery = q;
    const keyword = q.trim();
    if (keyword.length === 0) {
      if (this.globalSearchTimer >= 0) {
        clearTimeout(this.globalSearchTimer);
        this.globalSearchTimer = -1;
      }
      // 清空关键字时保留搜索作用域与类型筛选，仅清空全局搜索结果
      this.globalSearchItems = [];
      this.globalSearchLoading = false;
      return;
    }
    if (this.searchScope !== 'current') {
      this.scheduleGlobalSearch();
    }
  }

  exitSearchMode(): void {
    this.setSearchQuery('');
    this.filterType = 'all';
  }

  /** 设置筛选类型（仅影响本地展示列表） */
  setFilterType(type: string): void {
    this.filterType = type;
    if (this.searchScope !== 'current' && this.searchQuery.trim().length > 0) {
      this.scheduleGlobalSearch();
    }
  }

  setSearchScope(scope: string): void {
    const next = scope === 'global' ? 'global' : scope === 'subtree' ? 'subtree' : 'current';
    if (this.searchScope === next) {
      return;
    }
    this.searchScope = next;
    if (next === 'current') {
      if (this.globalSearchTimer >= 0) {
        clearTimeout(this.globalSearchTimer);
        this.globalSearchTimer = -1;
      }
      this.globalSearchItems = [];
      this.globalSearchLoading = false;
      return;
    }
    if (this.searchQuery.trim().length > 0) {
      this.scheduleGlobalSearch();
    }
  }

  private scheduleGlobalSearch(): void {
    if (this.globalSearchTimer >= 0) {
      clearTimeout(this.globalSearchTimer);
    }
    this.globalSearchTimer = setTimeout((): void => {
      void this.performGlobalSearch();
    }, 280);
  }

  private async performGlobalSearch(): Promise<void> {
    const keyword = this.searchQuery.trim();
    if (keyword.length === 0) {
      return;
    }
    const type = this.filterType;
    let mode = '';
    let suffixes: string[] = [];
    if (type === 'dir') {
      mode = 'dir';
    } else if (type === 'file') {
      mode = 'file';
    } else if (type === 'image') {
      suffixes = FileSuffixes.IMAGE;
    } else if (type === 'video') {
      suffixes = FileSuffixes.VIDEO;
    } else if (type === 'archive') {
      suffixes = FileSuffixes.ARCHIVE;
    } else if (type === 'audio') {
      suffixes = FileSuffixes.AUDIO;
    } else if (type === 'document') {
      suffixes = FileSuffixes.DOCUMENT;
    }
    const rawDir = this.currentPath.trim();
    const dir = (this.searchScope === 'subtree' && rawDir.length > 0) ? rawDir : '';
    this.globalSearchLoading = true;
    try {
      const res = await this.api.searchGlobal(keyword, dir, suffixes, mode, 500, this.searchApiPath,
        this.currentSourceType);
      if (!res.success) {
        console.error('[FileSearch] failed scope=' + this.searchScope + ' msg=' + (res.message ?? ''));
        this.globalSearchItems = [];
        return;
      }
      const list = (res.data?.items ?? []) as FileItem[];
      const uniq: FileItem[] = [];
      const seen = new Set<string>();
      for (const it of list) {
        const p = FileModelAccess.path(it);
        if (p.length === 0 || seen.has(p)) {
          continue;
        }
        seen.add(p);
        uniq.push(it);
      }
      console.info('[FileSearch] scope=' + this.searchScope + ' dir=' + dir + ' results=' + uniq.length);
      this.globalSearchItems = uniq;
    } finally {
      this.globalSearchLoading = false;
    }
  }

  /** 获取用于显示的文件列表（应用搜索与类型筛选；根目录追加“添加自定义路径”虚拟行） */
  get displayItems(): FileItem[] {
    const q = this.searchQuery.trim().toLowerCase();
    const list = (this.searchScope !== 'current' && q.length > 0) ? this.globalSearchItems : this.items;
    const type = this.filterType;
    const filtered = list.filter((e: FileItem): boolean => {
      const name = FileModelAccess.fileName(e).toLowerCase();
      const p = FileModelAccess.path(e).toLowerCase();
      if (q.length > 0) {
        if (this.searchScope !== 'current') {
          if (!name.includes(q)) {
            return false;
          }
        } else if (!(name.includes(q) || p.includes(q))) {
          return false;
        }
      }
      if (type === 'all') {
        return true;
      }
      if (type === 'dir') {
        return FileModelAccess.isDir(e);
      }
      if (type === 'image') {
        return FileModelAccess.type(e) === 'image' || FileSuffixes.isImage(e);
      }
      if (type === 'video') {
        return FileSuffixes.isVideo(e);
      }
      if (type === 'audio') {
        return FileSuffixes.isAudio(e);
      }
      if (type === 'document') {
        return FileSuffixes.isDocument(e);
      }
      if (type === 'archive') {
        return FileSuffixes.isArchive(e);
      }
      if (type === 'file') {
        return !FileModelAccess.isDir(e);
      }
      return true;
    });

    const atRoot = this.currentPath.trim().length === 0;
    const inNormal = this.currentModule === 'normal';
    if (this.showRootCustomPathEntry && atRoot && inNormal && q.length === 0 && this.searchScope === 'current') {
      const virtual = new FileItem();
      virtual.path = '__custom_path_add__';
      virtual.name = L10n.t('file_custom_path_entry', '添加常用路径');
      virtual.type = 'dir';
      virtual.virtualType = 'custom_add';
      return filtered.concat([virtual]);
    }
    return filtered;
  }

  /** 刷新当前页面，根据当前模块重新加载目录列表 */
  refreshPage(): void {
    const base = this.currentPath;
    let source = 'normal';
    if (this.currentModule === 'favorites') {
      source = 'favorites';
    } else if (this.currentModule === 'recent') {
      source = 'recent';
    }
    void this.listDirectory(base, source, this.currentSourceType);
  }

  async listDirectory(path: string, listSource: string = 'normal', sourceType: string = ''): Promise<void> {
    const sourceTypeToUse = listSource === 'normal' ? (sourceType.length > 0 ? sourceType : this.currentSourceType) : '';
    this.currentSourceType = sourceTypeToUse;
    // 进入新目录时清空当前选中状态
    this.clearSelect();
    const seq = ++this.listDirectorySeq;
    this.loading = true;
    try {
      const res = await this.api.listDirectory(path, this.onlyShowDir, this.showHidden,
        listSource, sourceTypeToUse, this.listApiPath);
      if (seq !== this.listDirectorySeq) {
        return;
      }
      this.currentPath = res.base ?? path;
      this.items = (res.items ?? []) as FileItem[];
      this.segments = (res.segments ?? []) as FileItem[];
      this.sep = res.sep ?? this.sep;
      if (path === '' && listSource === 'normal') {
        // 更新服务器根目录列表
        this.serverRoots = (res.items ?? []) as FileItem[];
      }
      if (listSource !== 'recent') {
        this.applySort();
      }
      this.currentModule = listSource;
      this.loading = false;

      if (path.length > 0 && listSource === 'normal') {
        this.fileWatcher?.connect(path);
      } else {
        this.fileWatcher?.disconnect();
      }

      if (this.searchScope !== 'current' && this.searchQuery.trim().length > 0) {
        this.scheduleGlobalSearch();
      }
    } catch (e) {
      console.error(`[FileController] listDirectory error: ${e}`);
      if (seq !== this.listDirectorySeq) {
        return;
      }
      this.loading = false;
      DialogUtil.showErrorDialog(L10n.operationFailed);
    }
  }

  async goUp(): Promise<void> {
    if (this.segments.length <= 1) {
      await this.listDirectory('', 'normal', this.currentSourceType);
      return;
    }
    const parent = FileModelAccess.path(this.segments[this.segments.length - 2]);
    await this.listDirectory(parent, 'normal', this.currentSourceType);
  }

  async navigateTo(path: string): Promise<void> {
    await this.listDirectory(path, 'normal', this.currentSourceType);
  }

  get isRoot(): boolean {
    return this.segments.length === 0;
  }

  /** 添加自定义根路径 */
  async addCustomPath(name: string, path: string): Promise<APIResponse<Object>> {
    return this.api.addCustomPath(name, path);
  }

  /** 移除自定义根路径 */
  async removeCustomPath(path: string): Promise<void> {
    const p = path.trim();
    if (p.length === 0) {
      return;
    }
    const res = await this.api.removeCustomPath(p);
    if (!res.success) {
      ToastUtil.show(res.message ?? L10n.operationFailed);
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    await this.listDirectory('', 'normal', this.currentSourceType);
  }

  // ==================== sort ====================

  /** 自然排序文件名比较（对齐 Flutter _naturalFileNameCompare） */
  private naturalFileNameCompare(a: string, b: string): number {
    if (a === b) {
      return 0;
    }
    if (a.length === 0) {
      return b.length === 0 ? 0 : -1;
    }
    if (b.length === 0) {
      return 1;
    }
    const al = a.toLowerCase();
    const bl = b.toLowerCase();
    const splitRe: RegExp = new RegExp('\\d+|\\D+', 'g');
    const ap = al.match(splitRe) ?? [];
    const bp = bl.match(splitRe) ?? [];
    const isDigits = (s: string): boolean => {
      if (s.length === 0) {
        return false;
      }
      for (let i = 0; i < s.length; i++) {
        const c = s.charCodeAt(i);
        if (c < 48 || c > 57) {
          return false;
        }
      }
      return true;
    };
    const cmpDigits = (x: string, y: string): number => {
      const xn0 = x.replace(/^0+/, '');
      const yn0 = y.replace(/^0+/, '');
      const xn = xn0.length === 0 ? '0' : xn0;
      const yn = yn0.length === 0 ? '0' : yn0;
      if (xn.length !== yn.length) {
        return xn.length - yn.length;
      }
      const c = xn.localeCompare(yn);
      if (c !== 0) {
        return c;
      }
      return x.length - y.length;
    };
    const len = Math.min(ap.length, bp.length);
    for (let i = 0; i < len; i++) {
      const as = ap[i];
      const bs = bp[i];
      if (as === bs) {
        continue;
      }
      const aNum = isDigits(as);
      const bNum = isDigits(bs);
      if (aNum && bNum) {
        const c = cmpDigits(as, bs);
        if (c !== 0) {
          return c;
        }
        continue;
      }
      if (aNum !== bNum) {
        return aNum ? -1 : 1;
      }
      const c = as.localeCompare(bs);
      if (c !== 0) {
        return c;
      }
    }
    if (ap.length !== bp.length) {
      return ap.length - bp.length;
    }
    const c2 = a.localeCompare(b);
    if (c2 !== 0) {
      return c2;
    }
    return a.length - b.length;
  }

  setSortMode(mode: string): void {
    this.sortMode = mode;
    if (this.currentModule !== 'recent') {
      this.applySort();
    }
    void PreferencesStore.getInstance().setString('file_sort_mode', mode);
  }

  /** 设置视图模式（图标/大图标/列表），持久化 */
  setViewMode(mode: string): void {
    this.viewMode = mode;
    void PreferencesStore.getInstance().setString('file_view_mode', mode);
  }

  applySort(): void {
    const mode = this.sortMode;
    const desc = mode.endsWith('_desc');
    const cmp = (a: FileItem, b: FileItem): number => {
      switch (mode) {
        case 'size_asc':
        case 'size_desc': {
          const as = FileModelAccess.size(a);
          const bs = FileModelAccess.size(b);
          return as - bs;
        }
        case 'mtime_asc':
        case 'mtime_desc': {
          const am = FileModelAccess.mtimeMs(a) ?? 0;
          const bm = FileModelAccess.mtimeMs(b) ?? 0;
          return am - bm;
        }
        case 'type_asc':
        case 'type_desc': {
          return FileModelAccess.type(a).localeCompare(FileModelAccess.type(b));
        }
        case 'name_asc':
        case 'name_desc':
        default:
          return this.naturalFileNameCompare(FileModelAccess.fileName(a), FileModelAccess.fileName(b));
      }
    };
    const sorted = this.items.slice().sort((a: FileItem, b: FileItem): number => {
      const c = cmp(a, b);
      return desc ? -c : c;
    });
    this.items = sorted;
  }

  private async loadSortMode(): Promise<void> {
    try {
      const v = PreferencesStore.getInstance().getString('file_sort_mode');
      if (v !== undefined && v.length > 0) {
        this.sortMode = v;
        this.applySort();
      }
    } catch (_e) {
    }
  }

  private async loadViewMode(): Promise<void> {
    try {
      const v = PreferencesStore.getInstance().getString('file_view_mode');
      if (v !== undefined && v.length > 0) {
        this.viewMode = v;
      }
    } catch (_e) {
    }
  }

  private async loadShowHidden(): Promise<void> {
    try {
      const v = PreferencesStore.getInstance().getBool('file_show_hidden', false);
      if (this.showHidden === v) {
        return;
      }
      this.showHidden = v;
      if (this.currentPath.length === 0 && !this.autoLoadRoot) {
        return;
      }
      this.refreshPage();
    } catch (_e) {
    }
  }

  async toggleShowHidden(): Promise<void> {
    this.showHidden = !this.showHidden;
    await PreferencesStore.getInstance().setBool('file_show_hidden', this.showHidden);
    this.refreshPage();
  }

  // ==================== selection ====================

  toggleSelect(path: string): void {
    if (this.selected.includes(path)) {
      this.selected = this.selected.filter((p: string) => p !== path);
    } else {
      this.selected = this.selected.concat([path]);
    }
  }

  clearSelect(): void {
    this.selected = [];
  }

  /** 仅选中指定项目 */
  selectOnly(path: string): void {
    this.selected = [path];
  }

  getSelected(): string[] {
    return this.selected.slice();
  }

  enterMultiSelectMode(firstSelectedPath: string): void {
    this.isMultiSelectMode = true;
    if (firstSelectedPath.length > 0) {
      this.selectOnly(firstSelectedPath);
    }
  }

  exitMultiSelectMode(): void {
    this.isMultiSelectMode = false;
    this.clearSelect();
  }

  // ==================== format ====================

  /** 非缩略图类型对应的本地图标（rawfile 相对路径），缩略图类型返回 'tiny' 标记 */
  static iconFor(name: string, filePath: string, type: string): string {
    if (type === 'image' || type === 'video' || type === 'raw') {
      return 'tiny';
    }
    if (type === 'dir') {
      return 'icons/file/folder.png';
    }
    const dot = name.lastIndexOf('.');
    const ext = dot >= 0 && dot < name.length - 1 ? name.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'epub':
      case 'mobi':
      case 'azw3':
        return 'icons/file/ebook.png';
      case 'zip':
        return 'icons/file/zip.png';
      case 'rar':
        return 'icons/file/rar.png';
      case 'tar':
        return 'icons/file/tar.png';
      case 'doc':
        return 'icons/file/doc.png';
      case 'docx':
        return 'icons/file/docx.png';
      case 'ppt':
        return 'icons/file/ppt.png';
      case 'md':
        return 'icons/file/md.png';
      case 'pdf':
        return 'icons/file/pdf.png';
      case 'pptx':
        return 'icons/file/pptx.png';
      case 'xls':
        return 'icons/file/xls.png';
      case 'xlsx':
        return 'icons/file/xlsx.png';
      case 'xml':
        return 'icons/file/xml.png';
      case 'txt':
        return 'icons/file/txt.png';
      case 'log':
        return 'icons/file/log.png';
      case 'mp3':
      case 'flac':
      case 'aac':
      case 'wav':
      case 'ogg':
      case 'opus':
      case 'wma':
      case 'ape':
      case 'm4a':
        return 'icons/file/audio.png';
      default:
        return 'icons/file/file.png';
    }
  }

  /** 条目是否需要网络缩略图 */
  needsTinyThumb(it: FileItem): boolean {
    const type = FileModelAccess.type(it);
    return type === 'image' || type === 'video' || type === 'raw';
  }

  // ==================== actions ====================

  private async ensureWriteSupported(): Promise<boolean> {
    const base = this.currentPath;
    try {
      const res = await this.api.checkMkdirSupport(base);
      if (!res.success) {
        ToastUtil.show(res.message ?? L10n.operationFailed);
        return false;
      }
      const data = res.data as Record<string, Object> | undefined;
      const supported = data !== undefined && data['supported'] === true;
      if (!supported) {
        ToastUtil.show(L10n.t('folder_action_not_supported', '当前目录不支持该操作'));
      }
      return supported;
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
      return false;
    }
  }

  ensureCreateFolderSupported(): Promise<boolean> {
    return this.ensureWriteSupported();
  }

  ensureCreateFileSupported(): Promise<boolean> {
    return this.ensureWriteSupported();
  }

  ensureUploadSupported(): Promise<boolean> {
    return this.ensureWriteSupported();
  }

  /** 创建文件夹 */
  async createFolder(name: string): Promise<boolean> {
    const base = this.currentPath;
    if (base.length === 0 || name.trim().length === 0) {
      return false;
    }
    try {
      const res = await this.api.mkdir(base, name.trim());
      if (res.success) {
        // 重新获取列表以确保数据最新
        await this.listDirectory(base, 'normal');
      } else {
        ToastUtil.show(res.message ?? L10n.operationFailed);
      }
      return res.success;
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
      return false;
    }
  }

  /** 新建 txt/md 文件（打开编辑器功能未迁移，创建成功后仅刷新列表） */
  async createTextFile(name: string, type: string): Promise<boolean> {
    const base = this.currentPath;
    const trimmed = name.trim();
    if (base.length === 0 || trimmed.length === 0) {
      return false;
    }
    try {
      const res = await this.api.createFile(base, trimmed, type);
      if (!res.success) {
        ToastUtil.show(res.message ?? L10n.operationFailed);
        return false;
      }
      await this.listDirectory(base, 'normal');
      return true;
    } catch (_e) {
      ToastUtil.show(L10n.operationFailed);
      return false;
    }
  }

  /** 复制到/移动到：弹出目录选择器选择目标目录，确认后调用后端任务 */
  async handleCopyOrMove(isCopy: boolean): Promise<void> {
    const paths = this.getSelected();
    if (paths.length === 0) {
      return;
    }
    const hook = this.uiHook;
    const targetList = hook ? await hook.pickTargetFolder() : [];
    if (targetList.length === 0) {
      return;
    }
    const targetPath = targetList[0];
    const contentKey = isCopy ? 'folder_action_confirm_copy' : 'folder_action_confirm_move';
    const fallback = isCopy ? '确定将 @count 个项目复制到 @target ？' : '确定将 @count 个项目移动到 @target ？';
    const confirmed = await DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t(contentKey, fallback, l10nParams([
        ['count', `${paths.length}`],
        ['target', targetPath]
      ])));
    if (confirmed !== true) {
      return;
    }
    const result: APIResponse<Object> = isCopy ?
      await this.api.copyFiles(paths, targetPath) :
      await this.api.moveFiles(paths, targetPath);
    if (result.success) {
      // 运行任务列表依赖传输模块，暂以成功提示占位
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } else {
      ToastUtil.show(result.message ?? L10n.operationFailed);
    }
  }

  /** 删除已选中的文件或文件夹 */
  async deleteSelectedEntries(recycle: boolean = false): Promise<boolean> {
    const targets = this.getSelected();
    if (targets.length === 0) {
      return false;
    }
    try {
      const res = await this.api.deleteEntries(targets, recycle);
      if (res.success) {
        this.clearSelect();
        // 从当前列表中移除被删除的项，而不是重新获取整个列表，以保持滚动位置
        this.items = this.items.filter((it: FileItem) => !targets.includes(FileModelAccess.path(it)));
        ToastUtil.show(L10n.t('delete_success', '删除成功'));
      } else {
        DialogUtil.showErrorDialog(res.message ?? L10n.operationFailed);
      }
      return res.success;
    } catch (_e) {
      return false;
    }
  }

  /** 重命名文件或文件夹 */
  async renameEntry(path: string, newName: string): Promise<boolean> {
    try {
      const res = await this.api.rename(path, newName);
      if (res.success) {
        const result = res.data;
        if (result !== undefined) {
          // 更新本地列表中的数据，而不是重新获取整个列表，以保持滚动位置
          const index = this.items.findIndex((it: FileItem) => FileModelAccess.path(it) === path);
          if (index >= 0) {
            this.items.splice(index, 1, result as FileItem);
          }
          ToastUtil.show(L10n.t('operation_success', '操作成功'));
        }
        return true;
      }
      DialogUtil.showErrorDialog(res.message ?? L10n.operationFailed);
      return false;
    } catch (_e) {
      DialogUtil.showErrorDialog(L10n.operationFailed);
      return false;
    }
  }

  // ==================== favorites / recent ====================

  async clearRecent(): Promise<boolean> {
    try {
      const ok = await this.api.clearRecent();
      if (ok && this.currentModule === 'recent') {
        await this.listDirectory('', 'recent');
      }
      return ok;
    } catch (_e) {
      return false;
    }
  }

  /** 添加到收藏 */
  async addFavorites(paths: string[]): Promise<boolean> {
    try {
      const ok = await this.api.addFavorites(paths);
      if (this.currentModule === 'favorites') {
        this.refreshPage();
      }
      return ok;
    } catch (_e) {
      return false;
    }
  }

  /** 取消收藏 */
  async removeFavorites(paths: string[]): Promise<boolean> {
    try {
      const ok = await this.api.removeFavorites(paths);
      if (this.currentModule === 'favorites') {
        this.refreshPage();
      }
      return ok;
    } catch (_e) {
      return false;
    }
  }

  // ==================== clipboard ====================

  copyToClipboard(): void {
    if (this.selected.length === 0) {
      return;
    }
    this.clipboard.items = this.getSelected();
    this.clipboard.action = 'copy';
    ToastUtil.show(L10n.t('file_clipboard_copy', '已复制 @count 个文件到剪贴板',
      l10nParams([['count', `${this.selected.length}`]])));
  }

  cutToClipboard(): void {
    if (this.selected.length === 0) {
      return;
    }
    this.clipboard.items = this.getSelected();
    this.clipboard.action = 'cut';
    ToastUtil.show(L10n.t('file_clipboard_cut', '已剪切 @count 个文件到剪贴板',
      l10nParams([['count', `${this.selected.length}`]])));
  }

  /** 清空剪贴板 */
  clearClipboard(): void {
    this.clipboard.clear();
    ToastUtil.show(L10n.t('folder_clean_clipboard', '已清空剪贴板'));
  }

  async pasteFromClipboard(): Promise<void> {
    if (this.clipboard.isEmpty()) {
      return;
    }
    // “最近”“收藏”列表不能作为黏贴目的地
    if (this.currentModule === 'recent' || this.currentModule === 'favorites') {
      return;
    }
    const targetPath = this.currentPath;
    const isCopy = this.clipboard.action === 'copy';
    const confirmed = await DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      L10n.t('file_clipboard_paste', '确定将 @count 个项目粘贴到 @target ？', l10nParams([
        ['count', `${this.clipboard.items.length}`],
        ['target', targetPath]
      ])));
    if (confirmed !== true) {
      return;
    }
    const res: APIResponse<Object> = isCopy ?
      await this.api.copyFiles(this.clipboard.items, targetPath) :
      await this.api.moveFiles(this.clipboard.items, targetPath);
    if (res.success) {
      // 运行任务列表依赖传输模块，暂以成功提示占位
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      if (!isCopy) {
        this.clipboard.clear();
      }
      this.refreshPage();
    } else {
      DialogUtil.showErrorDialog(res.message ?? L10n.operationFailed);
    }
  }

  // ==================== open（未迁移依赖模块的分支以 toast 占位） ====================

  /** 点击条目（对齐 Flutter handleItemTap；仅保留目录导航，其余类型打开器未迁移） */
  handleItemTap(it: FileItem, forceEnter: boolean): void {
    const virtualType = FileModelAccess.virtualType(it);
    if (virtualType === 'custom_add') {
      this.uiHook?.showAddCustomPath();
      return;
    }
    const path = FileModelAccess.path(it);
    const type = FileModelAccess.type(it);
    if (forceEnter) {
      if (type === 'dir') {
        if (this.searchScope !== 'current' && this.searchQuery.trim().length > 0) {
          this.exitSearchMode();
        }
        void this.navigateTo(path);
        return;
      }
      // 图片/视频/文档/书籍/压缩包等打开器依赖相册、播放器、编辑器、传输等未迁移模块
      ToastUtil.show(L10n.featureComingSoon);
      return;
    }
    this.selectOnly(path);
  }

  // ==================== index settings ====================

  async loadIndexConfig(showLoadingToast: boolean): Promise<void> {
    if (this.indexConfigLoading) {
      return;
    }
    this.indexConfigLoading = true;
    try {
      const res = await this.api.getIndexSettings();
      if (!res.success) {
        // 对齐 Flutter AppFileController.loadIndexConfig：加载失败必提示，否则 scope 切换被静默拦截
        console.error('[FileIndex] load failed: ' + (res.message ?? ''));
        ToastUtil.show(res.message ?? L10n.operationFailed);
        return;
      }
      const data = (res.data ?? {}) as Record<string, Object>;
      console.info('[FileIndex] config raw: ' + JSON.stringify(data));
      this.indexEnabled = data['enabled'] === true;
      const v = Number(data['intervalHours']);
      this.indexIntervalHours = Number.isFinite(v) && v > 0 ? Math.floor(v) : 72;
    } finally {
      this.indexConfigLoading = false;
    }
  }

  async saveIndexConfig(enabled: boolean, intervalHours: number): Promise<boolean> {
    if (this.indexConfigSaving) {
      return false;
    }
    this.indexConfigSaving = true;
    try {
      const res = await this.api.saveIndexSettings(enabled, intervalHours);
      if (!res.success) {
        ToastUtil.show(res.message ?? L10n.operationFailed);
        return false;
      }
      const data = (res.data ?? {}) as Record<string, Object>;
      this.indexEnabled = data['enabled'] === true;
      const v = Number(data['intervalHours']);
      this.indexIntervalHours = Number.isFinite(v) && v > 0 ? Math.floor(v) : intervalHours;
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
      return true;
    } finally {
      this.indexConfigSaving = false;
    }
  }

  async resetIndex(): Promise<boolean> {
    const res = await this.api.resetIndex();
    if (!res.success) {
      ToastUtil.show(res.message ?? L10n.operationFailed);
      return false;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    await this.loadIndexConfig(false);
    return true;
  }

  get isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  get shellSupported(): boolean {
    return APIClient.getInstance().state.shellSupported;
  }

  get clipboardHasContent(): boolean {
    return !this.clipboard.isEmpty();
  }

  /** 隐藏文件半透明（供视图使用） */
  itemOpacity(it: FileItem): number {
    return fileItemIsDotHidden(it) ? 0.52 : 1.0;
  }
}
