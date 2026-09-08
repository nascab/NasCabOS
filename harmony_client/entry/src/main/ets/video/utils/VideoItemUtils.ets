import { L10n } from '../../core/localization/L10n';
import { ApiUrls } from '../../core/network/ApiUrls';
import { APIClient } from '../../core/network/APIClient';
import { AppEventBus } from '../../common/AppEventBus';
import { VideoHomeItemBean } from '../models/VideoModels';

/**
 * 视频条目工具（对齐 Flutter video 模块 base/video_utils 与 utils/browse_path_utils.dart）。
 */

/** 浏览用视频类文件扩展名（对齐 kBrowseVideoFileExtensions） */
const VIDEO_FILE_EXTENSIONS: string[] = [
  '.mkv', '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.ts',
  '.m2ts', '.mts', '.mpg', '.mpeg', '.mpe', '.divx', '.rm', '.rmvb', '.iso',
  '.strm', '.srt', '.ass', '.ssa', '.sub', '.idx', '.sup', '.nfo'
];

function fileExtension(path: string): string {
  const s = path.trim();
  const idx = s.lastIndexOf('.');
  if (idx < 0) {
    return '';
  }
  return s.substring(idx).toLowerCase();
}

function looksLikeWindowsServerPath(s: string): boolean {
  const t = s.trim();
  if (t.length >= 3) {
    const a = t.charCodeAt(0);
    const isLetter = (a >= 0x41 && a <= 0x5A) || (a >= 0x61 && a <= 0x7A);
    if (isLetter && t[1] === ':' && (t[2] === '\\' || t[2] === '/')) {
      return true;
    }
  }
  return t.startsWith('\\\\');
}

/** 取父目录：远端 Windows/UNC 路径按 Windows 语义解析（对齐 browsePathDirname） */
function browsePathDirname(path: string): string {
  const s = path.trim();
  if (s.length === 0) {
    return s;
  }
  const normalized = s.replace(/\\/g, '/');
  const idx = normalized.lastIndexOf('/');
  if (idx <= 0) {
    return looksLikeWindowsServerPath(s) ? s : '';
  }
  let dir = normalized.substring(0, idx);
  // Windows 盘符根目录（如 E:/）保留尾部斜杠
  if (/^[A-Za-z]:$/.test(dir)) {
    dir += '/';
  }
  return dir;
}

/** 文件浏览需传入目录：已知文件扩展名取父目录（对齐 browseFolderPathForKnownFile） */
function browseFolderPathForKnownFile(path: string): string {
  const s = path.trim();
  if (s.length === 0) {
    return '';
  }
  const ext = fileExtension(s);
  if (ext.length === 0) {
    return s;
  }
  if (VIDEO_FILE_EXTENSIONS.includes(ext)) {
    return browsePathDirname(s);
  }
  return s;
}

function joinPath(base: string, name: string): string {
  const b = base.trim().replace(/\/+$/, '').replace(/\\+$/, '');
  const n = name.trim().replace(/^\/+/, '').replace(/^\\+/, '');
  if (b.length === 0) {
    return n;
  }
  const sep = b.includes('\\') || /^[A-Za-z]:/.test(b) ? '\\' : '/';
  return `${b}${sep}${n}`;
}

/** 媒体类型显示文案（对齐 videoMediaTypeText） */
export function videoMediaTypeText(mediaType: string): string {
  const t = mediaType.toLowerCase();
  if (t === 'tv' || t === 'episod' || t === 'season') {
    return L10n.t('video_home_type_tv', '电视剧');
  }
  if (t === 'movie' || t === 'bdmv' || t === 'video_ts') {
    return L10n.t('video_home_type_movie', '电影');
  }
  return mediaType;
}

function pickFirstPart(s: string): string {
  const parts = s.split(/[,，/|、]/)
    .map((e: string) => e.trim())
    .filter((e: string) => e.length > 0);
  return parts.length > 0 ? parts[0] : '';
}

/** 海报下方的国家 · 类型 元信息（对齐 buildVideoHomeMeta） */
export function buildVideoHomeMeta(item: VideoHomeItemBean): string {
  const country = pickFirstPart(item.nfoRegions);
  const genre = pickFirstPart(item.nfoGenres);
  if (country.length === 0 && genre.length === 0) {
    return '';
  }
  if (country.length === 0) {
    return genre;
  }
  if (genre.length === 0) {
    return country;
  }
  return `${country} · ${genre}`;
}

/** 是否电影类媒体（movie/bdmv/video_ts） */
export function isMovieMediaType(mediaType: string): boolean {
  const t = mediaType.toLowerCase().trim();
  return t === 'movie' || t === 'bdmv' || t === 'video_ts';
}

function isTvMediaType(mediaType: string): boolean {
  const t = mediaType.toLowerCase().trim();
  return t === 'tv' || t === 'season' || t === 'episod';
}

/** 文件浏览目标目录（对齐 resolveVideoBrowsePath） */
export function resolveVideoBrowsePath(item: VideoHomeItemBean): string {
  const t = item.mediaType.toLowerCase().trim();
  if (isMovieMediaType(item.mediaType)) {
    const full = item.fullPath.trim().length > 0
      ? item.fullPath.trim()
      : (item.path.trim().length > 0 && item.filename.trim().length > 0)
        ? joinPath(item.path, item.filename)
        : '';
    return full.length > 0 ? browseFolderPathForKnownFile(full) : '';
  }
  if (t === 'tv' || t === 'season' || t === 'episod') {
    const full = item.fullPath.trim();
    if (full.length > 0) {
      return browseFolderPathForKnownFile(full);
    }
  }
  const base = item.path.trim();
  if (base.length > 0) {
    return browseFolderPathForKnownFile(base);
  }
  const full = item.fullPath.trim();
  return full.length > 0 ? browseFolderPathForKnownFile(full) : '';
}

/** 删除目标路径（对齐 resolveVideoDeletePath） */
export function resolveVideoDeletePath(item: VideoHomeItemBean): string {
  const t = item.mediaType.toLowerCase().trim();
  if (isMovieMediaType(item.mediaType)) {
    if (item.fullPath.trim().length > 0) {
      return item.fullPath.trim();
    }
    if (item.path.trim().length > 0 && item.filename.trim().length > 0) {
      return joinPath(item.path, item.filename);
    }
  }
  if (t === 'tv' || t === 'season') {
    const full = item.fullPath.trim();
    if (full.length > 0) {
      return full;
    }
  }
  const base = item.path.trim();
  if (base.length > 0) {
    return base;
  }
  return item.fullPath.trim();
}

/** 下载目标路径（对齐 resolveVideoDownloadPath） */
export function resolveVideoDownloadPath(item: VideoHomeItemBean): string {
  const t = item.mediaType.toLowerCase().trim();
  if (isMovieMediaType(item.mediaType)) {
    if (item.fullPath.trim().length > 0) {
      return item.fullPath.trim();
    }
    if (item.path.trim().length > 0 && item.filename.trim().length > 0) {
      return joinPath(item.path, item.filename);
    }
    return '';
  }
  if (t === 'tv' || t === 'season') {
    if (item.fullPath.trim().length > 0) {
      return item.fullPath.trim();
    }
    if (item.path.trim().length > 0 && item.filename.trim().length > 0) {
      return joinPath(item.path, item.filename);
    }
    return item.path.trim();
  }
  if (item.fullPath.trim().length > 0) {
    return item.fullPath.trim();
  }
  if (item.path.trim().length > 0 && item.filename.trim().length > 0) {
    return joinPath(item.path, item.filename);
  }
  return item.path.trim();
}

/**
 * 视频条目删除同步服务（对齐 Flutter VideoItemSyncService）：
 * 删除条目后广播事件，各列表页自行刷新。
 */
export class VideoItemSyncService {
  /** AppEventBus 事件名 */
  static readonly EVENT_VIDEO_ITEM_DELETED: string = 'video_item_deleted';

  static notifyDeleted(indexId: number): void {
    if (indexId <= 0) {
      return;
    }
    AppEventBus.emit(VideoItemSyncService.EVENT_VIDEO_ITEM_DELETED, `${indexId}`);
  }
}

/** 评分/类型角标短文案映射（对齐 _BadgeRow._shortLabelMap） */
const SHORT_LABEL_MAP: Map<string, string> = new Map<string, string>([
  ['电视剧', '剧'],
  ['电影', '影']
]);

export function shortTypeLabel(typeText: string): string {
  const mapped = SHORT_LABEL_MAP.get(typeText);
  return mapped !== undefined ? mapped : typeText;
}

/**
 * 海报/背景图 URL 工具（对齐 Flutter VideoUtils）。
 * 注意：鸿蒙端 ApiUrls.getTinyUrl/getRawFileUrl 为异步加密 URL，返回 Promise。
 */
export class VideoUtils {
  /** 海报缩略图：优先 poster_path，回退 firstFilePath/fullPath（对齐 getPosterUrl） */
  static async getPosterUrl(item: VideoHomeItemBean, size: number = 500): Promise<string> {
    const posterPath = item.posterPath.trim();
    if (posterPath.length > 0) {
      return ApiUrls.getTinyUrl(posterPath, size);
    }
    const fallbackFilePath = item.firstFilePath.length > 0 ? item.firstFilePath : item.fullPath;
    if (fallbackFilePath.trim().length === 0) {
      return '';
    }
    return ApiUrls.getTinyUrl(fallbackFilePath, size);
  }

  /** 背景大图：优先 fanart_path，回退 poster（rawFile，对齐 getFanartUrl） */
  static async getFanartUrl(item: VideoHomeItemBean): Promise<string> {
    const fanartPath = item.fanartPath.trim();
    if (fanartPath.length > 0) {
      return ApiUrls.getRawFileUrl(fanartPath);
    }
    const posterPath = item.posterPath.trim();
    if (posterPath.length > 0) {
      return ApiUrls.getRawFileUrl(posterPath);
    }
    const fallbackFilePath = item.firstFilePath.length > 0 ? item.firstFilePath : item.fullPath;
    if (fallbackFilePath.trim().length === 0) {
      // 诊断日志：三个图片来源字段均为空时输出，便于定位大图不显示
      console.error(`[VideoFanart] no image source: id=${item.id}, name=${item.nfoName}`);
      return '';
    }
    return VideoUtils.getPosterUrl(item, 1600);
  }

  /** 演职人员头像 URL（对齐 Flutter getVideoPersonImageUrl） */
  static async getPersonImageUrl(tmdbId: string, size: number = 240, thumb: string = ''): Promise<string> {
    const id = tmdbId.trim();
    if (id.length === 0) {
      return '';
    }
    const api = APIClient.getInstance();
    const token = (api.accessToken ?? '').trim();
    const params = new Map<string, string>();
    params.set('tmdb_id', id);
    params.set('size', `${size}`);
    if (thumb.trim().length > 0) {
      params.set('thumb', thumb.trim());
    }
    if (token.length > 0) {
      params.set('accessToken', token);
    }
    const aes = await ApiUrls.encryptParams(params);
    const base = api.state.baseUrl;
    if (aes.length > 0) {
      return `${base}/api/video/person/image?aes=${encodeURIComponent(aes)}`;
    }
    let url = `${base}/api/video/person/image?tmdb_id=${encodeURIComponent(id)}&size=${encodeURIComponent(`${size}`)}`;
    if (thumb.trim().length > 0) {
      url += `&thumb=${encodeURIComponent(thumb.trim())}`;
    }
    if (token.length > 0) {
      url += `&accessToken=${encodeURIComponent(token)}`;
    }
    return url;
  }
}

/**
 * 智能相册筛选条件提示文案工具（对齐 Flutter VideoSmartAlbumTooltipUtil）：
 * 将 filterContent（logic + conditions）转为可读文案，如"名称包含 xx 且 年份 大于 2020"。
 */
export class VideoSmartAlbumTooltipUtil {
  /** 构建提示文案；无条件时返回空串 */
  static buildTooltip(filterContent: Record<string, Object>): string {
    const keys = Object.keys(filterContent);
    if (keys.length === 0) {
      return '';
    }
    const logicRaw = filterContent['logic'] as string | undefined;
    const logic = (logicRaw ?? 'and').trim().toLowerCase();
    const joiner = logic === 'or'
      ? L10n.t('smart_album_join_or', '或')
      : L10n.t('smart_album_join_and', '且');
    const raw = filterContent['conditions'];
    if (!Array.isArray(raw)) {
      return '';
    }

    const parts: string[] = [];
    for (const e of raw as Object[]) {
      if (e === null || e === undefined || typeof e !== 'object') {
        continue;
      }
      const m = e as Record<string, Object>;
      const field = VideoSmartAlbumTooltipUtil.asText(m['field']);
      const op = VideoSmartAlbumTooltipUtil.asText(m['operator']);
      const value = m['value'];
      const text = VideoSmartAlbumTooltipUtil.formatConditionItem(field, op, value);
      if (text.trim().length > 0) {
        parts.push(text);
      }
    }
    return parts.join(joiner);
  }

  private static asText(v: Object | undefined): string {
    if (v === null || v === undefined) {
      return '';
    }
    return `${v}`.trim();
  }

  private static fieldLabel(field: string): string {
    switch (field.trim()) {
      case 'name':
        return L10n.t('smart_album_field_name', '名称');
      case 'nfo_name':
        return L10n.t('smart_album_field_nfo_name', '影片名');
      case 'nfo_actor':
        return L10n.t('smart_album_field_nfo_actor', '演员');
      case 'nfo_director':
        return L10n.t('smart_album_field_nfo_director', '导演');
      case 'nfo_genres':
        return L10n.t('smart_album_field_nfo_genres', '类型');
      case 'nfo_regions':
        return L10n.t('smart_album_field_nfo_regions', '地区');
      case 'filename':
        return L10n.t('filename', '文件名');
      case 'path':
        return L10n.t('path', '路径');
      case 'year':
        return L10n.t('smart_album_field_year', '年份');
      case 'score':
        return L10n.t('smart_album_field_score', '评分');
      case 'duration_min':
        return L10n.t('smart_album_field_duration', '时长(分钟)');
      default:
        return field.trim();
    }
  }

  private static formatConditionItem(field: string, operator: string, value: Object | undefined): string {
    const f = field.trim();
    if (f.length === 0) {
      return '';
    }
    const op = operator.trim();
    if (op.length === 0) {
      return '';
    }

    if (op === 'contains') {
      const s = value === null || value === undefined ? '' : `${value}`;
      if (s.trim().length === 0) {
        return '';
      }
      const params = new Map<string, string>();
      params.set('field', VideoSmartAlbumTooltipUtil.fieldLabel(f));
      params.set('value', s);
      return L10n.t('smart_album_tooltip_contains', '包含', params);
    }

    if (op !== 'gt' && op !== 'eq' && op !== 'lt') {
      return '';
    }
    const n = Number(value);
    if (!Number.isFinite(n)) {
      return '';
    }

    const opText = op === 'gt'
      ? L10n.t('smart_album_cmp_gt', '大于')
      : (op === 'lt' ? L10n.t('smart_album_cmp_lt', '小于')
        : L10n.t('smart_album_cmp_eq', '等于'));

    const v = n % 1 === 0 ? `${Math.trunc(n)}` : `${n}`;
    const params = new Map<string, string>();
    params.set('field', VideoSmartAlbumTooltipUtil.fieldLabel(f));
    params.set('op', opText);
    params.set('value', v);
    if (f === 'duration_min') {
      params.set('unit', L10n.t('smart_album_unit_min', '分钟'));
      return L10n.t('smart_album_tooltip_compare', '比较', params);
    }
    return L10n.t('smart_album_tooltip_compare_no_unit', '比较', params);
  }
}

export { isTvMediaType };
