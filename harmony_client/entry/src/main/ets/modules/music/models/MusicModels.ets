/**
 * 音乐库模块数据模型（对齐 Flutter music 模块各 model 文件，fromJson 双写兼容）。
 * MusicListItem 用 @ObservedV2 + @Trace：列表项收藏等属性变更可刷新 UI。
 */

// ===== 解析辅助 =====

export function asStr(v: Object | undefined | null, fallback: string = ''): string {
  if (v === undefined || v === null) {
    return fallback;
  }
  return `${v}`;
}

export function asNum(v: Object | undefined | null, fallback: number = 0): number {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'number') {
    return v;
  }
  const parsed = Number(`${v}`);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function asBool(v: Object | undefined | null, fallback: boolean = false): boolean {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return v === 1;
  }
  if (typeof v === 'string') {
    const s = v.toLowerCase();
    if (s === 'true' || s === '1') {
      return true;
    }
    if (s === 'false' || s === '0') {
      return false;
    }
  }
  return fallback;
}

export function asArray(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

export function asRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
    return {};
  }
  return v as Record<string, Object>;
}

function asStringArray(v: Object | undefined | null): string[] {
  const out: string[] = [];
  for (const e of asArray(v)) {
    const s = `${e}`.trim();
    if (s.length > 0) {
      out.push(s);
    }
  }
  return out;
}

// ===== 排序枚举（值与 Flutter 枚举转参一致） =====

/** 音频文件浏览目录：带音频扩展名时取父目录（对齐 Flutter browseFolderPathMusic） */
export function browseMusicFolder(path: string): string {
  const s = path.trim();
  if (s.length === 0) {
    return '';
  }
  const i = s.lastIndexOf('.');
  if (i <= 0 || i === s.length - 1) {
    return s;
  }
  const ext = s.substring(i).toLowerCase();
  const audioExts = ['.mp3', '.flac', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape', '.m4a'];
  if (audioExts.indexOf(ext) < 0) {
    return s;
  }
  const slash = s.lastIndexOf('/');
  return slash > 0 ? s.substring(0, slash) : s;
}

export class MusicSortKeys {
  static readonly TITLE: string = 'title';
  static readonly ARTIST: string = 'artist';
  static readonly ALBUM: string = 'album';
  static readonly YEAR: string = 'year';
  static readonly DURATION: string = 'duration';
  static readonly CTIME: string = 'ctime';
  static readonly MTIME: string = 'mtime';
  static readonly FAVORITE_TIME: string = 'favorite_time';
  static readonly FILENAME: string = 'filename';
  static readonly COUNT: string = 'count';
  static readonly CREATE_TIME: string = 'create_time';
}

export class MusicLoopModes {
  static readonly SEQUENCE: string = 'sequence';
  static readonly LIST_LOOP: string = 'listLoop';
  static readonly SINGLE_LOOP: string = 'singleLoop';
  static readonly SHUFFLE: string = 'shuffle';
  /** 循环模式切换顺序：sequence→listLoop→singleLoop→shuffle→sequence（对齐 Flutter） */
  static readonly ORDER: string[] =
    [MusicLoopModes.SEQUENCE, MusicLoopModes.LIST_LOOP, MusicLoopModes.SINGLE_LOOP, MusicLoopModes.SHUFFLE];
}

// ===== MusicListItem =====

@ObservedV2
export class MusicListItem {
  @Trace id: number = 0;
  @Trace path: string = '';
  @Trace filename: string = '';
  @Trace fileHash: string = '';
  @Trace title: string = '';
  @Trace artist: string = '';
  @Trace album: string = '';
  @Trace year: number = 0;
  @Trace genre: string = '';
  /** 秒 */
  @Trace duration: number = 0;
  @Trace size: number = 0;
  @Trace ext: string = '';
  @Trace hasInnerCover: number = 0;
  @Trace showType: string = '';
  @Trace musicCount: number = 0;
  @Trace isFavorite: boolean = false;
  @Trace isFromFile: boolean = false;
  @Trace ctime: number = 0;
  @Trace mtime: number = 0;
  @Trace birthtime: number = 0;
  @Trace firstFilePath: string = '';
  @Trace fullPath: string = '';
  @Trace bitrate: number = 0;
  @Trace sampleRate: number = 0;
  @Trace bitDepth: number = -1;

  get isSeries(): boolean {
    return this.showType === 'series';
  }

  get displayTitle(): string {
    return this.filename.trim();
  }

  get displaySubtitle(): string {
    const a = this.artist.trim();
    const al = this.album.trim();
    if (a.length > 0 && al.length > 0) {
      return `${a} · ${al}`;
    }
    if (al.length > 0) {
      return al;
    }
    return a;
  }

  /** 可播放路径：full 或 path+'/'+filename（series 用 firstFilePath） */
  resolvePlayablePath(): string {
    if (this.isSeries) {
      const p = this.firstFilePath.trim();
      if (p.length > 0) {
        return p;
      }
    }
    const full = this.fullPath.trim();
    if (full.length > 0) {
      return full;
    }
    const base = this.path.trim();
    const name = this.filename.trim();
    if (base.length > 0 && name.length > 0) {
      return `${base}/${name}`;
    }
    return base;
  }

  /** 封面文件路径（isSeries 用 firstFilePath） */
  coverFilePath(): string {
    if (this.isSeries) {
      return this.firstFilePath.trim();
    }
    const full = this.fullPath.trim();
    if (full.length > 0) {
      return full;
    }
    const base = this.path.trim();
    const name = this.filename.trim();
    if (base.length > 0 && name.length > 0) {
      return `${base}/${name}`;
    }
    return base;
  }
}

export function musicItemFromJson(obj: Object | undefined | null): MusicListItem {
  const r = asRecord(obj);
  const it = new MusicListItem();
  it.id = Math.trunc(asNum(r['id']));
  it.path = asStr(r['path']).trim();
  it.filename = asStr(r['filename']);
  it.fileHash = asStr(r['file_hash'] ?? r['fileHash']).trim();
  it.title = asStr(r['title']);
  it.artist = asStr(r['artist']);
  it.album = asStr(r['album']);
  it.year = Math.trunc(asNum(r['year']));
  it.genre = asStr(r['genre']);
  it.duration = asNum(r['duration']);
  it.size = Math.trunc(asNum(r['size']));
  it.ext = asStr(r['ext']).trim();
  it.hasInnerCover = Math.trunc(asNum(r['has_inner_cover'] ?? r['hasInnerCover']));
  it.showType = asStr(r['show_type'] ?? r['showType']).trim();
  it.musicCount = Math.trunc(asNum(r['music_count'] ?? r['musicCount'], -1));
  it.isFavorite = asBool(r['is_favorite'] ?? r['isFavorite']);
  it.isFromFile = asBool(r['is_from_file'] ?? r['isFromFile']);
  it.ctime = Math.trunc(asNum(r['ctime']));
  it.mtime = Math.trunc(asNum(r['mtime']));
  it.birthtime = Math.trunc(asNum(r['birthtime']));
  it.firstFilePath = asStr(r['first_file_path'] ?? r['firstFilePath']).trim();
  it.fullPath = asStr(r['full_path'] ?? r['fullPath']).trim();
  it.bitrate = Math.trunc(asNum(r['bitrate']));
  it.sampleRate = Math.trunc(asNum(r['sample_rate'] ?? r['sampleRate']));
  it.bitDepth = r['bit_depth'] !== undefined && r['bit_depth'] !== null
    ? Math.trunc(asNum(r['bit_depth'], -1)) : -1;
  if (it.filename.length === 0) {
    // 与 Flutter 一致：filename 缺失时回退文件名（fullPath/path 最后一段）
    const raw = it.fullPath.length > 0 ? it.fullPath : it.path;
    const slash = raw.lastIndexOf('/');
    it.filename = slash >= 0 ? raw.substring(slash + 1) : raw;
  }
  return it;
}

export function musicItemsFromJson(v: Object | undefined | null): MusicListItem[] {
  const out: MusicListItem[] = [];
  for (const e of asArray(v)) {
    out.push(musicItemFromJson(e));
  }
  return out;
}

// ===== 分页 / 筛选 =====

@ObservedV2
export class MusicListPagination {
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace limit: number = 300;

  get hasNextPage(): boolean {
    if (this.total <= 0) {
      return false;
    }
    const size = this.limit <= 0 ? 300 : this.limit;
    const maxPage = Math.floor((this.total + size - 1) / size);
    return this.page < maxPage;
  }

  get hasPrevPage(): boolean {
    return this.page > 1;
  }
}

export function musicPaginationFromJson(v: Object | undefined | null): MusicListPagination {
  const r = asRecord(v);
  const p = new MusicListPagination();
  p.total = Math.trunc(asNum(r['total']));
  p.page = Math.trunc(asNum(r['page'], 1));
  p.limit = Math.trunc(asNum(r['limit'] ?? r['page_size'] ?? r['pageSize'], 300));
  if (p.limit <= 0) {
    p.limit = 300;
  }
  return p;
}

@ObservedV2
export class MusicListFilters {
  @Trace artists: string[] = [];
  @Trace albums: string[] = [];
  @Trace genres: string[] = [];
}

@ObservedV2
export class MusicListPathItem {
  @Trace path: string = '';
  @Trace valid: boolean = true;
}

@ObservedV2
export class MusicListPagedResult {
  @Trace items: MusicListItem[] = [];
  @Trace pagination: MusicListPagination = new MusicListPagination();
  @Trace filters: MusicListFilters = new MusicListFilters();
  @Trace validPaths: MusicListPathItem[] = [];

  static fromJson(obj: Object | undefined | null): MusicListPagedResult {
    const r = asRecord(obj);
    const res = new MusicListPagedResult();
    res.items = musicItemsFromJson(r['items']);
    res.pagination = musicPaginationFromJson(r['pagination']);
    const fr = asRecord(r['filters'] ?? r['filterOptions']);
    res.filters.artists = asStringArray(fr['artists']);
    res.filters.albums = asStringArray(fr['albums']);
    res.filters.genres = asStringArray(fr['genres']);
    const vp = r['validPaths'] ?? r['valid_paths'];
    if (Array.isArray(vp)) {
      for (const e of vp as Object[]) {
        if (typeof e === 'string') {
          const p = new MusicListPathItem();
          p.path = `${e}`;
          res.validPaths.push(p);
        } else {
          const pr = asRecord(e);
          const p = new MusicListPathItem();
          p.path = asStr(pr['path']).trim();
          p.valid = asBool(pr['valid'], true);
          res.validPaths.push(p);
        }
      }
    }
    return res;
  }
}

// ===== 列表计数 / 删除 =====

export class MusicListCountResult {
  songs: number = 0;

  static fromJson(obj: Object | undefined | null): MusicListCountResult {
    const r = asRecord(obj);
    const res = new MusicListCountResult();
    res.songs = Math.trunc(asNum(r['songs']));
    return res;
  }
}

// ===== 专辑 / 艺人分组 =====

@ObservedV2
export class AlbumArtistGroupItem {
  @Trace keyType: string = '';
  @Trace name: string = '';
  @Trace firstFilePath: string = '';
  @Trace indexCount: number = 0;
}

@ObservedV2
export class AlbumArtistListPagedResult {
  @Trace items: AlbumArtistGroupItem[] = [];
  @Trace pagination: MusicListPagination = new MusicListPagination();
  @Trace validPaths: MusicListPathItem[] = [];

  static fromJson(obj: Object | undefined | null): AlbumArtistListPagedResult {
    const r = asRecord(obj);
    const res = new AlbumArtistListPagedResult();
    for (const e of asArray(r['items'])) {
      const er = asRecord(e);
      const it = new AlbumArtistGroupItem();
      it.keyType = asStr(er['key_type'] ?? er['keyType']).trim();
      it.name = asStr(er['name']);
      it.firstFilePath = asStr(er['first_file_path'] ?? er['firstFilePath']).trim();
      it.indexCount = Math.trunc(asNum(er['index_count'] ?? er['indexCount']));
      res.items.push(it);
    }
    res.pagination = musicPaginationFromJson(r['pagination']);
    const vp = r['validPaths'] ?? r['valid_paths'];
    if (Array.isArray(vp)) {
      for (const e of vp as Object[]) {
        const pr = asRecord(e);
        const p = new MusicListPathItem();
        p.path = typeof e === 'string' ? `${e}` : asStr(pr['path']).trim();
        p.valid = typeof e === 'string' ? true : asBool(pr['valid'], true);
        res.validPaths.push(p);
      }
    }
    return res;
  }
}

// ===== 歌单 =====

@ObservedV2
export class PlayListItem {
  @Trace id: number = 0;
  @Trace uid: number = 0;
  @Trace name: string = '';
  @Trace createTime: string = '';
  @Trace previews: MusicListItem[] = [];

  static fromJson(obj: Object | undefined | null): PlayListItem {
    const r = asRecord(obj);
    const it = new PlayListItem();
    it.id = Math.trunc(asNum(r['id']));
    it.uid = Math.trunc(asNum(r['uid']));
    it.name = asStr(r['name']);
    it.createTime = asStr(r['create_time'] ?? r['createTime']);
    it.previews = musicItemsFromJson(r['previews']);
    return it;
  }
}

@ObservedV2
export class PlayListPagedResult {
  @Trace items: PlayListItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace pageSize: number = 30;

  get hasNextPage(): boolean {
    const size = this.pageSize <= 0 ? 30 : this.pageSize;
    const maxPage = this.total <= 0 ? 1 : Math.floor((this.total + size - 1) / size);
    return this.page < maxPage;
  }

  static fromJson(obj: Object | undefined | null): PlayListPagedResult {
    const r = asRecord(obj);
    const res = new PlayListPagedResult();
    for (const e of asArray(r['items'])) {
      res.items.push(PlayListItem.fromJson(e));
    }
    const pr = asRecord(r['pagination']);
    res.total = Math.trunc(asNum(pr['total']));
    res.page = Math.trunc(asNum(pr['page'], 1));
    res.pageSize = Math.trunc(asNum(pr['pageSize'] ?? pr['page_size'], 30));
    return res;
  }
}

// ===== 合集 =====

@ObservedV2
export class MusicCollectionPreviewItem {
  @Trace id: number = 0;
  @Trace path: string = '';
  @Trace filename: string = '';
  @Trace showType: string = '';
  @Trace firstFilePath: string = '';
  @Trace hasInnerCover: number = 0;

  get fullPath(): string {
    const p = this.path.trim();
    const f = this.filename.trim();
    if (p.length === 0) {
      return '';
    }
    if (f.length === 0) {
      return p;
    }
    if (p.endsWith('/')) {
      return `${p}${f}`;
    }
    return `${p}/${f}`;
  }
}

@ObservedV2
export class MusicCollectionItem {
  @Trace id: number = 0;
  @Trace ownerId: number = 0;
  @Trace name: string = '';
  @Trace pathList: string[] = [];
  @Trace createTime: string = '';
  @Trace previews: MusicCollectionPreviewItem[] = [];

  static fromJson(obj: Object | undefined | null): MusicCollectionItem {
    const r = asRecord(obj);
    const it = new MusicCollectionItem();
    it.id = Math.trunc(asNum(r['id']));
    it.ownerId = Math.trunc(asNum(r['uid']));
    it.name = asStr(r['name']);
    it.pathList = asStringArray(r['path_list'] ?? r['pathList']);
    it.createTime = asStr(r['create_time'] ?? r['createTime']);
    for (const e of asArray(r['previews'])) {
      const er = asRecord(e);
      const p = new MusicCollectionPreviewItem();
      p.id = Math.trunc(asNum(er['id']));
      p.path = asStr(er['path']).trim();
      p.filename = asStr(er['filename']);
      p.showType = asStr(er['show_type'] ?? er['showType']).trim();
      p.firstFilePath = asStr(er['first_file_path'] ?? er['firstFilePath']).trim();
      p.hasInnerCover = Math.trunc(asNum(er['has_inner_cover'] ?? er['hasInnerCover']));
      if (p.id > 0) {
        it.previews.push(p);
      }
    }
    return it;
  }
}

@ObservedV2
export class MusicCollectionListResult {
  @Trace items: MusicCollectionItem[] = [];
  @Trace total: number = 0;
  @Trace page: number = 1;
  @Trace pageSize: number = 20;

  get hasNextPage(): boolean {
    const size = this.pageSize <= 0 ? 20 : this.pageSize;
    const maxPage = this.total <= 0 ? 1 : Math.floor((this.total + size - 1) / size);
    return this.page < maxPage;
  }

  static fromJson(obj: Object | undefined | null): MusicCollectionListResult {
    const r = asRecord(obj);
    const res = new MusicCollectionListResult();
    for (const e of asArray(r['items'])) {
      const it = MusicCollectionItem.fromJson(e);
      if (it.id > 0) {
        res.items.push(it);
      }
    }
    const pr = asRecord(r['pagination']);
    res.total = Math.trunc(asNum(pr['total']));
    res.page = Math.trunc(asNum(pr['page'], 1));
    res.pageSize = Math.trunc(asNum(pr['pageSize'], 20));
    return res;
  }
}

// ===== 音乐源 =====

@ObservedV2
export class MusicSource {
  @Trace id: number = 0;
  @Trace path: string = '';
  @Trace exists: boolean = true;
  @Trace scanWhenStart: boolean = false;
  @Trace scanWhenChange: boolean = false;
  @Trace isShow: boolean = true;
  @Trace showType: string = '';
  @Trace scanInterval: number = 0;
  @Trace scanIntervalMs: number = 0;
  @Trace lastScanTime: number = 0;

  static fromJson(obj: Object | undefined | null): MusicSource {
    const r = asRecord(obj);
    const it = new MusicSource();
    it.id = Math.trunc(asNum(r['id']));
    it.path = asStr(r['path']).trim();
    it.exists = asBool(r['exists'], true);
    it.scanWhenStart = asBool(r['scan_when_start'] ?? r['scanWhenStart']);
    it.scanWhenChange = asBool(r['scan_when_change'] ?? r['scanWhenChange']);
    it.isShow = asBool(r['is_show'] ?? r['isShow'], true);
    it.showType = asStr(r['show_type'] ?? r['showType']).trim();
    it.scanInterval = Math.trunc(asNum(r['scan_interval'] ?? r['scanInterval']));
    it.scanIntervalMs = Math.trunc(asNum(r['scan_interval_ms'] ?? r['scanIntervalMs']));
    it.lastScanTime = Math.trunc(asNum(r['last_scan_time'] ?? r['lastScanTime']));
    return it;
  }
}

// ===== 歌词搜索 =====

@ObservedV2
export class LyricSearchItem {
  @Trace id: string = '';
  @Trace source: string = '';
  @Trace title: string = '';
  @Trace album: string = '';
  @Trace artist: string = '';
  /** 毫秒（服务端为字符串） */
  @Trace durationMs: number = 0;
  @Trace preview: string = '';
  @Trace lrc: string = '';

  static fromJson(obj: Object): LyricSearchItem {
    const r = asRecord(obj);
    const it = new LyricSearchItem();
    it.id = asStr(r['id']).trim();
    it.source = asStr(r['source']).trim();
    it.title = asStr(r['title']).trim();
    it.album = asStr(r['album']).trim();
    it.artist = asStr(r['artist']).trim();
    it.durationMs = Math.trunc(asNum(r['duration']));
    it.preview = asStr(r['preview']);
    it.lrc = asStr(r['lrc']);
    return it;
  }

  get durationSec(): number {
    return Math.max(0, Math.round(this.durationMs / 1000));
  }

  /** LRC 第一句文本（对齐 Flutter previewLine） */
  get previewLine(): string {
    const text = this.lrc.trim();
    if (text.length === 0) {
      return '';
    }
    const lines = text.split('\n');
    for (let raw of lines) {
      const line = raw.trim();
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('[') && line.includes(']')) {
        const idx = line.lastIndexOf(']');
        const after = idx >= 0 ? line.substring(idx + 1).trim() : '';
        if (after.length > 0) {
          return after;
        }
        continue;
      }
      return line;
    }
    return '';
  }
}

// ===== 通用响应包装 =====

export class MusicApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;

  static ok<T>(data: T | undefined, message: string = ''): MusicApiResult<T> {
    const r = new MusicApiResult<T>();
    r.success = true;
    r.data = data;
    r.message = message;
    return r;
  }

  static fail<T>(message: string): MusicApiResult<T> {
    const r = new MusicApiResult<T>();
    r.success = false;
    r.message = message;
    return r;
  }
}
