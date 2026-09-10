import pasteboard from '@ohos.pasteboard';
import { display } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickServerFileViaSheet, pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { DockerController } from '../controllers/DockerController';
import {
  buildDockerImageOptions, DOCKER_RESTART_POLICY_OPTIONS, dockerStr, DockerContainer,
  DockerEnvVar, DockerImage, DockerImageOption, DockerMountInfo, DockerPortBinding,
  isDockerImageArchivePath
} from '../models/DockerModels';
import {
  DockerAddTag, DockerEditorTag, DockerModeToggle, DockerTaskLogsPanel
} from '../views/parts/DockerSharedWidgets';

/**
 * Docker 模块弹窗集合（对齐 Flutter docker_dialogs.dart）：
 * 拉取镜像/导入镜像/创建容器/修改标签/容器日志/配置编辑，以及
 * 环境变量/端口映射/卷挂载子编辑器与任务日志底部弹层。
 * 统一通过 DialogUtil.openCustom / SheetUtil.present 实现。
 */

/** 对话框确认按钮行（取消 + 主操作，样式对齐 DialogUtil 内部组件） */
@ComponentV2
struct DockerDialogActions {
  @Param confirmText: string = '';
  @Param isEnabled: boolean = true;
  @Param onCancel: () => void = (): void => {
  };
  @Param onConfirm: () => void = (): void => {
  };

  build() {
    Row({ space: 8 }) {
      Button(L10n.cancel)
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .backgroundColor(Color.Transparent)
        .height(36)
        .layoutWeight(1)
        .onClick((): void => {
          this.onCancel();
        })
      Button(this.confirmText)
        .fontSize(14)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .height(36)
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.4)
        .layoutWeight(1)
        .onClick((): void => {
          this.onConfirm();
        })
    }
    .margin({ top: 20 })
    .width('100%')
  }
}

/** 对话框文本输入行（label + TextInput） */
@ComponentV2
struct DockerDialogField {
  @Param label: string = '';
  @Param hint: string = '';
  @Param isPassword: boolean = false;
  @Param value: string = '';
  @Param onChange: (v: string) => void = (_v: string): void => {
  };

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .width('100%')
      TextInput({ text: this.value, placeholder: this.hint })
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 6 })
        .width('100%')
        .onChange((v: string): void => {
          this.onChange(v);
        })
    }
    .width('100%')
  }
}

/** 对话框路径选择行（label + 只读路径展示 + 文件夹按钮，点击选择服务器路径） */
@ComponentV2
struct DockerDialogPathField {
  @Param label: string = '';
  @Param hint: string = '';
  @Param path: string = '';
  @Param onPick: () => void = (): void => {
  };

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .width('100%')
      Row({ space: 8 }) {
        Text(this.path.length > 0 ? this.path : this.hint)
          .fontSize(14)
          .fontColor(this.path.length > 0 ? AppTheme.current().onSurface : AppTheme.current().hint)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        BorderedIconButton({
          icon: $r('sys.symbol.folder'),
          onTap: (): void => {
            this.onPick();
          }
        })
      }
      .alignItems(VerticalAlign.Center)
      .height(48)
      .padding({ left: 12, right: 8 })
      .backgroundColor(AppTheme.current().inputFill)
      .borderRadius(8)
      .border({ width: 1, color: AppTheme.current().inputBorder })
      .margin({ top: 6 })
      .width('100%')
      .onClick((): void => {
        this.onPick();
      })
    }
    .width('100%')
  }
}

/** 下拉选择行（label + 当前值 + 展开图标，点击弹选项弹层） */
@ComponentV2
struct DockerDialogSelectField {
  @Param label: string = '';
  @Param value: string = '';
  @Param isEnabled: boolean = true;
  @Param onPick: () => void = (): void => {
  };

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .width('100%')
      Row() {
        Text(this.value.length > 0 ? this.value : '--')
          .fontSize(14)
          .fontColor(this.value.length > 0 ? AppTheme.current().onSurface : AppTheme.current().hint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([AppTheme.current().subText])
      }
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor(AppTheme.current().inputFill)
      .borderRadius(8)
      .border({ width: 1, color: this.isEnabled ? AppTheme.current().inputBorder : AppTheme.current().divider })
      .opacity(this.isEnabled ? 1 : 0.5)
      .margin({ top: 6 })
      .width('100%')
      .onClick((): void => {
        if (this.isEnabled) {
          this.onPick();
        }
      })
    }
    .width('100%')
  }
}

/** 写文本到剪贴板并提示 */
async function copyPlainText(text: string, toastKey: string, toastFallback: string): Promise<void> {
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  pasteboard.getSystemPasteboard().setPasteData(data);
  ToastUtil.show(L10n.t(toastKey, toastFallback));
}

/** 从容器日志接口 data 中提取文本行 */
function extractLogLines(data: Record<string, Object>): string[] {
  const raw = data['items'];
  if (!Array.isArray(raw)) {
    return [];
  }
  const lines: string[] = [];
  (raw as Object[]).forEach((item: Object): void => {
    if (typeof item === 'object' && item !== null) {
      lines.push(dockerStr((item as Record<string, Object>)['text']));
    } else {
      lines.push(`${item}`);
    }
  });
  return lines;
}

/** 重启策略展示文案 */
function restartPolicyLabel(value: string): string {
  for (const opt of DOCKER_RESTART_POLICY_OPTIONS) {
    if (opt.value === value) {
      return L10n.t(opt.labelKey, restartPolicyFallback(value));
    }
  }
  return value;
}

function restartPolicyFallback(value: string): string {
  if (value === 'no') {
    return '不自动重启';
  }
  if (value === 'always') {
    return '总是重启';
  }
  if (value === 'on-failure') {
    return '失败时重启';
  }
  return '除非手动停止';
}

// ============================================================
// 拉取镜像弹窗（对齐 Flutter _showPullImageDialog）
// ============================================================

class DockerPullImageParams extends DialogParamsBase {
  ctrl: DockerController = new DockerController();
}

@Builder
function DockerPullImageContent(p: DockerPullImageParams) {
  DockerPullImageInner({ p: p })
}

@ComponentV2
struct DockerPullImageInner {
  @Param p: DockerPullImageParams = new DockerPullImageParams();
  @Local registry: string = '';
  @Local image: string = '';
  @Local tag: string = 'latest';
  @Local username: string = '';
  @Local password: string = '';
  @Local submitting: boolean = false;

  private async submit(): Promise<void> {
    if (this.image.trim().length === 0) {
      ToastUtil.show(L10n.t('docker_image_name_required', '请先输入镜像名称'));
      return;
    }
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const ok = await this.p.ctrl.pullImage(this.image.trim(), this.registry.trim(), this.tag.trim(),
      this.username.trim(), this.password);
    this.submitting = false;
    if (ok) {
      this.p.onResult(undefined);
    }
  }

  build() {
    Column() {
      Text(L10n.t('docker_pull_image', '拉取镜像'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Scroll() {
        Column() {
          DockerDialogField({
            label: `${L10n.t('docker_registry', '仓库地址')} (${L10n.t('user_mgmt_optional_hint', '可选')})`,
            hint: L10n.t('docker_registry_hint', '例如 docker.io 或 harbor.example.com'),
            value: this.registry,
            onChange: (v: string): void => {
              this.registry = v;
            }
          })
          DockerDialogField({
            label: L10n.t('docker_image_name', '镜像名称'),
            hint: L10n.t('docker_image_name_hint', '例如 ypptec/nascabos'),
            value: this.image,
            onChange: (v: string): void => {
              this.image = v;
            }
          })
          DockerDialogField({
            label: L10n.t('docker_tag', '标签'),
            value: this.tag,
            onChange: (v: string): void => {
              this.tag = v;
            }
          })
          DockerDialogField({
            label: `${L10n.t('docker_registry_username', '仓库用户名')} (${L10n.t('user_mgmt_optional_hint', '可选')})`,
            value: this.username,
            onChange: (v: string): void => {
              this.username = v;
            }
          })
          DockerDialogField({
            label: `${L10n.t('docker_registry_password', '仓库密码')} (${L10n.t('user_mgmt_optional_hint', '可选')})`,
            isPassword: true,
            value: this.password,
            onChange: (v: string): void => {
              this.password = v;
            }
          })
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 380 })
      .margin({ top: 14 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.t('docker_start_pull', '开始拉取'),
        isEnabled: !this.submitting,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          void this.submit();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 280, maxWidth: 420 })
  }
}

/** 打开拉取镜像弹窗 */
export function showDockerPullImageDialog(ctrl: DockerController): void {
  const p = new DockerPullImageParams();
  p.ctrl = ctrl;
  DialogUtil.openCustom<DockerPullImageParams>(p, wrapBuilder(DockerPullImageContent), true);
}

// ============================================================
// 导入镜像弹窗（对齐 Flutter _showImportImageDialog）
// ============================================================

class DockerImportImageParams extends DialogParamsBase {
  ctrl: DockerController = new DockerController();
}

@Builder
function DockerImportImageContent(p: DockerImportImageParams) {
  DockerImportImageInner({ p: p })
}

@ComponentV2
struct DockerImportImageInner {
  @Param p: DockerImportImageParams = new DockerImportImageParams();
  @Local archivePath: string = '';
  @Local submitting: boolean = false;

  private pickArchive(): void {
    pickServerFileViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const path = paths[0].trim();
      if (path.length === 0) {
        return;
      }
      if (!isDockerImageArchivePath(path)) {
        ToastUtil.show(L10n.t('docker_image_archive_invalid', '仅支持 .tar、.tar.gz 或 .tgz 格式的镜像归档文件'));
        return;
      }
      this.archivePath = path;
    });
  }

  private async submit(): Promise<void> {
    const archivePath = this.archivePath.trim();
    if (archivePath.length === 0) {
      ToastUtil.show(L10n.t('docker_image_archive_required', '请先选择镜像归档文件'));
      return;
    }
    if (!isDockerImageArchivePath(archivePath)) {
      ToastUtil.show(L10n.t('docker_image_archive_invalid', '仅支持 .tar、.tar.gz 或 .tgz 格式的镜像归档文件'));
      return;
    }
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const ok = await this.p.ctrl.importImage(archivePath);
    this.submitting = false;
    if (ok) {
      this.p.onResult(undefined);
    }
  }

  build() {
    Column() {
      Text(L10n.t('docker_import_image', '导入镜像'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Text(L10n.t('docker_import_image_hint',
        '请选择服务器上的 Docker 镜像归档文件，支持 .tar、.tar.gz、.tgz，并会以异步任务方式导入。'))
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .margin({ top: 12 })
        .width('100%')
      Column() {
        DockerDialogPathField({
          label: L10n.t('docker_image_archive', '镜像归档文件'),
          hint: L10n.t('docker_image_archive_hint', '请选择服务器上的 tar 镜像文件'),
          path: this.archivePath,
          onPick: (): void => {
            this.pickArchive();
          }
        })
      }
      .margin({ top: 12 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.t('docker_start_import', '开始导入'),
        isEnabled: !this.submitting,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          void this.submit();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 280, maxWidth: 460 })
  }
}

/** 打开导入镜像弹窗 */
export function showDockerImportImageDialog(ctrl: DockerController): void {
  const p = new DockerImportImageParams();
  p.ctrl = ctrl;
  DialogUtil.openCustom<DockerImportImageParams>(p, wrapBuilder(DockerImportImageContent), false);
}

// ============================================================
// 修改镜像标签弹窗（对齐 Flutter _showTagImageDialog）
// ============================================================

class DockerTagImageParams extends DialogParamsBase {
  ctrl: DockerController = new DockerController();
  image: DockerImage = new DockerImage();
}

@Builder
function DockerTagImageContent(p: DockerTagImageParams) {
  DockerTagImageInner({ p: p })
}

@ComponentV2
struct DockerTagImageInner {
  @Param p: DockerTagImageParams = new DockerTagImageParams();
  @Local repository: string = '';
  @Local tag: string = '';
  @Local submitting: boolean = false;

  aboutToAppear(): void {
    const repo = this.p.image.repository.trim();
    const tag = this.p.image.tag.trim();
    this.repository = repo === '<none>' ? '' : repo;
    this.tag = tag === '<none>' ? 'latest' : (tag.length > 0 ? tag : 'latest');
  }

  private async submit(): Promise<void> {
    if (this.repository.trim().length === 0 || this.tag.trim().length === 0) {
      ToastUtil.show(L10n.t('docker_image_tag_required', '镜像名称和标签不能为空'));
      return;
    }
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const ok = await this.p.ctrl.tagImage(this.p.image.id, this.repository.trim(), this.tag.trim(),
      this.p.image.reference.trim());
    this.submitting = false;
    if (ok) {
      this.p.onResult(undefined);
    }
  }

  build() {
    Column() {
      Text(L10n.t('docker_change_tag', '修改标签'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Column() {
        DockerDialogField({
          label: L10n.t('docker_image_name', '镜像名称'),
          value: this.repository,
          onChange: (v: string): void => {
            this.repository = v;
          }
        })
        Column() {
          DockerDialogField({
            label: L10n.t('docker_tag', '标签'),
            value: this.tag,
            onChange: (v: string): void => {
              this.tag = v;
            }
          })
        }
        .margin({ top: 12 })
        .width('100%')
      }
      .margin({ top: 14 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.save,
        isEnabled: !this.submitting,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          void this.submit();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 280, maxWidth: 460 })
  }
}

/** 打开修改镜像标签弹窗 */
export function showDockerTagImageDialog(ctrl: DockerController, image: DockerImage): void {
  const p = new DockerTagImageParams();
  p.ctrl = ctrl;
  p.image = image;
  DialogUtil.openCustom<DockerTagImageParams>(p, wrapBuilder(DockerTagImageContent), false);
}

// ============================================================
// 容器日志弹窗（对齐 Flutter _showLogsDialog）
// ============================================================

class DockerLogsParams extends DialogParamsBase {
  ctrl: DockerController = new DockerController();
  containerId: string = '';
  initialLines: string[] = [];
}

@Builder
function DockerLogsContent(p: DockerLogsParams) {
  DockerLogsInner({ p: p })
}

@ComponentV2
struct DockerLogsInner {
  @Param p: DockerLogsParams = new DockerLogsParams();
  @Local tail: string = '200';
  @Local lines: string[] = [];

  aboutToAppear(): void {
    this.lines = this.p.initialLines.slice();
  }

  private tailCount(): number {
    const parsed = Number(this.tail.trim());
    return Number.isFinite(parsed) ? parsed : 200;
  }

  private refresh(): void {
    this.p.ctrl.fetchContainerLogs(this.p.containerId, '', '', this.tailCount(), false)
      .then((res: Record<string, Object> | undefined): void => {
        if (res !== undefined) {
          this.lines = extractLogLines(res);
        }
      });
  }

  private follow(): void {
    this.p.ctrl.fetchContainerLogs(this.p.containerId, '', '', this.tailCount(), true)
      .then((res: Record<string, Object> | undefined): void => {
        if (res !== undefined) {
          this.p.onResult(undefined);
        }
      });
  }

  build() {
    Column() {
      Text(L10n.t('docker_view_logs', '日志'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Row({ space: 10 }) {
        TextInput({ text: this.tail })
          .type(InputType.Number)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(42)
          .layoutWeight(1)
          .onChange((v: string): void => {
            this.tail = v;
          })
        Text(L10n.t('refresh', '刷新'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick((): void => {
            this.refresh();
          })
        Text(L10n.t('docker_follow_logs', '实时跟踪'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick((): void => {
            this.follow();
          })
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })
      .width('100%')
      Column() {
        if (this.lines.length === 0) {
          Text(L10n.t('no_data', '暂无数据'))
            .fontSize(13)
            .fontColor(AppTheme.current().hint)
        } else {
          List({ space: 0 }) {
            ForEach(this.lines, (line: string, idx: number): void => {
              ListItem() {
                Text(line)
                  .fontSize(11)
                  .fontColor(AppTheme.current().onSurface)
                  .copyOption(CopyOptions.InApp)
                  .width('100%')
                  .padding({ bottom: 6 })
              }
            }, (line: string, idx: number): string => `${idx}_${line}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 12 })
      .padding(12)
      .backgroundColor(AppTheme.current().inputFill)
      .borderRadius(12)
      Row({ space: 8 }) {
        Button(L10n.t('copy', '复制'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .layoutWeight(1)
          .onClick((): void => {
            void copyPlainText(this.lines.join('\n'), 'docker_logs_copied', '日志已复制');
          })
        Button(L10n.ok)
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .layoutWeight(1)
          .onClick((): void => {
            this.p.onResult(undefined);
          })
      }
      .margin({ top: 12 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('86%')
    .height('68%')
  }
}

/** 打开容器日志弹窗（先拉取日志，失败时不弹窗） */
export function showDockerLogsDialog(ctrl: DockerController, container: DockerContainer): void {
  ctrl.fetchContainerLogs(container.id, '', '', 200, false)
    .then((res: Record<string, Object> | undefined): void => {
      if (res === undefined) {
        return;
      }
      const p = new DockerLogsParams();
      p.ctrl = ctrl;
      p.containerId = container.id;
      p.initialLines = extractLogLines(res);
      DialogUtil.openCustom<DockerLogsParams>(p, wrapBuilder(DockerLogsContent), true);
    });
}

// ============================================================
// 配置文件编辑弹窗（对齐 Flutter _showConfigEditorDialog）
// ============================================================

class DockerConfigEditorParams extends DialogParamsBase {
  ctrl: DockerController = new DockerController();
  initialContent: string = '{\n}\n';
  pathText: string = '--';
}

@Builder
function DockerConfigEditorContent(p: DockerConfigEditorParams) {
  DockerConfigEditorInner({ p: p })
}

@ComponentV2
struct DockerConfigEditorInner {
  @Param p: DockerConfigEditorParams = new DockerConfigEditorParams();
  @Local content: string = '';

  aboutToAppear(): void {
    this.content = this.p.initialContent;
  }

  private async toggleService(): Promise<void> {
    const ok = await this.p.ctrl.toggleDockerService();
    if (ok) {
      this.p.onResult(undefined);
    }
  }

  private async save(): Promise<void> {
    let parsed: Object | null = null;
    try {
      parsed = JSON.parse(this.content) as Object;
    } catch (_e) {
      ToastUtil.show(L10n.t('docker_config_json_invalid', '配置文件不是合法的 JSON'));
      return;
    }
    if (parsed === null || Array.isArray(parsed)) {
      ToastUtil.show(L10n.t('docker_config_json_object_required', '配置文件内容必须是 JSON 对象'));
      return;
    }
    const ok = await this.p.ctrl.saveConfigContent(this.content);
    if (ok) {
      this.p.onResult(undefined);
    }
  }

  build() {
    Column() {
      Text(L10n.t('docker_config_file', '配置文件'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Row() {
        Text(L10n.t('docker_config_path', '配置文件路径'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .width(110)
        Text(this.p.pathText)
          .fontSize(13)
          .fontColor(AppTheme.current().onSurface)
          .copyOption(CopyOptions.InApp)
          .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .margin({ top: 12 })
      .width('100%')
      Text(L10n.t('docker_config_file_hint', '请填写合法的 JSON 对象内容，保存前会先进行 JSON 格式校验'))
        .fontSize(12)
        .fontColor(AppTheme.current().subText)
        .margin({ top: 8 })
        .width('100%')
      Column() {
        Text(L10n.t('docker_config_content', '配置内容'))
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .width('100%')
        TextArea({ text: this.content })
          .fontSize(13)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(200)
          .margin({ top: 6 })
          .width('100%')
          .onChange((v: string): void => {
            this.content = v;
          })
      }
      .margin({ top: 12 })
      .width('100%')
      Row({ space: 8 }) {
        Button(this.p.ctrl.dockerAvailable
          ? L10n.t('docker_stop_service', '停止 Docker')
          : L10n.t('docker_start_service', '启动 Docker'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .enabled(!this.p.ctrl.dockerServiceOperating)
          .opacity(this.p.ctrl.dockerServiceOperating ? 0.4 : 1)
          .layoutWeight(1)
          .onClick((): void => {
            void this.toggleService();
          })
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .layoutWeight(1)
          .onClick((): void => {
            this.p.onResult(undefined);
          })
        Button(L10n.save)
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .layoutWeight(1)
          .onClick((): void => {
            void this.save();
          })
      }
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('86%')
  }
}

/** 打开配置文件编辑弹窗 */
export function showDockerConfigEditorDialog(ctrl: DockerController): void {
  const p = new DockerConfigEditorParams();
  p.ctrl = ctrl;
  const content = dockerStr(ctrl.config['content']);
  p.initialContent = content.length > 0 ? content : '{\n}\n';
  const path = dockerStr(ctrl.config['path']).trim();
  p.pathText = path.length > 0 ? path : '--';
  DialogUtil.openCustom<DockerConfigEditorParams>(p, wrapBuilder(DockerConfigEditorContent), true);
}

// ============================================================
// 任务日志底部弹层（对齐 Flutter _showTaskLogsSheet）
// ============================================================

class DockerTaskLogsSheetParams extends SheetParamsBase {
  ctrl: DockerController = new DockerController();
}

@Builder
function DockerTaskLogsSheetContent(p: DockerTaskLogsSheetParams) {
  Column() {
    SheetHandle()
    Column() {
      DockerTaskLogsPanel({ ctrl: p.ctrl })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
  }
  .height(px2vp(display.getDefaultDisplaySync().height) * 0.76)
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/** 打开任务日志底部弹层（关闭时停止日志轮询，对齐 Flutter finally 分支） */
export function showDockerTaskLogsSheet(ctrl: DockerController): void {
  const p = new DockerTaskLogsSheetParams();
  p.ctrl = ctrl;
  p.onDismissed = (): void => {
    ctrl.setTaskLogsPolling(false);
  };
  SheetUtil.present(p, wrapBuilder(DockerTaskLogsSheetContent));
}

// ============================================================
// 环境变量编辑子弹窗（对齐 Flutter _showEnvVarEditorDialog）
// ============================================================

class DockerEnvEditorParams extends DialogParamsBase {
  initial: DockerEnvVar | undefined = undefined;
  onConfirmed: (v: DockerEnvVar) => void = (_v: DockerEnvVar): void => {
  };
}

@Builder
function DockerEnvEditorContent(p: DockerEnvEditorParams) {
  DockerEnvEditorInner({ p: p })
}

@ComponentV2
struct DockerEnvEditorInner {
  @Param p: DockerEnvEditorParams = new DockerEnvEditorParams();
  @Local envKey: string = '';
  @Local value: string = '';

  aboutToAppear(): void {
    this.envKey = this.p.initial !== undefined ? this.p.initial.key : '';
    this.value = this.p.initial !== undefined ? this.p.initial.value : '';
  }

  build() {
    Column() {
      Text(this.p.initial === undefined
        ? `${L10n.t('add', '添加')} ${L10n.t('docker_env_vars', '环境变量')}`
        : `${L10n.edit} ${L10n.t('docker_env_vars', '环境变量')}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Column() {
        DockerDialogField({
          label: L10n.t('docker_key', '键'),
          value: this.envKey,
          onChange: (v: string): void => {
            this.envKey = v;
          }
        })
        Column() {
          DockerDialogField({
            label: L10n.t('docker_value', '值'),
            value: this.value,
            onChange: (v: string): void => {
              this.value = v;
            }
          })
        }
        .margin({ top: 12 })
        .width('100%')
      }
      .margin({ top: 14 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.save,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          if (this.envKey.trim().length === 0) {
            ToastUtil.show(L10n.t('docker_key_required', '键不能为空'));
            return;
          }
          this.p.onConfirmed(new DockerEnvVar(this.envKey.trim(), this.value));
          this.p.onResult(undefined);
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 280, maxWidth: 420 })
  }
}

// ============================================================
// 端口映射编辑子弹窗（对齐 Flutter _showPortBindingEditorDialog）
// ============================================================

class DockerPortEditorParams extends DialogParamsBase {
  initial: DockerPortBinding | undefined = undefined;
  onConfirmed: (v: DockerPortBinding) => void = (_v: DockerPortBinding): void => {
  };
}

@Builder
function DockerPortEditorContent(p: DockerPortEditorParams) {
  DockerPortEditorInner({ p: p })
}

@ComponentV2
struct DockerPortEditorInner {
  @Param p: DockerPortEditorParams = new DockerPortEditorParams();
  @Local hostIp: string = '0.0.0.0';
  @Local hostPort: string = '';
  @Local containerPort: string = '';
  @Local protocol: string = 'tcp';

  aboutToAppear(): void {
    if (this.p.initial !== undefined) {
      this.hostIp = this.p.initial.hostIp.length > 0 ? this.p.initial.hostIp : '0.0.0.0';
      this.hostPort = this.p.initial.hostPort;
      this.containerPort = this.p.initial.containerPort;
      this.protocol = this.p.initial.protocol;
    }
  }

  private pickProtocol(): void {
    const options: PickOption[] = [
      new PickOption('tcp', 'TCP'),
      new PickOption('udp', 'UDP')
    ];
    showOptionPickSheet(L10n.t('docker_protocol', '协议'), options, this.protocol, (key: string): void => {
      this.protocol = key;
    });
  }

  build() {
    Column() {
      Text(this.p.initial === undefined
        ? `${L10n.t('add', '添加')} ${L10n.t('docker_ports', '端口映射')}`
        : `${L10n.edit} ${L10n.t('docker_ports', '端口映射')}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Column() {
        DockerDialogField({
          label: L10n.t('docker_host_ip', '主机 IP'),
          value: this.hostIp,
          onChange: (v: string): void => {
            this.hostIp = v;
          }
        })
        Row({ space: 12 }) {
          Column() {
            DockerDialogField({
              label: L10n.t('docker_host_port', '主机端口'),
              value: this.hostPort,
              onChange: (v: string): void => {
                this.hostPort = v;
              }
            })
          }
          .layoutWeight(1)
          Column() {
            DockerDialogField({
              label: L10n.t('docker_container_port', '容器端口'),
              value: this.containerPort,
              onChange: (v: string): void => {
                this.containerPort = v;
              }
            })
          }
          .layoutWeight(1)
        }
        .margin({ top: 12 })
        .width('100%')
        Column() {
          DockerDialogSelectField({
            label: L10n.t('docker_protocol', '协议'),
            value: this.protocol.toUpperCase(),
            onPick: (): void => {
              this.pickProtocol();
            }
          })
        }
        .margin({ top: 12 })
        .width('100%')
      }
      .margin({ top: 14 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.save,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          const hostPort = Number(this.hostPort.trim());
          const containerPort = Number(this.containerPort.trim());
          const hostOk = this.hostPort.trim().length > 0 && Number.isInteger(hostPort);
          const containerOk = this.containerPort.trim().length > 0 && Number.isInteger(containerPort);
          if (!hostOk || !containerOk) {
            ToastUtil.show(L10n.t('docker_port_invalid', '端口填写无效'));
            return;
          }
          const result = new DockerPortBinding();
          result.hostIp = this.hostIp.trim();
          result.hostPort = this.hostPort.trim();
          result.containerPort = this.containerPort.trim();
          result.protocol = this.protocol;
          this.p.onConfirmed(result);
          this.p.onResult(undefined);
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 280, maxWidth: 460 })
  }
}

// ============================================================
// 卷挂载编辑子弹窗（对齐 Flutter _showVolumeBindingEditorDialog）
// ============================================================

class DockerVolumeEditorParams extends DialogParamsBase {
  initial: DockerMountInfo | undefined = undefined;
  onConfirmed: (v: DockerMountInfo) => void = (_v: DockerMountInfo): void => {
  };
}

@Builder
function DockerVolumeEditorContent(p: DockerVolumeEditorParams) {
  DockerVolumeEditorInner({ p: p })
}

@ComponentV2
struct DockerVolumeEditorInner {
  @Param p: DockerVolumeEditorParams = new DockerVolumeEditorParams();
  @Local source: string = '';
  @Local target: string = '';
  @Local readOnly: boolean = false;

  aboutToAppear(): void {
    if (this.p.initial !== undefined) {
      this.source = this.p.initial.source;
      this.target = this.p.initial.target;
      this.readOnly = this.p.initial.readOnly;
    }
  }

  private pickSource(): void {
    pickTargetFolderViaSheet('', (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const path = paths[0].trim();
      if (path.length === 0) {
        return;
      }
      this.source = path;
    });
  }

  build() {
    Column() {
      Text(this.p.initial === undefined
        ? `${L10n.t('add', '添加')} ${L10n.t('docker_mounts', '卷挂载')}`
        : `${L10n.edit} ${L10n.t('docker_mounts', '卷挂载')}`)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Column() {
        DockerDialogPathField({
          label: L10n.t('source', '来源'),
          hint: L10n.t('docker_mounts_hint', '每行一个 /host/path:/container/path[:ro]'),
          path: this.source,
          onPick: (): void => {
            this.pickSource();
          }
        })
        Column() {
          DockerDialogField({
            label: L10n.t('docker_target_path', '容器内路径'),
            value: this.target,
            onChange: (v: string): void => {
              this.target = v;
            }
          })
        }
        .margin({ top: 12 })
        .width('100%')
        Row({ space: 10 }) {
          CircleCheckbox({
            value: this.readOnly,
            onChanged: (c: boolean): void => {
              this.readOnly = c;
            }
          })
          Text(L10n.t('docker_read_only', '只读'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
        }
        .margin({ top: 12 })
        .width('100%')
      }
      .margin({ top: 14 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.save,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          if (this.source.trim().length === 0 || this.target.trim().length === 0) {
            ToastUtil.show(L10n.t('docker_volume_source_target_required', '来源路径和容器内路径不能为空'));
            return;
          }
          const result = new DockerMountInfo();
          result.source = this.source.trim();
          result.target = this.target.trim();
          result.readOnly = this.readOnly;
          this.p.onConfirmed(result);
          this.p.onResult(undefined);
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 280, maxWidth: 460 })
  }
}

// ============================================================
// 创建容器弹窗（对齐 Flutter _showCreateContainerDialog）
// ============================================================

/** 将环境变量列表转为请求体数组 */
function envToRecords(items: DockerEnvVar[]): Array<Record<string, Object>> {
  const arr: Array<Record<string, Object>> = [];
  items.forEach((item: DockerEnvVar): void => {
    const rec: Record<string, Object> = { 'key': item.key, 'value': item.value };
    arr.push(rec);
  });
  return arr;
}

/** 将端口映射列表转为请求体数组（hostPort/containerPort 为数字） */
function portsToRecords(items: DockerPortBinding[]): Array<Record<string, Object>> {
  const arr: Array<Record<string, Object>> = [];
  items.forEach((item: DockerPortBinding): void => {
    const rec: Record<string, Object> = {
      'hostIp': item.hostIp,
      'hostPort': Number(item.hostPort),
      'containerPort': Number(item.containerPort),
      'protocol': item.protocol
    };
    arr.push(rec);
  });
  return arr;
}

/** 将卷挂载列表转为请求体数组 */
function volumesToRecords(items: DockerMountInfo[]): Array<Record<string, Object>> {
  const arr: Array<Record<string, Object>> = [];
  items.forEach((item: DockerMountInfo): void => {
    const rec: Record<string, Object> = {
      'source': item.source,
      'target': item.target,
      'readOnly': item.readOnly
    };
    arr.push(rec);
  });
  return arr;
}

class DockerCreateContainerParams extends DialogParamsBase {
  ctrl: DockerController = new DockerController();
  imageOptions: DockerImageOption[] = [];
}

@Builder
function DockerCreateContainerContent(p: DockerCreateContainerParams) {
  DockerCreateContainerInner({ p: p })
}

@ComponentV2
struct DockerCreateContainerInner {
  @Param p: DockerCreateContainerParams = new DockerCreateContainerParams();
  @Local selectedImageId: string = '';
  @Local restartPolicy: string = 'unless-stopped';
  @Local advancedMode: boolean = false;
  @Local name: string = '';
  @Local command: string = '';
  @Local cpu: string = '';
  @Local memory: string = '';
  @Local envItems: DockerEnvVar[] = [];
  @Local portItems: DockerPortBinding[] = [];
  @Local volumeItems: DockerMountInfo[] = [];
  @Local submitting: boolean = false;

  aboutToAppear(): void {
    if (this.p.imageOptions.length > 0) {
      this.selectedImageId = this.p.imageOptions[0].id;
    }
  }

  private selectedImage(): DockerImageOption | undefined {
    for (const opt of this.p.imageOptions) {
      if (opt.id === this.selectedImageId) {
        return opt;
      }
    }
    return undefined;
  }

  private pickImage(): void {
    const options: PickOption[] = [];
    this.p.imageOptions.forEach((opt: DockerImageOption): void => {
      options.push(new PickOption(opt.id, opt.label));
    });
    showOptionPickSheet(L10n.t('docker_image_name', '镜像名称'), options, this.selectedImageId,
      (key: string): void => {
        this.selectedImageId = key;
      });
  }

  private pickRestartPolicy(): void {
    const options: PickOption[] = [];
    DOCKER_RESTART_POLICY_OPTIONS.forEach((opt): void => {
      options.push(new PickOption(opt.value, restartPolicyLabel(opt.value)));
    });
    showOptionPickSheet(L10n.t('docker_restart_policy', '重启策略'), options, this.restartPolicy,
      (key: string): void => {
        this.restartPolicy = key;
      });
  }

  private showPortEditor(initial: DockerPortBinding | undefined, index: number): void {
    const params = new DockerPortEditorParams();
    params.initial = initial;
    params.onConfirmed = (v: DockerPortBinding): void => {
      const next = this.portItems.slice();
      if (index >= 0) {
        next.splice(index, 1, v);
      } else {
        next.push(v);
      }
      this.portItems = next;
    };
    DialogUtil.openCustom<DockerPortEditorParams>(params, wrapBuilder(DockerPortEditorContent), true);
  }

  private showVolumeEditor(initial: DockerMountInfo | undefined, index: number): void {
    const params = new DockerVolumeEditorParams();
    params.initial = initial;
    params.onConfirmed = (v: DockerMountInfo): void => {
      const next = this.volumeItems.slice();
      if (index >= 0) {
        next.splice(index, 1, v);
      } else {
        next.push(v);
      }
      this.volumeItems = next;
    };
    DialogUtil.openCustom<DockerVolumeEditorParams>(params, wrapBuilder(DockerVolumeEditorContent), true);
  }

  private showEnvEditor(initial: DockerEnvVar | undefined, index: number): void {
    const params = new DockerEnvEditorParams();
    params.initial = initial;
    params.onConfirmed = (v: DockerEnvVar): void => {
      const next = this.envItems.slice();
      if (index >= 0) {
        next.splice(index, 1, v);
      } else {
        next.push(v);
      }
      this.envItems = next;
    };
    DialogUtil.openCustom<DockerEnvEditorParams>(params, wrapBuilder(DockerEnvEditorContent), true);
  }

  private async submit(): Promise<void> {
    const chosen = this.selectedImage();
    if (chosen === undefined) {
      ToastUtil.show(L10n.t('docker_image_name_required', '请先输入镜像名称'));
      return;
    }
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const resources: Record<string, Object> = { 'cpus': this.cpu.trim(), 'memory': this.memory.trim() };
    const body: Record<string, Object> = {
      'image': chosen.repository,
      'tag': chosen.tag,
      'name': this.name.trim(),
      'command': this.command.trim(),
      'restartPolicy': this.restartPolicy,
      'env': envToRecords(this.envItems),
      'ports': portsToRecords(this.portItems),
      'volumes': volumesToRecords(this.volumeItems),
      'resources': resources
    };
    const ok = await this.p.ctrl.createContainer(body);
    this.submitting = false;
    if (ok) {
      this.p.onResult(undefined);
    }
  }

  @Builder
  ListSection(title: string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Text(subtitle)
        .fontSize(11)
        .fontColor(AppTheme.current().subText)
        .margin({ top: 4 })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      Text(L10n.t('docker_create_container', '创建容器'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Scroll() {
        Column() {
          DockerDialogSelectField({
            label: L10n.t('docker_image_name', '镜像名称'),
            value: this.selectedImage() !== undefined ? this.selectedImage()!.label : '--',
            isEnabled: this.p.imageOptions.length > 0,
            onPick: (): void => {
              this.pickImage();
            }
          })
          if (this.selectedImage() !== undefined) {
            Text(`SHA256: ${this.selectedImage()!.id}`)
              .fontSize(11)
              .fontColor(AppTheme.current().subText)
              .copyOption(CopyOptions.InApp)
              .margin({ top: 8 })
              .width('100%')
          }
          if (this.p.imageOptions.length === 0) {
            Text(L10n.t('docker_no_local_image', '暂无本地镜像可用，请先拉取镜像'))
              .fontSize(12)
              .fontColor(AppTheme.current().error)
              .margin({ top: 8 })
              .width('100%')
          }
          Column() {
            DockerModeToggle({
              advanced: this.advancedMode,
              onChanged: (v: boolean): void => {
                this.advancedMode = v;
              }
            })
          }
          .margin({ top: 12, bottom: 10 })
          .width('100%')
          DockerDialogField({
            label: L10n.t('docker_container_name', '容器名称'),
            value: this.name,
            onChange: (v: string): void => {
              this.name = v;
            }
          })
          Column() {
            DockerDialogSelectField({
              label: L10n.t('docker_restart_policy', '重启策略'),
              value: restartPolicyLabel(this.restartPolicy),
              onPick: (): void => {
                this.pickRestartPolicy();
              }
            })
          }
          .margin({ top: 12 })
          .width('100%')
          Column() {
            this.ListSection(L10n.t('docker_ports', '端口映射'),
              L10n.t('docker_ports_section_hint', '把主机端口映射到容器端口，可按需逐条添加'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.portItems, (item: DockerPortBinding, idx: number): void => {
                DockerEditorTag({
                  label: `${item.hostIp.length > 0 ? `${item.hostIp}:` : ''}${item.hostPort} -> ${item.containerPort}`,
                  onTap: (): void => {
                    this.showPortEditor(item, idx);
                  },
                  onDelete: (): void => {
                    const next = this.portItems.slice();
                    next.splice(idx, 1);
                    this.portItems = next;
                  }
                })
              }, (item: DockerPortBinding, idx: number): string => `${idx}_${item.hostPort}_${item.containerPort}`)
              DockerAddTag({
                label: `${L10n.t('add', '添加')} ${L10n.t('docker_ports', '端口映射')}`,
                onTap: (): void => {
                  this.showPortEditor(undefined, -1);
                }
              })
            }
            .margin({ top: 10 })
            .width('100%')
          }
          .margin({ top: 16 })
          .width('100%')
          Column() {
            this.ListSection(L10n.t('docker_mounts', '卷挂载'),
              L10n.t('docker_mounts_section_hint', '把服务器目录挂载到容器目录，可按需逐条添加'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.volumeItems, (item: DockerMountInfo, idx: number): void => {
                DockerEditorTag({
                  label: `${item.source} -> ${item.target}(${item.readOnly
                    ? L10n.t('docker_read_only', '只读') : L10n.t('docker_read_write', '读写')})`,
                  onTap: (): void => {
                    this.showVolumeEditor(item, idx);
                  },
                  onDelete: (): void => {
                    const next = this.volumeItems.slice();
                    next.splice(idx, 1);
                    this.volumeItems = next;
                  }
                })
              }, (item: DockerMountInfo, idx: number): string => `${idx}_${item.source}_${item.target}`)
              DockerAddTag({
                label: `${L10n.t('add', '添加')} ${L10n.t('docker_mounts', '卷挂载')}`,
                onTap: (): void => {
                  this.showVolumeEditor(undefined, -1);
                }
              })
            }
            .margin({ top: 10 })
            .width('100%')
          }
          .margin({ top: 16 })
          .width('100%')
          if (this.advancedMode) {
            Text(L10n.t('docker_advanced_mode', '高级模式'))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
              .margin({ top: 16 })
              .width('100%')
            Text(L10n.t('docker_advanced_mode_hint',
              '用于设置启动命令、资源限制和环境变量等高级参数'))
              .fontSize(11)
              .fontColor(AppTheme.current().subText)
              .margin({ top: 4 })
              .width('100%')
            Column() {
              DockerDialogField({
                label: L10n.t('docker_container_command', '启动命令'),
                hint: L10n.t('docker_container_command_hint', '可选，例如 /bin/sh -c "echo hello"'),
                value: this.command,
                onChange: (v: string): void => {
                  this.command = v;
                }
              })
            }
            .margin({ top: 10 })
            .width('100%')
            Row({ space: 12 }) {
              Column() {
                DockerDialogField({
                  label: L10n.t('docker_cpu_limit', 'CPU 限制'),
                  hint: L10n.t('docker_cpu_limit_hint', '例如 1.5'),
                  value: this.cpu,
                  onChange: (v: string): void => {
                    this.cpu = v;
                  }
                })
              }
              .layoutWeight(1)
              Column() {
                DockerDialogField({
                  label: L10n.t('docker_memory_limit', '内存限制'),
                  hint: L10n.t('docker_memory_limit_hint', '例如 512m、2g'),
                  value: this.memory,
                  onChange: (v: string): void => {
                    this.memory = v;
                  }
                })
              }
              .layoutWeight(1)
            }
            .margin({ top: 12 })
            .width('100%')
            Column() {
              this.ListSection(L10n.t('docker_env_vars', '环境变量'),
                L10n.t('docker_env_vars_section_hint', '为容器添加环境变量，可按需逐条添加'))
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.envItems, (item: DockerEnvVar, idx: number): void => {
                  DockerEditorTag({
                    label: `${item.key}=${item.value}`,
                    onTap: (): void => {
                      this.showEnvEditor(item, idx);
                    },
                    onDelete: (): void => {
                      const next = this.envItems.slice();
                      next.splice(idx, 1);
                      this.envItems = next;
                    }
                  })
                }, (item: DockerEnvVar, idx: number): string => `${idx}_${item.key}`)
                DockerAddTag({
                  label: `${L10n.t('add', '添加')} ${L10n.t('docker_env_vars', '环境变量')}`,
                  onTap: (): void => {
                    this.showEnvEditor(undefined, -1);
                  }
                })
              }
              .margin({ top: 10 })
              .width('100%')
            }
            .margin({ top: 16 })
            .width('100%')
          }
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .margin({ top: 14 })
      .width('100%')
      DockerDialogActions({
        confirmText: L10n.t('create', '创建'),
        isEnabled: !this.submitting,
        onCancel: (): void => {
          this.p.onResult(undefined);
        },
        onConfirm: (): void => {
          void this.submit();
        }
      })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('90%')
  }
}

/** 打开创建容器弹窗（镜像可选项在打开时快照，对齐 Flutter 行为） */
export function showDockerCreateContainerDialog(ctrl: DockerController): void {
  const p = new DockerCreateContainerParams();
  p.ctrl = ctrl;
  p.imageOptions = buildDockerImageOptions(ctrl.images.slice());
  DialogUtil.openCustom<DockerCreateContainerParams>(p, wrapBuilder(DockerCreateContainerContent), false);
}
