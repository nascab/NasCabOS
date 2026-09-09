/**
 * 音乐库分组/歌单/合集控制器合集（对齐 Flutter）：
 * - MusicAlbumArtistController ← album_artist_list_controller.dart（专辑/艺人分组列表）
 * - MusicPlaylistController   ← play_list_controller.dart（歌单列表 + Overlay payload）
 * - MusicCollectionController ← music_collection_controller.dart（合集列表 + activeCollection）
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../../../core/localization/L10n';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import {
  AlbumArtistListPagedResult, MusicCollectionItem, MusicListPathItem,
  MusicListItem, PlayListItem
} from '../models/MusicModels';
import {
  AlbumArtistListApiService, MusicListApiService, MusicListQueryFactory, MusicCollectionApiService, PlayListApiService
} from '../services/MusicApiServices';

const TAG = 'MusicLibraryControllers';

// ===== 专辑 / 艺人分组列表（对齐 AlbumArtistListController） =====

export enum AlbumArtistSortBy {
  count = 0,
  name = 1
}

export enum AlbumArtistSortOrder {
  asc = 0,
  desc = 1
}

function albumArtistSortByParam(by: AlbumArtistSortBy): string {
  return by === AlbumArtistSortBy.count ? 'count' : 'name';
}

@ObservedV2
export class MusicAlbumArtistController {
  readonly keyType: string;
  readonly initialSortBy: AlbumArtistSortBy;
  readonly initialSortOrder: AlbumArtistSortOrder;

  @Trace items: MusicListItem[] = [];
  @Trace loading: boolean = false;
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace autoLoadFailed: boolean = false;
  @Trace total: number = 0;
  @Trace searchText: string = '';
  @Trace availablePaths: MusicListPathItem[] = [];
  @Trace selectedPaths: string[] = [];
  @Trace sortBy: AlbumArtistSortBy = AlbumArtistSortBy.count;
  @Trace sortOrder: AlbumArtistSortOrder = AlbumArtistSortOrder.desc;

  private page: number = 1;
  private readonly pageSize: number = 30;
  private searchDebounce: number = -1;

  constructor(keyType: string, initialSortBy: AlbumArtistSortBy = AlbumArtistSortBy.count,
    initialSortOrder: AlbumArtistSortOrder = AlbumArtistSortOrder.desc) {
    this.keyType = keyType;
    this.initialSortBy = initialSortBy;
    this.initialSortOrder = initialSortOrder;
  }

  get badgeLabel(): string {
    const t = this.keyType.trim().toLowerCase();
    return t === 'artist' ? L10n.t('music_menu_library_artists') : L10n.t('music_menu_library_albums');
  }

  onInit(): void {
    this.sortBy = this.initialSortBy;
    this.sortOrder = this.initialSortOrder;
    this.refreshList(true);
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  setSort(by: AlbumArtistSortBy, order: AlbumArtistSortOrder): void {
    if (this.sortBy === by && this.sortOrder === order) {
      return;
    }
    this.sortBy = by;
    this.sortOrder = order;
    this.refreshList(false);
  }

  onSearchChanged(v: string): void {
    this.searchText = v;
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.refreshList(false);
    }, 400);
  }

  setSearchImmediate(v: string): void {
    this.searchText = v;
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshList(false);
  }

  clearSearch(): void {
    if (this.searchText.length === 0) {
      return;
    }
    this.searchText = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshList(false);
  }

  togglePath(path: string): void {
    const p = path.trim();
    if (p.length === 0) {
      return;
    }
    const next = this.selectedPaths.slice();
    const idx = next.indexOf(p);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(p);
    }
    this.selectedPaths = next.sort();
    this.refreshList(false);
  }

  async refreshList(showLoading: boolean = false): Promise<void> {
    // 静默刷新（字母索引/搜索防抖）：不切换 loading，旧数据保持显示，数据到达后原地更新一次
    if (showLoading) {
      this.loading = true;
    }
    this.autoLoadFailed = false;
    try {
      this.page = 1;
      const res = await AlbumArtistListApiService.listPaged(this.keyType, 1, this.pageSize,
        this.searchText, this.selectedPaths.slice(), albumArtistSortByParam(this.sortBy),
        this.sortOrder === AlbumArtistSortOrder.asc ? 'asc' : 'desc');
      if (res.success && res.data !== undefined) {
        const data: AlbumArtistListPagedResult = res.data;
        this.items = this.toGroupItems(data);
        this.total = data.pagination.total;
        this.hasMore = data.pagination.hasNextPage;
        this.availablePaths = data.validPaths;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'albumArtist refreshList failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loading = false;
    }
  }

  private toGroupItems(data: AlbumArtistListPagedResult): MusicListItem[] {
    // 分组项复用 MusicListItem 承载（name→filename，indexCount→musicCount，firstFilePath）
    const out: MusicListItem[] = [];
    for (const g of data.items) {
      const it = new MusicListItem();
      it.filename = g.name;
      it.musicCount = g.indexCount;
      it.firstFilePath = g.firstFilePath;
      it.showType = this.keyType.trim().toLowerCase();
      out.push(it);
    }
    return out;
  }

  async loadMore(fromAuto: boolean = false): Promise<void> {
    if (this.loadingMore || this.loading) {
      return;
    }
    if (!this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const nextPage = this.page + 1;
      const res = await AlbumArtistListApiService.listPaged(this.keyType, nextPage, this.pageSize,
        this.searchText, this.selectedPaths.slice(), albumArtistSortByParam(this.sortBy),
        this.sortOrder === AlbumArtistSortOrder.asc ? 'asc' : 'desc');
      if (res.success && res.data !== undefined) {
        const data: AlbumArtistListPagedResult = res.data;
        this.page = nextPage;
        this.items = this.items.concat(this.toGroupItems(data));
        this.total = data.pagination.total;
        this.hasMore = data.pagination.hasNextPage;
        this.availablePaths = data.validPaths;
        this.autoLoadFailed = false;
      }
    } catch (e) {
      if (fromAuto) {
        this.autoLoadFailed = true;
      }
      hilog.error(0x0000, TAG, 'albumArtist loadMore failed: %{public}s', JSON.stringify(e));
    } finally {
      this.loadingMore = false;
    }
  }

  /** 全部分组内歌曲 index ids（对齐 _fetchAllIndexIds，分页拉取） */
  private async fetchAllIndexIds(name: string, isArtist: boolean, indexCount: number): Promise<number[]> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return [];
    }
    const pageSize = 200;
    let page = 1;
    const ids = new Set<number>();
    while (true) {
      const q = MusicListQueryFactory.default();
      q.page = page;
      q.pageSize = pageSize;
      q.artists = isArtist ? [trimmed] : [];
      q.albums = isArtist ? [] : [trimmed];
      q.sourceList = this.selectedPaths.slice();
      const res = await MusicListApiService.listPaged(q);
      if (!res.success || res.data === undefined) {
        break;
      }
      for (const item of res.data.items) {
        if (item.id > 0) {
          ids.add(item.id);
        }
      }
      if (!res.data.pagination.hasNextPage) {
        break;
      }
      if (indexCount > 0 && ids.size >= indexCount) {
        break;
      }
      page += 1;
      if (page > 200) {
        break;
      }
    }
    return Array.from(ids).sort();
  }

  /** 分组全部加入歌单（歌单选择由 UI 弹出后传入 listId） */
  async addToPlayList(groupName: string, isArtist: boolean, indexCount: number, listId: number): Promise<boolean> {
    if (listId <= 0) {
      return false;
    }
    const ids = await this.fetchAllIndexIds(groupName, isArtist, indexCount);
    if (ids.length === 0) {
      return false;
    }
    const res = await PlayListApiService.addIndexes(listId, ids);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
      return true;
    }
    ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    return false;
  }
}

// ===== 歌单（对齐 PlayListController） =====

/** 歌单 Overlay 打开参数（对齐 PlayListOverlayPayload） */
export class MusicPlaylistOverlayPayload {
  listId: number = 0;
  name: string = '';
}

@ObservedV2
export class MusicPlaylistController {
  private static readonly KEY_SORT_FIELD: string = 'music_playlist_sort_field';
  private static readonly KEY_SORT_ORDER: string = 'music_playlist_sort_order';

  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace items: PlayListItem[] = [];
  @Trace page: number = 1;
  @Trace pageSize: number = 30;
  @Trace total: number = 0;
  @Trace keyword: string = '';
  @Trace sortBy: string = 'create_time';
  @Trace sortOrder: string = 'desc';

  private searchDebounce: number = -1;

  onInit(): void {
    this.loadSortSettings();
    this.refreshLists();
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  onSearchChanged(v: string): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.keyword = v.trim();
      this.refreshLists();
    }, 450);
  }

  clearSearch(): void {
    this.keyword = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshLists();
  }

  setSort(field: string, order: string): void {
    const nextField = field === 'name' || field === 'create_time' ? field : 'create_time';
    const nextOrder = order === 'asc' ? 'asc' : 'desc';
    if (this.sortBy === nextField && this.sortOrder === nextOrder) {
      return;
    }
    this.sortBy = nextField;
    this.sortOrder = nextOrder;
    this.saveSortSettings();
    this.refreshLists();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(MusicPlaylistController.KEY_SORT_FIELD, '');
    const cachedOrder = store.getString(MusicPlaylistController.KEY_SORT_ORDER, '');
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortBy = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    store.setString(MusicPlaylistController.KEY_SORT_FIELD, this.sortBy);
    store.setString(MusicPlaylistController.KEY_SORT_ORDER, this.sortOrder);
  }

  async refreshLists(): Promise<void> {
    this.hasMore = true;
    await this.loadLists(1, false);
  }

  async loadLists(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await PlayListApiService.listLists(pageNumber, this.pageSize, this.keyword,
        this.sortBy, this.sortOrder);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      if (append) {
        const existing = new Set<number>(this.items.map((e: PlayListItem): number => e.id));
        this.items = this.items.concat(data.items.filter((e: PlayListItem): boolean => !existing.has(e.id)));
      } else {
        this.items = data.items;
      }
      this.total = data.total;
      this.page = data.page;
      this.pageSize = data.pageSize;
      this.hasMore = data.hasNextPage;
    } finally {
      this.isLoading = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return;
    }
    await this.loadLists(this.page + 1, true);
  }

  async createList(name: string): Promise<boolean> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const res = await PlayListApiService.createList(trimmed);
    if (!res.success) {
      return false;
    }
    await this.refreshLists();
    return true;
  }

  /** 创建歌单并返回新建项（选择模式空列表时创建后直接选用） */
  async createListReturnItem(name: string): Promise<PlayListItem | undefined> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    const res = await PlayListApiService.createList(trimmed);
    if (!res.success || res.data === undefined) {
      return undefined;
    }
    const item = res.data;
    if (item.id <= 0) {
      return undefined;
    }
    await this.refreshLists();
    return item;
  }

  async updateList(id: number, name: string): Promise<boolean> {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const res = await PlayListApiService.updateList(id, trimmed);
    if (!res.success) {
      return false;
    }
    await this.refreshLists();
    return true;
  }

  async deleteList(id: number): Promise<boolean> {
    const res = await PlayListApiService.deleteList(id);
    if (!res.success) {
      return false;
    }
    await this.refreshLists();
    return true;
  }
}

// ===== 合集（对齐 MusicCollectionController） =====

@ObservedV2
export class MusicCollectionController {
  private static readonly KEY_SORT_FIELD: string = 'music_collection_sort_field';
  private static readonly KEY_SORT_ORDER: string = 'music_collection_sort_order';

  @Trace isLoading: boolean = false;
  @Trace hasMore: boolean = true;
  @Trace items: MusicCollectionItem[] = [];
  @Trace page: number = 1;
  @Trace pageSize: number = 20;
  @Trace total: number = 0;
  @Trace keyword: string = '';
  @Trace sortField: string = 'create_time';
  @Trace sortOrder: string = 'desc';
  @Trace activeCollection: MusicCollectionItem | undefined = undefined;

  private searchDebounce: number = -1;

  onInit(): void {
    this.loadSortSettings();
    this.refreshCollections();
  }

  onClose(): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
  }

  onSearchChanged(val: string): void {
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout((): void => {
      this.searchDebounce = -1;
      this.keyword = val.trim();
      this.refreshCollections();
    }, 500);
  }

  clearSearch(): void {
    this.keyword = '';
    if (this.searchDebounce >= 0) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = -1;
    }
    this.refreshCollections();
  }

  setSort(field: string, order: string): void {
    if (this.sortField === field && this.sortOrder === order) {
      return;
    }
    this.sortField = field;
    this.sortOrder = order;
    this.saveSortSettings();
    this.refreshCollections();
  }

  private loadSortSettings(): void {
    const store = PreferencesStore.getInstance();
    const cachedField = store.getString(MusicCollectionController.KEY_SORT_FIELD, '');
    const cachedOrder = store.getString(MusicCollectionController.KEY_SORT_ORDER, '');
    if (cachedField === 'name' || cachedField === 'create_time') {
      this.sortField = cachedField;
    }
    if (cachedOrder === 'asc' || cachedOrder === 'desc') {
      this.sortOrder = cachedOrder;
    }
  }

  private saveSortSettings(): void {
    const store = PreferencesStore.getInstance();
    store.setString(MusicCollectionController.KEY_SORT_FIELD, this.sortField);
    store.setString(MusicCollectionController.KEY_SORT_ORDER, this.sortOrder);
  }

  async refreshCollections(): Promise<void> {
    this.hasMore = true;
    await this.loadCollections(1, false);
  }

  async loadCollections(pageNumber: number, append: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const res = await MusicCollectionApiService.listCollections(pageNumber, this.pageSize,
        this.keyword, this.sortField, this.sortOrder);
      if (!res.success || res.data === undefined) {
        return;
      }
      const data = res.data;
      if (append) {
        const existing = new Set<number>(this.items.map((e: MusicCollectionItem): number => e.id));
        this.items = this.items.concat(data.items.filter((e: MusicCollectionItem): boolean => !existing.has(e.id)));
      } else {
        this.items = data.items;
      }
      this.total = data.total;
      this.page = data.page;
      this.pageSize = data.pageSize;
      const size = this.pageSize <= 0 ? 20 : this.pageSize;
      const maxPage = this.total <= 0 ? 1 : Math.floor((this.total + size - 1) / size);
      this.hasMore = this.page < maxPage;
    } finally {
      this.isLoading = false;
    }
  }

  async loadMore(): Promise<void> {
    if (this.isLoading || !this.hasMore) {
      return;
    }
    await this.loadCollections(this.page + 1, true);
  }

  openCollection(collection: MusicCollectionItem): void {
    this.activeCollection = collection;
  }

  closeCollection(): void {
    this.activeCollection = undefined;
  }

  async createCollection(name: string, pathList: string[]): Promise<boolean> {
    const trimmed = name.trim();
    const cleanedPaths = pathList.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0);
    if (trimmed.length === 0 || cleanedPaths.length === 0) {
      return false;
    }
    const res = await MusicCollectionApiService.createCollection(trimmed, cleanedPaths);
    if (res.success) {
      await this.refreshCollections();
      return true;
    }
    if (res.message.length > 0) {
      DialogUtil.showInfoDialog(L10n.t('tip'), res.message);
    }
    return false;
  }

  async updateCollection(id: number, name: string, pathList: string[]): Promise<boolean> {
    const trimmed = name.trim();
    const cleanedPaths = pathList.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0);
    if (trimmed.length === 0 || cleanedPaths.length === 0) {
      return false;
    }
    const res = await MusicCollectionApiService.updateCollection(id, trimmed, cleanedPaths);
    if (res.success) {
      await this.refreshCollections();
      return true;
    }
    if (res.message.length > 0) {
      DialogUtil.showInfoDialog(L10n.t('tip'), res.message);
    }
    return false;
  }

  async deleteCollection(id: number): Promise<boolean> {
    const res = await MusicCollectionApiService.deleteCollection(id);
    if (!res.success) {
      if (res.message.length > 0) {
        DialogUtil.showInfoDialog(L10n.t('tip'), res.message);
      }
      return false;
    }
    if (this.activeCollection !== undefined && this.activeCollection.id === id) {
      this.activeCollection = undefined;
    }
    await this.refreshCollections();
    return true;
  }
}
