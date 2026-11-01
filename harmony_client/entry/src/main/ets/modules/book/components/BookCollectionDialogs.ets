import { DialogParamsBase, DialogUtil } from '../../../common/DialogUtil';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { pickTargetFolderViaSheet } from '../../files/views/FolderPickerSheet';
import { BookCollectionController } from '../controllers/BookControllers';
import { BookCollectionItem } from '../models/BookModels';

/** 合集创建/编辑弹窗参数（对齐 Flutter BookCollectionDialogs showDialog + StatefulBuilder） */
class BookCollectionEditParams extends DialogParamsBase {
  title: string = '';
  showHelp: boolean = false;
  name: string = '';
  pathList: string[] = [];
  confirmText: string = '';
  controller: BookCollectionController = new BookCollectionController();
  /** 编辑模式传原合集；创建传 undefined */
  editing: BookCollectionItem | undefined = undefined;
}

function canSubmitCollection(name: string, paths: string[]): boolean {
  return name.trim().length > 0 && paths.length > 0;
}

@Builder
function BookCollectionEditDialogBuilder(p: BookCollectionEditParams) {
  BookCollectionEditDialogInner({ p: p })
}

@ComponentV2
struct BookCollectionEditDialogInner {
  @Param p: BookCollectionEditParams = new BookCollectionEditParams();
  @Local name: string = '';
  @Local paths: string[] = [];
  @Local canSubmit: boolean = false;

  aboutToAppear(): void {
    this.name = this.p.name;
    this.paths = this.p.pathList.slice();
    this.recomputeCanSubmit();
  }

  private recomputeCanSubmit(): void {
    this.canSubmit = canSubmitCollection(this.name, this.paths);
  }

  private submit(): void {
    if (!this.canSubmit) {
      return;
    }
    const trimmedName = this.name.trim();
    const paths = this.paths.slice();
    const ctrl = this.p.controller;
    const editing = this.p.editing;
    const run = async (): Promise<void> => {
      const ok = editing !== undefined
        ? await ctrl.updateCollection(editing.id, trimmedName, paths)
        : await ctrl.createCollection(trimmedName, paths);
      if (ok) {
        this.p.onResult(true);
      }
    };
    void run();
  }

  @Builder
  PathRow(path: string, index: number) {
    Row({ space: 8 }) {
      Text(path)
        .fontSize(13)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(16)
        .fontColor([AppTheme.current().hint])
        .onClick(() => {
          if (index < 0 || index >= this.paths.length) {
            return;
          }
          this.paths.splice(index, 1);
          this.paths = this.paths.slice();
          this.recomputeCanSubmit();
        })
    }
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.15) })
    .margin({ top: index > 0 ? 6 : 0 })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.p.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        if (this.p.showHelp) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(18)
            .fontColor([AppTheme.current().hint])
            .onClick(() => {
              DialogUtil.showInfoDialog(this.p.title,
                L10n.t('book_create_collection_alert',
                  '合集用于把多个文件夹聚合为一个入口，选择多个文件夹路径后即可在合集内浏览其中的图书。'));
            })
        }
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')

      TextInput({ text: this.name })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderFont({ size: 14 })
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 16 })
        .width('100%')
        .onChange((v: string): void => {
          this.name = v;
          this.recomputeCanSubmit();
        })

      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(16)
            .fontColor([AppTheme.current().buttonText])
          Text(L10n.t('choose_path', '选择路径'))
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
        }
      }
      .backgroundColor(AppTheme.current().buttonBg)
      .height(40)
      .width('100%')
      .margin({ top: 12 })
      .onClick(() => {
        pickTargetFolderViaSheet('', (picked: string[]): void => {
          if (picked.length === 0) {
            return;
          }
          let changed = false;
          for (const path of picked) {
            const v = path.trim();
            if (v.length > 0 && !this.paths.includes(v)) {
              this.paths.push(v);
              changed = true;
            }
          }
          if (changed) {
            this.paths = this.paths.slice();
            this.recomputeCanSubmit();
          }
        }, true, 'book');
      })

      if (this.paths.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.paths, (path: string, index: number) => {
              this.PathRow(path, index)
            }, (path: string, index: number): string => `${index}_${path}`)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 220 })
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
        .margin({ top: 12 })
        .width('100%')
      }

      Row({ space: 10 }) {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText.length > 0 ? this.p.confirmText : L10n.ok)
          .fontSize(14)
          .fontColor(this.canSubmit ? AppTheme.current().buttonText : AppTheme.current().hint)
          .backgroundColor(this.canSubmit ? AppTheme.current().buttonBg
            : AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            if (this.canSubmit) {
              this.submit();
            }
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
    .width('92%')
  }
}

/** 创建合集弹窗（对齐 Flutter BookCollectionDialogs.showCreateDialog） */
export function showBookCollectionCreateDialog(controller: BookCollectionController): void {
  const p = new BookCollectionEditParams();
  p.title = L10n.t('book_create_collection', '创建合集');
  p.showHelp = true;
  p.name = '';
  p.pathList = [];
  p.confirmText = L10n.t('create', '创建');
  p.controller = controller;
  p.editing = undefined;
  DialogUtil.openCustom(p, wrapBuilder(BookCollectionEditDialogBuilder), true);
}

/** 编辑合集弹窗（对齐 Flutter BookCollectionDialogs.showEditDialog） */
export function showBookCollectionEditDialog(controller: BookCollectionController,
  collection: BookCollectionItem): void {
  const p = new BookCollectionEditParams();
  p.title = L10n.t('edit', '编辑');
  p.showHelp = false;
  p.name = collection.name;
  p.pathList = collection.pathList.slice();
  p.confirmText = L10n.t('ok', '确定');
  p.controller = controller;
  p.editing = collection;
  DialogUtil.openCustom(p, wrapBuilder(BookCollectionEditDialogBuilder), true);
}

/** 删除合集确认（对齐 Flutter BookCollectionDialogs.confirmDelete） */
export async function confirmDeleteBookCollection(controller: BookCollectionController,
  collection: BookCollectionItem): Promise<void> {
  const ok = await DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
    `${L10n.t('confirm_delete', '确认删除')}[${collection.name}]`,
    undefined, L10n.t('confirm', '确认'), L10n.t('cancel', '取消'));
  if (ok !== true) {
    return;
  }
  const deleted = await controller.deleteCollection(collection.id);
  if (!deleted) {
    ToastUtil.show(L10n.operationFailed);
  }
}

/** 路径帮助弹窗（对齐 Flutter _showHelp） */
export function showBookCollectionPathHelp(pathList: string[]): void {
  const content = pathList.join('\n');
  DialogUtil.showInfoDialog(L10n.t('path', '路径'),
    content.length === 0 ? L10n.t('no_path', '暂无路径') : content);
}
