import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { DialogUtil } from '../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { FileController } from '../controllers/FileController';
import { FileFormat, FileItem, FileModelAccess, FileStats } from '../models/FileModels';
import { FileStatsService } from '../service/FileStatsService';

/** 筛选类型选项（对齐 Flutter _appFileFilterOptions） */
const FILTER_OPTIONS: string[][] = [
  ['all', 'all'],
  ['dir', 'dir'],
  ['document', 'folder_filter_document'],
  ['video', 'folder_filter_video'],
  ['audio', 'folder_filter_audio'],
  ['image', 'folder_filter_image'],
  ['archive', 'folder_filter_archive'],
  ['file', 'file']
];

/** 排序选项（对齐 Flutter showAppFileSortSheet） */
const SORT_OPTIONS: string[][] = [
  ['name_asc', 'folder_picker_sort_name_asc'],
  ['name_desc', 'folder_picker_sort_name_desc'],
  ['size_asc', 'folder_picker_sort_size_asc'],
  ['size_desc', 'folder_picker_sort_size_desc'],
  ['type_asc', 'folder_picker_sort_type_asc'],
  ['type_desc', 'folder_picker_sort_type_desc'],
  ['mtime_asc', 'folder_picker_sort_mtime_asc'],
  ['mtime_desc', 'folder_picker_sort_mtime_desc']
];

const VIEW_OPTIONS: string[][] = [
  ['grid', 'folder_view_grid'],
  ['large_grid', 'folder_view_large_grid'],
  ['list', 'folder_view_list']
];

// ==================== 新建弹层 ====================

class FileCreateSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileCreateSheetContent(p: FileCreateSheetParams) {
  FileCreateSheetInner({ p: p })
}

@ComponentV2
struct FileCreateSheetInner {
  @Param p: FileCreateSheetParams = new FileCreateSheetParams();

  private async ensureUpload(): Promise<void> {
    const supported = await this.p.ctrl.ensureUploadSupported();
    if (!supported) {
      return;
    }
    // 上传中心依赖传输模块（未迁移）
    ToastUtil.show(L10n.featureComingSoon);
  }

  private async createFolder(): Promise<void> {
    const ctrl = this.p.ctrl;
    const supported = await ctrl.ensureCreateFolderSupported();
    if (!supported) {
      return;
    }
    const name = await DialogUtil.showInputDialog(
      L10n.t('folder_new_dir', '新建文件夹'),
      L10n.t('app_files_enter_folder_name', '请输入文件夹名称'),
      '', '', '',
      (value: string): string | undefined => {
        return value.trim().length === 0 ? L10n.t('name_cannot_be_empty', '名称不能为空') : undefined;
      });
    if (typeof name === 'string' && name.length > 0) {
      await ctrl.createFolder(name);
    }
  }

  private async createTextFile(type: string): Promise<void> {
    const ctrl = this.p.ctrl;
    const supported = await ctrl.ensureCreateFileSupported();
    if (!supported) {
      return;
    }
    const titleKey = type === 'txt' ? 'folder_new_txt' : 'folder_new_md';
    const title = L10n.t(titleKey, type === 'txt' ? '新建TXT' : '新建MD');
    const name = await DialogUtil.showInputDialog(
      title, L10n.t('enter_new_name', '输入新名称'), '', '', '',
      (value: string): string | undefined => {
        return value.trim().length === 0 ? L10n.t('name_cannot_be_empty', '名称不能为空') : undefined;
      });
    if (typeof name !== 'string' || name.trim().length === 0) {
      return;
    }
    const raw = name.trim();
    const fileName = raw.toLowerCase().endsWith(`.${type}`) ? raw : `${raw}.${type}`;
    await ctrl.createTextFile(fileName, type);
  }

  build() {
    Column() {
      SheetHandle()
      SheetListItem({
        icon: $r('sys.symbol.upload'),
        title: L10n.t('folder_upload_file', '上传文件'),
        onSelect: (): void => {
          this.p.close();
          void this.ensureUpload();
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.plus_circle'),
        title: L10n.t('folder_new_dir', '新建文件夹'),
        onSelect: (): void => {
          this.p.close();
          void this.createFolder();
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.doc'),
        title: L10n.t('folder_new_txt', '新建TXT'),
        onSelect: (): void => {
          this.p.close();
          void this.createTextFile('txt');
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.doc'),
        title: L10n.t('folder_new_md', '新建MD'),
        onSelect: (): void => {
          this.p.close();
          void this.createTextFile('md');
        }
      })
    }
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示“新建”底部弹层（对齐 Flutter showAppFileCreateSheet） */
export function showFileCreateSheet(ctrl: FileController): void {
  const p = new FileCreateSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileCreateSheetContent));
}

// ==================== 排序弹层 ====================

class FileSortSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileSortSheetContent(p: FileSortSheetParams) {
  FileSortSheetInner({ p: p })
}

@ComponentV2
struct FileSortSheetInner {
  @Param p: FileSortSheetParams = new FileSortSheetParams();

  build() {
    Column() {
      SheetHandle()
      ForEach(SORT_OPTIONS, (op: string[]): void => {
        SheetListItem({
          showIcon: false,
          title: L10n.t(op[1], op[1]),
          showCheck: true,
          checked: this.p.ctrl.sortMode === op[0],
          onSelect: (): void => {
            this.p.ctrl.setSortMode(op[0]);
            this.p.close();
          }
        })
      }, (op: string[]): string => op[0])
    }
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示排序底部弹层（对齐 Flutter showAppFileSortSheet） */
export function showFileSortSheet(ctrl: FileController): void {
  const p = new FileSortSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileSortSheetContent));
}

// ==================== 筛选弹层 ====================

class FileFilterSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileFilterSheetContent(p: FileFilterSheetParams) {
  FileFilterSheetInner({ p: p })
}

@ComponentV2
struct FileFilterSheetInner {
  @Param p: FileFilterSheetParams = new FileFilterSheetParams();

  build() {
    Column() {
      SheetHandle()
      ForEach(FILTER_OPTIONS, (op: string[]): void => {
        SheetListItem({
          showIcon: false,
          title: L10n.t(op[1], op[1]),
          showCheck: true,
          checked: this.p.ctrl.filterType === op[0],
          onSelect: (): void => {
            this.p.ctrl.setFilterType(op[0]);
            this.p.close();
          }
        })
      }, (op: string[]): string => op[0])
    }
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示类型筛选底部弹层（对齐 Flutter showAppFileFilterSheet） */
export function showFileFilterSheet(ctrl: FileController): void {
  const p = new FileFilterSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileFilterSheetContent));
}

// ==================== 视图切换弹层 ====================

class FileViewSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileViewSheetContent(p: FileViewSheetParams) {
  FileViewSheetInner({ p: p })
}

@ComponentV2
struct FileViewSheetInner {
  @Param p: FileViewSheetParams = new FileViewSheetParams();

  build() {
    Column() {
      SheetHandle()
      ForEach(VIEW_OPTIONS, (op: string[]): void => {
        SheetListItem({
          showIcon: false,
          title: L10n.t(op[1], op[1]),
          showCheck: true,
          checked: this.p.ctrl.viewMode === op[0],
          onSelect: (): void => {
            this.p.ctrl.setViewMode(op[0]);
            this.p.close();
          }
        })
      }, (op: string[]): string => op[0])
    }
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示视图切换底部弹层（对齐 Flutter showAppFileViewSheet） */
export function showFileViewSheet(ctrl: FileController): void {
  const p = new FileViewSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileViewSheetContent));
}

// ==================== 搜索选项弹层（作用域 + 类型 + 索引入口） ====================

class FileSearchOptionsSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

// ==================== 索引设置弹层 ====================

class FileIndexSettingsSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileIndexSettingsSheetContent(p: FileIndexSettingsSheetParams) {
  FileIndexSettingsSheetInner({ p: p })
}

@ComponentV2
struct FileIndexSettingsSheetInner {
  @Param p: FileIndexSettingsSheetParams = new FileIndexSettingsSheetParams();
  @Local indexOn: boolean = false;
  @Local intervalText: string = '72';
  @Local loading: boolean = false;

  aboutToAppear(): void {
    this.indexOn = this.p.ctrl.indexEnabled;
    this.intervalText = `${this.p.ctrl.indexIntervalHours}`;
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      await this.p.ctrl.loadIndexConfig(false);
      this.indexOn = this.p.ctrl.indexEnabled;
      this.intervalText = `${this.p.ctrl.indexIntervalHours}`;
    } finally {
      this.loading = false;
    }
  }

  private safeIntervalHours(): number {
    const v = Number.parseInt(this.intervalText.trim());
    if (Number.isNaN(v)) {
      return 72;
    }
    if (v < 1) {
      return 1;
    }
    if (v > 24 * 365) {
      return 24 * 365;
    }
    return v;
  }

  private async save(): Promise<void> {
    const ok = await this.p.ctrl.saveIndexConfig(this.indexOn, this.safeIntervalHours());
    if (ok) {
      this.indexOn = this.p.ctrl.indexEnabled;
      this.intervalText = `${this.p.ctrl.indexIntervalHours}`;
    }
  }

  private async reset(): Promise<void> {
    const confirmed = await DialogUtil.showConfirmDialog(
      L10n.t('need_confirm', '需要确认'),
      L10n.t('file_index_reset_confirm', '确定要重置索引吗？'));
    if (confirmed === true) {
      await this.p.ctrl.resetIndex();
    }
  }

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          Text(L10n.t('file_index_settings', '索引设置'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
          Row({ space: 12 }) {
            Column() {
              Text(L10n.t('file_index_enable_title', '启用索引'))
                .fontSize(15)
                .fontColor(AppTheme.current().onSurface)
              Text(L10n.t('file_index_enable_subtitle', '启用后可使用全局搜索与子树搜索'))
                .fontSize(12)
                .fontColor(AppTheme.current().subText)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.indexOn })
              .selectedColor(AppTheme.current().primary)
              .enabled(!this.loading && !this.p.ctrl.indexConfigSaving)
              .onChange((on: boolean): void => {
                this.indexOn = on;
                void this.save();
              })
          }
          .width('100%')
          .margin({ top: 12 })
          Row({ space: 10 }) {
            TextInput({ text: this.intervalText, placeholder: L10n.t('file_index_interval_hint', '如 72') })
              .type(InputType.Number)
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .placeholderColor(AppTheme.current().hint)
              .backgroundColor(AppTheme.current().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: AppTheme.current().inputBorder })
              .height(42)
              .layoutWeight(1)
              .enabled(!this.loading && !this.p.ctrl.indexConfigSaving)
              .onChange((v: string): void => {
                this.intervalText = v;
              })
            Button(L10n.save)
              .fontSize(13)
              .fontColor(AppTheme.current().buttonText)
              .backgroundColor(AppTheme.current().buttonBg)
              .height(40)
              .enabled(!this.loading && !this.p.ctrl.indexConfigSaving)
              .onClick((): void => {
                void this.save();
              })
          }
          .width('100%')
          .margin({ top: 12 })
          Row() {
            Button(L10n.t('file_index_reset', '重建索引'))
              .fontSize(13)
              .fontColor(AppTheme.current().primary)
              .backgroundColor('#00000000')
              .border({ width: 1, color: AppTheme.current().divider })
              .height(36)
              .enabled(!this.loading && !this.p.ctrl.indexConfigSaving)
              .onClick((): void => {
                void this.reset();
              })
            Blank()
            if (this.loading) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(AppTheme.current().primary)
            }
          }
          .width('100%')
          .margin({ top: 14 })
        }
        .padding({ left: 20, right: 20, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 420 })
      .width('100%')
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示索引设置底部弹层（对齐 Flutter showAppFileIndexSettingsSheet） */
export function showFileIndexSettingsSheet(ctrl: FileController): void {
  const p = new FileIndexSettingsSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileIndexSettingsSheetContent));
}

// ==================== 搜索选项弹层（作用域 + 类型 + 索引入口） ====================

@ComponentV2
struct FileSearchOptionsRealSheet {
  @Param p: FileSearchOptionsSheetParams = new FileSearchOptionsSheetParams();

  private ctrl(): FileController {
    return this.p.ctrl;
  }

  private isAdmin(): boolean {
    return CurrentUserStore.getInstance().isAdmin;
  }

  /** 切换搜索作用域（对齐 Flutter handleScopeTap） */
  private async handleScopeTap(scope: string): Promise<void> {
    const ctrl = this.ctrl();
    try {
      if (ctrl.searchScope === scope) {
        this.p.close();
        return;
      }
      if (scope === 'current') {
        ctrl.setSearchScope('current');
        this.p.close();
        return;
      }
      await ctrl.loadIndexConfig(false);
      console.info('[FileSearchOptions] scope=' + scope + ' indexEnabled=' + ctrl.indexEnabled);
      if (ctrl.indexEnabled) {
        ctrl.setSearchScope(scope);
        this.p.close();
        return;
      }
      // 索引未启用：先关弹层，确保提示可见（对齐 Flutter 拦截语义）
      this.p.close();
      if (this.isAdmin()) {
        const go = await DialogUtil.showConfirmDialog(
          L10n.t('file_global_search_disabled_title', '全局搜索未启用'),
          L10n.t('file_global_search_disabled_content', '需要先启用文件索引后才能使用全局搜索，是否前往设置？'),
          undefined,
          L10n.t('file_global_search_disabled_go_view', '前往设置'));
        if (go === true) {
          showFileIndexSettingsSheet(ctrl);
        }
        return;
      }
      ToastUtil.show(L10n.t('file_global_search_disabled_title', '全局搜索未启用'));
    } catch (e) {
      console.error('[FileSearchOptions] handleScopeTap error: ' + JSON.stringify(e));
      ToastUtil.show(L10n.operationFailed);
    }
  }

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          SheetListItem({
            icon: $r('sys.symbol.checkmark_circle'),
            iconColor: this.ctrl().searchScope === 'current' ? AppTheme.current().primary : AppTheme.current().subText,
            title: L10n.t('file_search_scope_current_dir', '当前目录'),
            onSelect: (): void => {
              void this.handleScopeTap('current');
            }
          })
          SheetListItem({
            icon: $r('sys.symbol.checkmark_circle'),
            iconColor: this.ctrl().searchScope === 'subtree' ? AppTheme.current().primary : AppTheme.current().subText,
            title: L10n.t('file_search_scope_current_dir_subtree', '当前目录及子目录'),
            onSelect: (): void => {
              void this.handleScopeTap('subtree');
            }
          })
          SheetListItem({
            icon: $r('sys.symbol.checkmark_circle'),
            iconColor: this.ctrl().searchScope === 'global' ? AppTheme.current().primary : AppTheme.current().subText,
            title: L10n.t('file_search_scope_global', '全局搜索'),
            onSelect: (): void => {
              void this.handleScopeTap('global');
            }
          })
          Divider()
            .color(AppTheme.current().divider)
            .margin({ top: 4, bottom: 4 })
          ForEach(FILTER_OPTIONS, (op: string[]): void => {
            SheetListItem({
              icon: $r('sys.symbol.circle'),
              iconColor: this.ctrl().filterType === op[0] ? AppTheme.current().primary : AppTheme.current().subText,
              title: L10n.t(op[1], op[1]),
              onSelect: (): void => {
                this.ctrl().setFilterType(op[0]);
                this.p.close();
              }
            })
          }, (op: string[]): string => op[0])
          if (this.isAdmin()) {
            Divider()
              .color(AppTheme.current().divider)
              .margin({ top: 4, bottom: 4 })
            SheetListItem({
              icon: $r('sys.symbol.gearshape'),
              title: L10n.t('file_index_settings', '索引设置'),
              onSelect: (): void => {
                this.p.close();
                showFileIndexSettingsSheet(this.ctrl());
              }
            })
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 560 })
      .width('100%')
    }
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示搜索选项底部弹层（对齐 Flutter showAppFileSearchOptionsSheet） */
export function showFileSearchOptionsSheet(ctrl: FileController): void {
  const p = new FileSearchOptionsSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileSearchOptionsRealSheetBuilder));
}

@Builder
function FileSearchOptionsRealSheetBuilder(p: FileSearchOptionsSheetParams) {
  FileSearchOptionsRealSheet({ p: p })
}

// ==================== 条目菜单弹层 ====================

class FileItemMenuSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
  item: FileItem = new FileItem();
  allItems: FileItem[] = [];
}

@Builder
function FileItemMenuSheetContent(p: FileItemMenuSheetParams) {
  FileItemMenuSheetInner({ p: p })
}

@ComponentV2
struct FileItemMenuSheetInner {
  @Param p: FileItemMenuSheetParams = new FileItemMenuSheetParams();

  private get path(): string {
    return FileModelAccess.path(this.p.item);
  }

  private get name(): string {
    return FileModelAccess.fileName(this.p.item);
  }

  private get isCustomPath(): boolean {
    return FileModelAccess.isCustomPath(this.p.item);
  }

  private get inFavorites(): boolean {
    return this.p.ctrl.currentModule === 'favorites';
  }

  private get isTxt(): boolean {
    const type = FileModelAccess.type(this.p.item);
    const dot = this.name.lastIndexOf('.');
    const ext = dot >= 0 && dot < this.name.length - 1 ? this.name.substring(dot + 1).toLowerCase() : '';
    return type.trim().toLowerCase() === 'txt' || ext === 'txt';
  }

  build() {
    Scroll() {
      Column() {
        // 标题区
        Column() {
          Text(this.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.path)
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 10 })
        .alignItems(HorizontalAlign.Start)
        Divider()
          .color(AppTheme.current().divider)
        if (this.isCustomPath) {
          // 自定义根路径菜单：仅移除
          SheetListItem({
            icon: $r('sys.symbol.minus_circle'),
            iconColor: AppTheme.current().error,
            title: L10n.t('file_custom_path_remove', '移除常用路径'),
            titleColor: AppTheme.current().error,
            onSelect: (): void => {
              this.p.close();
              void this.removeCustomPath();
            }
          })
        } else {
          SheetListItem({
            icon: $r('sys.symbol.square_and_pencil'),
            title: L10n.t('rename', '重命名'),
            onSelect: (): void => {
              this.p.close();
              void this.rename();
            }
          })
          if (this.isTxt && FileModelAccess.type(this.p.item) !== 'dir') {
            SheetListItem({
              icon: $r('sys.symbol.square_and_pencil'),
              title: L10n.t('edit', '编辑'),
              onSelect: (): void => {
                this.p.close();
                // 文本编辑器模块未迁移
                ToastUtil.show(L10n.featureComingSoon);
                this.p.ctrl.clearSelect();
              }
            })
          }
          SheetListItem({
            icon: $r('sys.symbol.square_and_arrow_down'),
            title: L10n.t('download', '下载'),
            onSelect: (): void => {
              this.p.close();
              // 下载依赖传输模块（未迁移）
              ToastUtil.show(L10n.featureComingSoon);
              this.p.ctrl.clearSelect();
            }
          })
          SheetListItem({
            icon: $r('sys.symbol.bolt'),
            title: L10n.t('quick_share_title', '快速分享'),
            onSelect: (): void => {
              this.p.close();
              // 快速分享模块未迁移
              ToastUtil.show(L10n.featureComingSoon);
              this.p.ctrl.clearSelect();
            }
          })
          if (!this.inFavorites) {
            SheetListItem({
              icon: $r('sys.symbol.doc_text_on_doc_text'),
              title: L10n.t('folder_action_copy_to', '复制到…'),
              onSelect: (): void => {
                this.p.close();
                void this.copyOrMove(true);
              }
            })
            SheetListItem({
              icon: $r('sys.symbol.folder'),
              title: L10n.t('folder_action_move_to', '移动到…'),
              onSelect: (): void => {
                this.p.close();
                void this.copyOrMove(false);
              }
            })
            SheetListItem({
              icon: $r('sys.symbol.star'),
              title: L10n.t('folder_add_favorite', '添加到收藏'),
              onSelect: (): void => {
                this.p.close();
                void this.addFavorite();
              }
            })
          } else {
            SheetListItem({
              icon: $r('sys.symbol.star'),
              title: L10n.t('unfavorite', '取消收藏'),
              onSelect: (): void => {
                this.p.close();
                void this.removeFavorite();
              }
            })
          }
          SheetListItem({
            icon: $r('sys.symbol.trash'),
            iconColor: AppTheme.current().error,
            title: L10n.t('delete', '删除'),
            titleColor: AppTheme.current().error,
            onSelect: (): void => {
              this.p.close();
              void this.deleteConfirm();
            }
          })
          SheetListItem({
            icon: $r('sys.symbol.info_circle'),
            title: L10n.t('property', '属性'),
            onSelect: (): void => {
              this.p.close();
              showFilePropertiesSheet(this.p.ctrl, this.p.item);
            }
          })
        }
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: 560 })
    .width('100%')
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  private async removeCustomPath(): Promise<void> {
    const p = this.path.trim();
    this.p.ctrl.clearSelect();
    if (p.length === 0) {
      return;
    }
    await this.p.ctrl.removeCustomPath(p);
  }

  private async rename(): Promise<void> {
    const newName = await DialogUtil.showInputDialog(
      L10n.t('rename', '重命名'),
      L10n.t('enter_new_name', '输入新名称'),
      this.name, '', '',
      (value: string): string | undefined => {
        return value.trim().length === 0 ? L10n.t('name_cannot_be_empty', '名称不能为空') : undefined;
      });
    if (typeof newName === 'string' && newName.length > 0 && newName !== this.name) {
      await this.p.ctrl.renameEntry(this.path, newName);
    }
    this.p.ctrl.clearSelect();
  }

  private async copyOrMove(isCopy: boolean): Promise<void> {
    await this.p.ctrl.handleCopyOrMove(isCopy);
    this.p.ctrl.clearSelect();
  }

  private async addFavorite(): Promise<void> {
    const ok = await this.p.ctrl.addFavorites(this.p.ctrl.getSelected());
    ToastUtil.show(ok ? L10n.t('operation_success', '操作成功') : L10n.operationFailed);
    this.p.ctrl.clearSelect();
  }

  private async removeFavorite(): Promise<void> {
    const ok = await this.p.ctrl.removeFavorites(this.p.ctrl.getSelected());
    ToastUtil.show(ok ? L10n.t('operation_success', '操作成功') : L10n.operationFailed);
    this.p.ctrl.clearSelect();
  }

  private async deleteConfirm(): Promise<void> {
    const ctrl = this.p.ctrl;
    const count = `${ctrl.selected.length}`;
    const content = L10n.t('folder_delete_confirm', '确定删除这 @fileCount 项吗？',
      L10n.paramsOf('fileCount', count));
    if (ctrl.shellSupported) {
      await DialogUtil.showConfirmThreeButtonsDialog(
        L10n.t('need_confirm', '需要确认'),
        content,
        (): void => {
          void ctrl.deleteSelectedEntries(false);
        },
        (): void => {
          void ctrl.deleteSelectedEntries(true);
        },
        L10n.cancel,
        L10n.t('delete', '删除'),
        L10n.t('put_in_recycle_bin', '放入回收站'));
    } else {
      const confirmed = await DialogUtil.showConfirmDialog(
        L10n.t('need_confirm', '需要确认'), content);
      if (confirmed === true) {
        await ctrl.deleteSelectedEntries(false);
      }
    }
    ctrl.clearSelect();
  }
}

/** 显示条目菜单底部弹层（对齐 Flutter showAppFileItemMenuBottomSheet） */
export function showFileItemMenuSheet(ctrl: FileController, item: FileItem, allItems: FileItem[]): void {
  const path = FileModelAccess.path(item);
  if (path.length > 0) {
    ctrl.selectOnly(path);
  }
  const p = new FileItemMenuSheetParams();
  p.ctrl = ctrl;
  p.item = item;
  p.allItems = allItems;
  p.onDismissed = (): void => {
    // 未触发任何操作关闭时清空选择（对齐 Flutter actionTaken 逻辑）
  };
  SheetUtil.present(p, wrapBuilder(FileItemMenuSheetContent));
}

// ==================== 属性弹层 ====================

class FilePropertiesSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
  item: FileItem = new FileItem();
}

@Builder
function FilePropertiesSheetContent(p: FilePropertiesSheetParams) {
  FilePropertiesSheetInner({ p: p })
}

@ComponentV2
struct FilePropertiesSheetInner {
  @Param p: FilePropertiesSheetParams = new FilePropertiesSheetParams();
  @Local statsSize: number = 0;
  @Local statsFileCount: number = 0;
  @Local statsFolderCount: number = 0;
  @Local statsCtime: string = '';
  @Local statsMtime: string = '';
  @Local isCalculating: boolean = false;
  private statsService: FileStatsService = new FileStatsService();

  aboutToAppear(): void {
    const isDir = FileModelAccess.type(this.p.item) === 'dir';
    const path = FileModelAccess.path(this.p.item);
    if (isDir && path.length > 0) {
      this.isCalculating = true;
      this.statsService.connect([path],
        (stats: FileStats): void => {
          this.statsSize = stats.size;
          this.statsFileCount = stats.count;
          this.statsFolderCount = stats.folderCount;
          const c = FileStats.parseToLocalMs(stats.ctime);
          if (c !== undefined) {
            this.statsCtime = FileFormat.formatFullTime(c);
          }
          const m = FileStats.parseToLocalMs(stats.mtime);
          if (m !== undefined) {
            this.statsMtime = FileFormat.formatFullTime(m);
          }
        },
        (stats: FileStats): void => {
          this.statsSize = stats.size;
          this.statsFileCount = stats.count;
          this.statsFolderCount = stats.folderCount;
          this.isCalculating = false;
        },
        (_message: string): void => {
          this.isCalculating = false;
        });
    }
  }

  aboutToDisappear(): void {
    this.statsService.close();
  }

  private get isDir(): boolean {
    return FileModelAccess.type(this.p.item) === 'dir';
  }

  private typeLabel(): string {
    const type = FileModelAccess.type(this.p.item);
    if (type === 'dir') {
      return L10n.t('dir', '文件夹');
    }
    if (type === 'image') {
      return L10n.t('file_type_image', '图片');
    }
    if (type === 'video') {
      return L10n.t('file_type_video', '视频');
    }
    if (type === 'archive') {
      return L10n.t('file_type_archive', '压缩包');
    }
    return L10n.t('file', '文件');
  }

  private sizeText(): string {
    if (this.isDir) {
      return FileFormat.formatSize(this.statsSize);
    }
    const size = FileModelAccess.size(this.p.item);
    return size >= 0 ? FileFormat.formatSize(size) : '';
  }

  private mtimeText(): string {
    if (this.isDir) {
      return this.statsMtime;
    }
    return FileFormat.formatMtime(FileModelAccess.mtimeMs(this.p.item));
  }

  build() {
    Scroll() {
      Column() {
        Text(L10n.t('property', '属性'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .width('100%')
        this.KvRow(L10n.t('name', '名称'), FileModelAccess.fileName(this.p.item))
        this.KvRow(L10n.t('path', '路径'), FileModelAccess.path(this.p.item))
        this.KvRow(L10n.t('type', '类型'), this.typeLabel())
        this.KvRow(L10n.t('size', '大小'), this.sizeText())
        if (this.isDir) {
          this.KvRow(L10n.t('contains', '包含'),
            `${L10n.t('file_count_format', '@count 个文件', L10n.paramsOf('count', `${this.statsFileCount}`))}, ` +
            `${L10n.t('folder_count_format', '@count 个文件夹', L10n.paramsOf('count', `${this.statsFolderCount}`))}`)
        }
        if (this.statsCtime.length > 0) {
          this.KvRow(L10n.t('create_time', '创建时间'), this.statsCtime)
        }
        this.KvRow(L10n.t('modified_at', '修改时间'), this.mtimeText())
        if (this.isDir && this.isCalculating) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(AppTheme.current().primary)
            .margin({ top: 12 })
        }
        Button(L10n.t('home_window_close', '关闭'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(40)
          .width('100%')
          .margin({ top: 16 })
          .onClick((): void => {
            this.p.close();
          })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 28 })
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: 520 })
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  @Builder
  KvRow(k: string, v: string) {
    Row() {
      Text(k)
        .fontSize(14)
        .fontColor(AppTheme.current().subText)
        .width(76)
      Text(v)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .margin({ top: 8 })
    .width('100%')
  }
}

/** 显示属性底部弹层（对齐 Flutter showAppFilePropertiesSheet） */
export function showFilePropertiesSheet(ctrl: FileController, item: FileItem): void {
  const p = new FilePropertiesSheetParams();
  p.ctrl = ctrl;
  p.item = item;
  SheetUtil.present(p, wrapBuilder(FilePropertiesSheetContent));
}

// ==================== 多选“更多”弹层 ====================

class FileMoreSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileMoreSheetContent(p: FileMoreSheetParams) {
  FileMoreSheetInner({ p: p })
}

@ComponentV2
struct FileMoreSheetInner {
  @Param p: FileMoreSheetParams = new FileMoreSheetParams();

  build() {
    Column() {
      SheetListItem({
        icon: $r('sys.symbol.folder'),
        title: L10n.t('folder_action_move_to', '移动到…'),
        onSelect: (): void => {
          this.p.close();
          void this.p.ctrl.handleCopyOrMove(false);
        }
      })
      SheetListItem({
        icon: $r('sys.symbol.doc_text_on_doc_text'),
        title: L10n.t('folder_action_copy_to', '复制到…'),
        onSelect: (): void => {
          this.p.close();
          void this.p.ctrl.handleCopyOrMove(true);
        }
      })
    }
    .padding({ bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示多选更多操作底部弹层（对齐 Flutter AppFileMultiSelectBar._showMoreSheet） */
export function showFileMoreSheet(ctrl: FileController): void {
  const p = new FileMoreSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileMoreSheetContent));
}

// ==================== 添加自定义路径弹层 ====================

class FileAddCustomPathSheetParams extends SheetParamsBase {
  ctrl: FileController = new FileController(false);
}

@Builder
function FileAddCustomPathSheetContent(p: FileAddCustomPathSheetParams) {
  FileAddCustomPathSheetInner({ p: p })
}

@ComponentV2
struct FileAddCustomPathSheetInner {
  @Param p: FileAddCustomPathSheetParams = new FileAddCustomPathSheetParams();
  @Local name: string = '';
  @Local path: string = '';
  @Local submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const n = this.name.trim();
    const pt = this.path.trim();
    if (n.length === 0 || pt.length === 0) {
      ToastUtil.show(L10n.t('name_cannot_be_empty', '名称不能为空'));
      return;
    }
    this.submitting = true;
    try {
      const res = await this.p.ctrl.addCustomPath(n, pt);
      if (res.success) {
        ToastUtil.show(L10n.t('operation_success', '操作成功'));
        this.p.close();
        await this.p.ctrl.listDirectory('', 'normal');
      } else {
        ToastUtil.show(res.message ?? L10n.operationFailed);
      }
    } catch (e) {
      console.error('[FileAddCustomPath] submit error: ' + JSON.stringify(e));
      ToastUtil.show(L10n.operationFailed);
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('file_custom_path_entry', '添加常用路径'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
        .padding({ left: 20, right: 20 })
      TextInput({ text: this.name, placeholder: L10n.t('file_custom_path_name_hint', '路径名称') })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 14 })
        .width('100%')
        .enterKeyType(EnterKeyType.Next)
        .onChange((v: string): void => {
          this.name = v;
        })
      TextInput({ text: this.path, placeholder: L10n.t('file_custom_path_path_hint', '服务器绝对路径，如 /volume1/media') })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 10 })
        .width('100%')
        .enterKeyType(EnterKeyType.Done)
        .onChange((v: string): void => {
          this.path = v;
        })
        .onSubmit((): void => {
          // 键盘“完成/确认”键与按钮等价
          void this.submit();
        })
      Button(L10n.confirm)
        .fontSize(14)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .height(40)
        .width('100%')
        .margin({ top: 16 })
        .enabled(!this.submitting)
        .onClick((): void => {
          void this.submit();
        })
    }
    .padding({ left: 20, right: 20, bottom: 28 })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 显示添加自定义路径底部弹层 */
export function showFileAddCustomPathSheet(ctrl: FileController): void {
  const p = new FileAddCustomPathSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(FileAddCustomPathSheetContent));
}
