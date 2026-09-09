/**
 * 图书馆模块数据模型（对齐 Flutter book 模块各 model / *_api_service.dart 内嵌模型）。
 * BookListItem 用 @ObservedV2 + @Trace：收藏等属性变更可刷新 UI。
 */

// ===== 解析辅助 =====

export function bStr(v: Object | undefined | null, fallback: string = ''): string {
  if (v === undefined || v === null) {
    return fallback;
  }
  return `${v}`.trim();
}

export function bNum(v: Object | undefined | null, fallback: number = 0): number {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'number') {
    return v;
  }
  const parsed = Number(`${v}`);
  return Number.isNaN(parsed) ? fallback : parsed;
}

export function bBool(v: Object | undefined | null, fallback: boolean = false): boolean {
  if (v === undefined || v === null) {
    return fallback;
  }
  if (typeof v === 'boolean') {
    return v;
  }
  if (typeof v === 'number') {
    return v === 1;
  }
  const s = `${v}`.toLowerCase();
  if (s === '1' || s === 'true') {
    return true;
  }
  if (s === 'false' || s === '0') {
    return false;
  }
  return fallback;
}

export function bArray(v: Object | undefined | null): Object[] {
  if (v === undefined || v === null || !Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

export function bRecord(v: Object | undefined | null): Record<string, Object> {
  if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
    return {};
  }
  return v as Record<string, Object>;
}

export function bStringArray(v: Object | undefined | null): string[] {
  const out: string[] = [];
  for (const e of bArray(v)) {
    const s = `${e}`.trim();
    if (s.length > 0) {
      out.push(s);
    }
  }
  return out;
}

// ===== API 结果包装 =====

export class BookApiResult<T> {
  success: boolean = false;
  message: string = '';
  data: T | undefined = undefined;

  static ok<D>(data: D | undefined, message: string = ''): BookApiResult<D> {
    const r = new BookApiResult<D>();
    r.success = true;
    r.data = data;
    r.message = message;
    return r;
  }

  static fail<D>(message: string): BookApiResult<D> {
    const r = new BookApiResult<D>();
    r.success = false;
    r.message = message;
    return r;
  }
}

// ===== 排序（对齐 Flutter BookListSortBy/BookListSortOrder） =====

export class BookSortBy {
  static readonly VIEW_TIME: string = 'view_time';
  static readonly CREATE_TIME: string = 'create_time';
  static readonly FAVORITE_TIME: string = 'favorite_time';
  static readonly NAME: string = 'name';
}

export const BOOK_SORT_ORDER_ASC = 'asc';
export const BOOK_SORT_ORDER_DESC = 'desc';

// ===== /api/book/list/count =====

export class BookIndexCountResult {
  book: number = 0;
  comic: number = 0;

  get total(): number {
    return this.book + this.comic;
  }

  static fromJson(obj: Object): BookIndexCountResult {
    const r = new BookIndexCountResult();
    const rec = bRecord(obj);
    r.book = bNum(rec['book']);
    r.comic = bNum(rec['comic']);
    return r;
  }
}

// ===== /api/book/list 列表项 =====

@ObservedV2
export class BookListItem {
  @Trace id: number = 0;
  @Trace type: string = '';
  @Trace path: string = '';
  @Trace filename: string = '';
  @Trace fileHash: string = '';
  @Trace title: string = '';
  @Trace artist: string = '';
  @Trace year: string = '';
  @Trace ext: string = '';
  @Trace size: number = 0;
  @Trace coverState: number = 0;
  @Trace viewTime: number = 0;
  @Trace createTime: string = '';
  @Trace fullPath: string = '';
  @Trace showType: string = '';
  @Trace firstFilePath: string = '';
  @Trace totalPage: number = 0;
  @Trace bookCount: number = 0;
  @Trace isFavorite: boolean = false;
  @Trace currentPage: number = 0;
  @Trace fraction: number = 0;
  @Trace lastReadAt: string = '';

  get displayTitle(): string {
    return this.title.trim().length > 0 ? this.title.trim() : this.filename;
  }

  get extLabel(): string {
    const e = this.ext.trim();
    if (e.length === 0) {
      return '';
    }
    const noDot = e.startsWith('.') ? e.substring(1) : e;
    return noDot.toUpperCase();
  }

  get isSeries(): boolean {
    return this.showType === 'series';
  }

  get isComicType(): boolean {
    return this.type === 'comic';
  }

  get isBookType(): boolean {
    return this.type === 'book';
  }

  static fromJson(obj: Object): BookListItem {
    const r = new BookListItem();
    const j = bRecord(obj);
    r.id = bNum(j['id']);
    r.type = bStr(j['type']);
    r.path = bStr(j['path']);
    r.filename = bStr(j['filename']);
    r.fileHash = j['file_hash'] !== undefined && j['file_hash'] !== null
      ? bStr(j['file_hash'])
      : bStr(j['fileHash']);
    r.title = bStr(j['title']);
    r.artist = bStr(j['artist']);
    r.year = bStr(j['year']);
    r.ext = bStr(j['ext']);
    r.size = bNum(j['size']);
    r.coverState = j['cover_state'] !== undefined && j['cover_state'] !== null
      ? bNum(j['cover_state'])
      : bNum(j['coverState']);
    r.viewTime = j['view_time'] !== undefined && j['view_time'] !== null
      ? bNum(j['view_time'])
      : bNum(j['viewTime']);
    r.createTime = j['create_time'] !== undefined && j['create_time'] !== null
      ? bStr(j['create_time'])
      : bStr(j['createTime']);
    r.fullPath = j['full_path'] !== undefined && j['full_path'] !== null
      ? bStr(j['full_path'])
      : bStr(j['fullPath']);
    r.showType = j['show_type'] !== undefined && j['show_type'] !== null
      ? bStr(j['show_type'])
      : bStr(j['showType']);
    r.firstFilePath = j['first_file_path'] !== undefined && j['first_file_path'] !== null
      ? bStr(j['first_file_path'])
      : bStr(j['firstFilePath']);
    r.totalPage = j['total_page'] !== undefined && j['total_page'] !== null
      ? bNum(j['total_page'])
      : bNum(j['totalPage']);
    r.bookCount = j['book_count'] !== undefined && j['book_count'] !== null
      ? bNum(j['book_count'])
      : bNum(j['bookCount']);
    r.isFavorite = j['is_favorite'] !== undefined && j['is_favorite'] !== null
      ? bBool(j['is_favorite'])
      : bBool(j['isFavorite']);
    r.currentPage = j['current_page'] !== undefined && j['current_page'] !== null
      ? bNum(j['current_page'])
      : bNum(j['currentPage']);
    r.fraction = bNum(j['fraction']);
    r.lastReadAt = j['last_read_at'] !== undefined && j['last_read_at'] !== null
      ? bStr(j['last_read_at'])
      : bStr(j['lastReadAt']);
    return r;
  }

  static listFrom(v: Object | undefined | null): BookListItem[] {
    const out: BookListItem[] = [];
    for (const e of bArray(v)) {
      out.push(BookListItem.fromJson(e));
    }
    return out;
  }

  /** 对齐 Flutter copyWith(isFavorite:) */
  copyWithFavorite(next: boolean): BookListItem {
    const r = new BookListItem();
    r.id = this.id;
    r.type = this.type;
    r.path = this.path;
    r.filename = this.filename;
    r.fileHash = this.fileHash;
    r.title = this.title;
    r.artist = this.artist;
    r.year = this.year;
    r.ext = this.ext;
    r.size = this.size;
    r.coverState = this.coverState;
    r.viewTime = this.viewTime;
    r.createTime = this.createTime;
    r.fullPath = this.fullPath;
    r.showType = this.showType;
    r.firstFilePath = this.firstFilePath;
    r.totalPage = this.totalPage;
    r.bookCount = this.bookCount;
    r.isFavorite = next;
    r.currentPage = this.currentPage;
    r.fraction = this.fraction;
    r.lastReadAt = this.lastReadAt;
    return r;
  }
}

// ===== 分页 =====

export class BookListPagination {
  total: number = 0;
  page: number = 1;
  limit: number = 30;
  totalPages: number = 0;
  hasNextPage: boolean = false;
  hasPrevPage: boolean = false;

  static empty(): BookListPagination {
    return new BookListPagination();
  }

  static fromJson(obj: Object): BookListPagination {
    const r = new BookListPagination();
    const j = bRecord(obj);
    r.total = bNum(j['total']);
    r.page = bNum(j['page'], 1);
    r.limit = bNum(j['limit'], 30);
    r.totalPages = bNum(j['totalPages']);
    r.hasNextPage = bBool(j['hasNextPage']);
    r.hasPrevPage = bBool(j['hasPrevPage']);
    return r;
  }
}

export class BookListPathItem {
  path: string = '';
  valid: boolean = false;

  static fromJson(obj: Object): BookListPathItem {
    const r = new BookListPathItem();
    const j = bRecord(obj);
    r.path = bStr(j['path']);
    r.valid = bBool(j['valid']);
    return r;
  }

  static listFrom(v: Object | undefined | null): BookListPathItem[] {
    const out: BookListPathItem[] = [];
    for (const e of bArray(v)) {
      out.push(BookListPathItem.fromJson(e));
    }
    return out;
  }
}

export class BookListPagedResult {
  items: BookListItem[] = [];
  pagination: BookListPagination = BookListPagination.empty();
  validPaths: BookListPathItem[] = [];

  static empty(): BookListPagedResult {
    return new BookListPagedResult();
  }

  static fromJson(obj: Object): BookListPagedResult {
    const r = new BookListPagedResult();
    const j = bRecord(obj);
    r.items = BookListItem.listFrom(j['items']);
    r.pagination = BookListPagination.fromJson(bRecord(j['pagination']));
    r.validPaths = BookListPathItem.listFrom(j['validPaths']);
    return r;
  }
}

// ===== 自建书单（/api/book/book_list/*） =====

export class BookCustomListItem {
  id: number = 0;
  uid: number = 0;
  name: string = '';
  createTime: string = '';
  previews: BookListItem[] = [];

  static fromJson(obj: Object): BookCustomListItem {
    const r = new BookCustomListItem();
    const j = bRecord(obj);
    r.id = bNum(j['id']);
    r.uid = bNum(j['uid']);
    r.name = bStr(j['name']);
    r.createTime = j['create_time'] !== undefined && j['create_time'] !== null
      ? bStr(j['create_time'])
      : bStr(j['createTime']);
    r.previews = BookListItem.listFrom(j['previews']);
    return r;
  }

  static listFrom(v: Object | undefined | null): BookCustomListItem[] {
    const out: BookCustomListItem[] = [];
    for (const e of bArray(v)) {
      out.push(BookCustomListItem.fromJson(e));
    }
    return out;
  }
}

export class BookCustomListPagination {
  total: number = 0;
  page: number = 1;
  pageSize: number = 30;

  static empty(): BookCustomListPagination {
    return new BookCustomListPagination();
  }

  static fromJson(obj: Object): BookCustomListPagination {
    const r = new BookCustomListPagination();
    const j = bRecord(obj);
    r.total = bNum(j['total']);
    r.page = bNum(j['page'], 1);
    r.pageSize = j['pageSize'] !== undefined && j['pageSize'] !== null
      ? bNum(j['pageSize'], 30)
      : bNum(j['page_size'], 30);
    return r;
  }

  get hasNextPage(): boolean {
    const size = this.pageSize <= 0 ? 30 : this.pageSize;
    const maxPage = this.total <= 0 ? 1 : Math.floor((this.total + size - 1) / size);
    return this.page < maxPage;
  }
}

export class BookCustomListPagedResult {
  items: BookCustomListItem[] = [];
  pagination: BookCustomListPagination = BookCustomListPagination.empty();

  static empty(): BookCustomListPagedResult {
    return new BookCustomListPagedResult();
  }

  static fromJson(obj: Object): BookCustomListPagedResult {
    const r = new BookCustomListPagedResult();
    const j = bRecord(obj);
    r.items = BookCustomListItem.listFrom(j['items']);
    r.pagination = BookCustomListPagination.fromJson(bRecord(j['pagination']));
    return r;
  }
}

// ===== 合集（/api/book/collection/*） =====

export class BookCollectionPreviewItem {
  id: number = 0;
  fileHash: string = '';
  showType: string = '';
  coverState: number = 0;
  fullPath: string = '';
  firstFilePath: string = '';

  static fromJson(obj: Object): BookCollectionPreviewItem {
    const r = new BookCollectionPreviewItem();
    const j = bRecord(obj);
    r.id = bNum(j['id']);
    r.fileHash = bStr(j['file_hash']);
    r.showType = bStr(j['show_type']);
    r.coverState = bNum(j['cover_state']);
    r.fullPath = bStr(j['full_path']);
    r.firstFilePath = bStr(j['first_file_path']);
    return r;
  }

  static listFrom(v: Object | undefined | null): BookCollectionPreviewItem[] {
    const out: BookCollectionPreviewItem[] = [];
    for (const e of bArray(v)) {
      const it = BookCollectionPreviewItem.fromJson(e);
      if (it.id > 0) {
        out.push(it);
      }
    }
    return out;
  }
}

export class BookCollectionItem {
  id: number = 0;
  ownerId: number = 0;
  name: string = '';
  pathList: string[] = [];
  createTime: string = '';
  previews: BookCollectionPreviewItem[] = [];

  static fromJson(obj: Object): BookCollectionItem {
    const r = new BookCollectionItem();
    const j = bRecord(obj);
    r.id = bNum(j['id']);
    r.ownerId = bNum(j['uid']);
    r.name = bStr(j['name']);
    r.pathList = bStringArray(j['path_list']);
    r.createTime = bStr(j['create_time']);
    r.previews = BookCollectionPreviewItem.listFrom(j['previews']);
    return r;
  }

  static listFrom(v: Object | undefined | null): BookCollectionItem[] {
    const out: BookCollectionItem[] = [];
    for (const e of bArray(v)) {
      const it = BookCollectionItem.fromJson(e);
      if (it.id > 0) {
        out.push(it);
      }
    }
    return out;
  }
}

export class BookCollectionListResult {
  items: BookCollectionItem[] = [];
  total: number = 0;
  page: number = 1;
  pageSize: number = 20;

  static fromJson(obj: Object): BookCollectionListResult {
    const r = new BookCollectionListResult();
    const j = bRecord(obj);
    r.items = BookCollectionItem.listFrom(j['items']);
    const pagination = bRecord(j['pagination']);
    r.total = bNum(pagination['total']);
    r.page = bNum(pagination['page'], 1);
    r.pageSize = bNum(pagination['pageSize'], 20);
    return r;
  }
}

// ===== 来源路径（/api/book/source/*，对齐 BookSource） =====

export class BookSource {
  id: number = 0;
  path: string = '';
  exists: boolean = true;
  scanWhenStart: number = 0;
  scanWhenChange: number = 1;
  isShow: number = 1;
  ctime: string = '';
  scanInterval: number = 0;
  scanIntervalMs: number = 0;
  scanIntervalConfig: string = '';
  lastScanTime: number = 0;
  showType: string = 'book';

  static fromJson(obj: Object): BookSource {
    const r = new BookSource();
    const j = bRecord(obj);
    r.id = bNum(j['id']);
    r.path = bStr(j['path']);
    r.exists = bBool(j['exists'], true);
    r.scanWhenStart = bNum(j['scan_when_start']);
    r.scanWhenChange = bNum(j['scan_when_change'], 1);
    r.isShow = bNum(j['is_show'], 1);
    r.ctime = j['ctime'] !== undefined && j['ctime'] !== null ? `${j['ctime']}` : '';
    r.scanInterval = bNum(j['scan_interval']);
    r.scanIntervalMs = bNum(j['scan_interval_ms']);
    r.scanIntervalConfig = j['scan_interval_config'] !== undefined && j['scan_interval_config'] !== null
      ? `${j['scan_interval_config']}` : '';
    r.lastScanTime = bNum(j['last_scan_time']);
    const st = bStr(j['show_type']);
    r.showType = st.length > 0 ? st : 'book';
    return r;
  }

  static listFrom(v: Object | undefined | null): BookSource[] {
    const out: BookSource[] = [];
    for (const e of bArray(v)) {
      out.push(BookSource.fromJson(e));
    }
    return out;
  }
}

// ===== 文件扩展名（对齐 electron_server config bookTypeList） =====

export class BookFormat {
  /** 服务器支持的图书格式（.txt .epub .pdf .mobi .azw3 .cbz .cbr .rar .zip） */
  static readonly BOOK_TYPE_LIST: string[] =
    ['.txt', '.epub', '.pdf', '.mobi', '.azw3', '.cbz', '.cbr', '.rar', '.zip'];

  static isSupported(ext: string): boolean {
    let e = ext.trim().toLowerCase();
    if (e.length === 0) {
      return false;
    }
    if (!e.startsWith('.')) {
      e = `.${e}`;
    }
    return BookFormat.BOOK_TYPE_LIST.indexOf(e) >= 0;
  }
}
