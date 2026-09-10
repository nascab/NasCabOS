import { L10n } from '../../../core/localization/L10n';

// ===== 服务端版本判定（移植 Flutter utils/server_version_util.dart） =====

export class ServerVersionUtil {
  static parseMajorVersion(version: string | undefined): number | undefined {
    if (version === undefined) {
      return undefined;
    }
    const trimmed = version.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    let normalized = trimmed;
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    const parts = normalized.split('.');
    if (parts.length === 0) {
      return undefined;
    }
    const match = parts[0].match(/\d+/);
    if (match === null) {
      return undefined;
    }
    const n = Number(match[0]);
    return Number.isNaN(n) ? undefined : n;
  }

  static isAtLeast(version: string | undefined, majorVersion: number,
    unknownAsSupported: boolean = true): boolean {
    const major = ServerVersionUtil.parseMajorVersion(version);
    if (major === undefined) {
      return unknownAsSupported;
    }
    return major >= majorVersion;
  }
}

// ===== JSON 边界取值工具 =====

/** Record 取字符串（含数字转字符串），缺省回退 */
export function mtAsString(v: Object | undefined | null, fallback: string): string {
  if (v === undefined || v === null) {
    return fallback;
  }
  const s = `${v}`;
  return s.length === 0 ? fallback : s;
}

/** Record 取数字（兼容数字/数字字符串），缺省 undefined */
export function mtAsNum(v: Object | undefined | null): number | undefined {
  if (v === undefined || v === null) {
    return undefined;
  }
  if (typeof v === 'number') {
    return Number.isNaN(v) ? undefined : v;
  }
  const s = `${v}`.trim();
  if (s.length === 0) {
    return undefined;
  }
  const n = Number(s);
  return Number.isNaN(n) ? undefined : n;
}

/** Record 取布尔（兼容字符串 'true'/'false'），缺省 fallback */
export function mtAsBool(v: Object | undefined | null, fallback: boolean): boolean {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  const s = `${v}`.trim().toLowerCase();
  if (s === 'false') {
    return false;
  }
  if (s === 'true') {
    return true;
  }
  return fallback;
}

/** 任意值转 Record（非对象/数组时返回空 Record，对齐 Flutter _parseConfig） */
export function mtAsRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || Array.isArray(v) || typeof v !== 'object') {
    return {} as Record<string, Object>;
  }
  return v as Record<string, Object>;
}

// ===== 入口菜单项（对齐 app_media_tool_items.dart） =====

export class MediaToolMenuItem {
  key: string = '';
  groupTitleKey: string = '';
  titleKey: string = '';
  subtitleKey: string = '';
  icon: Resource = $r('sys.symbol.picture');

  constructor(key: string, groupTitleKey: string, titleKey: string,
    subtitleKey: string, icon: Resource) {
    this.key = key;
    this.groupTitleKey = groupTitleKey;
    this.titleKey = titleKey;
    this.subtitleKey = subtitleKey;
    this.icon = icon;
  }
}

/** 子工具菜单定义（语义对齐 Flutter Icons → Harmony SymbolGlyph） */
export const MEDIA_TOOL_MENU_ITEMS: MediaToolMenuItem[] = [
  new MediaToolMenuItem('image.compress', 'media_tool_menu_image',
    'media_tool_menu_image_compress', 'media_tool_menu_image_compress_help',
    $r('sys.symbol.arrow_up_left_and_arrow_down_right')),
  new MediaToolMenuItem('image.batch_compress', 'media_tool_menu_image',
    'media_tool_menu_image_batch_compress', 'media_tool_menu_image_batch_compress_help',
    $r('sys.symbol.rectangle_stack')),
  new MediaToolMenuItem('video.trans', 'media_tool_menu_video',
    'media_tool_menu_video_trans', 'media_tool_menu_video_trans_help',
    $r('sys.symbol.film')),
  new MediaToolMenuItem('audio.trans', 'media_tool_menu_audio',
    'media_tool_menu_audio_trans', 'media_tool_menu_audio_trans_help',
    $r('sys.symbol.music_note_list')),
  new MediaToolMenuItem('other.media_arrange', 'media_tool_menu_other',
    'media_tool_menu_media_arrange', 'media_tool_arrange_help',
    $r('sys.symbol.folder')),
];

// ===== 批量任务数据模型（对齐 Flutter 各 controller 的 Map<String, dynamic> 解析） =====

/** 任务工具种类 */
export type MediaToolKind = 'img_batch' | 'video_trans' | 'audio_trans' | 'media_arrange';

export class MediaToolTaskItem {
  id: number = 0;
  status: string = 'stopped';
  sourcePath: string = '';
  targetPath: string = '';
  progress: string = '';
  lastError: string = '';
  totalFiles: number = 0;
  doneFiles: number = 0;
  /** 任务原始字段（out_format/quality/arrange_type/same_name_policy/non_xxx_policy 等） */
  raw: Record<string, Object> = {};
  /** trans_config 解析结果（视频/音频转换用） */
  config: Record<string, Object> = {};

  static fromJson(o: Record<string, Object>): MediaToolTaskItem {
    const it = new MediaToolTaskItem();
    it.raw = o;
    it.id = mtAsNum(o['id']) ?? 0;
    it.status = mtAsString(o['status'], 'stopped').trim().toLowerCase();
    it.sourcePath = mtAsString(o['source_path'], '');
    it.targetPath = mtAsString(o['target_path'], '');
    it.progress = mtAsString(o['progress'], '');
    it.lastError = mtAsString(o['last_error'], '');
    it.totalFiles = mtAsNum(o['total_files']) ?? 0;
    it.doneFiles = mtAsNum(o['done_files']) ?? 0;
    const cfgRaw = o['trans_config'];
    if (cfgRaw !== undefined && cfgRaw !== null && typeof cfgRaw === 'string') {
      try {
        it.config = mtAsRecord(JSON.parse(cfgRaw as string));
      } catch (_e) {
        it.config = {} as Record<string, Object>;
      }
    } else {
      it.config = mtAsRecord(cfgRaw);
    }
    return it;
  }
}

// ===== 展示辅助（对齐 Flutter 各 parts/*_helpers.dart） =====

/** 状态文案：running/stopped/error/finished（finished 仅媒体整理有，对齐 Flutter 'completed'.tr） */
export function mediaTaskStatusText(kind: MediaToolKind, status: string): string {
  if (status === 'running') {
    return L10n.t(`media_tool_${kind}_status_running`, '运行中');
  }
  if (status === 'stopped') {
    return L10n.t(`media_tool_${kind}_status_stopped`, '已停止');
  }
  if (status === 'error') {
    return L10n.t(`media_tool_${kind}_status_error`, '异常');
  }
  if (kind === 'media_arrange' && status === 'finished') {
    return L10n.t('completed', '已完成');
  }
  return status;
}

/** 状态颜色：running=主色 / error=错误色 / 其他=次要文本 */
export function mediaTaskStatusColor(status: string): string {
  if (status === 'running') {
    return 'primary';
  }
  if (status === 'error') {
    return 'error';
  }
  return 'sub';
}

/** 格式文本：空回退 '-'，统一大写 */
export function mediaFormatText(fmt: string): string {
  const f = fmt.trim().toLowerCase();
  if (f.length === 0) {
    return '-';
  }
  return f.toUpperCase();
}

/**
 * 最近错误展示文本：取第一行；命中映射 key 时走翻译。
 * sigkillStoppedKey 非空时（视频/音频转换）：ffmpeg 被 SIGKILL 杀死显示为"已停止"。
 */
export function mediaLastErrorDisplay(raw: string, mappedKeys: string[],
  sigkillStoppedKey: string = ''): string {
  const firstLine = raw.trim().split('\n')[0].trim();
  if (firstLine.length === 0) {
    return '';
  }
  if (sigkillStoppedKey.length > 0
    && firstLine.toLowerCase().includes('ffmpeg was killed with signal sigkill')) {
    return L10n.t(sigkillStoppedKey, '已停止');
  }
  if (mappedKeys.indexOf(firstLine) >= 0) {
    return L10n.t(firstLine, firstLine);
  }
  return firstLine;
}

/** 进度文本：runtime 优先，其次 done/total（对齐 Flutter progressText 组合逻辑） */
export function mediaProgressText(runtimeProgress: string, totalFiles: number,
  doneFiles: number): string {
  const rt = runtimeProgress.trim();
  const base = totalFiles > 0 ? `${doneFiles}/${totalFiles}` : '';
  if (rt.length === 0) {
    return base.length === 0 ? '-' : base;
  }
  if (/^\d+\/\d+$/.test(rt)) {
    return rt;
  }
  return base.length === 0 ? rt : `${base} · ${rt}`;
}

/** 码率文本：空/非正数 → 自动，否则 "n 单位"（对齐 Flutter bitrateText） */
export function mediaBitrateText(v: Object | undefined, unit: string): string {
  const n = mtAsNum(v);
  if (n === undefined || n <= 0) {
    return L10n.t('auto', '自动');
  }
  const asText = n % 1 === 0 ? `${Math.round(n)}` : `${n}`;
  return `${asText} ${unit}`;
}

/** 帧率文本：空/非正数 → 自动 */
export function mediaFpsText(v: Object | undefined): string {
  const n = mtAsNum(v);
  if (n === undefined || n <= 0) {
    return L10n.t('auto', '自动');
  }
  return n % 1 === 0 ? `${Math.round(n)}` : `${n}`;
}

/** 视频分辨率文案（对齐 Flutter resolutionText） */
export function videoResolutionText(v: string): string {
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

/** 音频采样率文案（对齐 Flutter _sampleRateText） */
export function audioSampleRateText(v: string): string {
  const s = v.trim().toLowerCase();
  if (s === 'source' || s.length === 0) {
    return L10n.t('media_tool_audio_trans_sample_rate_source', '保持原采样率');
  }
  return `${s} Hz`;
}

/** 声道文案（对齐 Flutter _channelsText） */
export function audioChannelsText(v: string): string {
  const s = v.trim().toLowerCase();
  if (s === 'mono') {
    return L10n.t('media_tool_audio_trans_channels_mono', '单声道');
  }
  if (s === 'stereo') {
    return L10n.t('media_tool_audio_trans_channels_stereo', '立体声');
  }
  return L10n.t('media_tool_audio_trans_channels_source', '保持原声道');
}

/** 音频输出格式 → 编码器（对齐 Flutter _codecForFormat） */
export function audioCodecForFormat(format: string): string {
  switch (format.trim().toLowerCase()) {
    case 'mp3':
      return 'mp3';
    case 'flac':
      return 'flac';
    case 'ogg':
      return 'vorbis';
    case 'wav':
      return 'pcm';
    case 'opus':
      return 'opus';
    case 'wma':
      return 'wmav2';
    case 'aac':
      return 'aac';
    default:
      return 'aac';
  }
}

/** 数字收敛到 [min, max]（NaN 时回退 fallback） */
export function mtClampInt(text: string, min: number, max: number, fallback: number): number {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return fallback;
  }
  const digits = trimmed.replace(/[^0-9]/g, '');
  if (digits.length === 0) {
    return fallback;
  }
  const n = Number(digits);
  if (Number.isNaN(n)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, Math.round(n)));
}

/** 可空正数解析（超出范围时收敛到边界，对齐 Flutter _parseNullablePositiveNum） */
export function mtParsePositiveNum(text: string, min: number, max: number): number | undefined {
  const raw = text.trim();
  if (raw.length === 0) {
    return undefined;
  }
  const n = Number(raw);
  if (Number.isNaN(n) || n <= 0) {
    return undefined;
  }
  if (n < min) {
    return min;
  }
  if (n > max) {
    return max;
  }
  return n;
}
