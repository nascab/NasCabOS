import { L10n } from '../../../core/localization/L10n';
import { util } from '@kit.ArkTS';

/**
 * 加密空间数据模型（对齐 Flutter encrypted_space_controller.dart 中的模型与常量）。
 */

/** 已解锁的活动加密空间（对齐 EncryptedSpaceActiveSpace） */
export class EncryptedSpaceActiveSpace {
  spaceId: number = 0;
  token: string = '';
  name: string = '';
  path: string = '';

  constructor(spaceId: number, token: string, name: string, path: string) {
    this.spaceId = spaceId;
    this.token = token;
    this.name = name;
    this.path = path;
  }
}

/** 文件列表文件条目（对齐 Flutter files Map 的常用字段） */
@ObservedV2
export class EncryptedFileItem {
  @Trace indexId: number = 0;
  @Trace fileType: string = 'other';
  @Trace showName: string = '';
  @Trace size: number = 0;
  @Trace duration: number = 0;

  displayTitle(): string {
    return this.showName.length > 0 ? this.showName : `${this.indexId}`;
  }
}

/** 后端记录 → 文件条目（file_type/show_name 解析对齐 fileTypeOf/displayNameOf） */
export function encryptedFileItemFrom(rec: Record<string, Object>): EncryptedFileItem {
  const it = new EncryptedFileItem();
  it.indexId = encryptedSpaceToInt(rec['id']);
  const t = `${rec['file_type'] ?? ''}`.trim().toLowerCase();
  it.fileType = (t === 'image' || t === 'video') ? t : 'other';
  it.showName = encryptedSpaceDisplayName(rec);
  it.size = encryptedSpaceToInt(rec['size']);
  it.duration = encryptedSpaceToInt(rec['duration']);
  return it;
}

export function encryptedSpaceToInt(v: Object | undefined | null): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  const n = Number(`${v}`);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

/** 显示名：show_name 优先，否则 base64 解码 filename（对齐 displayNameOf） */
export function encryptedSpaceDisplayName(rec: Record<string, Object>): string {
  const showName = `${rec['show_name'] ?? ''}`.trim();
  if (showName.length > 0) {
    return showName;
  }
  const b64 = `${rec['filename'] ?? ''}`.trim();
  if (b64.length === 0) {
    return '';
  }
  try {
    const bytes = new util.Base64Helper().decodeSync(b64);
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(bytes);
  } catch (_e) {
    return b64;
  }
}

/** 文件列表排序项（对齐 _EncryptedSpaceSortEntry，labelKey 为主语言包既有 key） */
export class EncryptedSpaceSortEntry {
  field: string = '';
  order: string = '';
  labelKey: string = '';

  constructor(field: string, order: string, labelKey: string) {
    this.field = field;
    this.order = order;
    this.labelKey = labelKey;
  }
}

/** App 端底部排序弹层条目（对齐 _getEncryptedSpaceSortEntries） */
export function encryptedSpaceSortEntries(): EncryptedSpaceSortEntry[] {
  const out: EncryptedSpaceSortEntry[] = [];
  out.push(new EncryptedSpaceSortEntry('show_name', 'asc', 'name_asc'));
  out.push(new EncryptedSpaceSortEntry('show_name', 'desc', 'name_desc'));
  out.push(new EncryptedSpaceSortEntry('create_time', 'asc', 'photo_album_sort_create_time_asc'));
  out.push(new EncryptedSpaceSortEntry('create_time', 'desc', 'photo_album_sort_create_time_desc'));
  out.push(new EncryptedSpaceSortEntry('original_time', 'asc', 'photo_timeline_sort_asc'));
  out.push(new EncryptedSpaceSortEntry('original_time', 'desc', 'photo_timeline_sort_desc'));
  out.push(new EncryptedSpaceSortEntry('size', 'asc', 'folder_picker_sort_size_asc'));
  out.push(new EncryptedSpaceSortEntry('size', 'desc', 'folder_picker_sort_size_desc'));
  out.push(new EncryptedSpaceSortEntry('duration', 'asc', 'music_list_sort_duration_asc'));
  out.push(new EncryptedSpaceSortEntry('duration', 'desc', 'music_list_sort_duration_desc'));
  return out;
}

/** 根据排序字段/顺序取 labelKey（对齐 _getEncryptedSpaceDetailSortLabelKey） */
export function encryptedSpaceSortLabelKey(field: string, order: string): string {
  const entries = encryptedSpaceSortEntries();
  for (const e of entries) {
    if (e.field === field && e.order === order) {
      return e.labelKey;
    }
  }
  return '';
}

/** 类型筛选可选项（与后端 private_space_index.file_type 一致：all / image / video / other） */
export const ENCRYPTED_SPACE_FILE_TYPE_OPTIONS: string[] = ['all', 'image', 'video', 'other'];

/** 类型筛选文案（对齐 _getFileTypeFilterLabel） */
export function encryptedSpaceFilterLabel(value: string): string {
  if (value === 'image') {
    return L10n.t('file_type_image', '图片');
  }
  if (value === 'video') {
    return L10n.t('file_type_video', '视频');
  }
  if (value === 'other') {
    return L10n.t('encrypted_space_filter_other', '其他文件');
  }
  return L10n.t('all', '全部');
}

/** 列表允许的排序字段（对齐 _allowedSortFields） */
export const ENCRYPTED_SPACE_SORT_FIELDS: string[] =
  ['id', 'create_time', 'check_time', 'original_time', 'size', 'duration', 'show_name'];

/** 非媒体文件的类型图标（对齐 Flutter iconForName 的 assets/icons/file 映射） */
export function encryptedSpaceFileIcon(name: string): Resource {
  const dot = name.lastIndexOf('.');
  const ext = dot >= 0 && dot < name.length - 1 ? name.substring(dot + 1).toLowerCase() : '';
  if (ext === 'epub' || ext === 'mobi' || ext === 'azw3') {
    return $rawfile('icons/file/ebook.png');
  }
  if (ext === 'doc') {
    return $rawfile('icons/file/doc.png');
  }
  if (ext === 'docx') {
    return $rawfile('icons/file/docx.png');
  }
  if (ext === 'xls') {
    return $rawfile('icons/file/xls.png');
  }
  if (ext === 'xlsx') {
    return $rawfile('icons/file/xlsx.png');
  }
  if (ext === 'xml') {
    return $rawfile('icons/file/xml.png');
  }
  if (ext === 'txt') {
    return $rawfile('icons/file/txt.png');
  }
  if (ext === 'log') {
    return $rawfile('icons/file/log.png');
  }
  if (ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav' || ext === 'ogg'
    || ext === 'opus' || ext === 'wma' || ext === 'ape') {
    return $rawfile('icons/file/audio.png');
  }
  return $rawfile('icons/file/file.png');
}
