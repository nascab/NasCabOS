import { L10n } from '../../../../core/localization/L10n';
import { DialogUtil } from '../../../../common/DialogUtil';
import { pickTargetFolderViaSheet } from '../../../../files/views/FolderPickerSheet';
import { PickOption } from '../../../../common/components/OptionPickSheet';
import { MediaToolTaskController, buildImgBatchUpsertBody,
  parseImgBatchOutSize, parseImgBatchQuality } from '../../controllers/MediaToolControllers';
import { MediaToolTaskItem, mtAsNum } from '../../models/MediaToolModels';
import { MediaToolDialogShell, MediaToolGap, MediaToolNumberField,
  MediaToolPickField, MediaToolSelectField } from './MediaToolWidgets';

/**
 * 图片批量压缩任务新建/编辑弹窗（对齐 Flutter _ImgBatchCompressDialog）。
 * 运行中的任务禁止编辑（所有字段禁用）。
 */
@ComponentV2
export struct ImgBatchCompressDialog {
  @Param ctrl: MediaToolTaskController = new MediaToolTaskController('img_batch');
  /** 编辑目标；undefined 表示新建 */
  @Param initial: MediaToolTaskItem | undefined = undefined;
  @Param onDismiss: () => void = (): void => {
  };

  @Local sourceText: string = '';
  @Local targetText: string = '';
  @Local format: string = 'jpeg';
  @Local qualityText: string = '80';
  @Local sizeMode: string = 'keep';
  @Local customSizeText: string = '';
  @Local nonImagePolicy: string = 'skip';
  @Local saving: boolean = false;

  aboutToAppear(): void {
    const init = this.initial;
    if (init === undefined) {
      return;
    }
    this.sourceText = init.sourcePath;
    this.targetText = init.targetPath;
    const initFormat = (init.raw['out_format'] !== undefined && init.raw['out_format'] !== null
      ? `${init.raw['out_format']}` : 'jpeg').trim().toLowerCase();
    this.format = (initFormat === 'png' || initFormat === 'webp' || initFormat === 'jpeg')
      ? initFormat : 'jpeg';
    const initQ = mtAsNum(init.raw['quality']);
    this.qualityText = `${initQ === undefined ? 80
      : Math.min(100, Math.max(30, Math.round(initQ)))}`;
    const size = mtAsNum(init.raw['out_size']);
    if (size !== undefined && size > 0) {
      this.customSizeText = `${Math.round(size)}`;
      this.sizeMode = 'custom';
    }
    const pol = (init.raw['non_image_policy'] !== undefined && init.raw['non_image_policy'] !== null
      ? `${init.raw['non_image_policy']}` : 'skip').trim().toLowerCase();
    this.nonImagePolicy = pol === 'copy' ? 'copy' : 'skip';
  }

  private get disabled(): boolean {
    return this.initial !== undefined && this.initial.status === 'running' || this.saving;
  }

  private pickSource(): void {
    pickTargetFolderViaSheet(this.sourceText.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const picked = paths[0].trim();
      if (picked.length > 0) {
        this.sourceText = picked;
      }
    });
  }

  private pickTarget(): void {
    pickTargetFolderViaSheet(this.targetText.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const picked = paths[0].trim();
      if (picked.length > 0) {
        this.targetText = picked;
      }
    });
  }

  /** 质量输入（对齐 Flutter onChanged：digits-only + clamp 30..100） */
  private onQualityChange(raw: string): void {
    const digits = raw.replace(/[^0-9]/g, '');
    if (digits.length === 0) {
      if (raw.length === 0) {
        return;
      }
      this.qualityText = '';
      return;
    }
    const n = Number(digits);
    if (Number.isNaN(n)) {
      return;
    }
    const next = `${Math.min(100, Math.max(30, Math.round(n)))}`;
    if (next !== raw) {
      this.qualityText = next;
    } else {
      this.qualityText = raw;
    }
  }

  /** 自定义尺寸输入（对齐 Flutter onChanged：digits-only + clamp 10..20000，空清空） */
  private onCustomSizeChange(raw: string): void {
    const digits = raw.replace(/[^0-9]/g, '');
    if (digits.length === 0) {
      if (raw.length === 0) {
        return;
      }
      this.customSizeText = '';
      return;
    }
    const n = Number(digits);
    if (Number.isNaN(n)) {
      return;
    }
    const next = `${Math.min(20000, Math.max(10, Math.round(n)))}`;
    if (next !== raw) {
      this.customSizeText = next;
    } else {
      this.customSizeText = raw;
    }
  }

  private async submit(): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    const id = this.initial !== undefined && this.initial.id > 0 ? this.initial.id : undefined;
    const source = this.sourceText.trim();
    const target = this.targetText.trim();
    if (source.length === 0 || target.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('media_tool_img_batch_required', '请选择源路径与目标路径'));
      return false;
    }
    const outSize = this.sizeMode === 'custom' ? parseImgBatchOutSize(this.customSizeText) : undefined;
    this.saving = true;
    try {
      return await this.ctrl.upsert(buildImgBatchUpsertBody(id, source, target,
        this.format, parseImgBatchQuality(this.qualityText), outSize, this.nonImagePolicy));
    } finally {
      this.saving = false;
    }
  }

  private formatOptions(): PickOption[] {
    return [
      new PickOption('jpeg', 'JPEG'),
      new PickOption('png', 'PNG'),
      new PickOption('webp', 'WEBP')
    ];
  }

  private sizeModeOptions(): PickOption[] {
    return [
      new PickOption('keep', L10n.t('media_tool_img_batch_keep_size', '保持原尺寸')),
      new PickOption('custom', L10n.t('media_tool_custom_size', '自定义尺寸'))
    ];
  }

  private policyOptions(): PickOption[] {
    return [
      new PickOption('skip', L10n.t('skip', '跳过')),
      new PickOption('copy', L10n.t('media_tool_img_batch_non_image_copy', '复制'))
    ];
  }

  build() {
    MediaToolDialogShell({
      title: this.initial !== undefined ? L10n.edit : L10n.t('create', '新建'),
      saving: this.saving,
      onConfirm: (): Promise<boolean> => this.submit(),
      onDismiss: (): void => {
        this.onDismiss();
      }
    }) {
      Column({ space: 12 }) {
        MediaToolPickField({
          label: L10n.t('media_tool_img_batch_source', '源路径'),
          value: this.sourceText,
          hint: L10n.t('media_tool_img_batch_pick_source', '点击选择源目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickSource();
          }
        })
        MediaToolPickField({
          label: L10n.t('media_tool_img_batch_target', '目标路径'),
          value: this.targetText,
          hint: L10n.t('media_tool_img_batch_pick_target', '点击选择目标目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickTarget();
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_format', '输出格式'),
          options: this.formatOptions(),
          value: this.format,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'jpeg' || key === 'png' || key === 'webp') {
              this.format = key;
            }
          }
        })
        MediaToolNumberField({
          label: L10n.t('media_tool_quality', '质量'),
          value: this.qualityText,
          disabled: this.disabled,
          onChanged: (t: string): void => {
            this.onQualityChange(t);
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_out_size', '输出尺寸'),
          options: this.sizeModeOptions(),
          value: this.sizeMode,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'keep' || key === 'custom') {
              this.sizeMode = key;
            }
          }
        })
        if (this.sizeMode === 'custom') {
          MediaToolNumberField({
            label: L10n.t('media_tool_custom_size', '自定义尺寸'),
            hint: L10n.t('media_tool_out_size_hint', '最大边长像素（10-20000）'),
            value: this.customSizeText,
            disabled: this.disabled,
            onChanged: (t: string): void => {
              this.onCustomSizeChange(t);
            }
          })
        }
        MediaToolSelectField({
          label: L10n.t('media_tool_img_batch_non_image', '非图片文件'),
          options: this.policyOptions(),
          value: this.nonImagePolicy,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'skip' || key === 'copy') {
              this.nonImagePolicy = key;
            }
          }
        })
        MediaToolGap({ gapHeight: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
