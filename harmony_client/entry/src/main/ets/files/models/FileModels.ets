/**
 * 文件模块数据模型（对齐 Flutter items Map<String, dynamic> 结构与 parts/format.dart、file_stats_service.dart）
 */

/** 服务端文件/目录条目（字段读取统一用 FileModelAccess 辅助函数） */
export class FileItem {
  path?: string;
  name?: string;
  type?: string;
  ext?: string;
  size?: number;
  /** 服务端可能下发数字或字符串，统一在使用处转换 */
  mtimeMs?: number | string;
  virtualType?: string;
  isCustomPath?: boolean;
  fileHash?: string;
}

/** FileItem 字段便捷读取（空值兜底，对齐 Flutter `item['x']?.toString() ?? ''` 用法） */
export class FileModelAccess {
  static path(it: FileItem): string {
    return it.path ?? '';
  }

  static fileName(it: FileItem): string {
    return it.name ?? '';
  }

  static type(it: FileItem): string {
    return it.type ?? '';
  }

  static ext(it: FileItem): string {
    return it.ext ?? '';
  }

  static virtualType(it: FileItem): string {
    return it.virtualType ?? '';
  }

  static isCustomPath(it: FileItem): boolean {
    return it.isCustomPath === true;
  }

  static size(it: FileItem): number {
    const s = it.size;
    return s === undefined ? -1 : s;
  }

  static mtimeMs(it: FileItem): number | undefined {
    const m = it.mtimeMs;
    if (m === undefined || m === null) {
      return undefined;
    }
    if (typeof m === 'number') {
      return m;
    }
    const parsed = Number(m);
    return Number.isNaN(parsed) ? undefined : parsed;
  }

  static isDir(it: FileItem): boolean {
    return FileModelAccess.type(it) === 'dir';
  }
}

/** POST /api/file/list 响应 data */
export class FileListData {
  base?: string;
  items?: Object[];
  segments?: Object[];
  sep?: string;
}

/** POST /api/file/search 响应 data */
export class FileSearchData {
  items?: Object[];
}

/** WS /api/file/stats 统计结果 */
export class FileStats {
  size: number = 0;
  count: number = 0;
  folderCount: number = 0;
  ctime?: string;
  mtime?: string;
  name?: string;
  path?: string;

  /** Node JSON.stringify(Date) 为带 Z 的 UTC ISO 字符串，解析后转本地时间戳 */
  static parseToLocalMs(value: string | undefined): number | undefined {
    if (value === undefined || value === null || value.length === 0) {
      return undefined;
    }
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? undefined : ms;
  }
}

/** 视频/图片等类型后缀（对齐 Flutter parts/directory.dart 常量） */
export class FileSuffixes {
  static readonly VIDEO: string[] = [
    '.mov', '.mp4', '.avi', '.rm', '.mkv', '.f4v', '.vob', '.mpg', '.rmvb',
    '.asf', '.mts', '.ts', '.wmv', '.m4v', '.m2ts', '.ogg', '.3gp', '.flv'
  ];
  static readonly IMAGE: string[] = [
    '.jpeg', '.jpg', '.png', '.heic', '.heif', '.hif', '.gif', '.webp', '.tiff',
    '.svg', '.bmp', '.dng', '.cr2', '.nef', '.orf', '.raf', '.raw', '.x3f',
    '.rw2', '.nrw', '.arw'
  ];
  static readonly ARCHIVE: string[] = ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz'];
  static readonly AUDIO: string[] = [
    '.mp3', '.flac', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape', '.m4a'
  ];
  static readonly DOCUMENT: string[] = [
    '.pdf', '.txt', '.md', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx',
    '.csv', '.epub', '.mobi', '.azw3'
  ];

  static isVideo(it: FileItem): boolean {
    return FileSuffixes.VIDEO.includes(FileModelAccess.ext(it).toLowerCase());
  }

  static isImage(it: FileItem): boolean {
    return FileSuffixes.IMAGE.includes(FileModelAccess.ext(it).toLowerCase());
  }

  static isArchive(it: FileItem): boolean {
    return FileSuffixes.ARCHIVE.includes(FileModelAccess.ext(it).toLowerCase());
  }

  static isAudio(it: FileItem): boolean {
    return FileSuffixes.AUDIO.includes(FileModelAccess.ext(it).toLowerCase());
  }

  static isDocument(it: FileItem): boolean {
    return FileSuffixes.DOCUMENT.includes(FileModelAccess.ext(it).toLowerCase());
  }
}

/** 文件名以 `.` 开头视为隐藏（与 Flutter file_item_dot_hidden.dart 一致） */
export function fileItemIsDotHidden(it: FileItem): boolean {
  const vt = it.virtualType ?? '';
  if (vt.length > 0) {
    return false;
  }
  const n = it.name ?? '';
  return n.length > 0 && n.startsWith('.');
}

/** 隐藏文件在列表中的不透明度 */
export const FILE_HIDDEN_LIST_OPACITY: number = 0.52;

/** 格式化工具（对齐 Flutter FileUtil.formatSize / format.dart formatMtime） */
export class FileFormat {
  static formatSize(bytes: number | undefined): string {
    const b = bytes === undefined || bytes === null ? 0 : bytes;
    if (b <= 0) {
      return '0 B';
    }
    const suffixes: string[] = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    const i = Math.floor(Math.log(b) / Math.log(1024));
    const v = b / Math.pow(1024, i);
    return `${v.toFixed(1)} ${suffixes[i]}`;
  }

  static formatMtime(ms: number | undefined): string {
    if (ms === undefined) {
      return '';
    }
    const dt = new Date(ms);
    const two = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    return `${dt.getFullYear()}-${two(dt.getMonth() + 1)}-${two(dt.getDate())} ` +
      `${two(dt.getHours())}:${two(dt.getMinutes())}`;
  }

  static formatFullTime(ms: number | undefined): string {
    if (ms === undefined) {
      return '';
    }
    const dt = new Date(ms);
    const two = (v: number): string => v < 10 ? `0${v}` : `${v}`;
    return `${dt.getFullYear()}-${two(dt.getMonth() + 1)}-${two(dt.getDate())} ` +
      `${two(dt.getHours())}:${two(dt.getMinutes())}:${two(dt.getSeconds())}`;
  }
}
