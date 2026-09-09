import { DialogParamsBase, DialogUtil } from '../../../common/DialogUtil';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
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

function canSubmit(name: string, paths: string[]): boolean {
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

  aboutToAppear(): void {
    this.name = this.p.name;
    this.paths = this.p.pathList.slice();
  }

  private submit(): void {
    if (!canSubmit(this.name, this.paths)) {
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
        .fontSize(14)
        .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.6)])
        .onClick(() => {
          const next = this.paths.slice();
          next.splice(index, 1);
          this.paths = next;
        })
    }
    .width('100%')
    .padding({ left: 10, right: 6, top: 6, bottom: 6 })
    .borderRadius(8)
    .border({ width: 1, color: AppTheme.current().divider })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(this.p.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        if (this.p.showHelp) {
          SymbolGlyph($r('sys.symbol.questionmark_circle'))
            .fontSize(20)
            .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.6)])
            .onClick(() => {
              DialogUtil.showInfoDialog(L10n.t('book_create_collection', '创建合集'),
                L10n.t('book_create_collection_alert',
                  '合集用于把多个文件夹聚合为一个入口，选择多个文件夹路径后即可在合集内浏览其中的图书。'));
            })
        }
      }
      .width('100%')

      TextInput({ text: this.name, placeholder: L10n.t('name', '名称') })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(AppTheme.current().inputFill)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .onChange((v: string): void => {
          this.name = v;
        })

      Button(L10n.t('choose_path', '选择路径'))
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(AppTheme.current().inputFill)
        .fontColor(AppTheme.current().onSurface)
        .onClick(() => {
          pickTargetFolderViaSheet('', (picked: string[]): void => {
            if (picked.length === 0) {
              return;
            }
            const next = this.paths.slice();
            for (const path of picked) {
              if (next.indexOf(path) < 0) {
                next.push(path);
              }
            }
            this.paths = next;
          }, true, 'book');
        })

      if (this.paths.length > 0) {
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.paths, (path: string, index: number) => {
              this.PathRow(path, index)
            }, (path: string, index: number): string => `${index}_${path}`)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 220 })
        .align(Alignment.Top)
        .scrollBar(BarState.Auto)
      }

      Row({ space: 12 }) {
        Button(L10n.t('cancel', '取消'), { buttonStyle: ButtonStyleMode.NORMAL })
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.current().inputFill)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .enabled(canSubmit(this.name, this.paths))
          .backgroundColor(AppTheme.current().primary)
          .fontColor(AppTheme.current().buttonText)
          .opacity(canSubmit(this.name, this.paths) ? 1 : 0.4)
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('92%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
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
