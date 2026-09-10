import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { EncryptedSpaceEntry } from '../controllers/EncryptedSpaceController';
import {
  EncryptedSpaceSortEntry, encryptedSpaceSortEntries, encryptedSpaceFilterLabel,
  ENCRYPTED_SPACE_FILE_TYPE_OPTIONS
} from '../models/EncryptedSpaceModels';

// ===== 排序弹层（对齐 Flutter _openSortSheet） =====

class EncryptedSortSheetParams extends SheetParamsBase {
  sortField: string = 'original_time';
  sortOrder: string = 'desc';
  onPicked: (field: string, order: string) => void = (_f: string, _o: string): void => {
  };
}

@Builder
function EncryptedSortSheetContent(p: EncryptedSortSheetParams) {
  EncryptedSortSheetInner({ p: p })
}

@ComponentV2
struct EncryptedSortSheetInner {
  @Param p: EncryptedSortSheetParams = new EncryptedSortSheetParams();

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          ForEach(encryptedSpaceSortEntries(), (e: EncryptedSpaceSortEntry) => {
            SheetListItem({
              title: L10n.t(e.labelKey, e.labelKey),
              showIcon: false,
              showCheck: true,
              checked: this.p.sortField === e.field && this.p.sortOrder === e.order,
              onSelect: (): void => {
                const field = e.field;
                const order = e.order;
                this.p.close();
                this.p.onPicked(field, order);
              }
            })
          }, (e: EncryptedSpaceSortEntry) => `${e.field}_${e.order}`)
          Blank().height(24)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 打开排序弹层（对齐 _openSortSheet） */
export function showEncryptedSortSheet(sortField: string, sortOrder: string,
  onPicked: (field: string, order: string) => void): void {
  const p = new EncryptedSortSheetParams();
  p.sortField = sortField;
  p.sortOrder = sortOrder;
  p.onPicked = onPicked;
  SheetUtil.present(p, wrapBuilder(EncryptedSortSheetContent));
}

// ===== 类型筛选弹层（对齐 Flutter _openFileTypeFilterSheet） =====

class EncryptedFilterSheetParams extends SheetParamsBase {
  fileTypeFilter: string = 'all';
  onPicked: (value: string) => void = (_v: string): void => {
  };
}

@Builder
function EncryptedFilterSheetContent(p: EncryptedFilterSheetParams) {
  EncryptedFilterSheetInner({ p: p })
}

@ComponentV2
struct EncryptedFilterSheetInner {
  @Param p: EncryptedFilterSheetParams = new EncryptedFilterSheetParams();

  build() {
    Column() {
      SheetHandle()
      Scroll() {
        Column() {
          ForEach(ENCRYPTED_SPACE_FILE_TYPE_OPTIONS, (value: string) => {
            SheetListItem({
              title: encryptedSpaceFilterLabel(value),
              showIcon: false,
              showCheck: true,
              checked: this.p.fileTypeFilter === value,
              onSelect: (): void => {
                this.p.close();
                this.p.onPicked(value);
              }
            })
          }, (value: string) => value)
          Blank().height(24)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 打开类型筛选弹层（对齐 _openFileTypeFilterSheet） */
export function showEncryptedFilterSheet(current: string,
  onPicked: (value: string) => void): void {
  const p = new EncryptedFilterSheetParams();
  p.fileTypeFilter = current;
  p.onPicked = onPicked;
  SheetUtil.present(p, wrapBuilder(EncryptedFilterSheetContent));
}

// ===== 上传来源弹层（对齐 Flutter showMobileUploadSourcePicker） =====

class EncryptedUploadSourceSheetParams extends SheetParamsBase {
  onPicked: (source: string) => void = (_s: string): void => {
  };
}

@Builder
function EncryptedUploadSourceSheetContent(p: EncryptedUploadSourceSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.picture'),
      title: L10n.t('file_type_image', '图片'),
      onSelect: (): void => {
        p.close();
        p.onPicked('media');
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.doc'),
      title: L10n.t('file', '文件'),
      onSelect: (): void => {
        p.close();
        p.onPicked('files');
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 打开上传来源选择弹层；返回 'media'（相册）或 'files'（文件） */
export function showEncryptedUploadSourceSheet(onPicked: (source: string) => void): void {
  const p = new EncryptedUploadSourceSheetParams();
  p.onPicked = onPicked;
  SheetUtil.present(p, wrapBuilder(EncryptedUploadSourceSheetContent));
}

// ===== 单个文件操作弹层（对齐 Flutter 文件卡片 more 菜单：打开/下载/删除） =====

class EncryptedFileActionSheetParams extends SheetParamsBase {
  canOpen: boolean = false;
  onOpen: () => void = (): void => {
  };
  onDownload: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function EncryptedFileActionSheetContent(p: EncryptedFileActionSheetParams) {
  Column() {
    SheetHandle()
    if (p.canOpen) {
      SheetListItem({
        icon: $r('sys.symbol.arrow_up_left_and_arrow_down_right'),
        title: L10n.t('open', '打开'),
        onSelect: (): void => {
          p.close();
          p.onOpen();
        }
      })
    }
    SheetListItem({
      icon: $r('sys.symbol.square_and_arrow_down'),
      title: L10n.t('download', '下载'),
      onSelect: (): void => {
        p.close();
        p.onDownload();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      titleColor: '#E53935',
      iconColor: '#E53935',
      onSelect: (): void => {
        p.close();
        p.onDelete();
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 打开文件操作弹层（打开/下载/删除；非媒体类型隐藏打开项） */
export function showEncryptedFileActionSheet(canOpen: boolean, onOpen: () => void,
  onDownload: () => void, onDelete: () => void): void {
  const p = new EncryptedFileActionSheetParams();
  p.canOpen = canOpen;
  p.onOpen = onOpen;
  p.onDownload = onDownload;
  p.onDelete = onDelete;
  SheetUtil.present(p, wrapBuilder(EncryptedFileActionSheetContent));
}

// ===== 空间操作弹层（对齐 Flutter AppEncryptedSpaceGridCard more 菜单：打开/导出/重命名/删除） =====

class EncryptedSpaceActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onExport: () => void = (): void => {
  };
  onRename: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function EncryptedSpaceActionSheetContent(p: EncryptedSpaceActionSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.folder'),
      title: L10n.t('open', '打开'),
      onSelect: (): void => {
        p.close();
        p.onOpen();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.square_and_arrow_down'),
      title: L10n.t('encrypted_space_export', '导出'),
      onSelect: (): void => {
        p.close();
        p.onExport();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.square_and_pencil'),
      title: L10n.t('rename', '重命名'),
      onSelect: (): void => {
        p.close();
        p.onRename();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      titleColor: '#E53935',
      iconColor: '#E53935',
      onSelect: (): void => {
        p.close();
        p.onDelete();
      }
    })
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 打开空间操作弹层（打开/导出/重命名/删除） */
export function showEncryptedSpaceActionSheet(_space: EncryptedSpaceEntry, onOpen: () => void,
  onExport: () => void, onRename: () => void, onDelete: () => void): void {
  const p = new EncryptedSpaceActionSheetParams();
  p.onOpen = onOpen;
  p.onExport = onExport;
  p.onRename = onRename;
  p.onDelete = onDelete;
  SheetUtil.present(p, wrapBuilder(EncryptedSpaceActionSheetContent));
}
