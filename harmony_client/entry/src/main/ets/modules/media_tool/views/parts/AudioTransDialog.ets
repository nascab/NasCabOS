import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { DialogUtil } from '../../../../common/DialogUtil';
import { pickTargetFolderViaSheet, pickServerFileViaSheet } from '../../../../files/views/FolderPickerSheet';
import { PickOption } from '../../../../common/components/OptionPickSheet';
import { MediaToolTaskController, buildAudioTransConfig } from '../../controllers/MediaToolControllers';
import { MediaToolTaskItem, mtAsNum, mtParsePositiveNum } from '../../models/MediaToolModels';
import { MediaToolDialogShell, MediaToolGap, MediaToolFieldLabel, MediaToolNumberField,
  MediaToolPickField, MediaToolSelectField } from './MediaToolWidgets';

/** 支持的音频扩展名（对齐 Flutter _supportedAudioExts） */
const SUPPORTED_AUDIO_EXTS: string[] = [
  '.mp3', '.flac', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape', '.m4a'
];

function normalizeIn(raw: string, options: string[], fallback: string): string {
  const s = raw.trim().toLowerCase();
  return options.indexOf(s) >= 0 ? s : fallback;
}

/**
 * 音频转换任务新建/编辑弹窗（对齐 Flutter _AudioTransDialog）。
 * 分组：路径 / 格式（输出格式、采样率、声道）/ 高级（码率、线程数、非音频策略）。
 */
@ComponentV2
export struct AudioTransDialog {
  @Param ctrl: MediaToolTaskController = new MediaToolTaskController('audio_trans');
  @Param initial: MediaToolTaskItem | undefined = undefined;
  @Param onDismiss: () => void = (): void => {
  };

  @Local sourceText: string = '';
  @Local targetText: string = '';
  @Local format: string = 'mp3';
  @Local sampleRate: string = 'source';
  @Local channels: string = 'source';
  @Local bitrateMode: string = 'auto';
  @Local audioBitrateText: string = '';
  @Local threadCountText: string = '5';
  @Local nonAudioPolicy: string = 'skip';
  @Local saving: boolean = false;

  private get disabled(): boolean {
    return (this.initial !== undefined && this.initial.status === 'running') || this.saving;
  }

  aboutToAppear(): void {
    const init = this.initial;
    if (init === undefined) {
      return;
    }
    this.sourceText = init.sourcePath;
    this.targetText = init.targetPath;
    const pol = (init.raw['non_audio_policy'] !== undefined && init.raw['non_audio_policy'] !== null
      ? `${init.raw['non_audio_policy']}` : 'skip').trim().toLowerCase();
    this.nonAudioPolicy = pol === 'copy' ? 'copy' : 'skip';
    const cfg = init.config;
    const cfgText = (key: string): string => {
      const v = cfg[key];
      return v !== undefined && v !== null ? `${v}` : '';
    };
    this.format = normalizeIn(cfgText('out_format'),
      ['mp3', 'm4a', 'aac', 'flac', 'ogg', 'wav', 'opus', 'wma'], 'mp3');
    this.sampleRate = normalizeIn(cfgText('sample_rate'),
      ['source', '48000', '44100', '32000', '22050'], 'source');
    this.channels = normalizeIn(cfgText('channels'), ['source', 'stereo', 'mono'], 'source');
    const ab = mtAsNum(cfg['audio_bitrate_kbps']);
    const threadRaw = mtAsNum(cfg['thread_count']);
    this.threadCountText = `${Math.min(50, Math.max(1, threadRaw === undefined ? 5 : Math.round(threadRaw)))}`;
    this.bitrateMode = ab !== undefined && ab > 0 ? 'custom' : 'auto';
    this.audioBitrateText = ab === undefined ? '' : `${ab}`;
  }

  private pickSource(): void {
    pickServerFileViaSheet(this.sourceText.trim(), (paths: string[]): void => {
      if (paths.length === 0) {
        return;
      }
      const picked = paths[0].trim();
      if (picked.length === 0) {
        return;
      }
      const dot = picked.lastIndexOf('.');
      const ext = dot >= 0 ? picked.substring(dot).toLowerCase() : '';
      if (ext.length > 0 && SUPPORTED_AUDIO_EXTS.indexOf(ext) < 0) {
        DialogUtil.showErrorDialog(`${L10n.t('support_format', '支持的格式')}：${SUPPORTED_AUDIO_EXTS.join(', ')}`);
        return;
      }
      this.sourceText = picked;
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

  private buildConfig(): Record<string, Object> {
    const ab = this.bitrateMode === 'custom'
      ? mtParsePositiveNum(this.audioBitrateText, 8, 2000) : undefined;
    const threadRaw = mtAsNum(this.threadCountText);
    const threadCount = Math.min(50, Math.max(1, threadRaw === undefined ? 5 : Math.round(threadRaw)));
    this.threadCountText = `${threadCount}`;
    return buildAudioTransConfig(this.format, this.sampleRate, this.channels, ab, threadCount);
  }

  private async submit(): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    const id = this.initial !== undefined && this.initial.id > 0 ? this.initial.id : undefined;
    const source = this.sourceText.trim();
    const target = this.targetText.trim();
    if (source.length === 0 || target.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('media_tool_audio_trans_required', '请选择源路径与目标路径'));
      return false;
    }
    this.saving = true;
    try {
      const body: Record<string, Object> = {
        'source_path': source,
        'target_path': target,
        'trans_config': this.buildConfig(),
        'non_audio_policy': this.nonAudioPolicy
      };
      if (id !== undefined) {
        body['id'] = id;
      }
      return await this.ctrl.upsert(body);
    } finally {
      this.saving = false;
    }
  }

  private modeOptions(): PickOption[] {
    return [
      new PickOption('auto', L10n.t('auto', '自动')),
      new PickOption('custom', L10n.t('media_tool_custom', '自定义'))
    ];
  }

  private formatOptions(): PickOption[] {
    return [
      new PickOption('mp3', 'MP3'),
      new PickOption('m4a', 'M4A'),
      new PickOption('aac', 'AAC'),
      new PickOption('flac', 'FLAC'),
      new PickOption('ogg', 'OGG'),
      new PickOption('wav', 'WAV'),
      new PickOption('opus', 'Opus'),
      new PickOption('wma', 'WMA')
    ];
  }

  private sampleRateOptions(): PickOption[] {
    return [
      new PickOption('source', L10n.t('media_tool_audio_trans_sample_rate_source', '保持原采样率')),
      new PickOption('48000', '48000 Hz'),
      new PickOption('44100', '44100 Hz'),
      new PickOption('32000', '32000 Hz'),
      new PickOption('22050', '22050 Hz')
    ];
  }

  private channelsOptions(): PickOption[] {
    return [
      new PickOption('source', L10n.t('media_tool_audio_trans_channels_source', '保持原声道')),
      new PickOption('stereo', L10n.t('media_tool_audio_trans_channels_stereo', '立体声')),
      new PickOption('mono', L10n.t('media_tool_audio_trans_channels_mono', '单声道'))
    ];
  }

  private policyOptions(): PickOption[] {
    return [
      new PickOption('skip', L10n.t('skip', '跳过')),
      new PickOption('copy', L10n.t('media_tool_audio_trans_non_audio_copy', '复制'))
    ];
  }

  /** 分组标题（对齐 Flutter _sectionHeader） */
  @Builder
  SectionHeader(title: string, icon: Resource) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([AppTheme.current().primary])
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
    }
    .margin({ top: 4 })
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
        this.SectionHeader(L10n.t('media_tool_audio_trans_section_paths', '路径'),
          $r('sys.symbol.folder'))
        MediaToolPickField({
          label: L10n.t('media_tool_audio_trans_source', '源路径'),
          value: this.sourceText,
          hint: L10n.t('media_tool_audio_trans_pick_source', '点击选择音频文件或目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickSource();
          }
        })
        MediaToolPickField({
          label: L10n.t('media_tool_audio_trans_target', '目标路径'),
          value: this.targetText,
          hint: L10n.t('media_tool_audio_trans_pick_target', '点击选择目标目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickTarget();
          }
        })
        this.SectionHeader(L10n.t('media_tool_audio_trans_section_format', '格式'),
          $r('sys.symbol.music_note_list'))
        MediaToolSelectField({
          label: L10n.t('media_tool_audio_trans_out_format', '输出格式'),
          options: this.formatOptions(),
          value: this.format,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (this.formatOptions().some((o: PickOption): boolean => o.key === key)) {
              this.format = key;
            }
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_audio_trans_sample_rate', '采样率'),
          options: this.sampleRateOptions(),
          value: this.sampleRate,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (this.sampleRateOptions().some((o: PickOption): boolean => o.key === key)) {
              this.sampleRate = key;
            }
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_audio_trans_channels', '声道'),
          options: this.channelsOptions(),
          value: this.channels,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'source' || key === 'stereo' || key === 'mono') {
              this.channels = key;
            }
          }
        })
        this.SectionHeader(L10n.t('media_tool_audio_trans_section_advanced', '高级'),
          $r('sys.symbol.gearshape'))
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            MediaToolFieldLabel({ label: L10n.t('media_tool_audio_trans_audio_bitrate', '音频码率') })
            MediaToolSelectField({
              label: '',
              options: this.modeOptions(),
              value: this.bitrateMode,
              disabled: this.disabled,
              onChanged: (key: string): void => {
                if (key === 'auto' || key === 'custom') {
                  this.bitrateMode = key;
                }
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Column({ space: 6 }) {
            MediaToolFieldLabel({
              label: L10n.t('media_tool_audio_trans_audio_bitrate_kbps', '音频码率 (Kbps)')
            })
            MediaToolNumberField({
              label: '',
              value: this.audioBitrateText,
              disabled: this.disabled || this.bitrateMode !== 'custom',
              onChanged: (t: string): void => {
                this.audioBitrateText = t;
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        MediaToolNumberField({
          label: L10n.t('media_tool_audio_trans_thread_count', '线程数'),
          value: this.threadCountText,
          disabled: this.disabled,
          onChanged: (t: string): void => {
            this.threadCountText = t;
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_audio_trans_non_audio', '非音频文件'),
          options: this.policyOptions(),
          value: this.nonAudioPolicy,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'skip' || key === 'copy') {
              this.nonAudioPolicy = key;
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
