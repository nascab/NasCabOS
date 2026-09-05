import { AppTheme } from '../../core/theme/AppTheme';
import { L10n } from '../../core/localization/L10n';
import { CircleCheckbox } from '../../common/components/CircleCheckbox';
import { FileController } from '../controllers/FileController';
import {
  FILE_HIDDEN_LIST_OPACITY, FileFormat, FileItem, FileModelAccess, fileItemIsDotHidden
} from '../models/FileModels';
import { FileThumb } from './FileThumb';
import { showFileItemMenuSheet } from './FileSheets';

/** 打开目录回调（页面上推新目录页） */
export type OpenDirCallback = (path: string, folderName: string) => void;

/**
 * 竖向三点菜单图标（对齐 Flutter Icons.more_vert_outlined）：
 * sys.symbol.more 字形为方块组合且无竖向变体，故自绘三个圆点。
 */
@ComponentV2
export struct VerticalDotsIcon {
  @Param dotColor: string = '#8C8C8C';
  @Param dotSize: number = 3;
  @Param gap: number = 2;

  build() {
    Column({ space: this.gap }) {
      Circle().width(this.dotSize).height(this.dotSize).fill(this.dotColor)
      Circle().width(this.dotSize).height(this.dotSize).fill(this.dotColor)
      Circle().width(this.dotSize).height(this.dotSize).fill(this.dotColor)
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}

/** 列表副标题（修改时间 · 大小，目录只有时间） */
function listSubtitleLine(ctrl: FileController, it: FileItem): string {
  const mtimeText = FileFormat.formatMtime(FileModelAccess.mtimeMs(it));
  if (FileModelAccess.type(it) === 'dir') {
    return mtimeText;
  }
  const bytes = FileModelAccess.size(it);
  if (bytes < 0) {
    return mtimeText;
  }
  return `${mtimeText} · ${FileFormat.formatSize(bytes)}`;
}

/** 长按手势进入/切换多选 */
function longPressAction(ctrl: FileController, path: string, isCustomAdd: boolean): void {
  if (isCustomAdd) {
    return;
  }
  if (!ctrl.isMultiSelectMode) {
    ctrl.enterMultiSelectMode(path);
    return;
  }
  ctrl.toggleSelect(path);
}

/** 网格视图条目（对齐 Flutter AppFileGridItem） */
@ComponentV2
export struct FileGridItem {
  @Param ctrl: FileController = new FileController(false);
  @Param item: FileItem = new FileItem();
  @Param allItems: FileItem[] = [];
  /** 缩略图尺寸（页面按列宽计算，防止溢出边框） */
  @Param thumbSize: number = 80;
  /** 内容区总高度（含 padding，对齐 Flutter childAspectRatio 等高机制，custom_add 与普通条目一致） */
  @Param itemHeight: number = 158;
  @Param onOpenDir: OpenDirCallback = (_p: string, _n: string) => {
  };

  private get path(): string {
    return FileModelAccess.path(this.item);
  }

  private get isCustomAdd(): boolean {
    return FileModelAccess.virtualType(this.item) === 'custom_add';
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Column() {
          FileThumb({
            name: FileModelAccess.fileName(this.item),
            type: FileModelAccess.type(this.item),
            path: this.path,
            thumbSize: this.thumbSize,
            virtualType: FileModelAccess.virtualType(this.item),
            isCustomPath: FileModelAccess.isCustomPath(this.item)
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Text(FileModelAccess.fileName(this.item))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCustomAdd ? AppTheme.current().primary : AppTheme.current().onSurface)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')

        Row() {
          if (!this.isCustomAdd) {
            Text(FileFormat.formatMtime(FileModelAccess.mtimeMs(this.item)))
              .fontSize(12)
              .fontColor(AppTheme.current().subText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (!this.ctrl.isMultiSelectMode) {
              Column() {
                VerticalDotsIcon({ dotColor: AppTheme.current().subText })
              }
              .padding({ left: 6, right: 6, top: 4, bottom: 4 })
              .onClick(() => {
                showFileItemMenuSheet(this.ctrl, this.item, this.allItems);
              })
            }
          }
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .padding(10)
      .height(this.itemHeight)
      .borderRadius(12)
      .backgroundColor(this.isSelected() ?
        AppTheme.withAlpha(AppTheme.current().primary, 0.10) :
        AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.8))
      .border({
        width: 1,
        color: this.isSelected() ?
          AppTheme.withAlpha(AppTheme.current().primary, 0.6) :
          this.isCustomAdd ?
            AppTheme.withAlpha(AppTheme.current().primary, 0.4) :
            AppTheme.current().divider
      })
      .opacity(fileItemIsDotHidden(this.item) ? FILE_HIDDEN_LIST_OPACITY : 1.0)
      .alignItems(HorizontalAlign.Start)

      if (this.ctrl.isMultiSelectMode && !this.isCustomAdd) {
        CircleCheckbox({
          value: this.isSelected(),
          onChanged: (_c: boolean): void => {
            this.ctrl.toggleSelect(this.path);
          }
        })
          .margin(4)
      }
    }
    .width('100%')
    .onClick(() => {
      if (this.isCustomAdd) {
        this.ctrl.handleItemTap(this.item, true);
        return;
      }
      if (this.ctrl.isMultiSelectMode) {
        this.ctrl.toggleSelect(this.path);
        return;
      }
      if (FileModelAccess.type(this.item) === 'dir') {
        this.onOpenDir(this.path, FileModelAccess.fileName(this.item));
        return;
      }
      this.ctrl.handleItemTap(this.item, true);
    })
    .gesture(LongPressGesture()
      .onAction((): void => {
        longPressAction(this.ctrl, this.path, this.isCustomAdd);
      }))
  }

  private isSelected(): boolean {
    return this.ctrl.isMultiSelectMode && this.ctrl.selected.includes(this.path);
  }
}

/** 列表视图条目（对齐 Flutter AppFileListItem） */
@ComponentV2
export struct FileListItem {
  @Param ctrl: FileController = new FileController(false);
  @Param item: FileItem = new FileItem();
  @Param allItems: FileItem[] = [];
  @Param onOpenDir: OpenDirCallback = (_p: string, _n: string) => {
  };

  private get path(): string {
    return FileModelAccess.path(this.item);
  }

  private get isCustomAdd(): boolean {
    return FileModelAccess.virtualType(this.item) === 'custom_add';
  }

  build() {
    Row({ space: 10 }) {
      if (this.ctrl.isMultiSelectMode && !this.isCustomAdd) {
        Column() {
          CircleCheckbox({
            value: this.ctrl.selected.includes(this.path),
            onChanged: (_c: boolean): void => {
              this.ctrl.toggleSelect(this.path);
            }
          })
        }
        .width(34)
        .alignItems(HorizontalAlign.Center)
      }
      FileThumb({
        name: FileModelAccess.fileName(this.item),
        type: FileModelAccess.type(this.item),
        path: this.path,
        thumbSize: 42,
        virtualType: FileModelAccess.virtualType(this.item),
        isCustomPath: FileModelAccess.isCustomPath(this.item)
      })
      Column() {
        Text(FileModelAccess.fileName(this.item))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isCustomAdd ? AppTheme.current().primary : AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (!this.isCustomAdd) {
          Text(listSubtitleLine(this.ctrl, this.item))
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.ctrl.isMultiSelectMode && !this.isCustomAdd) {
        Column() {
          VerticalDotsIcon({ dotColor: AppTheme.current().subText, dotSize: 3.5 })
        }
        .padding({ left: 8, top: 6, bottom: 6 })
        .onClick(() => {
          showFileItemMenuSheet(this.ctrl, this.item, this.allItems);
        })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.ctrl.isMultiSelectMode && this.ctrl.selected.includes(this.path) ?
      AppTheme.withAlpha(AppTheme.current().primary, 0.08) : '#00000000')
    .opacity(fileItemIsDotHidden(this.item) ? FILE_HIDDEN_LIST_OPACITY : 1.0)
    .onClick(() => {
      if (this.isCustomAdd) {
        this.ctrl.handleItemTap(this.item, true);
        return;
      }
      if (this.ctrl.isMultiSelectMode) {
        this.ctrl.toggleSelect(this.path);
        return;
      }
      if (FileModelAccess.type(this.item) === 'dir') {
        this.onOpenDir(this.path, FileModelAccess.fileName(this.item));
        return;
      }
      this.ctrl.handleItemTap(this.item, true);
    })
    .gesture(LongPressGesture()
      .onAction((): void => {
        longPressAction(this.ctrl, this.path, this.isCustomAdd);
      }))
  }
}

/** 空列表占位文案（供 ListBody 使用） */
export function fileEmptyMessage(): string {
  return L10n.t('no_data', '暂无数据');
}
