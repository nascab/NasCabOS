import { L10n } from '../../core/localization/L10n';
import { JsonCodec } from '../../common/JsonTypes';
import { VideoDetailApiService } from '../service/VideoApiServices';
import { asArray, asNum, asRecord, asStr, VideoHomeItemBean } from '../models/VideoModels';

/**
 * 视频详情控制器（对齐 Flutter VideoDetailController）：
 * 详情 + 剧集分页 + 原盘内容 + 演职人员 + 播放历史。
 */

/** 演职人员条目（解析 nfo_director_json / nfo_actor_json） */
export class VideoPersonInfo {
  name: string = '';
  tmdbId: string = '';
  thumb: string = '';
  role: string = '';
}

function parsePeopleJson(v: Object | undefined | null, role: string): VideoPersonInfo[] {
  if (v === undefined || v === null) {
    return [];
  }
  try {
    const decoded = JsonCodec.parseStr<Object[]>(`${v}`);
    const list = Array.isArray(decoded) ? decoded : [];
    const result: VideoPersonInfo[] = [];
    for (const e of list) {
      const m = asRecord(e);
      const p = new VideoPersonInfo();
      p.name = asStr(m['name']).trim();
      p.tmdbId = asStr(m['tmdbId']).trim();
      p.thumb = asStr(m['thumb']).trim();
      p.role = role;
      if (p.name.length > 0) {
        result.push(p);
      }
    }
    return result;
  } catch (_e) {
    return [];
  }
}

@ObservedV2
export class VideoDetailController {
  readonly indexId: number;
  readonly episodePageSize: number = 20;

  @Trace loading: boolean = false;
  /** 详情原始数据：{ item, history, season_list } */
  @Trace raw: Record<string, Object> | undefined = undefined;
  @Trace episodeAsc: boolean = true;
  /** true=简介视图 false=文件视图（对齐 EpisodeViewMode.intro/file） */
  @Trace episodeIntroMode: boolean = true;
  @Trace episodeLoading: boolean = false;
  @Trace episodes: Record<string, Object>[] = [];
  @Trace episodeTotal: number = 0;
  @Trace episodePage: number = 1;
  @Trace discContentLoading: boolean = false;
  @Trace discContents: Record<string, Object>[] = [];

  constructor(indexId: number) {
    this.indexId = indexId;
  }

  async refreshDetail(): Promise<void> {
    if (this.loading) {
      return;
    }
    if (this.indexId <= 0) {
      return;
    }
    this.loading = true;
    try {
      const res = await new VideoDetailApiService().getDetail(this.indexId);
      if (!res.success || res.data === undefined) {
        this.raw = undefined;
        this.episodes = [];
        this.discContents = [];
        this.episodeTotal = 0;
        this.episodePage = 1;
        return;
      }
      this.raw = res.data;
      await this.refreshEpisodesAfterDetail();
      await this.refreshDiscContentsAfterDetail();
    } finally {
      this.loading = false;
    }
  }

  private async refreshDiscContentsAfterDetail(): Promise<void> {
    if (!this.showDiscContentSection) {
      this.discContents = [];
      return;
    }
    await this.fetchDiscContents();
  }

  private async refreshEpisodesAfterDetail(): Promise<void> {
    if (!this.needAutoLoadEpisodes()) {
      this.episodes = [];
      this.episodeTotal = 0;
      this.episodePage = 1;
      return;
    }
    await this.fetchEpisodes(1);
  }

  /** season 必须；tv 且季数<=1 自动加载（对齐 _needAutoLoadEpisodes） */
  private needAutoLoadEpisodes(): boolean {
    const t = this.mediaType;
    if (t === 'season') {
      return true;
    }
    if (t === 'tv') {
      return this.itemSeasonCount <= 1;
    }
    return false;
  }

  private needAutoLoadDiscContents(): boolean {
    const t = this.mediaType;
    return t === 'bdmv' || t === 'video_ts';
  }

  get episodeTotalPages(): number {
    return this.episodePageSize <= 0 ? 0 : Math.ceil(this.episodeTotal / this.episodePageSize);
  }

  async fetchEpisodes(page: number = 1): Promise<void> {
    if (this.episodeLoading) {
      return;
    }
    if (this.indexId <= 0) {
      return;
    }
    if (!this.needAutoLoadEpisodes()) {
      return;
    }
    this.episodeLoading = true;
    try {
      const res = await new VideoDetailApiService().getEpisodes(
        this.indexId, page, this.episodePageSize, this.episodeAsc ? 'asc' : 'desc');
      if (!res.success || res.data === undefined) {
        this.episodes = [];
        this.episodeTotal = 0;
        this.episodePage = 1;
        return;
      }
      const data = res.data;
      const list = asArray(data['items']);
      const mapped: Record<string, Object>[] = [];
      for (const e of list) {
        mapped.push(asRecord(e));
      }
      const pm = asRecord(data['pagination']);
      this.episodes = mapped;
      this.episodeTotal = asNum(pm['total']);
      this.episodePage = asNum(pm['page'], page);
    } finally {
      this.episodeLoading = false;
    }
  }

  /** 排序切换：镜像页码（对齐 toggleEpisodeSort） */
  async toggleEpisodeSort(): Promise<void> {
    const totalPages = this.episodeTotalPages;
    const current = this.episodePage;
    this.episodeAsc = !this.episodeAsc;
    let mirrored = 1;
    if (totalPages > 0) {
      mirrored = Math.min(Math.max(totalPages - current + 1, 1), totalPages);
    }
    await this.fetchEpisodes(mirrored);
  }

  async jumpToEpisodePage(page: number): Promise<void> {
    const p = Math.min(Math.max(page, 1), Math.max(this.episodeTotalPages, 1));
    await this.fetchEpisodes(p);
  }

  async fetchDiscContents(): Promise<void> {
    if (this.discContentLoading) {
      return;
    }
    if (this.indexId <= 0) {
      return;
    }
    if (!this.needAutoLoadDiscContents()) {
      return;
    }
    this.discContentLoading = true;
    try {
      const res = await new VideoDetailApiService().getDiscContents(this.indexId);
      if (!res.success || res.data === undefined) {
        this.discContents = [];
        return;
      }
      const list = asArray(res.data['items']);
      const mapped: Record<string, Object>[] = [];
      for (const e of list) {
        mapped.push(asRecord(e));
      }
      this.discContents = mapped;
    } finally {
      this.discContentLoading = false;
    }
  }

  // ===== 派生数据（对齐 controller getters） =====

  get item(): Record<string, Object> {
    if (this.raw === undefined) {
      return {};
    }
    return asRecord(this.raw['item']);
  }

  get hasItem(): boolean {
    if (this.raw === undefined) {
      return false;
    }
    return Object.keys(asRecord(this.raw['item'])).length > 0;
  }

  get mediaType(): string {
    return asStr(this.item['media_type']).trim();
  }

  get itemSeasonCount(): number {
    return asNum(this.item['season_count']);
  }

  get openSkipStartSeconds(): number {
    return asNum(this.item['open_skip_start_sec']);
  }

  /** 评分（nfo_score） */
  get itemScore(): number {
    return asNum(this.item['nfo_score']);
  }

  /** 收藏状态回写（对齐 _patchCtrlFavorite） */
  patchFavorite(next: boolean): void {
    if (this.raw === undefined) {
      return;
    }
    const nextRaw: Record<string, Object> = JsonCodec.parse<Record<string, Object>>(this.raw as Object);
    const nextItem: Record<string, Object> = JsonCodec.parse<Record<string, Object>>(asRecord(this.raw['item']) as Object);
    nextItem['is_favorite'] = next;
    nextRaw['item'] = nextItem;
    this.raw = nextRaw;
  }

  get openSkipEndSeconds(): number {
    return asNum(this.item['open_skip_end_sec']);
  }

  get canEditOpenSkip(): boolean {
    return this.mediaType === 'tv' || this.mediaType === 'season';
  }

  get showEpisodeSection(): boolean {
    return this.needAutoLoadEpisodes();
  }

  get showDiscContentSection(): boolean {
    return this.needAutoLoadDiscContents();
  }

  get seasonList(): Record<string, Object>[] {
    if (this.raw === undefined) {
      return [];
    }
    const list = asArray(this.raw['season_list']);
    const out: Record<string, Object>[] = [];
    for (const e of list) {
      out.push(asRecord(e));
    }
    return out;
  }

  get directors(): VideoPersonInfo[] {
    return parsePeopleJson(this.item['nfo_director_json'], L10n.t('video_detail_directors', '导演'));
  }

  get actors(): VideoPersonInfo[] {
    return parsePeopleJson(this.item['nfo_actor_json'], L10n.t('video_detail_actors', '演员'));
  }

  get history(): Record<string, Object> {
    if (this.raw === undefined) {
      return {};
    }
    return asRecord(this.raw['history']);
  }

  get historySeconds(): number {
    return asNum(this.history['playback_position']);
  }

  get historyDurationSeconds(): number {
    const d = asNum(this.history['duration'], -1);
    if (d > 0) {
      return d;
    }
    return asNum(this.item['duration']);
  }

  get historyEpisodeNum(): number {
    return asNum(this.history['episod_num']);
  }

  get hasHistory(): boolean {
    return this.historySeconds > 0;
  }

  /** 季条目 → 海报 Bean（对齐 VideoDetailSeasonSection.toBean） */
  seasonToBean(s: Record<string, Object>): VideoHomeItemBean {
    const rawFav = s['is_favorite'];
    const bean = new VideoHomeItemBean();
    bean.id = this.parseId(s['id'] ?? s['index_id'] ?? s['indexId'] ?? s['season_id'] ?? s['seasonId']);
    bean.mediaType = asStr(s['media_type'], 'season');
    bean.path = asStr(s['path']);
    bean.filename = asStr(s['filename']);
    bean.firstFilePath = asStr(s['first_file_path']);
    bean.nfoName = asStr(s['nfo_name']);
    bean.nfoYear = asNum(s['nfo_year']);
    bean.nfoScore = asNum(s['nfo_score']);
    bean.nfoRegions = asStr(s['nfo_regions']);
    bean.nfoGenres = asStr(s['nfo_genres']);
    bean.posterPath = asStr(s['poster_path']);
    bean.fanartPath = asStr(s['fanart_path']);
    bean.fullPath = asStr(s['full_path']);
    bean.logoPath = asStr(s['logo_path']);
    bean.isFavorite = rawFav === true || rawFav === 1 || rawFav === '1';
    bean.viewTime = asStr(s['view_time']);
    bean.createTime = asStr(s['create_time']);
    return bean;
  }

  private parseId(v: Object | undefined | null): number {
    return asNum(v);
  }

  /** 原盘播放列表（对齐 buildDiscPlaybackPlaylist） */
  buildDiscPlaybackPlaylist(): Record<string, Object>[] {
    const out: Record<string, Object>[] = [];
    for (const item of this.discContents) {
      const rawPlaylist = asArray(item['playlist']);
      const first: Record<string, Object> = rawPlaylist.length > 0 ? asRecord(rawPlaylist[0]) : {};
      const path = asStr(item['path'], asStr(first['path'])).trim();
      if (path.length === 0) {
        continue;
      }
      const title = asStr(item['title']).trim();
      const m: Record<string, Object> = {
        'path': path,
        'internalPath': asStr(item['internal_path'], asStr(first['internal_path'])).trim(),
        'name': title.length > 0 ? title : asStr(item['display_name'])
      };
      out.push(m);
    }
    return out;
  }

  /** 定位原盘播放索引（对齐 findDiscPlaybackIndex） */
  findDiscPlaybackIndex(currentItem: Record<string, Object> | undefined): number {
    if (currentItem === undefined) {
      return 0;
    }
    const currentPath = asStr(currentItem['path']);
    const currentInternalPath = asStr(currentItem['internal_path']).trim();
    const list = this.discContents;
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      const rawPlaylist = asArray(item['playlist']);
      const first: Record<string, Object> = rawPlaylist.length > 0 ? asRecord(rawPlaylist[0]) : {};
      const path = asStr(item['path'], asStr(first['path']));
      const internalPath = asStr(item['internal_path'], asStr(first['internal_path'])).trim();
      if (path === currentPath && internalPath === currentInternalPath) {
        return i;
      }
    }
    return 0;
  }
}
