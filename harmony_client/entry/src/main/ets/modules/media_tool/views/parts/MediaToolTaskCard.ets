import { L10n } from '../../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../../core/theme/AppTheme';
import { DialogUtil } from '../../../../common/DialogUtil';
import { GlassCard } from '../../../../common/components/GlassCard';
import { openFolderInFileBrowser } from '../../../file_backup/components/FileBackupWidgets';
import { MediaToolTaskController } from '../../controllers/MediaToolControllers';
import { MediaToolKind, MediaToolTaskItem, mediaFormatText, mediaLastErrorDisplay,
  mediaProgressText, mediaTaskStatusColor, mediaTaskStatusText } from '../../models/MediaToolModels';
import { MediaToolKeyValueRow, MediaToolPathRow, MediaToolStartStopButton,
  MediaToolTextButton } from './MediaToolWidgets';

/** 各 kind 的最近错误映射 key 与 SIGKILL 停止文案 key（对齐 Flutter 各 *_helpers.dart） */
function errorMappedKeys(kind: MediaToolKind): string[] {
  if (kind === 'img_batch') {
    return ['source_not_found', 'target_not_found', 'target_not_dir', 'target_no_access'];
  }
  if (kind === 'media_arrange') {
    return ['source_not_found', 'target_not_found', 'target_not_dir', 'target_no_access',
      'invalid_path_relation', 'mediaTool.SOURCE_NOT_FOUND', 'mediaTool.TARGET_NO_WRITE_PERMISSION',
      'mediaTool.TARGET_NOT_EMPTY', 'mediaTool.TARGET_ACCESS_ERROR', 'mediaTool.PATH_CONFLICT'];
  }
  return ['source_not_found', 'target_not_found', 'target_not_dir', 'target_no_access',
    'invalid_path_relation'];
}

function errorSigkillKey(kind: MediaToolKind): string {
  if (kind === 'video_trans') {
    return 'media_tool_video_trans_status_stopped';
  }
  if (kind === 'audio_trans') {
    return 'media_tool_audio_trans_status_stopped';
  }
  return '';
}

/** 取 raw 字段字符串（缺省回退 fallback） */
function rawText(item: MediaToolTaskItem, key: string, fallback: string): string {
  const v = item.raw[key];
  return v !== undefined && v !== null ? `${v}` : fallback;
}

/** 文件路径 → 所在目录（有扩展名视为文件，对齐 Flutter p.dirname 逻辑） */
function parentDirOf(path: string): string {
  const trimmed = path.trim();
  const dot = trimmed.lastIndexOf('.');
  const slash = trimmed.lastIndexOf('/');
  if (dot > slash && slash > 0) {
    return trimmed.substring(0, slash);
  }
  return trimmed;
}

/**
 * 批量任务卡片（对齐 Flutter 各 *_task_card.dart，按 kind 参数化）：
 * 标题行（#id · 格式等 · 状态）+ 路径行（[查看]）+ kind 专属键值行 + 错误行 + 启停/编辑/删除按钮。
 */
@ComponentV2
export struct MediaToolTaskCard {
  @Param ctrl: MediaToolTaskController = new MediaToolTaskController('img_batch');
  @Param kind: MediaToolKind = 'img_batch';
  @Param item: MediaToolTaskItem = new MediaToolTaskItem();
  /** 编辑按钮回调（页面打开对应编辑弹窗） */
  @Param onEdit: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private get status(): string {
    return this.item.status;
  }

  private get opLoading(): boolean {
    return this.ctrl.isOpLoading(this.item.id);
  }

  private get canStop(): boolean {
    return this.status === 'running';
  }

  private get canEdit(): boolean {
    return this.status !== 'running' && !this.opLoading;
  }

  private get canDelete(): boolean {
    // 媒体整理任务运行中禁止删除（对齐 Flutter media_arrange 卡片）；其余 kind 不限制
    if (this.kind === 'media_arrange') {
      return this.item.id > 0 && this.status !== 'running' && !this.opLoading;
    }
    return this.item.id > 0;
  }

  private statusColor(): string {
    const tone = mediaTaskStatusColor(this.status);
    if (tone === 'primary') {
      return this.palette().primary;
    }
    if (tone === 'error') {
      return this.palette().error;
    }
    return this.palette().subText;
  }

  private errorText(): string {
    return mediaLastErrorDisplay(this.item.lastError, errorMappedKeys(this.kind),
      errorSigkillKey(this.kind));
  }

  private startLabel(): string {
    return L10n.t(this.ctrl.startLabelKey(), '开始');
  }

  private stopLabel(): string {
    return L10n.t(this.ctrl.stopLabelKey(), '停止');
  }

  private openPath(path: string): void {
    const target = path.trim();
    if (target.length === 0) {
      return;
    }
    openFolderInFileBrowser(this.kind === 'img_batch' ? target : parentDirOf(target));
  }

  private showTextDialog(title: string, content: string): void {
    DialogUtil.showInfoDialog(title, content);
  }

  // ===== 标题文案（对齐各卡片 Row 首行） =====

  private cardTitle(): string {
    const id = this.item.id;
    if (this.kind === 'img_batch') {
      const fmt = mediaFormatText(rawText(this.item, 'out_format', 'jpeg'));
      const fallback = rawText(this.item, 'out_format', '').trim().length === 0 ? 'JPEG' : fmt;
      const quality = Math.min(100, Math.max(1, Math.round(this.numOr(rawText(this.item, 'quality', '80'), 80))));
      return `#${id} · ${fallback} · ${L10n.t('media_tool_quality', '质量')} ${quality}`;
    }
    if (this.kind === 'video_trans') {
      const fmt = mediaFormatText(this.configText('out_format', 'mp4'));
      const resolution = this.resolutionShort(this.configText('resolution', 'source'));
      if (this.isAnimated) {
        return `#${id} · ${fmt} · ${resolution}`;
      }
      const vcodec = mediaFormatText(this.configText('vcodec', 'h264'));
      return `#${id} · ${fmt} · ${vcodec} · ${resolution}`;
    }
    if (this.kind === 'audio_trans') {
      return `#${id} · ${mediaFormatText(this.configText('out_format', 'mp3'))}`;
    }
    return `#${id} · ${this.arrangeTypeText(rawText(this.item, 'arrange_type', 'day'))}`;
  }

  private configText(key: string, fallback: string): string {
    const v = this.item.config[key];
    if (v === undefined || v === null) {
      return fallback;
    }
    const s = `${v}`.trim();
    return s.length === 0 ? fallback : s;
  }

  private numOr(text: string, fallback: number): number {
    const n = Number(text.trim());
    return Number.isNaN(n) ? fallback : n;
  }

  private get isAnimated(): boolean {
    const fmt = this.configText('out_format', 'mp4').trim().toLowerCase();
    return fmt === 'gif' || fmt === 'webp';
  }

  /** 分辨率短文案（卡片标题内使用，与 Flutter resolutionText 一致） */
  private resolutionShort(v: string): string {
    const s = v.trim().toLowerCase();
    if (s === '8k') {
      return L10n.t('media_tool_video_trans_resolution_8k', '8K');
    }
    if (s === '4k') {
      return L10n.t('media_tool_video_trans_resolution_4k', '4K');
    }
    if (s === '1080p') {
      return L10n.t('media_tool_video_trans_resolution_1080p', '1080P');
    }
    if (s === '720p') {
      return L10n.t('media_tool_video_trans_resolution_720p', '720P');
    }
    if (s === '480p') {
      return L10n.t('media_tool_video_trans_resolution_480p', '480P');
    }
    if (s === '320p') {
      return L10n.t('media_tool_video_trans_resolution_320p', '320P');
    }
    if (s === '240p') {
      return L10n.t('media_tool_video_trans_resolution_240p', '240P');
    }
    return L10n.t('media_tool_video_trans_resolution_source', '原分辨率');
  }

  private arrangeTypeText(type: string): string {
    const s = type.trim().toLowerCase();
    if (s === 'year') {
      return L10n.t('media_tool_arrange_type_year', '按年整理');
    }
    if (s === 'month') {
      return L10n.t('media_tool_arrange_type_month', '按年月整理');
    }
    if (s === 'day') {
      return L10n.t('media_tool_arrange_type_day', '按年月日整理');
    }
    return type;
  }

  /** 尺寸文案（对齐 Flutter _sizeText：空/非正 → 保持原尺寸） */
  private sizeText(): string {
    const n = this.numOr(rawText(this.item, 'out_size', ''), 0);
    if (n <= 0) {
      return L10n.t('media_tool_img_batch_keep_size', '保持原尺寸');
    }
    return `${L10n.t('media_tool_out_size', '输出尺寸')} ${Math.round(n)}`;
  }

  /** 策略文案（skip/copy） */
  private policyText(rawKey: string, copyKey: string): string {
    return rawText(this.item, rawKey, 'skip').trim().toLowerCase() === 'copy'
      ? L10n.t(copyKey, '复制') : L10n.t('skip', '跳过');
  }

  /** 线程数文案（空/非正 → '-'） */
  private threadCountText(): string {
    const n = this.numOr(this.configText('thread_count', ''), 0);
    return n > 0 ? `${Math.round(n)}` : '-';
  }

  /** 帧率文案（空/非正 → 自动） */
  private fpsText(): string {
    const n = this.numOr(this.configText('fps', ''), 0);
    if (n <= 0) {
      return L10n.t('auto', '自动');
    }
    return n % 1 === 0 ? `${Math.round(n)}` : `${n}`;
  }

  /** 码率文案（空/非正 → 自动，否则 "n 单位"） */
  private bitrateText(key: string, unit: string): string {
    const n = this.numOr(this.configText(key, ''), 0);
    if (n <= 0) {
      return L10n.t('auto', '自动');
    }
    const asText = n % 1 === 0 ? `${Math.round(n)}` : `${n}`;
    return `${asText} ${unit}`;
  }

  build() {
    GlassCard({ padValue: 12 }) {
      Column({ space: 6 }) {
        // 标题行：#id · 摘要 + 状态
        Row() {
          Text(this.cardTitle())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(mediaTaskStatusText(this.kind, this.status))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.statusColor())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.kind === 'img_batch') {
          MediaToolPathRow({
            label: L10n.t('media_tool_img_batch_source', '源路径'),
            path: this.item.sourcePath,
            onView: (): void => {
              this.openPath(this.item.sourcePath);
            }
          })
          MediaToolPathRow({
            label: L10n.t('media_tool_img_batch_target', '目标路径'),
            path: this.item.targetPath,
            onView: (): void => {
              this.openPath(this.item.targetPath);
            }
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_out_size', '输出尺寸'),
            value: this.sizeText()
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_img_batch_non_image', '非图片文件'),
            value: this.policyText('non_image_policy', 'media_tool_img_batch_non_image_copy')
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_img_batch_progress', '进度'),
            value: this.item.totalFiles > 0
              ? `${this.item.doneFiles}/${this.item.totalFiles}`
              : mediaProgressText(this.item.progress, 0, 0)
          })
        } else if (this.kind === 'video_trans') {
          MediaToolPathRow({
            label: L10n.t('media_tool_video_trans_source', '源路径'),
            path: this.item.sourcePath,
            onView: (): void => {
              this.openPath(this.item.sourcePath);
            }
          })
          MediaToolPathRow({
            label: L10n.t('media_tool_video_trans_target', '目标路径'),
            path: this.item.targetPath,
            onView: (): void => {
              this.openPath(this.item.targetPath);
            }
          })
          if (!this.isAnimated) {
            MediaToolKeyValueRow({
              label: L10n.t('media_tool_video_trans_video_bitrate', '视频码率'),
              value: this.bitrateText('video_bitrate_mbps', 'Mbps')
            })
            MediaToolKeyValueRow({
              label: L10n.t('media_tool_video_trans_audio_bitrate', '音频码率'),
              value: this.bitrateText('audio_bitrate_kbps', 'Kbps')
            })
            MediaToolKeyValueRow({
              label: L10n.t('media_tool_video_trans_audio_format', '音频格式'),
              value: mediaFormatText(this.configText('acodec', 'aac'))
            })
          }
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_video_trans_fps', '帧率'),
            value: this.fpsText()
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_video_trans_enable_hw_accel', '启用硬件加速'),
            value: (this.configText('enable_hw_accel', 'true').trim().toLowerCase() !== 'false')
              ? L10n.t('media_tool_video_trans_fast_start_on', '已开启')
              : L10n.t('media_tool_video_trans_fast_start_off', '已关闭')
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_video_trans_thread_count', '线程数'),
            value: this.threadCountText()
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_video_trans_non_video', '非视频文件'),
            value: this.policyText('non_video_policy', 'media_tool_video_trans_non_video_copy')
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_video_trans_progress', '进度'),
            value: mediaProgressText(this.item.progress, this.item.totalFiles, this.item.doneFiles)
          })
        } else if (this.kind === 'audio_trans') {
          MediaToolPathRow({
            label: L10n.t('media_tool_audio_trans_source', '源路径'),
            path: this.item.sourcePath,
            onView: (): void => {
              this.openPath(this.item.sourcePath);
            }
          })
          MediaToolPathRow({
            label: L10n.t('media_tool_audio_trans_target', '目标路径'),
            path: this.item.targetPath,
            onView: (): void => {
              this.openPath(this.item.targetPath);
            }
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_audio_trans_sample_rate', '采样率'),
            value: this.sampleRateText()
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_audio_trans_channels', '声道'),
            value: this.channelsText()
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_audio_trans_audio_bitrate', '音频码率'),
            value: this.bitrateText('audio_bitrate_kbps', 'Kbps')
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_audio_trans_thread_count', '线程数'),
            value: this.threadCountText()
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_audio_trans_non_audio', '非音频文件'),
            value: this.policyText('non_audio_policy', 'media_tool_audio_trans_non_audio_copy')
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_audio_trans_progress', '进度'),
            value: mediaProgressText(this.item.progress, this.item.totalFiles, this.item.doneFiles)
          })
        } else {
          MediaToolPathRow({
            label: L10n.t('media_tool_arrange_source', '源路径'),
            path: this.item.sourcePath,
            onView: (): void => {
              this.openPath(this.item.sourcePath);
            }
          })
          MediaToolPathRow({
            label: L10n.t('media_tool_arrange_target', '目标路径'),
            path: this.item.targetPath,
            onView: (): void => {
              this.openPath(this.item.targetPath);
            }
          })
          MediaToolKeyValueRow({
            label: L10n.t('media_tool_arrange_progress', '进度'),
            value: mediaProgressText(this.item.progress, this.item.totalFiles, this.item.doneFiles)
          })
        }

        if (this.item.lastError.trim().length > 0 && this.errorText().length > 0) {
          MediaToolKeyValueRow({
            label: this.errorLabel(),
            value: this.errorText(),
            valueTone: 'error',
            clickable: true,
            onTap: (): void => {
              this.showTextDialog(this.errorLabel(), this.errorText());
            }
          })
        }

        // 操作行：启停 / 编辑 / 删除
        Row({ space: 8 }) {
          MediaToolStartStopButton({
            running: this.canStop,
            startLabel: this.startLabel(),
            stopLabel: this.stopLabel(),
            loading: this.opLoading,
            onTap: (): void => {
              if (this.canStop) {
                void this.ctrl.stopTask(this.item.id);
              } else {
                void this.ctrl.startTask(this.item.id);
              }
            }
          })
          MediaToolTextButton({
            label: L10n.edit,
            icon: $r('sys.symbol.square_and_pencil'),
            disabled: !this.canEdit,
            onTap: (): void => {
              this.onEdit();
            }
          })
          MediaToolTextButton({
            label: L10n.delete,
            icon: $r('sys.symbol.trash'),
            disabled: !this.canDelete,
            onTap: (): void => {
              void this.ctrl.removeTask(this.item.id);
            }
          })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private errorLabel(): string {
    if (this.kind === 'img_batch') {
      return L10n.t('media_tool_img_batch_last_error', '最近错误');
    }
    if (this.kind === 'video_trans') {
      return L10n.t('media_tool_video_trans_last_error', '最近错误');
    }
    if (this.kind === 'audio_trans') {
      return L10n.t('media_tool_audio_trans_last_error', '最近错误');
    }
    return L10n.t('media_tool_arrange_last_error', '最近错误');
  }

  /** 采样率文案（对齐 Flutter _sampleRateText） */
  private sampleRateText(): string {
    const s = this.configText('sample_rate', 'source').trim().toLowerCase();
    if (s === 'source' || s.length === 0) {
      return L10n.t('media_tool_audio_trans_sample_rate_source', '保持原采样率');
    }
    return `${s} Hz`;
  }

  /** 声道文案（对齐 Flutter _channelsText） */
  private channelsText(): string {
    const s = this.configText('channels', 'source').trim().toLowerCase();
    if (s === 'mono') {
      return L10n.t('media_tool_audio_trans_channels_mono', '单声道');
    }
    if (s === 'stereo') {
      return L10n.t('media_tool_audio_trans_channels_stereo', '立体声');
    }
    return L10n.t('media_tool_audio_trans_channels_source', '保持原声道');
  }
}
