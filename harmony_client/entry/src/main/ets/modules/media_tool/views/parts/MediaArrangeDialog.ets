import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { DialogUtil } from '../../../../common/DialogUtil';
import { pickTargetFolderViaSheet } from '../../../../files/views/FolderPickerSheet';
import { PickOption } from '../../../../common/components/OptionPickSheet';
import { MediaToolTaskController } from '../../controllers/MediaToolControllers';
import { MediaToolTaskItem } from '../../models/MediaToolModels';
import { MediaToolDialogShell, MediaToolGap, MediaToolPickField,
  MediaToolSelectField } from './MediaToolWidgets';

/**
 * 媒体整理任务新建/编辑弹窗（对齐 Flutter _MediaArrangeDialog）。
 * 运行中的任务显示编辑提示且所有控件禁用。
 */
@ComponentV2
export struct MediaArrangeDialog {
  @Param ctrl: MediaToolTaskController = new MediaToolTaskController('media_arrange');
  @Param initial: MediaToolTaskItem | undefined = undefined;
  @Param onDismiss: () => void = (): void => {
  };

  @Local sourceText: string = '';
  @Local targetText: string = '';
  @Local arrangeType: string = 'day';
  @Local sameNamePolicy: string = 'rename';
  @Local saving: boolean = false;

  private get isRunning(): boolean {
    return this.initial !== undefined && this.initial.status === 'running';
  }

  private get disabled(): boolean {
    return this.isRunning || this.saving;
  }

  aboutToAppear(): void {
    const init = this.initial;
    if (init === undefined) {
      return;
    }
    this.sourceText = init.sourcePath;
    this.targetText = init.targetPath;
    const type = (init.raw['arrange_type'] !== undefined && init.raw['arrange_type'] !== null
      ? `${init.raw['arrange_type']}` : 'day').trim().toLowerCase();
    if (type === 'year' || type === 'month' || type === 'day') {
      this.arrangeType = type;
    }
    const pol = (init.raw['same_name_policy'] !== undefined && init.raw['same_name_policy'] !== null
      ? `${init.raw['same_name_policy']}` : 'rename').trim().toLowerCase();
    if (pol === 'skip' || pol === 'rename' || pol === 'overwrite') {
      this.sameNamePolicy = pol;
    }
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

  private async submit(): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    const s = this.sourceText.trim();
    const t = this.targetText.trim();
    if (s.length === 0 || t.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('media_tool_arrange_required', '请选择源路径与目标路径'));
      return false;
    }
    this.saving = true;
    try {
      const body: Record<string, Object> = {
        'source_path': s,
        'target_path': t,
        'arrange_type': this.arrangeType,
        'same_name_policy': this.sameNamePolicy
      };
      if (this.initial !== undefined && this.initial.id > 0) {
        body['id'] = this.initial.id;
      }
      const ok = await this.ctrl.upsert(body);
      return ok;
    } finally {
      this.saving = false;
    }
  }

  private typeOptions(): PickOption[] {
    return [
      new PickOption('year', L10n.t('media_tool_arrange_type_year', '按年整理')),
      new PickOption('month', L10n.t('media_tool_arrange_type_month', '按年月整理')),
      new PickOption('day', L10n.t('media_tool_arrange_type_day', '按年月日整理'))
    ];
  }

  private policyOptions(): PickOption[] {
    return [
      new PickOption('skip', L10n.t('skip', '跳过')),
      new PickOption('rename', L10n.t('rename', '重命名')),
      new PickOption('overwrite', L10n.t('overwrite', '覆盖'))
    ];
  }

  build() {
    MediaToolDialogShell({
      title: this.initial !== undefined
        ? L10n.edit
        : `${L10n.t('create', '新建')} ${L10n.t('media_tool_menu_media_arrange', '媒体整理')}`,
      saving: this.saving,
      confirmText: this.saving
        ? L10n.t('media_tool_arrange_saving', '保存中...')
        : L10n.ok,
      onConfirm: (): Promise<boolean> => this.submit(),
      onDismiss: (): void => {
        this.onDismiss();
      }
    }) {
      Column({ space: 12 }) {
        if (this.isRunning) {
          Text(L10n.t('media_tool_arrange_status_running_edit_hint',
            '任务运行中，暂不能修改配置'))
            .fontSize(12)
            .fontColor(AppTheme.current().error)
            .width('100%')
        }
        MediaToolPickField({
          label: L10n.t('media_tool_arrange_source', '源路径'),
          value: this.sourceText,
          hint: L10n.t('media_tool_arrange_pick_source', '点击选择源目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickSource();
          }
        })
        MediaToolPickField({
          label: L10n.t('media_tool_arrange_target', '目标路径'),
          value: this.targetText,
          hint: L10n.t('media_tool_arrange_pick_target', '点击选择目标目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickTarget();
          }
        })
        Text(L10n.t('media_tool_arrange_target_hint',
          '整理结果将按所选时间粒度建立子目录归类'))
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .width('100%')
          .margin({ top: -6 })
        MediaToolSelectField({
          label: L10n.t('media_tool_arrange_type', '整理方式'),
          options: this.typeOptions(),
          value: this.arrangeType,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'year' || key === 'month' || key === 'day') {
              this.arrangeType = key;
            }
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_arrange_same_name_policy', '同名文件策略'),
          options: this.policyOptions(),
          value: this.sameNamePolicy,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'skip' || key === 'rename' || key === 'overwrite') {
              this.sameNamePolicy = key;
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
