import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import {
  EncryptedSpaceController, EncryptedSpaceEntry, EncryptedExportTaskItem
} from '../controllers/EncryptedSpaceController';

// ===== 创建加密空间弹窗（对齐 Flutter _EncryptedCreateSpaceDialogContent） =====

class EncryptedCreateSpaceParams extends DialogParamsBase {
  onSubmit: (name: string, pwd: string, folderPath: string) => Promise<boolean> =
    (_n: string, _p: string, _f: string): Promise<boolean> => {
      return Promise.resolve(false);
    };
}

@Builder
function EncryptedCreateSpaceDialogContent(p: EncryptedCreateSpaceParams) {
  EncryptedSpaceFormDialog({
    title: L10n.t('encrypted_space_create_title', '添加加密空间'),
    showName: true,
    showPwd: true,
    hintLabel: L10n.t('encrypted_space_create_location_hint',
      '选择加密空间数据保存位置(所选文件夹必须为空)'),
    nameLabel: L10n.t('encrypted_space_space_name', '空间名称'),
    pwdLabel: L10n.t('encrypted_space_space_pwd', '空间密码'),
    pathLabel: L10n.t('encrypted_space_space_path', '空间路径'),
    pickLabel: L10n.t('encrypted_space_export_pick_folder', '选择文件夹'),
    submitLabel: L10n.t('encrypted_space_create_submit', '创建加密空间'),
    p: p
  })
}

// ===== 导入加密空间弹窗（对齐 Flutter _EncryptedImportSpaceDialogContent） =====

class EncryptedImportSpaceParams extends DialogParamsBase {
  onSubmit: (name: string, pwd: string, folderPath: string) => Promise<boolean> =
    (_n: string, _p: string, _f: string): Promise<boolean> => {
      return Promise.resolve(false);
    };
}

@Builder
function EncryptedImportSpaceDialogContent(p: EncryptedImportSpaceParams) {
  EncryptedSpaceFormDialog({
    title: L10n.t('encrypted_space_import_title', '导入加密空间'),
    showName: true,
    showPwd: true,
    hintLabel: L10n.t('encrypted_space_import_location_hint', '选择要导入的加密空间目录'),
    nameLabel: L10n.t('encrypted_space_space_name', '空间名称'),
    pwdLabel: L10n.t('encrypted_space_space_pwd', '空间密码'),
    pathLabel: L10n.t('encrypted_space_space_path', '空间路径'),
    pickLabel: L10n.t('encrypted_space_export_pick_folder', '选择文件夹'),
    submitLabel: L10n.t('encrypted_space_import_submit', '导入加密空间'),
    p: p
  })
}

// ===== 导出加密空间弹窗（对齐 Flutter _EncryptedExportDialogContent） =====

class EncryptedExportSpaceParams extends DialogParamsBase {
  onSubmit: (pwd: string, targetPath: string) => Promise<boolean> =
    (_p: string, _t: string): Promise<boolean> => {
      return Promise.resolve(false);
    };
}

@Builder
function EncryptedExportSpaceDialogContent(p: EncryptedExportSpaceParams) {
  EncryptedSpaceFormDialog({
    title: L10n.t('encrypted_space_export_title', '导出加密空间'),
    showName: false,
    showPwd: true,
    hintLabel: L10n.t('encrypted_space_export_target_hint', '选择导出目标文件夹（必须为空）'),
    nameLabel: '',
    pwdLabel: L10n.t('encrypted_space_export_space_pwd', '空间密码'),
    pathLabel: L10n.t('encrypted_space_export_target_path', '目标文件夹'),
    pickLabel: L10n.t('encrypted_space_export_pick_folder', '选择文件夹'),
    submitLabel: L10n.t('encrypted_space_export_start', '开始导出'),
    p: p
  })
}

/**
 * 创建/导入/导出共用表单弹窗（对齐三个 Flutter Dialog 内容结构）：
 * 标题 + 关闭按钮 + 密码输入[+名称输入] + 位置提示 + 只读路径选择 + 提交按钮。
 */
@ComponentV2
struct EncryptedSpaceFormDialog {
  @Param title: string = '';
  @Param showName: boolean = true;
  @Param showPwd: boolean = true;
  @Param hintLabel: string = '';
  @Param nameLabel: string = '';
  @Param pwdLabel: string = '';
  @Param pathLabel: string = '';
  @Param pickLabel: string = '';
  @Param submitLabel: string = '';
  @Param p: DialogParamsBase = new DialogParamsBase();
  @Local name: string = '';
  @Local pwd: string = '';
  @Local folderPath: string = '';
  @Local submitting: boolean = false;

  private th(): ThemePalette {
    return AppTheme.current();
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    const name = this.name.trim();
    const pwd = this.pwd.trim();
    const target = this.folderPath.trim();
    if ((this.showName && name.length === 0) || (this.showPwd && pwd.length === 0)
      || target.length === 0) {
      ToastUtil.show(L10n.inputPlease);
      return;
    }
    this.submitting = true;
    try {
      const form = this.p;
      let ok = false;
      if (form instanceof EncryptedCreateSpaceParams) {
        ok = await form.onSubmit(name, pwd, target);
      } else if (form instanceof EncryptedImportSpaceParams) {
        ok = await form.onSubmit(name, pwd, target);
      } else if (form instanceof EncryptedExportSpaceParams) {
        ok = await form.onSubmit(pwd, target);
      }
      if (ok) {
        form.onResult(true);
      }
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.th().onSurface)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([this.th().hint])
          .onClick(() => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')
      .margin({ bottom: 14 })

      if (this.showName) {
        TextInput({ text: this.name, placeholder: this.nameLabel })
          .type(InputType.Normal)
          .fontSize(15)
          .fontColor(this.th().onSurface)
          .placeholderColor(this.th().hint)
          .backgroundColor(this.th().inputFill)
          .borderRadius(10)
          .height(46)
          .width('100%')
          .margin({ bottom: 14 })
          .onChange((v: string) => {
            this.name = v;
          })
      }

      if (this.showPwd) {
        TextInput({ text: this.pwd, placeholder: this.pwdLabel })
          .type(InputType.Password)
          .fontSize(15)
          .fontColor(this.th().onSurface)
          .placeholderColor(this.th().hint)
          .backgroundColor(this.th().inputFill)
          .borderRadius(10)
          .height(46)
          .width('100%')
          .margin({ bottom: 16 })
          .onChange((v: string) => {
            this.pwd = v;
          })
      }

      Text(this.hintLabel)
        .fontSize(13)
        .fontColor(this.th().subText)
        .width('100%')
        .margin({ bottom: 10 })

      // 只读路径选择行（对齐 Flutter readOnly CustomTextField + folder 图标）
      Row({ space: 8 }) {
        Column() {
          Text(this.pathLabel)
            .fontSize(12)
            .fontColor(this.th().hint)
            .width('100%')
          Text(this.folderPath.length > 0 ? this.folderPath : this.pickLabel)
            .fontSize(14)
            .fontColor(this.folderPath.length > 0 ? this.th().onSurface : this.th().hint)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .onClick(() => {
          pickTargetFolderViaSheet('', (paths: string[]): void => {
            if (paths.length > 0) {
              this.folderPath = paths[0];
            }
          });
        })
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(20)
          .fontColor([this.th().subText])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(10)
      .border({ width: 1, color: this.th().divider })
      .margin({ bottom: 18 })

      Button(this.submitting ? L10n.loading : this.submitLabel)
        .fontSize(15)
        .fontColor(this.th().buttonText)
        .backgroundColor(this.th().buttonBg)
        .height(44)
        .width('100%')
        .enabled(!this.submitting)
        .onClick(() => {
          void this.submit();
        })
    }
    .width('100%')
    .constraintSize({ maxWidth: 480 })
    .padding({ left: 20, right: 20, top: 18, bottom: 20 })
    .backgroundColor(this.th().surfaceBg)
    .borderRadius(16)
  }
}

// ===== 打开入口 =====

/** 打开创建加密空间弹窗（对齐 createSpaceFlow 的 Get.dialog 部分） */
export function openEncryptedCreateSpaceDialog(
  onSubmit: (name: string, pwd: string, folderPath: string) => Promise<boolean>): void {
  const p = new EncryptedCreateSpaceParams();
  p.onSubmit = onSubmit;
  DialogUtil.openCustom(p, wrapBuilder(EncryptedCreateSpaceDialogContent), false);
}

/** 打开导入加密空间弹窗（对齐 importSpaceFlow 的 Get.dialog 部分） */
export function openEncryptedImportSpaceDialog(
  onSubmit: (name: string, pwd: string, folderPath: string) => Promise<boolean>): void {
  const p = new EncryptedImportSpaceParams();
  p.onSubmit = onSubmit;
  DialogUtil.openCustom(p, wrapBuilder(EncryptedImportSpaceDialogContent), false);
}

/** 打开导出加密空间弹窗（对齐 exportSpaceFlow 的 Get.dialog 部分） */
export function openEncryptedExportSpaceDialog(
  onSubmit: (pwd: string, targetPath: string) => Promise<boolean>): void {
  const p = new EncryptedExportSpaceParams();
  p.onSubmit = onSubmit;
  DialogUtil.openCustom(p, wrapBuilder(EncryptedExportSpaceDialogContent), false);
}

// ===== 导出任务弹层（对齐 Flutter showExportTasksDialog） =====

class EncryptedExportTasksSheetParams extends SheetParamsBase {
  ctrl: EncryptedSpaceController = new EncryptedSpaceController();
}

@Builder
function EncryptedExportTasksSheetContent(p: EncryptedExportTasksSheetParams) {
  EncryptedExportTasksSheetInner({ p: p })
}

@ComponentV2
struct EncryptedExportTasksSheetInner {
  @Param p: EncryptedExportTasksSheetParams = new EncryptedExportTasksSheetParams();

  aboutToAppear(): void {
    this.p.ctrl.startExportTaskTimer((): void => {
    });
  }

  build() {
    Column() {
      SheetHandle()
      // 标题行（对齐 Flutter 标题 + refresh/clean/close 按钮）
      Row({ space: 10 }) {
        Text(L10n.t('encrypted_space_export_tasks', '导出任务'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .onClick(() => {
            void this.p.ctrl.refreshExportTasks(false);
          })
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .onClick(() => {
            void this.p.ctrl.clearFinishedExportTasksFlow();
          })
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .onClick(() => {
            this.p.close();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 8 })

      if (this.p.ctrl.exportTasksLoading && this.p.ctrl.exportTasks.length === 0) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height(160)
        .justifyContent(FlexAlign.Center)
      } else if (this.p.ctrl.exportTasksErrorText.length > 0) {
        Text(this.p.ctrl.exportTasksErrorText)
          .fontSize(14)
          .fontColor(AppTheme.current().subText)
          .width('100%')
          .height(160)
          .textAlign(TextAlign.Center)
      } else if (this.p.ctrl.exportTasks.length === 0) {
        Text(L10n.t('no_data', '暂无数据'))
          .fontSize(14)
          .fontColor(AppTheme.current().hint)
          .width('100%')
          .height(160)
          .textAlign(TextAlign.Center)
      } else {
        List() {
          ForEach(this.p.ctrl.exportTasks, (it: EncryptedExportTaskItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Column({ space: 4 }) {
                  Text(`#${it.id} · ${L10n.t('encrypted_space_space_id', '空间ID')}: ${it.spaceId}`)
                    .fontSize(14)
                    .fontColor(AppTheme.current().onSurface)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  if (it.subtitle().length > 0) {
                    Text(it.subtitle())
                      .fontSize(12)
                      .fontColor(AppTheme.current().subText)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                  if (it.targetPath.length > 0) {
                    Text(`${L10n.t('encrypted_space_export_target_path', '目标文件夹')}: ${it.targetPath}`)
                      .fontSize(12)
                      .fontColor(AppTheme.current().subText)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                  if (it.lastError.length > 0) {
                    Text(`${L10n.error}: ${it.lastError}`)
                      .fontSize(12)
                      .fontColor('#E53935')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(18)
                  .fontColor([AppTheme.current().subText])
                  .onClick(() => {
                    void this.p.ctrl.deleteExportTaskFlow(it.id);
                  })
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            }
            .border({ width: { top: 0.5 }, color: AppTheme.current().divider })
          }, (it: EncryptedExportTaskItem) => `${it.id}`)
        }
        .width('100%')
        .height(300)
        .scrollBar(BarState.Off)
      }
      Blank().height(16)
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/** 打开导出任务弹层（轮询在弹层关闭后停止） */
export function showEncryptedExportTasksSheet(ctrl: EncryptedSpaceController): void {
  const p = new EncryptedExportTasksSheetParams();
  p.ctrl = ctrl;
  p.onDismissed = (): void => {
    ctrl.stopExportTaskTimer();
  };
  SheetUtil.present(p, wrapBuilder(EncryptedExportTasksSheetContent));
}

/** 供页面调用的导出流程（弹导出对话框并提交） */
export function runEncryptedExportSpaceFlow(ctrl: EncryptedSpaceController,
  space: EncryptedSpaceEntry): void {
  openEncryptedExportSpaceDialog(async (pwd: string, targetPath: string): Promise<boolean> => {
    return ctrl.submitExportSpace(space.id, pwd, targetPath);
  });
}

/** 供页面调用的创建流程 */
export function runEncryptedCreateSpaceFlow(ctrl: EncryptedSpaceController): void {
  openEncryptedCreateSpaceDialog(async (name: string, pwd: string, folderPath: string): Promise<boolean> => {
    return ctrl.submitCreateSpace(name, pwd, folderPath);
  });
}

/** 供页面调用的导入流程 */
export function runEncryptedImportSpaceFlow(ctrl: EncryptedSpaceController): void {
  openEncryptedImportSpaceDialog(async (name: string, pwd: string, folderPath: string): Promise<boolean> => {
    return ctrl.submitImportSpace(name, pwd, folderPath);
  });
}
