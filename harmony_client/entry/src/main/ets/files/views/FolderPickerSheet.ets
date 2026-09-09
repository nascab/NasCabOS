import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { CircleCheckbox } from '../../common/components/CircleCheckbox';
import { FileController } from '../controllers/FileController';
import { FileItem, FileModelAccess, fileItemIsDotHidden } from '../models/FileModels';
import { FILE_HIDDEN_LIST_OPACITY } from '../models/FileModels';

/**
 * 目标文件夹选择弹层（对齐 Flutter FolderPickerDialog 的文件系统浏览能力）：
 * 仅列出目录，点击进入子目录，支持返回上级，底部确认选择当前目录；
 * 多选模式（对齐 Flutter multiSelect: true）行首勾选框选择多个目录；
 * 文件选择模式（对齐 Flutter allowFileSelect: true）列出文件，点击勾选文件。
 */
class FolderPickerSheetParams extends SheetParamsBase {
  /** 确认选择时回调，返回所选目录路径数组 */
  onPicked: (paths: string[]) => void = (_p: string[]): void => {
  };
  /** 初始目录（默认从根开始） */
  initialPath: string = '';
  /** 多选模式（对齐 Flutter folder_picker multiSelect） */
  multiSelect: boolean = false;
  /** 允许选择文件（对齐 Flutter allowFileSelect） */
  allowFileSelect: boolean = false;
  /** 列目录 sourceType（对齐 Flutter sourceType，如音乐合集 'music'） */
  sourceType: string = '';
}

@Builder
function FolderPickerSheetContent(p: FolderPickerSheetParams) {
  FolderPickerSheetInner({ p: p })
}

@ComponentV2
struct FolderPickerSheetInner {
  @Param p: FolderPickerSheetParams = new FolderPickerSheetParams();
  @Local ctrl: FileController = new FileController(false, '/api/file/list', '/api/file/search', false);
  @Local loading: boolean = false;
  @Local selectedPaths: string[] = [];

  aboutToAppear(): void {
    // 对齐 Flutter：allowFileSelect 时同时列出文件（onlyShowDir=false）
    this.ctrl.onlyShowDir = !this.p.allowFileSelect;
    this.loading = true;
    this.ctrl.listDirectory(this.p.initialPath, 'normal', this.p.sourceType).finally((): void => {
      this.loading = false;
    });
  }

  private isSelected(path: string): boolean {
    return this.selectedPaths.indexOf(path) >= 0;
  }

  private toggleSelect(path: string): void {
    const next = this.selectedPaths.slice();
    const idx = next.indexOf(path);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(path);
    }
    this.selectedPaths = next;
  }

  private async enter(it: FileItem): Promise<void> {
    if (FileModelAccess.virtualType(it) === 'custom_add') {
      return;
    }
    this.loading = true;
    await this.ctrl.navigateTo(FileModelAccess.path(it));
    this.loading = false;
  }

  private async goUp(): Promise<void> {
    this.loading = true;
    await this.ctrl.goUp();
    this.loading = false;
  }

  build() {
    Column() {
      SheetHandle()
      // 顶部：返回上级 + 当前路径
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .opacity(this.ctrl.isRoot ? 0.35 : 1)
          .onClick((): void => {
            if (!this.ctrl.isRoot) {
              void this.goUp();
            }
          })
        Text(this.ctrl.currentPath.length > 0 ? this.ctrl.currentPath : L10n.t('app_folder', '文件'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 6, bottom: 10 })

      Divider()
        .color(AppTheme.current().divider)

      // 目录列表
      List({ space: 0 }) {
        if (this.loading) {
          ListItem() {
            Column() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(AppTheme.current().primary)
            }
            .width('100%')
            .height(120)
            .justifyContent(FlexAlign.Center)
          }
        } else if (this.ctrl.displayItems.length === 0) {
          ListItem() {
            Column() {
              Text(L10n.t('folder_picker_no_subdir', '没有子文件夹'))
                .fontSize(13)
                .fontColor(AppTheme.current().hint)
            }
            .width('100%')
            .height(120)
            .justifyContent(FlexAlign.Center)
          }
        } else {
          ForEach(this.ctrl.displayItems, (it: FileItem): void => {
            ListItem() {
              Row({ space: 10 }) {
                if (this.p.multiSelect || this.p.allowFileSelect) {
                  CircleCheckbox({
                    value: this.isSelected(FileModelAccess.path(it)),
                    onChanged: (_c: boolean): void => {
                      this.toggleSelect(FileModelAccess.path(it));
                    }
                  })
                }
                Image($rawfile(FileModelAccess.isDir(it) ? 'icons/file/folder.png' : 'icons/file/file.png'))
                  .width(34)
                  .height(34)
                  .objectFit(ImageFit.Contain)
                  .draggable(false)
                Text(FileModelAccess.fileName(it))
                  .fontSize(15)
                  .fontColor(AppTheme.current().onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (FileModelAccess.isDir(it)) {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(16)
                    .fontColor([AppTheme.current().subText])
                }
              }
              .width('100%')
              .padding({ left: 20, right: 16, top: 10, bottom: 10 })
              .opacity(fileItemIsDotHidden(it) ? FILE_HIDDEN_LIST_OPACITY : 1.0)
            }
            .onClick((): void => {
              if (FileModelAccess.isDir(it)) {
                void this.enter(it);
              } else {
                this.toggleSelect(FileModelAccess.path(it));
              }
            })
          }, (it: FileItem): string => FileModelAccess.path(it))
        }
      }
      .width('100%')
      .constraintSize({ maxHeight: 380 })
      .scrollBar(BarState.Auto)

      Divider()
        .color(AppTheme.current().divider)

      // 底部确认（多选模式显示已选数量，对齐 Flutter folder_picker_confirm_bar）
      Row() {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor('#00000000')
          .height(40)
          .layoutWeight(1)
          .onClick((): void => {
            this.p.close();
          })
        Button((this.p.multiSelect || this.p.allowFileSelect) && this.selectedPaths.length > 0
          ? `${L10n.confirm}(${this.selectedPaths.length})` : L10n.confirm)
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(40)
          .layoutWeight(1)
          .onClick((): void => {
            if (this.p.multiSelect) {
              if (this.selectedPaths.length === 0) {
                return;
              }
              this.p.close();
              this.p.onPicked(this.selectedPaths.slice());
              return;
            }
            if (this.p.allowFileSelect) {
              // 文件选择模式：必须勾选文件后确认
              if (this.selectedPaths.length === 0) {
                return;
              }
              this.p.close();
              this.p.onPicked(this.selectedPaths.slice());
              return;
            }
            const target = this.ctrl.currentPath;
            if (target.trim().length === 0) {
              // 根目录不可作为移动/复制目标
              return;
            }
            this.p.close();
            this.p.onPicked([target]);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 28 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/**
 * 打开目标文件夹选择弹层（对齐 Flutter FolderPickerDialog 的选择能力）。
 * 取消/关闭时 resolve 空数组，确认时返回 [path]（multiSelect=true 时返回所选路径数组）。
 */
export function pickTargetFolderViaSheet(initialPath: string,
  onResult: (paths: string[]) => void, multiSelect: boolean = false, sourceType: string = ''): void {
  const p = new FolderPickerSheetParams();
  p.onPicked = (paths: string[]): void => {
    onResult(paths);
  };
  p.onDismissed = (): void => {
    onResult([]);
  };
  p.initialPath = initialPath;
  p.multiSelect = multiSelect;
  p.sourceType = sourceType;
  SheetUtil.present(p, wrapBuilder(FolderPickerSheetContent));
}

/**
 * 服务器文件选择弹层（对齐 Flutter showFolderPickerBottomSheet(allowFileSelect: true)）：
 * 浏览服务器目录并勾选文件，确认时返回所选文件路径数组，取消返回空数组。
 */
export function pickServerFileViaSheet(initialPath: string, onResult: (paths: string[]) => void): void {
  const p = new FolderPickerSheetParams();
  p.onPicked = (paths: string[]): void => {
    onResult(paths);
  };
  p.onDismissed = (): void => {
    onResult([]);
  };
  p.initialPath = initialPath;
  p.allowFileSelect = true;
  SheetUtil.present(p, wrapBuilder(FolderPickerSheetContent));
}
