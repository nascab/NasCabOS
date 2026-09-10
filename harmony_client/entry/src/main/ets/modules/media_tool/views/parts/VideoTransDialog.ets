import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { DialogUtil } from '../../../../common/DialogUtil';
import { pickTargetFolderViaSheet, pickServerFileViaSheet } from '../../../../files/views/FolderPickerSheet';
import { PickOption } from '../../../../common/components/OptionPickSheet';
import { MediaToolTaskController, buildVideoTransConfig } from '../../controllers/MediaToolControllers';
import { MediaToolTaskItem, mtAsNum, mtParsePositiveNum } from '../../models/MediaToolModels';
import { MediaToolDialogShell, MediaToolGap, MediaToolNumberField,
  MediaToolPickField, MediaToolSelectField, MediaToolSwitchRow } from './MediaToolWidgets';

/** 支持的视频扩展名（对齐 Flutter _supportedVideoExts） */
const SUPPORTED_VIDEO_EXTS: string[] = [
  '.mov', '.mp4', '.avi', '.rm', '.mkv', '.f4v', '.vob', '.mpg', '.rmvb',
  '.asf', '.mts', '.ts', '.wmv', '.m4v', '.m2ts', '.ogg', '.3gp', '.flv'
];

function normalizeIn(raw: string, options: string[], fallback: string): string {
  const s = raw.trim().toLowerCase();
  return options.indexOf(s) >= 0 ? s : fallback;
}

/** 取 trans_config 字段字符串（缺省/空回退 ''，对齐 AudioTransDialog 内的 cfgText） */
function cfgText(cfg: Record<string, Object>, key: string): string {
  const v = cfg[key];
  return v !== undefined && v !== null ? `${v}` : '';
}

/**
 * 视频转换任务新建/编辑弹窗（对齐 Flutter _VideoTransDialog）。
 * GIF/WebP 动图模式隐藏视频/音频编码与码率项，分辨率选项收窄，帧率范围 5-20。
 */
@ComponentV2
export struct VideoTransDialog {
  @Param ctrl: MediaToolTaskController = new MediaToolTaskController('video_trans');
  @Param initial: MediaToolTaskItem | undefined = undefined;
  @Param onDismiss: () => void = (): void => {
  };

  @Local sourceText: string = '';
  @Local targetText: string = '';
  @Local format: string = 'mp4';
  @Local vcodec: string = 'h264';
  @Local acodec: string = 'aac';
  @Local resolution: string = 'source';
  @Local videoBitrateMode: string = 'auto';
  @Local audioBitrateMode: string = 'auto';
  @Local fpsMode: string = 'auto';
  @Local nonVideoPolicy: string = 'skip';
  @Local enableHwAccel: boolean = true;
  @Local videoBitrateText: string = '';
  @Local audioBitrateText: string = '';
  @Local fpsText: string = '';
  @Local threadCountText: string = '5';
  @Local saving: boolean = false;

  private get isAnimated(): boolean {
    return this.format === 'gif' || this.format === 'webp';
  }

  private get disabled(): boolean {
    return (this.initial !== undefined && this.initial.status === 'running') || this.saving;
  }

  private resolutionOptions(): string[] {
    if (this.isAnimated) {
      return ['1080p', '720p', '480p', '320p', '240p'];
    }
    return ['source', '8k', '4k', '1080p', '720p', '480p', '320p', '240p'];
  }

  private ensureResolutionValid(): void {
    if (this.resolutionOptions().indexOf(this.resolution) >= 0) {
      return;
    }
    this.resolution = this.isAnimated ? '480p' : 'source';
  }

  aboutToAppear(): void {
    const init = this.initial;
    if (init === undefined) {
      return;
    }
    this.sourceText = init.sourcePath;
    this.targetText = init.targetPath;
    const pol = (init.raw['non_video_policy'] !== undefined && init.raw['non_video_policy'] !== null
      ? `${init.raw['non_video_policy']}` : 'skip').trim().toLowerCase();
    this.nonVideoPolicy = pol === 'copy' ? 'copy' : 'skip';
    const cfg = init.config;
    this.format = normalizeIn(cfgText(cfg, 'out_format'), ['mp4', 'mov', 'avi', 'gif', 'webp'], 'mp4');
    this.vcodec = normalizeIn(cfgText(cfg, 'vcodec'), ['h264', 'h265'], 'h264');
    this.acodec = normalizeIn(cfgText(cfg, 'acodec'), ['aac', 'mp3'], 'aac');
    this.resolution = normalizeIn(cfgText(cfg, 'resolution'),
      ['source', '8k', '4k', '1080p', '720p', '480p', '320p', '240p'], 'source');
    this.ensureResolutionValid();
    const vb = mtAsNum(cfg['video_bitrate_mbps']);
    const ab = mtAsNum(cfg['audio_bitrate_kbps']);
    const fps = mtAsNum(cfg['fps']);
    const threadRaw = mtAsNum(cfg['thread_count']);
    this.threadCountText = `${Math.min(50, Math.max(1, threadRaw === undefined ? 5 : Math.round(threadRaw)))}`;
    const hw = cfg['enable_hw_accel'];
    this.enableHwAccel = typeof hw === 'boolean'
      ? hw as boolean
      : cfgText(cfg, 'enable_hw_accel').trim().toLowerCase() !== 'false';
    this.videoBitrateMode = vb !== undefined && vb > 0 ? 'custom' : 'auto';
    this.audioBitrateMode = ab !== undefined && ab > 0 ? 'custom' : 'auto';
    this.fpsMode = fps !== undefined && fps > 0 ? 'custom' : 'auto';
    this.videoBitrateText = vb === undefined ? '' : `${vb}`;
    this.audioBitrateText = ab === undefined ? '' : `${ab}`;
    this.fpsText = fps === undefined ? '' : `${fps}`;
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
      if (ext.length > 0 && SUPPORTED_VIDEO_EXTS.indexOf(ext) < 0) {
        DialogUtil.showErrorDialog(`${L10n.t('support_format', '支持的格式')}：${SUPPORTED_VIDEO_EXTS.join(', ')}`);
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
    const vb = !this.isAnimated && this.videoBitrateMode === 'custom'
      ? mtParsePositiveNum(this.videoBitrateText, 0.1, 500) : undefined;
    const ab = !this.isAnimated && this.audioBitrateMode === 'custom'
      ? mtParsePositiveNum(this.audioBitrateText, 8, 2000) : undefined;
    const fps = this.fpsMode === 'custom'
      ? mtParsePositiveNum(this.fpsText, this.isAnimated ? 5 : 20, this.isAnimated ? 20 : 240)
      : undefined;
    const threadRaw = mtAsNum(this.threadCountText);
    const threadCount = Math.min(50, Math.max(1, threadRaw === undefined ? 5 : Math.round(threadRaw)));
    this.threadCountText = `${threadCount}`;
    return buildVideoTransConfig(this.format, this.vcodec, this.acodec, this.resolution,
      vb, ab, fps, threadCount, this.enableHwAccel);
  }

  private async submit(): Promise<boolean> {
    if (this.saving) {
      return false;
    }
    const id = this.initial !== undefined && this.initial.id > 0 ? this.initial.id : undefined;
    const source = this.sourceText.trim();
    const target = this.targetText.trim();
    if (source.length === 0 || target.length === 0) {
      DialogUtil.showErrorDialog(L10n.t('media_tool_video_trans_required', '请选择源路径与目标路径'));
      return false;
    }
    this.saving = true;
    try {
      const body: Record<string, Object> = {
        'source_path': source,
        'target_path': target,
        'trans_config': this.buildConfig(),
        'non_video_policy': this.nonVideoPolicy
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
      new PickOption('mp4', 'MP4'),
      new PickOption('mov', 'MOV'),
      new PickOption('avi', 'AVI'),
      new PickOption('webp', L10n.t('media_tool_video_trans_out_format_webp', 'WebP 动图')),
      new PickOption('gif', L10n.t('media_tool_video_trans_out_format_gif', 'GIF 动图'))
    ];
  }

  private vcodecOptions(): PickOption[] {
    return [new PickOption('h264', 'H.264'), new PickOption('h265', 'H.265')];
  }

  private acodecOptions(): PickOption[] {
    return [new PickOption('aac', 'AAC'), new PickOption('mp3', 'MP3')];
  }

  private resolutionPickOptions(): PickOption[] {
    const keys = this.resolutionOptions();
    const out: PickOption[] = [];
    keys.forEach((k: string): void => {
      const lower = k.trim().toLowerCase();
      if (lower === 'source') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_source', '原分辨率')));
      } else if (lower === '8k') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_8k', '8K')));
      } else if (lower === '4k') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_4k', '4K')));
      } else if (lower === '1080p') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_1080p', '1080P')));
      } else if (lower === '720p') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_720p', '720P')));
      } else if (lower === '480p') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_480p', '480P')));
      } else if (lower === '320p') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_320p', '320P')));
      } else if (lower === '240p') {
        out.push(new PickOption(k, L10n.t('media_tool_video_trans_resolution_240p', '240P')));
      } else {
        out.push(new PickOption(k, k));
      }
    });
    return out;
  }

  private policyOptions(): PickOption[] {
    return [
      new PickOption('skip', L10n.t('skip', '跳过')),
      new PickOption('copy', L10n.t('media_tool_video_trans_non_video_copy', '复制'))
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
          label: L10n.t('media_tool_video_trans_source', '源路径'),
          value: this.sourceText,
          hint: L10n.t('media_tool_video_trans_pick_source', '点击选择视频文件或目录'),
          icon: $r('sys.symbol.video'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickSource();
          }
        })
        MediaToolPickField({
          label: L10n.t('media_tool_video_trans_target', '目标路径'),
          value: this.targetText,
          hint: L10n.t('media_tool_video_trans_pick_target', '点击选择目标目录'),
          disabled: this.disabled,
          onTap: (): void => {
            this.pickTarget();
          }
        })
        MediaToolSelectField({
          label: L10n.t('media_tool_video_trans_out_format', '输出格式'),
          options: this.formatOptions(),
          value: this.format,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            const next = key.toLowerCase();
            if (['mp4', 'mov', 'avi', 'gif', 'webp'].indexOf(next) < 0) {
              return;
            }
            this.format = next;
            this.ensureResolutionValid();
            if (this.isAnimated) {
              this.videoBitrateMode = 'auto';
              this.audioBitrateMode = 'auto';
              this.videoBitrateText = '';
              this.audioBitrateText = '';
            }
          }
        })
        if (this.isAnimated) {
          Text(L10n.t('media_tool_video_trans_animated_hint',
            '动图模式：仅保留帧率与分辨率设置'))
            .fontSize(12)
            .fontColor(AppTheme.current().subText)
            .width('100%')
        }
        if (!this.isAnimated) {
          MediaToolSelectField({
            label: L10n.t('media_tool_video_trans_video_codec', '视频编码'),
            options: this.vcodecOptions(),
            value: this.vcodec,
            disabled: this.disabled,
            onChanged: (key: string): void => {
              if (key === 'h264' || key === 'h265') {
                this.vcodec = key;
              }
            }
          })
          MediaToolSelectField({
            label: L10n.t('media_tool_video_trans_audio_format', '音频格式'),
            options: this.acodecOptions(),
            value: this.acodec,
            disabled: this.disabled,
            onChanged: (key: string): void => {
              if (key === 'aac' || key === 'mp3') {
                this.acodec = key;
              }
            }
          })
        }
        MediaToolSelectField({
          label: L10n.t('media_tool_video_trans_resolution', '分辨率'),
          options: this.resolutionPickOptions(),
          value: this.resolution,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (this.resolutionOptions().indexOf(key) >= 0) {
              this.resolution = key;
            }
          }
        })
        MediaToolSwitchRow({
          label: L10n.t('media_tool_video_trans_enable_hw_accel', '启用硬件加速'),
          value: this.enableHwAccel,
          disabled: this.disabled,
          onChanged: (v: boolean): void => {
            this.enableHwAccel = v;
          }
        })
        MediaToolNumberField({
          label: L10n.t('media_tool_video_trans_thread_count', '线程数'),
          value: this.threadCountText,
          disabled: this.disabled,
          onChanged: (t: string): void => {
            this.threadCountText = t;
          }
        })
        if (!this.isAnimated) {
          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text(L10n.t('media_tool_video_trans_video_bitrate', '视频码率'))
                .fontSize(13)
                .fontColor(AppTheme.current().onSurface)
              MediaToolSelectField({
                label: '',
                options: this.modeOptions(),
                value: this.videoBitrateMode,
                disabled: this.disabled,
                onChanged: (key: string): void => {
                  if (key === 'auto' || key === 'custom') {
                    this.videoBitrateMode = key;
                  }
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Column({ space: 6 }) {
              Text(L10n.t('media_tool_video_trans_video_bitrate_mbps', '视频码率 (Mbps)'))
                .fontSize(13)
                .fontColor(AppTheme.current().onSurface)
              MediaToolNumberField({
                label: '',
                value: this.videoBitrateText,
                disabled: this.disabled || this.videoBitrateMode !== 'custom',
                onChanged: (t: string): void => {
                  this.videoBitrateText = t;
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text(L10n.t('media_tool_video_trans_audio_bitrate', '音频码率'))
                .fontSize(13)
                .fontColor(AppTheme.current().onSurface)
              MediaToolSelectField({
                label: '',
                options: this.modeOptions(),
                value: this.audioBitrateMode,
                disabled: this.disabled,
                onChanged: (key: string): void => {
                  if (key === 'auto' || key === 'custom') {
                    this.audioBitrateMode = key;
                  }
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Column({ space: 6 }) {
              Text(L10n.t('media_tool_video_trans_audio_bitrate_kbps', '音频码率 (Kbps)'))
                .fontSize(13)
                .fontColor(AppTheme.current().onSurface)
              MediaToolNumberField({
                label: '',
                value: this.audioBitrateText,
                disabled: this.disabled || this.audioBitrateMode !== 'custom',
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
        }
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text(L10n.t('media_tool_video_trans_fps', '帧率'))
              .fontSize(13)
              .fontColor(AppTheme.current().onSurface)
            MediaToolSelectField({
              label: '',
              options: this.modeOptions(),
              value: this.fpsMode,
              disabled: this.disabled,
              onChanged: (key: string): void => {
                if (key === 'auto' || key === 'custom') {
                  this.fpsMode = key;
                }
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Column({ space: 6 }) {
            Text(this.isAnimated
              ? L10n.t('media_tool_video_trans_fps_value_animated', '帧率值 (5-20)')
              : L10n.t('media_tool_video_trans_fps_value', '帧率值 (20-240)'))
              .fontSize(13)
              .fontColor(AppTheme.current().onSurface)
            MediaToolNumberField({
              label: '',
              value: this.fpsText,
              disabled: this.disabled || this.fpsMode !== 'custom',
              onChanged: (t: string): void => {
                this.fpsText = t;
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        MediaToolSelectField({
          label: L10n.t('media_tool_video_trans_non_video', '非视频文件'),
          options: this.policyOptions(),
          value: this.nonVideoPolicy,
          disabled: this.disabled,
          onChanged: (key: string): void => {
            if (key === 'skip' || key === 'copy') {
              this.nonVideoPolicy = key;
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
