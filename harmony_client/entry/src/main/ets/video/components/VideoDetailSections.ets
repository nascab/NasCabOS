import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase, DialogResult } from '../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { CurrentUserStore } from '../../core/user/CurrentUserStore';
import { ApiUrls } from '../../core/network/ApiUrls';
import { VideoDetailApiService, VideoFavoriteApiService } from '../service/VideoApiServices';
import { VideoHomeItemBean, asNum, asStr, parseVideoHomeItemBean } from '../models/VideoModels';
import { VideoPersonInfo, VideoDetailController } from '../controllers/VideoDetailController';
import { VideoItemPoster } from './VideoItemPoster';
import { VideoItemActions, VideoSearchMediaHelper } from './VideoItemViews';
import { VideoDetailPageParam, VideoListPageParam } from '../router/VideoRoutes';
import { VideoUtils } from '../utils/VideoItemUtils';
import { AppImage } from '../../common/components/AppImage';

/**
 * 视频详情页区块组件（对齐 Flutter video/detail/view/parts，移动端版式）：
 * 详情页锁定深色主题（对齐 Flutter ThemeData.dark()），用色常量见 DetailColors。
 */

/** 元信息 token：meta/sep/region/genre */
export class VideoMetaToken {
  text: string;
  kind: string;

  constructor(text: string, kind: string) {
    this.text = text;
    this.kind = kind;
  }
}

/** 详情页锁定深色配色（对齐 Flutter ThemeData.dark()） */
export class DetailColors {
  static readonly surface: string = '#121212';
  static readonly container: string = '#2C2C2E';
  static readonly onSurface: string = '#FFFFFF';
  static readonly gold: string = '#D8A100';
  static readonly playBlue: string = '#1565C0';
  static readonly progressBlue: string = '#42A5F5';
  static readonly error: string = '#CF6679';

  /** 白色按透明度（onSurface.withValues(alpha) 对齐） */
  static alpha(alpha: number): string {
    return AppTheme.withAlpha('#FFFFFF', alpha);
  }
}

/** 分辨率标签（对齐 _resolutionLabel） */
export function detailResolutionLabel(width: number, height: number): string {
  const w = Math.max(0, width);
  const h = Math.max(0, height);
  if (w >= 3840 || h >= 2160) {
    return '4K';
  }
  if (w >= 1920 || h >= 1080) {
    return '1080P';
  }
  if (w >= 1280 || h >= 720) {
    return '720P';
  }
  return '';
}

/** 秒数格式化 h:mm:ss / m:ss（对齐 formatEpisodeDuration） */
export function formatEpisodeDuration(seconds: number): string {
  const s = Math.max(0, seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) {
    return `${h}:${`${m}`.padStart(2, '0')}:${`${sec}`.padStart(2, '0')}`;
  }
  return `${m}:${`${sec}`.padStart(2, '0')}`;
}

/** 逗号分隔字段拆分（对齐 splitComma） */
function splitComma(input: string): string[] {
  return input.split(',')
    .map((e: string): string => e.trim())
    .filter((e: string): boolean => e.length > 0);
}

/**
 * 详情页异步图片（详情锁定深色，加载失败/未加载时显示深色占位）。
 */
@ComponentV2
export struct DetailAsyncImage {
  @Param provider: () => Promise<string> = (): Promise<string> => Promise.resolve('');
  @Param imageRadius: number = 0;
  @Local url: string = '';

  aboutToAppear(): void {
    this.provider().then((url: string): void => {
      this.url = url;
    });
  }

  build() {
    AppImage({
      url: this.url,
      objectFit: ImageFit.Cover,
      imageRadius: this.imageRadius,
      showLoadingSpin: false
    })
  }
}

/** 顶部大图区（对齐 AppVideoDetailTopSection）：背景 + 上下渐变 + logo/评分/标题/元信息 */
@ComponentV2
export struct VideoDetailTopSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);
  @Local fanartUrl: string = '';
  @Local logoUrl: string = '';

  aboutToAppear(): void {
    this.loadImages();
  }

  /** 详情数据异步到达后重新解析图片（item 是 raw 的 getter，需监听 raw 替换） */
  @Monitor('ctrl.raw')
  onRawChange(): void {
    this.loadImages();
  }

  private loadImages(): void {
    const bean = parseVideoHomeItemBean(this.ctrl.item as Object);
    VideoUtils.getFanartUrl(bean).then((url: string): void => {
      this.fanartUrl = url;
    });
    const logo = asStr(this.ctrl.item['logo_path']).trim();
    if (logo.length > 0) {
      ApiUrls.getRawFileUrl(logo).then((url: string): void => {
        this.logoUrl = url;
      });
    } else {
      this.logoUrl = '';
    }
  }

  @Builder
  MetaJoined() {
    if (this.metaTokens().length > 0) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.metaTokens(), (t: VideoMetaToken) => {
          Text(t.text)
            .fontSize(12)
            .fontColor(t.kind === 'sep' ? DetailColors.alpha(0.5) : DetailColors.alpha(0.78))
            .decoration({
              type: TextDecorationType.Underline,
              color: (t.kind === 'region' || t.kind === 'genre') ? DetailColors.alpha(0.35) : '#00000000'
            })
            .onClick(() => {
              if (t.kind === 'region') {
                this.openFilter(true, t.text);
              } else if (t.kind === 'genre') {
                this.openFilter(false, t.text);
              }
            })
        }, (t: VideoMetaToken, idx: number): string => `${idx}_${t.text}`)
      }
    }
  }

  /** 元信息 token：meta/sep/region/genre（间隔 ' · '，地区/类型可点击，对齐 _AppMetaLine） */
  private metaTokens(): VideoMetaToken[] {
    const out: VideoMetaToken[] = [];
    const all: VideoMetaToken[] = [];
    for (const p of this.metaParts()) {
      all.push(new VideoMetaToken(p, 'meta'));
    }
    for (const p of this.regionList()) {
      all.push(new VideoMetaToken(p, 'region'));
    }
    for (const p of this.genreList()) {
      all.push(new VideoMetaToken(p, 'genre'));
    }
    for (let i = 0; i < all.length; i++) {
      if (i > 0) {
        out.push(new VideoMetaToken(' · ', 'sep'));
      }
      out.push(all[i]);
    }
    return out;
  }

  private metaParts(): string[] {
    const m = this.ctrl.item;
    const parts: string[] = [];
    const episodeCount = asNum(m['episode_count'], asNum(m['episod_count']));
    const seasonCount = asNum(m['season_count']);
    if (this.ctrl.mediaType === 'season' && episodeCount > 0) {
      parts.push(L10n.t('video_detail_episode_count', '共 @count 集', L10n.paramsOf('count', `${episodeCount}`)));
    }
    if (this.ctrl.mediaType === 'tv' && seasonCount > 0) {
      parts.push(L10n.t('video_detail_season_count', '共 @count 季', L10n.paramsOf('count', `${seasonCount}`)));
    }
    const year = asNum(m['nfo_year']);
    if (year > 0) {
      parts.push(`${year}`);
    }
    return parts;
  }

  private regionList(): string[] {
    return splitComma(asStr(this.ctrl.item['nfo_regions']).trim());
  }

  private genreList(): string[] {
    return splitComma(asStr(this.ctrl.item['nfo_genres']).trim());
  }

  /** 地区/类型点击 → 打开筛选后的列表页（对齐 openFilterOverlay） */
  private openFilter(isRegion: boolean, value: string): void {
    const v = value.trim();
    if (v.length === 0) {
      return;
    }
    const mediaType = this.ctrl.mediaType === 'season' ? 'tv' : this.ctrl.mediaType;
    const lp = new VideoListPageParam();
    lp.title = v;
    lp.initialMediaType = mediaType;
    if (isRegion) {
      lp.initialRegions = [v];
    } else {
      lp.initialGenres = [v];
    }
    NavUtil.push(AppRouter.VIDEO_LIST, lp);
  }

  /** ' · ' 分隔的元信息总条数（构建间隔符用） */
  private metaTotal(): number {
    return this.metaParts().length + this.regionList().length + this.genreList().length;
  }

  build() {
    Stack() {
      if (this.fanartUrl.length > 0) {
        AppImage({ url: this.fanartUrl, objectFit: ImageFit.Cover, showLoadingSpin: false })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(DetailColors.container)
      }
      // 底部黑色渐变（bottom→top 180 高，黑色在底部向上淡出）
      Column()
        .width('100%')
        .height(180)
        .position({ x: 0, y: '100%' })
        .markAnchor({ y: '100%' })
        .linearGradient({ angle: 0, colors: [[AppTheme.withAlpha('#000000', 0.88), 0], [AppTheme.withAlpha('#000000', 0.46), 0.5], ['#00000000', 1]] })
        .hitTestBehavior(HitTestMode.None)
      // 顶部黑色渐变（状态栏区域）
      Column()
        .width('100%')
        .height(120)
        .position({ x: 0, y: 0 })
        .linearGradient({ angle: 180, colors: [[AppTheme.withAlpha('#000000', 0.28), 0], ['#00000000', 1]] })
        .hitTestBehavior(HitTestMode.None)
      // 左下信息
      Column() {
        if (this.logoUrl.length > 0) {
          AppImage({ url: this.logoUrl, objectFit: ImageFit.Contain, showLoadingSpin: false })
            .height(60)
            .width('55%')
            .constraintSize({ maxWidth: 220 })
            .margin({ bottom: 8 })
        }
        Row({ space: 10 }) {
          if (this.ctrl.itemScore > 0) {
            Text(this.scoreText())
              .fontSize(24)
              .fontWeight(FontWeight.Bolder)
              .fontColor(DetailColors.gold)
          }
          Text(this.titleText())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(DetailColors.onSurface)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .alignItems(VerticalAlign.Bottom)
        .width('100%')
        if (this.metaTotal() > 0) {
          Row() {
            this.MetaJoined()
          }
          .margin({ top: 8 })
          .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 10, bottom: 12 })
      .position({ x: 0, y: '100%' })
      .markAnchor({ y: '100%' })
    }
    .width('100%')
    .height('100%')
  }

  private titleText(): string {
    const m = this.ctrl.item;
    const nfoName = asStr(m['nfo_name']).trim();
    return nfoName.length > 0 ? nfoName : asStr(m['filename']);
  }

  private scoreText(): string {
    const score = this.ctrl.itemScore;
    return Number.isInteger(score) ? `${score}` : score.toFixed(1);
  }
}

/** 剧情简介区（对齐 VideoDetailStorylineSection）：4 行预览 + 点击查看详情弹窗 */
@ComponentV2
export struct VideoDetailStorylineSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);

  private storyline(): string {
    const s = asStr(this.ctrl.item['nfo_storyline']).trim();
    return s.length > 0 ? s : L10n.t('video_detail_storyline_empty', '暂无剧情简介');
  }

  @Builder
  StoryRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(DetailColors.alpha(0.65))
        .fontWeight(FontWeight.Medium)
        .width(72)
      Text(value.trim().length > 0 ? value.trim() : '-')
        .fontSize(14)
        .fontColor(DetailColors.onSurface)
        .copyOption(CopyOptions.InApp)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 10 })
    .width('100%')
  }

  private showDetailDialog(): void {
    const m = this.ctrl.item;
    const p = new VideoStorylineDialogParams();
    p.title = this.titleText();
    p.rows = [];
    p.storyline = asStr(m['nfo_storyline']).trim();
    const directors = VideoDetailStorylineSection.joinPeople(this.ctrl.directors);
    const actors = VideoDetailStorylineSection.joinPeople(this.ctrl.actors);
    p.rows.push(new VideoStorylineRow(L10n.t('name', '名称'), asStr(m['filename']).trim()));
    p.rows.push(new VideoStorylineRow(L10n.t('path', '路径'), asStr(m['full_path']).trim()));
    p.rows.push(new VideoStorylineRow(L10n.t('video_detail_directors', '导演'), directors));
    p.rows.push(new VideoStorylineRow(L10n.t('video_detail_actors', '演员'), actors));
    p.rows.push(new VideoStorylineRow(L10n.t('video_detail_genres', '类型'), asStr(m['nfo_genres']).trim()));
    p.rows.push(new VideoStorylineRow(L10n.t('video_detail_regions', '地区'), asStr(m['nfo_regions']).trim()));
    DialogUtil.openCustom(p, wrapBuilder(VideoStorylineDialogContent));
  }

  private static joinPeople(people: VideoPersonInfo[]): string {
    return people.map((e: VideoPersonInfo): string => e.name.trim()).join('、');
  }

  private titleText(): string {
    const m = this.ctrl.item;
    const nfoName = asStr(m['nfo_name']).trim();
    return nfoName.length > 0 ? nfoName : asStr(m['filename']);
  }

  build() {
    // 标题与内容合并为单个 Text（标题在最前，粗体区分），点击查看完整信息
    Text() {
      Span(`${L10n.t('video_detail_storyline', '剧情简介')}:`)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(DetailColors.alpha(0.9))
      Span(` ${this.storyline()}`)
        .fontSize(14)
        .fontColor(DetailColors.alpha(0.85))
    }
    .lineHeight(22)
    .maxLines(4)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .copyOption(CopyOptions.InApp)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(12)
    .width('100%')
    .onClick(() => {
      this.showDetailDialog();
    })
  }
}

/** 剧情详情弹窗行 */
export class VideoStorylineRow {
  label: string;
  value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

class VideoStorylineDialogParams extends DialogParamsBase {
  title: string = '';
  rows: VideoStorylineRow[] = [];
  storyline: string = '';
}

@ComponentV2
struct VideoStorylineDialogInner {
  @Param p: VideoStorylineDialogParams = new VideoStorylineDialogParams();

  @Builder
  Row_(row: VideoStorylineRow) {
    Row() {
      Text(row.label)
        .fontSize(12)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
        .fontWeight(FontWeight.Medium)
        .width(72)
      Text(row.value.trim().length > 0 ? row.value.trim() : '-')
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .copyOption(CopyOptions.InApp)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 10 })
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text(L10n.t('detail', '详情'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')
      Scroll() {
        Column() {
          if (this.p.title.trim().length > 0) {
            Text(this.p.title)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
              .margin({ bottom: 8 })
              .width('100%')
          }
          ForEach(this.p.rows, (row: VideoStorylineRow) => {
            this.Row_(row)
          }, (row: VideoStorylineRow): string => row.label)
          Text(L10n.t('video_detail_storyline', '剧情简介'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .margin({ top: 4, bottom: 8 })
            .width('100%')
          Text(this.p.storyline.length > 0 ? this.p.storyline : L10n.t('video_detail_storyline_empty', '暂无剧情简介'))
            .fontSize(14)
            .lineHeight(22)
            .fontColor(AppTheme.current().onSurface)
            .copyOption(CopyOptions.InApp)
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .margin({ top: 14 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .width('100%')
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function VideoStorylineDialogContent(p: VideoStorylineDialogParams) {
  VideoStorylineDialogInner({ p: p })
}

/** 操作区（对齐 AppVideoDetailActionsSection）：播放/刷新/收藏/更多 + 观看进度 */
@ComponentV2
export struct VideoDetailActionsSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);
  /** 删除后关闭详情页 */
  @Param onDeleted: () => void = (): void => {
  };
  @Local favTouched: boolean = false;
  @Local favOverride: boolean = false;
  @Local favoriteLoading: boolean = false;

  private itemIsFavorite(): boolean {
    const raw = this.ctrl.item['is_favorite'];
    return raw === true || raw === 1 || raw === '1';
  }

  private effectiveFavorite(): boolean {
    return this.favTouched ? this.favOverride : this.itemIsFavorite();
  }

  private async toggleFavorite(): Promise<void> {
    if (this.favoriteLoading) {
      return;
    }
    const id = this.ctrl.indexId;
    if (id <= 0) {
      return;
    }
    const prev = this.effectiveFavorite();
    const next = !prev;
    this.favoriteLoading = true;
    this.favTouched = true;
    this.favOverride = next;
    try {
      const api = new VideoFavoriteApiService();
      const ok = next ? await api.addFavorite(id) : await api.removeFavorite(id);
      if (!ok) {
        this.favOverride = prev;
        ToastUtil.show(L10n.t('operation_failed', '操作失败'));
        return;
      }
      this.ctrl.patchFavorite(next);
      ToastUtil.show(L10n.t('operation_success', '操作成功'));
    } finally {
      this.favoriteLoading = false;
    }
  }

  /** 详情页路径解析（对齐详情页本地 _resolve*Path，含 BDMV/VIDEO_TS 特殊处理） */
  private static resolveBrowsePath(m: Record<string, Object>): string {
    const mediaType = asStr(m['media_type']).trim().toLowerCase();
    const filePath = asStr(m['full_path']).trim();
    const basePath = asStr(m['path']).trim();
    const filename = asStr(m['filename']).trim();
    const isMovieLike = mediaType === 'movie' || mediaType === 'bdmv' || mediaType === 'video_ts';
    if (isMovieLike) {
      if (filePath.length > 0) {
        return DetailActions.dirname(filePath);
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.dirname(DetailActions.join(basePath, filename));
      }
    }
    if (mediaType === 'tv' || mediaType === 'season') {
      if (filePath.length > 0) {
        return filePath;
      }
    }
    if (basePath.length > 0) {
      return basePath;
    }
    if (filePath.length > 0) {
      return DetailActions.dirname(filePath);
    }
    return '';
  }

  private static resolveDeletePath(m: Record<string, Object>): string {
    const mediaType = asStr(m['media_type']).trim().toLowerCase();
    const filePath = asStr(m['full_path']).trim();
    const basePath = asStr(m['path']).trim();
    const filename = asStr(m['filename']).trim();
    if (mediaType === 'bdmv') {
      if (filePath.length > 0) {
        return DetailActions.join(filePath, 'BDMV');
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.join(DetailActions.join(basePath, filename), 'BDMV');
      }
      return '';
    }
    if (mediaType === 'video_ts') {
      if (filePath.length > 0) {
        return DetailActions.join(filePath, 'VIDEO_TS');
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.join(DetailActions.join(basePath, filename), 'VIDEO_TS');
      }
      return '';
    }
    if (mediaType === 'movie' || mediaType === 'bdmv' || mediaType === 'video_ts') {
      if (filePath.length > 0) {
        return filePath;
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.join(basePath, filename);
      }
    }
    if (basePath.length > 0) {
      return basePath;
    }
    return filePath;
  }

  private static resolveDownloadPath(m: Record<string, Object>): string {
    const mediaType = asStr(m['media_type']).trim().toLowerCase();
    const filePath = asStr(m['full_path']).trim();
    const basePath = asStr(m['path']).trim();
    const filename = asStr(m['filename']).trim();
    if (mediaType === 'movie' || mediaType === 'bdmv' || mediaType === 'video_ts') {
      if (filePath.length > 0) {
        return filePath;
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.join(basePath, filename);
      }
      return '';
    }
    if (mediaType === 'tv' || mediaType === 'season') {
      if (filePath.length > 0) {
        return filePath;
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.join(basePath, filename);
      }
      return basePath;
    }
    if (filePath.length > 0) {
      return filePath;
    }
    if (basePath.length > 0 && filename.length > 0) {
      return DetailActions.join(basePath, filename);
    }
    return basePath;
  }

  private showProgress(): boolean {
    const t = this.ctrl.mediaType;
    const isMovieLike = t === 'movie' || t === 'bdmv' || t === 'video_ts';
    return this.ctrl.hasHistory && (t === 'season' || isMovieLike);
  }

  private watchedText(): string {
    const watched = formatEpisodeDuration(this.ctrl.historySeconds);
    if (this.ctrl.mediaType === 'season' && this.ctrl.historyEpisodeNum > 0) {
      const params = L10n.paramsOf('time', watched);
      params.set('ep', `${this.ctrl.historyEpisodeNum}`);
      return L10n.t('video_detail_watched_episode', '已观看 @time [Ep @ep]', params);
    }
    return L10n.t('video_detail_watched', '已观看 @time', L10n.paramsOf('time', watched));
  }

  @Builder
  ActionButton(icon: Resource, bg: string, fg: string, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([fg])
    }
    .justifyContent(FlexAlign.Center)
    .width(42)
    .height(42)
    .borderRadius(12)
    .backgroundColor(bg)
    .onClick(() => {
      onTap();
    })
  }

  private showMoreSheet(): void {
    const m = this.ctrl.item;
    const p = new VideoDetailMoreSheetParams();
    p.isAdmin = CurrentUserStore.getInstance().isAdmin;
    p.canEditOpenSkip = p.isAdmin && this.ctrl.canEditOpenSkip;
    p.downloadTarget = VideoDetailActionsSection.resolveDownloadPath(m);
    p.browseTarget = VideoDetailActionsSection.resolveBrowsePath(m);
    p.deleteTarget = VideoDetailActionsSection.resolveDeletePath(m);
    p.onDownload = (): void => {
      // 下载依赖传输模块（未迁移）
      ToastUtil.show(L10n.featureComingSoon);
    };
    p.onBrowse = (): void => {
      if (p.browseTarget.length === 0) {
        return;
      }
      NavUtil.push(AppRouter.FILES, { 'initialPath': p.browseTarget } as Record<string, string>);
    };
    p.onSearchMedia = (): void => {
      VideoSearchMediaHelper.open(parseVideoHomeItemBean(m as Object));
    };
    p.onEditOpenSkip = (): void => {
      void this.editOpenSkip();
    };
    p.onAutoScrape = (): void => {
      void VideoItemActions.startAutoScrape(parseVideoHomeItemBean(m as Object));
    };
    p.onCleanupScrape = (): void => {
      void VideoItemActions.cleanupScrapeInfo(parseVideoHomeItemBean(m as Object));
    };
    p.onScanChanges = (): void => {
      void VideoItemActions.scanChanges(parseVideoHomeItemBean(m as Object));
    };
    p.onDelete = (): void => {
      VideoItemActions.deletePath(p.deleteTarget, true, false, this.ctrl.indexId, (): void => {
        this.onDeleted();
      });
    };
    SheetUtil.present(p, wrapBuilder(VideoDetailMoreSheetContent));
  }

  private async editOpenSkip(): Promise<void> {
    if (!CurrentUserStore.getInstance().isAdmin || !this.ctrl.canEditOpenSkip) {
      return;
    }
    if (this.ctrl.indexId <= 0) {
      return;
    }
    const form = await showVideoOpenSkipDialog(this.ctrl.openSkipStartSeconds, this.ctrl.openSkipEndSeconds);
    if (form === undefined) {
      return;
    }
    const res = await new VideoDetailApiService().setOpenSkip(
      this.ctrl.indexId, form.startSeconds, form.endSeconds);
    if (!res.success) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    await this.ctrl.refreshDetail();
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        // 播放（播放器未迁移，与下载一致提示）
        this.ActionButton($r('sys.symbol.play_fill'), DetailColors.playBlue, DetailColors.onSurface, (): void => {
          ToastUtil.show(L10n.featureComingSoon);
        })
        // 刷新
        this.ActionButton($r('sys.symbol.arrow_clockwise'), DetailColors.container, DetailColors.onSurface,
          (): void => {
            void this.ctrl.refreshDetail();
          })
        // 收藏
        this.ActionButton(
          this.effectiveFavorite() ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
          DetailColors.container,
          this.effectiveFavorite() ? '#FF453A' : DetailColors.onSurface,
          (): void => {
            void this.toggleFavorite();
          })
        // 更多
        this.ActionButton($r('sys.symbol.more'), DetailColors.container, DetailColors.onSurface, (): void => {
          this.showMoreSheet();
        })
      }
      .width('100%')

      if (this.showProgress()) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .height(6)
            .width('100%')
            .borderRadius(999)
            .backgroundColor(DetailColors.alpha(0.12))
          Row()
            .height(6)
            .width(`${Math.min(Math.max(this.ctrl.historySeconds / Math.max(this.ctrl.historyDurationSeconds, 1), 0), 1) * 100}%`)
            .borderRadius(999)
            .backgroundColor(DetailColors.progressBlue)
        }
        .margin({ top: 10 })
        .width('100%')
        Text(this.watchedText())
          .fontSize(12)
          .lineHeight(16)
          .fontColor(DetailColors.alpha(0.62))
          .margin({ top: 10 })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

/** 详情更多操作弹层参数 */
class VideoDetailMoreSheetParams extends SheetParamsBase {
  isAdmin: boolean = false;
  canEditOpenSkip: boolean = false;
  downloadTarget: string = '';
  browseTarget: string = '';
  deleteTarget: string = '';
  onDownload: () => void = (): void => {
  };
  onBrowse: () => void = (): void => {
  };
  onSearchMedia: () => void = (): void => {
  };
  onEditOpenSkip: () => void = (): void => {
  };
  onAutoScrape: () => void = (): void => {
  };
  onCleanupScrape: () => void = (): void => {
  };
  onScanChanges: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

/** 详情页路径工具（对齐 package:path 的 dirname/join） */
export class DetailActions {
  static dirname(path: string): string {
    const s = path.trim();
    if (s.length === 0) {
      return s;
    }
    const normalized = s.replace(/\\/g, '/');
    const idx = normalized.lastIndexOf('/');
    if (idx <= 0) {
      return s;
    }
    return normalized.substring(0, idx);
  }

  static join(base: string, name: string): string {
    const b = base.trim().replace(/\/+$/, '').replace(/\\+$/, '');
    const n = name.trim().replace(/^\/+/, '').replace(/^\\+/, '');
    if (b.length === 0) {
      return n;
    }
    const sep = b.includes('\\') || /^[A-Za-z]:/.test(b) ? '\\' : '/';
    return `${b}${sep}${n}`;
  }
}

@ComponentV2
struct VideoDetailMoreSheetInner {
  @Param p: VideoDetailMoreSheetParams = new VideoDetailMoreSheetParams();

  @Builder
  Item(icon: Resource, title: string, enabled: boolean, danger: boolean, onTap: () => void) {
    Row({ space: 14 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([danger ? AppTheme.current().error : (enabled ? AppTheme.current().onSurface : AppTheme.current().hint)])
      Text(title)
        .fontSize(15)
        .fontColor(danger ? AppTheme.current().error : (enabled ? AppTheme.current().onSurface : AppTheme.current().hint))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    .onClick(() => {
      if (enabled) {
        this.p.close();
        onTap();
      }
    })
  }

  build() {
    Column() {
      SheetHandle()
      this.Item($r('sys.symbol.square_and_arrow_down'), L10n.t('download', '下载'),
        this.p.downloadTarget.length > 0, false, this.p.onDownload)
      this.Item($r('sys.symbol.folder'), L10n.t('file_browse', '浏览文件'),
        this.p.browseTarget.length > 0, false, this.p.onBrowse)
      if (this.p.isAdmin) {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor(AppTheme.current().divider)
          .margin({ top: 4, bottom: 4 })
        this.Item($r('sys.symbol.magnifyingglass'), L10n.t('video_search_media_info', '搜索媒体信息'),
          true, false, this.p.onSearchMedia)
        if (this.p.canEditOpenSkip) {
          this.Item($r('sys.symbol.stopwatch'), L10n.t('video_detail_open_skip', '设置片头跳过'),
            true, false, this.p.onEditOpenSkip)
        }
        this.Item($r('sys.symbol.wand_and_stars'), L10n.t('video_scrape_auto', '自动刮削'),
          true, false, this.p.onAutoScrape)
        this.Item($r('sys.symbol.clean'), L10n.t('video_scrape_cleanup', '清理刮削信息'),
          true, false, this.p.onCleanupScrape)
        this.Item($r('sys.symbol.arrow_clockwise'), L10n.t('video_item_scan_changes', '扫描变更'),
          true, false, this.p.onScanChanges)
      }
      Row()
        .width('100%')
        .height(1)
        .backgroundColor(AppTheme.current().divider)
        .margin({ top: 4, bottom: 4 })
      this.Item($r('sys.symbol.trash'), L10n.t('delete', '删除'),
        this.p.deleteTarget.length > 0, true, this.p.onDelete)
      Blank().height(24)
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function VideoDetailMoreSheetContent(p: VideoDetailMoreSheetParams) {
  VideoDetailMoreSheetInner({ p: p })
}

/** 季列表区（对齐 VideoDetailSeasonSection）：横向海报，点击进入对应季详情 */
@ComponentV2
export struct VideoDetailSeasonSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);
  @Local viewWidth: number = 0;

  private itemWidth(): number {
    const w = this.viewWidth;
    if (w <= 0 || w < 420) {
      return 120;
    }
    if (w < 720) {
      return 140;
    }
    return 168;
  }

  private openSeason(indexId: number): void {
    if (indexId <= 0) {
      return;
    }
    const param = new VideoDetailPageParam();
    param.indexId = indexId;
    NavUtil.push(AppRouter.VIDEO_DETAIL, param);
  }

  build() {
    Column() {
      Text(L10n.t('video_detail_season_list_title', '季（@count）',
        L10n.paramsOf('count', `${this.ctrl.seasonList.length}`)))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(DetailColors.onSurface)
      Scroll() {
        Row({ space: 12 }) {
          ForEach(this.ctrl.seasonList, (s: Record<string, Object>) => {
            Column() {
              VideoItemPoster({ item: this.ctrl.seasonToBean(s) })
            }
            .width(this.itemWidth())
            .onClick(() => {
              this.openSeason(this.ctrl.seasonToBean(s).id);
            })
          }, (s: Record<string, Object>, idx: number): string => `${idx}_${asNum(s['id'])}`)
        }
        .padding({ right: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .margin({ top: 10 })
      .onAreaChange((_o: Area, n: Area): void => {
        this.viewWidth = Number(n.width);
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

/** 剧集区（对齐 VideoDetailEpisodeSection）：排序 + 简介/文件视图 + 分页 + 网格卡片 */
@ComponentV2
export struct VideoDetailEpisodeSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);
  @Local viewWidth: number = 0;

  private gridColumnCount(): number {
    const w = this.viewWidth;
    if (w <= 0) {
      return 1;
    }
    return Math.max(1, Math.floor((w + 10) / 330));
  }

  private itemWidth(): number {
    const cols = this.gridColumnCount();
    const w = this.viewWidth > 0 ? this.viewWidth : 330;
    return (w - (cols - 1) * 10) / cols;
  }

  /** 按列数分行（Grid 嵌套滚动问题 → 手动分块） */
  private episodeRows(): Record<string, Object>[][] {
    const cols = this.gridColumnCount();
    const rows: Record<string, Object>[][] = [];
    let row: Record<string, Object>[] = [];
    for (const e of this.ctrl.episodes) {
      row.push(e);
      if (row.length >= cols) {
        rows.push(row);
        row = [];
      }
    }
    if (row.length > 0) {
      rows.push(row);
    }
    return rows;
  }

  private isShowingAllEpisodes(): boolean {
    const total = this.ctrl.episodeTotal;
    if (total <= 0) {
      return false;
    }
    return this.ctrl.episodes.length >= total;
  }

  private static episodeName(e: Record<string, Object>): string {
    const nfo = asStr(e['nfo_name']).trim();
    return nfo.length > 0 ? nfo : asStr(e['filename']);
  }

  private static episodePath(e: Record<string, Object>): string {
    return asStr(e['full_path']).trim();
  }

  /** 剧集点击播放（播放器未迁移，提示） */
  private playEpisode(_index: number): void {
    ToastUtil.show(L10n.featureComingSoon);
  }

  private showEpisodeIntroDialog(e: Record<string, Object>): void {
    const p = new VideoEpisodeIntroDialogParams();
    const epNum = asNum(e['episod_num']);
    p.title = epNum > 0
      ? L10n.t('video_detail_episode_no', '第 @num 集', L10n.paramsOf('num', `${epNum}`))
      : L10n.t('video_detail_episodes', '剧集');
    p.name = VideoDetailEpisodeSection.episodeName(e);
    p.path = VideoDetailEpisodeSection.episodePath(e);
    const plot = asStr(e['nfo_storyline']).trim();
    p.plot = plot.length > 0 ? plot : L10n.t('video_detail_storyline_empty', '暂无剧情简介');
    DialogUtil.openCustom(p, wrapBuilder(VideoEpisodeIntroDialogContent));
  }

  @Builder
  PagerChip(page: number, label: string, selected: boolean) {
    Text(label)
      .fontSize(12)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(selected ? DetailColors.onSurface : DetailColors.alpha(0.8))
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(10)
      .backgroundColor(selected ? DetailColors.playBlue : DetailColors.container)
      // chip 之间右侧间距 + 换行行间距
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        void this.ctrl.jumpToEpisodePage(page);
      })
  }

  @Builder
  Pager() {
    if (this.ctrl.episodeLoading) {
      Row() {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(DetailColors.playBlue)
      }
      .height(40)
      .width('100%')
    } else if (this.ctrl.episodeTotalPages > 1) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.pagerLabels(), (c: VideoPagerChip) => {
          this.PagerChip(c.page, c.label, c.selected)
        }, (c: VideoPagerChip): string => `${c.page}`)
      }
      // 与剧集列表之间留白
      .margin({ bottom: 12 })
    }
  }

  private pagerLabels(): VideoPagerChip[] {
    const out: VideoPagerChip[] = [];
    const totalPages = this.ctrl.episodeTotalPages;
    const total = this.ctrl.episodeTotal;
    const asc = this.ctrl.episodeAsc;
    const size = this.ctrl.episodePageSize;
    for (let i = 0; i < totalPages; i++) {
      const page = i + 1;
      let start = 0;
      let end = 0;
      if (asc) {
        start = (page - 1) * size + 1;
        end = Math.min(Math.max(page * size, 1), Math.max(total, 1));
      } else {
        start = Math.min(Math.max(total - page * size + 1, 1), Math.max(total, 1));
        end = Math.min(Math.max(total - (page - 1) * size, 1), Math.max(total, 1));
      }
      const c = new VideoPagerChip();
      c.page = page;
      c.label = `${start}-${end}`;
      c.selected = page === this.ctrl.episodePage;
      out.push(c);
    }
    return out;
  }

  @Builder
  PlayBadge() {
    Column() {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(12)
        .fontColor([DetailColors.onSurface])
    }
    .padding(4)
    .borderRadius(999)
    .backgroundColor(AppTheme.withAlpha(DetailColors.playBlue, 0.8))
  }

  /** 剧集徽标（时长 + 集数，简介/文件卡片共用） */
  @Builder
  EpisodeBadges(e: Record<string, Object>) {
    if (asNum(e['duration']) > 0) {
      Text(`[${formatEpisodeDuration(asNum(e['duration']))}]`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(DetailColors.alpha(0.6))
    }
    if (asNum(e['episod_num']) > 0) {
      Text(L10n.t('video_detail_episode_no', '第 @num 集', L10n.paramsOf('num', `${asNum(e['episod_num'])}`)))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(DetailColors.alpha(0.6))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  @Builder
  EpisodeIntroCard(e: Record<string, Object>, index: number) {
    Row() {
      Stack() {
        DetailAsyncImage({
          provider: (): Promise<string> => {
            const bean = parseVideoHomeItemBean(e as Object);
            return VideoUtils.getPosterUrl(bean, 300);
          },
          imageRadius: 14
        })
        Column() {
          this.PlayBadge()
        }
        .margin({ top: 6, right: 6 })
      }
      .alignContent(Alignment.TopEnd)
      .width(115)
      .height(95)
      .border({ width: 1, color: DetailColors.alpha(0.3) })
      .borderRadius(14)
      .clip(true)

      Column() {
        Row({ space: 6 }) {
          this.EpisodeBadges(e)
        }
        Text(VideoDetailEpisodeSection.episodeName(e))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(DetailColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
        Row() {
          Text(this.plotOf(e))
            .fontSize(12)
            .lineHeight(17)
            .fontColor(DetailColors.alpha(0.7))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: 6 })
        .onClick(() => {
          this.showEpisodeIntroDialog(e);
        })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    }
    .alignItems(VerticalAlign.Center)
    .width(this.itemWidth())
    .height(95)
    .borderRadius(14)
    .clip(true)
    .onClick(() => {
      this.playEpisode(index);
    })
  }

  private plotOf(e: Record<string, Object>): string {
    const plot = asStr(e['nfo_storyline']).trim();
    return plot.length > 0 ? plot : L10n.t('video_detail_storyline_empty', '暂无剧情简介');
  }

  @Builder
  EpisodeFileCard(e: Record<string, Object>, index: number) {
    Row() {
      Stack() {
        if (asStr(e['full_path']).trim().length > 0) {
          DetailAsyncImage({
            provider: (): Promise<string> => ApiUrls.getTinyUrl(asStr(e['full_path']).trim()),
            imageRadius: 14
          })
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(DetailColors.surface)
        }
        if (asStr(e['full_path']).trim().length > 0) {
          Column() {
            this.PlayBadge()
          }
          .margin({ top: 6, right: 6 })
        }
      }
      .alignContent(Alignment.TopEnd)
      .width(115)
      .height(95)
      .border({ width: 1, color: DetailColors.alpha(0.3) })
      .borderRadius(14)
      .clip(true)

      Column() {
        Row({ space: 6 }) {
          this.EpisodeBadges(e)
        }
        Text(asStr(e['filename']))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(DetailColors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
        Text(asStr(e['full_path']).trim())
          .fontSize(12)
          .fontColor(DetailColors.alpha(0.7))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .alignItems(VerticalAlign.Center)
    .width(this.itemWidth())
    .height(95)
    .borderRadius(14)
    .clip(true)
    .onClick(() => {
      this.playEpisode(index);
    })
  }

  build() {
    Column() {
      // 头部：标题 + 排序 + 视图切换
      Row() {
        Text(this.headerText())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(DetailColors.onSurface)
        Blank()
        SymbolGlyph(this.ctrl.episodeAsc ? $r('sys.symbol.arrow_up') : $r('sys.symbol.arrow_down'))
          .fontSize(20)
          .fontColor([DetailColors.alpha(0.85)])
          .padding(6)
          .onClick(() => {
            void this.ctrl.toggleEpisodeSort();
          })
        Row({ space: 0 }) {
          Text(L10n.t('video_detail_view_intro', '简介'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.ctrl.episodeIntroMode ? DetailColors.onSurface : DetailColors.alpha(0.6))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(this.ctrl.episodeIntroMode ? DetailColors.playBlue : DetailColors.container)
            .borderRadius({ topLeft: 10, bottomLeft: 10 })
            .onClick(() => {
              this.ctrl.episodeIntroMode = true;
            })
          Text(L10n.t('file', '文件'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(!this.ctrl.episodeIntroMode ? DetailColors.onSurface : DetailColors.alpha(0.6))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(!this.ctrl.episodeIntroMode ? DetailColors.playBlue : DetailColors.container)
            .borderRadius({ topRight: 10, bottomRight: 10 })
            .onClick(() => {
              this.ctrl.episodeIntroMode = false;
            })
        }
      }
      .width('100%')
      .margin({ bottom: 10 })
      // 分页
      this.Pager()
      // 列表
      if (this.ctrl.episodes.length > 0) {
        Column({ space: 10 }) {
          ForEach(this.episodeRows(), (row: Record<string, Object>[], rowIdx: number) => {
            Row({ space: 10 }) {
              ForEach(row, (e: Record<string, Object>, colIdx: number) => {
                if (this.ctrl.episodeIntroMode) {
                  this.EpisodeIntroCard(e, rowIdx * this.gridColumnCount() + colIdx)
                } else {
                  this.EpisodeFileCard(e, rowIdx * this.gridColumnCount() + colIdx)
                }
              }, (e: Record<string, Object>, colIdx: number): string => `${rowIdx}_${colIdx}_${asStr(e['full_path'])}`)
            }
            .width('100%')
          }, (row: Record<string, Object>[], rowIdx: number): string => `row_${rowIdx}`)
        }
        .width('100%')
        .onAreaChange((_o: Area, n: Area): void => {
          this.viewWidth = Number(n.width);
        })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  private headerText(): string {
    const total = this.ctrl.episodeTotal;
    const suffix = total > 0 ? ` (${total})` : '';
    return `${L10n.t('video_detail_episodes', '剧集')}${suffix}`;
  }
}

class VideoPagerChip {
  page: number = 0;
  label: string = '';
  selected: boolean = false;
}

class VideoEpisodeIntroDialogParams extends DialogParamsBase {
  title: string = '';
  name: string = '';
  path: string = '';
  plot: string = '';
}

@ComponentV2
struct VideoEpisodeIntroDialogInner {
  @Param p: VideoEpisodeIntroDialogParams = new VideoEpisodeIntroDialogParams();

  build() {
    Column() {
      Row() {
        Text(this.p.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')
      Scroll() {
        Column() {
          if (this.p.name.trim().length > 0) {
            Text(this.p.name)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.current().onSurface)
              .margin({ bottom: 10 })
              .width('100%')
          }
          if (this.p.path.length > 0) {
            Row({ space: 8 }) {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(16)
                .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.75)])
              Text(this.p.path)
                .fontSize(12)
                .lineHeight(17)
                .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.85))
                .copyOption(CopyOptions.InApp)
                .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .margin({ bottom: 12 })
            .width('100%')
          }
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext'))
              .fontSize(16)
              .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.75)])
            Text(this.p.plot)
              .fontSize(14)
              .lineHeight(22)
              .fontColor(AppTheme.current().onSurface)
              .copyOption(CopyOptions.InApp)
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .constraintSize({ maxHeight: 420 })
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .margin({ top: 14 })
      .width('100%')
      Text(L10n.t('ok', '确定'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().primary)
        .textAlign(TextAlign.End)
        .width('100%')
        .margin({ top: 16 })
        .onClick(() => {
          this.p.onResult(undefined);
        })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .width('100%')
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function VideoEpisodeIntroDialogContent(p: VideoEpisodeIntroDialogParams) {
  VideoEpisodeIntroDialogInner({ p: p })
}

/** 原盘内容区（对齐 VideoDetailDiscContentSection；标题为 Flutter 端原文硬编码） */
@ComponentV2
export struct VideoDetailDiscContentSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);

  private thumbProvider(item: Record<string, Object>): () => Promise<string> {
    return (): Promise<string> => {
      const internalPath = asStr(item['thumbnail_internal_path']).trim();
      const thumbPath = asStr(item['thumbnail_path']).trim();
      if (thumbPath.length > 0) {
        return ApiUrls.getTinyUrl(thumbPath);
      }
      if (internalPath.length === 0) {
        return Promise.resolve('');
      }
      return Promise.resolve(new VideoDetailApiService().getDiscContentThumbUrl(this.ctrl.indexId, internalPath));
    };
  }

  private itemTitle(item: Record<string, Object>, index: number): string {
    const title = asStr(item['title']).trim();
    return title.length > 0 ? title : `Title ${index + 1}`;
  }

  build() {
    Column() {
      Row() {
        Text('原盘内容')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(DetailColors.onSurface)
        Blank()
        if (this.ctrl.discContentLoading) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(DetailColors.onSurface)
        }
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (!this.ctrl.discContentLoading && this.ctrl.discContents.length === 0) {
        Text('暂无原盘内容')
          .fontSize(14)
          .fontColor(DetailColors.alpha(0.75))
          .padding(14)
          .borderRadius(12)
          .backgroundColor(AppTheme.withAlpha(DetailColors.container, 0.35))
          .width('100%')
      }
      if (this.ctrl.discContents.length > 0) {
        Column({ space: 10 }) {
          ForEach(this.ctrl.discContents, (item: Record<string, Object>, index: number) => {
            Row() {
              DetailAsyncImage({ provider: this.thumbProvider(item), imageRadius: 10 })
                .width(128)
                .height(72)
              Column() {
                Text(this.itemTitle(item, index))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DetailColors.onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.displayNameOf(item))
                  .fontSize(12)
                  .fontColor(DetailColors.alpha(0.72))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 6 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .padding({ left: 12, right: 10 })
              SymbolGlyph($r('sys.symbol.play_circle'))
                .fontSize(22)
                .fontColor([DetailColors.onSurface])
            }
            .alignItems(VerticalAlign.Center)
            .padding(10)
            .borderRadius(12)
            .backgroundColor(AppTheme.withAlpha(DetailColors.container, 0.28))
            .width('100%')
            .onClick(() => {
              // 播放器未迁移
              ToastUtil.show(L10n.featureComingSoon);
            })
          }, (item: Record<string, Object>, index: number): string => `${index}_${asStr(item['path'])}`)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  private displayNameOf(item: Record<string, Object>): string {
    const name = asStr(item['display_name']).trim();
    return name.length > 0 ? name : '-';
  }
}

/** 演职人员区（对齐 VideoDetailPeopleSection）：导演+演员横向列表，点击进入其作品列表 */
@ComponentV2
export struct VideoDetailPeopleSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);

  private people(): VideoPersonInfo[] {
    const out: VideoPersonInfo[] = [];
    for (const d of this.ctrl.directors) {
      out.push(d);
    }
    for (const a of this.ctrl.actors) {
      out.push(a);
    }
    return out;
  }

  /** 演职人员点击 → 演员或导演筛选列表（对齐 AppVideoPersonVideosPage：复用列表页） */
  private openPerson(p: VideoPersonInfo): void {
    if (p.name.trim().length === 0) {
      return;
    }
    const isDirector = p.role === L10n.t('video_detail_directors', '导演');
    const lp = new VideoListPageParam();
    lp.title = `${isDirector ? L10n.t('video_detail_directors', '导演') : L10n.t('video_detail_actors', '演员')}-${p.name}`;
    lp.initialMediaType = this.ctrl.mediaType === 'season' ? 'tv' : this.ctrl.mediaType;
    if (isDirector) {
      lp.initialDirectors = [p.name];
    } else {
      lp.initialActors = [p.name];
    }
    NavUtil.push(AppRouter.VIDEO_LIST, lp);
  }

  build() {
    if (this.people().length > 0) {
      Column() {
        Text(L10n.t('video_detail_people', '演职人员'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(DetailColors.onSurface)
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.people(), (p: VideoPersonInfo) => {
              Column() {
                Stack() {
                  if (p.tmdbId.trim().length > 0) {
                    DetailAsyncImage({
                      provider: (): Promise<string> => VideoUtils.getPersonImageUrl(p.tmdbId, 240, p.thumb),
                      imageRadius: 10
                    })
                  } else {
                    Column() {
                      if (p.name.length > 0) {
                        Text(p.name.substring(0, 1))
                          .fontSize(20)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(DetailColors.alpha(0.55))
                      } else {
                        SymbolGlyph($r('sys.symbol.person'))
                          .fontSize(40)
                          .fontColor([DetailColors.alpha(0.55)])
                      }
                    }
                    .justifyContent(FlexAlign.Center)
                    .width('100%')
                    .height('100%')
                    .backgroundColor(DetailColors.container)
                  }
                }
                .width(120)
                .height(160)
                .borderRadius(10)
                .clip(true)
                Text(p.name)
                  .fontSize(12)
                  .fontColor(DetailColors.onSurface)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 8 })
                  .width(120)
                  .textAlign(TextAlign.Center)
                Text(p.role)
                  .fontSize(12)
                  .fontColor(DetailColors.alpha(0.65))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
                  .width(120)
                  .textAlign(TextAlign.Center)
              }
              .onClick(() => {
                this.openPerson(p);
              })
            }, (p: VideoPersonInfo, idx: number): string => `${idx}_${p.name}`)
            Blank().width(4)
          }
          .padding({ right: 4 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 10 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }
}

/** 文件信息区（对齐 VideoDetailFileInfoSection）：名称/路径/海报路径，点击打开文件浏览 */
@ComponentV2
export struct VideoDetailFileInfoSection {
  @Param ctrl: VideoDetailController = new VideoDetailController(0);

  private filename(): string {
    return asStr(this.ctrl.item['filename']).trim();
  }

  private fullPath(): string {
    return asStr(this.ctrl.item['full_path']).trim();
  }

  private posterPath(): string {
    return asStr(this.ctrl.item['poster_path']).trim();
  }

  /** 浏览目标目录（对齐 resolveBrowsePath） */
  private browseTarget(): string {
    const mediaType = this.ctrl.mediaType;
    const fullPath = this.fullPath();
    const basePath = asStr(this.ctrl.item['path']).trim();
    const filename = this.filename();
    if (mediaType === 'movie' || mediaType === 'bdmv' || mediaType === 'video_ts') {
      if (fullPath.length > 0) {
        return DetailActions.dirname(fullPath);
      }
      if (basePath.length > 0 && filename.length > 0) {
        return DetailActions.dirname(DetailActions.join(basePath, filename));
      }
    }
    if (mediaType === 'tv' || mediaType === 'season') {
      if (fullPath.length > 0) {
        return fullPath;
      }
    }
    if (basePath.length > 0) {
      return basePath;
    }
    if (fullPath.length > 0) {
      return DetailActions.dirname(fullPath);
    }
    return '';
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(DetailColors.alpha(0.65))
        .fontWeight(FontWeight.Medium)
        .width(56)
      Text(value)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(DetailColors.onSurface)
        .copyOption(CopyOptions.InApp)
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 10 })
    .width('100%')
  }

  build() {
    if (this.filename().length > 0 || this.fullPath().length > 0) {
      Column() {
        Text(L10n.t('fileinfo', '文件信息'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(DetailColors.onSurface)
        Row() {
          Column() {
            if (this.filename().length > 0) {
              this.InfoRow(L10n.t('name', '名称'), this.filename())
            }
            if (this.fullPath().length > 0) {
              this.InfoRow(L10n.t('path', '路径'), this.fullPath())
            }
            if (this.posterPath().length > 0) {
              this.InfoRow(L10n.t('poster', '海报'), this.posterPath())
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .padding(16)
        .borderRadius(14)
        .backgroundColor(AppTheme.withAlpha('#000000', 0.4))
        .margin({ top: 10 })
        .width('100%')
        .onClick(() => {
          const target = this.browseTarget();
          if (target.length === 0) {
            return;
          }
          NavUtil.push(AppRouter.FILES, { 'initialPath': target } as Record<string, string>);
        })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }
}

/** 片头片尾跳过设置弹窗结果（对齐 VideoOpenSkipFormResult） */
export class VideoOpenSkipFormResult {
  startSeconds: number = 0;
  endSeconds: number = 0;
}

class VideoOpenSkipDialogParams extends DialogParamsBase {
  startSeconds: number = 0;
  endSeconds: number = 0;
}

@ComponentV2
struct VideoOpenSkipDialogInner {
  @Param p: VideoOpenSkipDialogParams = new VideoOpenSkipDialogParams();
  @Local openMinutes: string = '0';
  @Local openSeconds: string = '00';
  @Local endMinutes: string = '0';
  @Local endSeconds: string = '00';

  aboutToAppear(): void {
    this.openMinutes = this.minutesText(this.p.startSeconds);
    this.openSeconds = this.secondsText(this.p.startSeconds);
    this.endMinutes = this.minutesText(this.p.endSeconds);
    this.endSeconds = this.secondsText(this.p.endSeconds);
  }

  private minutesText(total: number): string {
    const safe = Math.max(0, total);
    return `${Math.floor(safe / 60)}`;
  }

  private secondsText(total: number): string {
    const safe = Math.max(0, total);
    return `${safe % 60}`.padStart(2, '0');
  }

  private resolveSeconds(minutes: string, seconds: string): number {
    const m = Math.max(0, Number.parseInt(minutes.trim().length > 0 ? minutes.trim() : '0', 10) || 0);
    const s = Math.min(59, Math.max(0, Number.parseInt(seconds.trim().length > 0 ? seconds.trim() : '0', 10) || 0));
    return m * 60 + s;
  }

  private resetAll(): void {
    this.openMinutes = '0';
    this.openSeconds = '00';
    this.endMinutes = '0';
    this.endSeconds = '00';
  }

  @Builder
  TimeEditor(title: string, minutes: string, seconds: string, onMinutes: (v: string) => void,
    onSeconds: (v: string) => void) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
      Row({ space: 12 }) {
        TextInput({ text: minutes })
          .type(InputType.Number)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(42)
          .layoutWeight(1)
          .onChange((v: string): void => {
            onMinutes(v);
          })
        TextInput({ text: seconds })
          .type(InputType.Number)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(42)
          .layoutWeight(1)
          .onChange((v: string): void => {
            onSeconds(v);
          })
      }
      .margin({ top: 8 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column() {
      Text(L10n.t('video_detail_open_skip', '设置片头跳过'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
      Scroll() {
        Column() {
          Text(L10n.t('video_detail_open_skip_tip', '设置片头/片尾跳过时间，播放时将自动跳过'))
            .fontSize(14)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
          Column() {
            this.TimeEditor(L10n.t('video_detail_open_skip_opening', '片头'),
              this.openMinutes, this.openSeconds, (v: string): void => {
                this.openMinutes = v;
              }, (v: string): void => {
                this.openSeconds = v;
              })
            this.TimeEditor(L10n.t('video_detail_open_skip_ending', '片尾'),
              this.endMinutes, this.endSeconds, (v: string): void => {
                this.endMinutes = v;
              }, (v: string): void => {
                this.endSeconds = v;
              })
          }
          .margin({ top: 16 })
          .width('100%')
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
              .fontSize(16)
              .fontColor([AppTheme.current().primary])
            Text(L10n.t('video_detail_open_skip_clear', '清空'))
              .fontSize(14)
              .fontColor(AppTheme.current().primary)
          }
          .margin({ top: 12 })
          .onClick(() => {
            this.resetAll();
          })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .margin({ top: 16 })
      .width('100%')
      Row({ space: 8 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(L10n.t('save', '保存'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .onClick(() => {
            this.p.onResult(`${this.resolveSeconds(this.openMinutes, this.openSeconds)}|${this.resolveSeconds(this.endMinutes, this.endSeconds)}`);
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .width('100%')
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function VideoOpenSkipDialogContent(p: VideoOpenSkipDialogParams) {
  VideoOpenSkipDialogInner({ p: p })
}

/** 打开片头片尾跳过设置弹窗（对齐 showVideoOpenSkipDialog） */
export function showVideoOpenSkipDialog(initialStartSeconds: number, initialEndSeconds: number):
  Promise<VideoOpenSkipFormResult | undefined> {
  return new Promise<VideoOpenSkipFormResult | undefined>((resolve: (v: VideoOpenSkipFormResult | undefined) => void) => {
    const p = new VideoOpenSkipDialogParams();
    p.startSeconds = initialStartSeconds;
    p.endSeconds = initialEndSeconds;
    DialogUtil.openCustom(p, wrapBuilder(VideoOpenSkipDialogContent), true, (r: DialogResult | undefined): void => {
      if (typeof r === 'string') {
        const parts = r.split('|');
        const result = new VideoOpenSkipFormResult();
        result.startSeconds = Number.parseInt(parts[0], 10) || 0;
        result.endSeconds = parts.length > 1 ? (Number.parseInt(parts[1], 10) || 0) : 0;
        resolve(result);
        return;
      }
      resolve(undefined);
    });
  });
}
