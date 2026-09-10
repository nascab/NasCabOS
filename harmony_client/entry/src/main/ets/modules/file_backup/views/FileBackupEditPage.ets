import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { DialogUtil } from '../../../common/DialogUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';
import { FileBackupController } from '../controllers/FileBackupController';
import { FileBackupEditPageParam } from '../router/FileBackupRoutes';
import { BackupTask, parseIntOr } from '../models/FileBackupModels';

/** 频率上下限（小时，对齐 Flutter _minFreqHours/_maxFreqHours） */
const MIN_FREQ_HOURS: number = 1;
const MAX_FREQ_HOURS: number = 8760;

/**
 * 备份任务 新增/编辑页（对齐 Flutter _ServerBackupDialog，对话框转为移动端编辑页，功能不变）：
 * 源目录 chips（多选追加/单个移除）+ 目标目录（选目录）+ 模式（复制/同步）+ 频率（±1 小时）
 * + 排除列表（换行/逗号分隔）。运行中任务所有字段锁定（对齐 enabled: !_isRunning && !_saving）。
 */
@ComponentV2
export struct FileBackupEditPage {
  @Param param: FileBackupEditPageParam = new FileBackupEditPageParam();
  @Param popPage: () => void = (): void => {
  };
  private ctrl: FileBackupController = new FileBackupController();

  @Local sources: string[] = [];
  @Local targetText: string = '';
  @Local type: string = 'copy';
  @Local freqText: string = '24';
  @Local excludeText: string = '';
  @Local saving: boolean = false;

  private get isEdit(): boolean {
    return this.param.initial !== undefined;
  }

  private get isRunning(): boolean {
    return this.param.initial !== undefined && this.param.initial.status === 'running';
  }

  private get locked(): boolean {
    return this.isRunning || this.saving;
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  aboutToAppear(): void {
    const init: BackupTask | undefined = this.param.initial;
    if (init === undefined) {
      return;
    }
    this.sources = init.sourcePath.slice();
    this.type = init.type === 'sync' ? 'sync' : 'copy';
    this.targetText = init.targetPath;
    // 对齐 Flutter int.tryParse(...) ?? 24：非法/缺失时取 24
    this.freqText = init.frenquence > 0 ? `${init.frenquence}` : '24';
    this.excludeText = init.excludeList.join('\n');
  }

  // ===== 交互（对齐 Flutter _pickSources/_pickTarget/_stepFreq/_submit） =====

  private pickSources(): void {
    const initial = this.sources.length > 0 ? this.sources[0] : '';
    pickTargetFolderViaSheet(initial, (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      // 追加去重（对齐 Flutter merged/seen 逻辑）
      const seen = new Set<string>();
      const merged: string[] = [];
      const combine = this.sources.concat(paths);
      combine.forEach((p: string): void => {
        const v = p.trim();
        if (v.length === 0 || seen.has(v)) {
          return;
        }
        seen.add(v);
        merged.push(v);
      });
      if (merged.length === 0) {
        return;
      }
      this.sources = merged;
    }, true);
  }

  private removeSource(path: string): void {
    this.sources = this.sources.filter((e: string): boolean => e !== path);
  }

  private pickTarget(): void {
    pickTargetFolderViaSheet(this.targetText.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      this.targetText = paths[0];
    });
  }

  private pickType(): void {
    const options: PickOption[] = [
      new PickOption('copy', L10n.t('file_backup_type_copy', '复制')),
      new PickOption('sync', L10n.t('file_backup_type_sync', '同步'))
    ];
    showOptionPickSheet(L10n.t('file_backup_type', '模式'), options, this.type,
      (key: string): void => {
        if (key !== 'copy' && key !== 'sync') {
          return;
        }
        this.type = key;
      });
  }

  private clampFreq(v: number): number {
    if (v < MIN_FREQ_HOURS) {
      return MIN_FREQ_HOURS;
    }
    if (v > MAX_FREQ_HOURS) {
      return MAX_FREQ_HOURS;
    }
    return v;
  }

  private stepFreq(delta: number): void {
    const current = parseIntOr(this.freqText, 0);
    const next = this.clampFreq((current <= 0 ? MIN_FREQ_HOURS : current) + delta);
    this.freqText = `${next}`;
  }

  /** 排除列表解析（对齐 Flutter _parseExcludeList：按换行/逗号拆分，去空白） */
  private parseExcludeList(text: string): string[] {
    const t = text.trim();
    if (t.length === 0) {
      return [];
    }
    const out: string[] = [];
    t.split(/[\n,]/).forEach((e: string): void => {
      const v = e.trim();
      if (v.length > 0) {
        out.push(v);
      }
    });
    return out;
  }

  /** 提交（对齐 Flutter _submit：校验 → loading → upsert → 成功返回） */
  private async submit(): Promise<void> {
    if (this.saving) {
      return;
    }
    const init = this.param.initial;
    const id = this.isEdit && init !== undefined && init.id > 0 ? init.id : undefined;
    const target = this.targetText.trim();
    const freq = this.clampFreq(parseIntOr(this.freqText.trim(), 0));
    const excludes = this.parseExcludeList(this.excludeText);

    if (this.sources.length === 0 || target.length === 0 || freq <= 0) {
      void DialogUtil.showErrorDialog(L10n.t('file_backup_required', '源目录/目标目录/频率不能为空'));
      return;
    }

    this.freqText = `${freq}`;

    this.saving = true;
    void DialogUtil.showLoading(L10n.loading);
    try {
      const ok = await this.ctrl.upsert(id, this.sources, this.type, target, freq, excludes);
      if (ok) {
        this.popPage();
        return;
      }
    } finally {
      void DialogUtil.dismissLoading(true);
      this.saving = false;
    }
  }

  build() {
    PageScaffold({
      title: this.isEdit
        ? L10n.t('file_backup_edit', '编辑任务')
        : L10n.t('file_backup_create', '新增任务'),
      showBack: true,
      statusBarBg: AppTheme.current().pageBg,
      // 保存中阻止返回（对齐 Flutter WillPopScope onWillPop: !_saving）
      customBack: (): boolean => {
        return this.saving;
      },
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.FormBody()
      }
    })
  }

  @Builder
  FormBody() {
    Column() {
      Scroll() {
        Column({ space: 14 }) {
          // 源目录 chips（对齐 Flutter InputChip + ActionChip）
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.sources, (p: string) => {
              Row({ space: 5 }) {
                Text(p)
                  .fontSize(12)
                  .fontColor(this.palette().onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 220 })
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(11)
                  .fontColor([this.palette().hint])
                  .onClick((): void => {
                    if (!this.locked) {
                      this.removeSource(p);
                    }
                  })
              }
              .padding({ left: 10, right: 8, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor(this.palette().inputFill)
              .border({ width: 1, color: this.palette().divider })
              .margin({ right: 6, bottom: 6 })
            }, (p: string): string => p)
            Row({ space: 5 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(13)
                .fontColor([this.palette().primary])
              Text(L10n.t('file_backup_pick_source', '选择源目录'))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().primary)
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(16)
            .border({ width: 1, color: this.palette().primary })
            .margin({ right: 6, bottom: 6 })
            .opacity(this.locked ? 0.45 : 1)
            .onClick((): void => {
              if (!this.locked) {
                this.pickSources();
              }
            })
          }
          .width('100%')

          // 目标目录（只读 + 点击选目录，对齐 Flutter readOnly + suffix folder）
          Column({ space: 6 }) {
            Text(L10n.t('file_backup_target_path', '目标目录'))
              .fontSize(13)
              .fontColor(this.palette().subText)
            Row({ space: 8 }) {
              Text(this.targetText.trim().length > 0 ? this.targetText
                : L10n.t('file_backup_pick_target', '选择目标目录'))
                .fontSize(14)
                .fontColor(this.targetText.trim().length > 0
                  ? this.palette().onSurface
                  : AppTheme.withAlpha(this.palette().onSurface, 0.5))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(18)
                .fontColor([this.palette().primary])
            }
            .width('100%')
            .height(42)
            .padding({ left: 12, right: 12 })
            .borderRadius(8)
            .backgroundColor(this.palette().inputFill)
            .border({ width: 1, color: this.palette().inputBorder })
            .opacity(this.locked ? 0.5 : 1)
            .onClick((): void => {
              if (!this.locked) {
                this.pickTarget();
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // 模式（对齐 Flutter CustomDropdownField，鸿蒙端以底部弹层选择）
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text(this.type === 'sync'
                ? L10n.t('file_backup_type_sync', '同步')
                : L10n.t('file_backup_type_copy', '复制'))
                .fontSize(14)
                .fontColor(this.palette().onSurface)
                .maxLines(1)
                .layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(14)
                .fontColor([this.palette().hint])
            }
            .width('100%')
            .height(42)
            .padding({ left: 12, right: 12 })
            .borderRadius(8)
            .backgroundColor(this.palette().inputFill)
            .border({ width: 1, color: this.palette().inputBorder })
            .opacity(this.locked ? 0.5 : 1)
            .onClick((): void => {
              if (!this.locked) {
                this.pickType();
              }
            })
            Text(this.type === 'sync'
              ? L10n.t('file_backup_type_desc_sync',
                '同步：使目标存储和源存储完全一致，会删除目标中源没有的文件')
              : L10n.t('file_backup_type_desc_copy',
                '复制：仅复制源中存在、目标中不存在/更新的文件，不删除目标多余文件'))
              .fontSize(12)
              .fontColor(AppTheme.withAlpha(this.palette().onSurface, 0.6))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // 频率（数字输入 + ±1 按钮，对齐 Flutter CustomTextField + CustomIconButton）
          Row({ space: 8 }) {
            Column({ space: 6 }) {
              Text(L10n.t('file_backup_frequency_hours', '频率(小时)'))
                .fontSize(13)
                .fontColor(this.palette().subText)
              TextInput({ text: this.freqText, placeholder: L10n.inputPlease })
                .type(InputType.Number)
                .fontSize(14)
                .fontColor(this.palette().onSurface)
                .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
                .backgroundColor(this.palette().inputFill)
                .borderRadius(8)
                .border({ width: 1, color: this.palette().inputBorder })
                .height(42)
                .width('100%')
                .enabled(!this.locked)
                .onChange((v: string): void => {
                  this.freqText = v;
                })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            BorderedIconButton({
              icon: $r('sys.symbol.minus'),
              isEnabled: !this.locked,
              onTap: (): void => {
                this.stepFreq(-1);
              }
            })
            BorderedIconButton({
              icon: $r('sys.symbol.plus'),
              isEnabled: !this.locked,
              onTap: (): void => {
                this.stepFreq(1);
              }
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)

          // 排除列表（多行文本，对齐 Flutter CustomTextField maxLines: 4）
          Column({ space: 6 }) {
            Text(L10n.t('file_backup_exclude_list', '排除列表(一行一个)'))
              .fontSize(13)
              .fontColor(this.palette().subText)
            TextArea({ text: this.excludeText, placeholder: L10n.inputPlease })
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.5))
              .backgroundColor(this.palette().inputFill)
              .borderRadius(8)
              .border({ width: 1, color: this.palette().inputBorder })
              .height(96)
              .width('100%')
              .enabled(!this.locked)
              .onChange((v: string): void => {
                this.excludeText = v;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      this.BottomActions()
    }
    .width('100%')
    .height('100%')
  }

  /** 底部操作（对齐 Flutter dialog actions：取消 + 确定，运行中/保存中禁用确定） */
  @Builder
  BottomActions() {
    Row({ space: 12 }) {
      Button(L10n.cancel)
        .fontSize(15)
        .fontColor(this.palette().primary)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: this.palette().divider })
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .enabled(!this.saving)
        .onClick((): void => {
          this.popPage();
        })
      Button(L10n.ok)
        .fontSize(15)
        .fontColor(this.palette().buttonText)
        .backgroundColor(this.palette().buttonBg)
        .borderRadius(20)
        .height(40)
        .layoutWeight(1)
        .enabled(!this.isRunning && !this.saving)
        .opacity(this.isRunning || this.saving ? 0.5 : 1)
        .onClick((): void => {
          void this.submit();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }
}
