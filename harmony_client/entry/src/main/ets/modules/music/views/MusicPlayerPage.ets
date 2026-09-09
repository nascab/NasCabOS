import { window } from '@kit.ArkUI';
import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { WindowStore } from '../../../common/WindowStore';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { AppImage } from '../../../common/components/AppImage';
import { MusicPlayService, MusicLoopMode, LyricLine } from '../service/MusicPlayService';
import { MusicLoopModes } from '../models/MusicModels';
import { MusicListItem } from '../models/MusicModels';
import { MusicDiscWithNeedle } from '../components/MusicDiscWithNeedle';
import { MusicDiscCover } from '../components/MusicDiscCover';
import { MusicLyricsView } from '../components/MusicLyricsView';
import { MusicListApiService } from '../services/MusicApiServices';
import { PlayListApiService } from '../services/MusicApiServices';
import { MusicFileApiService, MusicFileAttributes } from '../services/MusicApiServices';
import { pickMusicPlayListId } from '../components/MusicPlayListSelectSheet';
import { FileFormat } from '../../../files/models/FileModels';
import { AppEventBus } from '../../../common/AppEventBus';
import { ThemeManager } from '../../../core/theme/ThemeManager';

/** 全屏播放页路由参数（对齐 Flutter MusicPlayCtrlFullScreenSheet） */
export class MusicPlayerPageParam {
}

// ===== 播放队列抽屉（对齐 MusicPlayCtrlFullScreenPlaylistDrawer.showBottomSheet） =====

class MusicQueueSheetParams extends SheetParamsBase {
  svc: MusicPlayService = MusicPlayService.getInstance();
}

@Builder
function musicQueueSheetBuilder(params: MusicQueueSheetParams) {
  Column() {
    SheetHandle()
    Row() {
      Text(L10n.t('player_playlist'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .layoutWeight(1)
        .margin({ left: 16 })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(20)
        .fontColor([AppTheme.current().onSurface])
        .padding(8)
        .onClick(() => {
          params.close();
        })
        .margin({ right: 12 })
    }
    .width('100%')
    .height(52)

    List({ space: 0 }) {
      ForEach(params.svc.playlist, (it: MusicListItem, i: number) => {
        ListItem() {
          MusicQueueRow({ svc: params.svc, item: it, index: i, close: params.close })
        }
      }, (it: MusicListItem) => `${it.id}_${it.fileHash}_${it.filename}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .padding({ bottom: 12 })
  }
  .width('100%')
  .height('86%')
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius({ topLeft: 16, topRight: 16 })
}

@ComponentV2
struct MusicQueueRow {
  @Param svc: MusicPlayService = MusicPlayService.getInstance();
  @Param item: MusicListItem = new MusicListItem();
  @Param index: number = 0;
  @Param close: () => void = (): void => {
  };

  @Local private url: string = '';
  private token: number = 0;

  aboutToAppear(): void {
    this.resolve();
  }

  @Monitor('item')
  onItemChange(): void {
    this.resolve();
  }

  private resolve(): void {
    const p = this.item.coverFilePath().trim();
    if (p.length === 0 || this.item.hasInnerCover !== 1) {
      this.url = '';
      return;
    }
    const token = ++this.token;
    ApiUrls.getMusicCoverUrl(p, 120).then((u: string): void => {
      if (token === this.token) {
        this.url = u;
      }
    }).catch((_e: Object): void => {
      if (token === this.token) {
        this.url = '';
      }
    });
  }

  build() {
    Row({ space: 12 }) {
      Stack() {
        if (this.url.length > 0) {
          AppImage({ url: this.url, showLoadingSpin: false })
        } else {
          Image($rawfile('music/icons/default_cover.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
        if (this.index === this.svc.currentIndex) {
          Column() {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(18)
              .fontColor(['#FFFFFF'])
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#59000000')
        }
      }
      .width(42)
      .height(42)
      .borderRadius(8)
      .clip(true)

      Column() {
        Text(this.item.displayTitle)
          .fontSize(15)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.item.artist.trim().length > 0 ? this.item.artist.trim() : '-')
          .fontSize(12)
          .fontColor(AppTheme.current().subText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    .backgroundColor(this.index === this.svc.currentIndex
      ? AppTheme.withAlpha(AppTheme.current().primary, 0.08) : '#00000000')
    .onClick(() => {
      this.svc.playAt(this.index).then((): void => {
        this.close();
      });
    })
  }
}

// ===== 歌词搜索弹窗（对齐 MusicPlayCtrlFullScreenLyricSearchDialog） =====

class LyricSearchDialogParams extends DialogParamsBase {
  musicPath: string = '';
  title: string = '';
  artist: string = '';
  onApplied: (lrc: string) => void = (_lrc: string): void => {
  };
}

class LyricSearchRowItem {
  id: string = '';
  title: string = '';
  album: string = '';
  artist: string = '';
  durationMs: number = 0;
  lrc: string = '';
}

class LyricSearchDialogState {
  keyword: string = '';
  loading: boolean = false;
  selectingId: string = '';
  results: LyricSearchRowItem[] = [];
}

@Builder
function musicLyricSearchDialogBuilder(params: LyricSearchDialogParams) {
  MusicLyricSearchDialogContent({ params: params })
}

@ComponentV2
struct MusicLyricSearchDialogContent {
  @Param params: LyricSearchDialogParams = new LyricSearchDialogParams();
  @Local state: LyricSearchDialogState = new LyricSearchDialogState();
  private autoSearched: boolean = false;

  aboutToAppear(): void {
    this.state.keyword = `${this.params.title} ${this.params.artist}`.trim();
    // 自动搜索（对齐 didAutoSearch postFrameCallback）
    setTimeout((): void => {
      this.doSearch();
    }, 60);
  }

  private async doSearch(): Promise<void> {
    const q = this.state.keyword.trim();
    if (q.length === 0) {
      ToastUtil.show(L10n.t('input_please'));
      return;
    }
    this.state.loading = true;
    this.state.results = [];
    try {
      this.state.results = await MusicListApiService.searchLyric(q);
    } catch (_e) {
      this.state.results = [];
    } finally {
      this.state.loading = false;
    }
  }

  private fileStem(path: string): string {
    const normalized = path.trim().replace(/\\/g, '/');
    const slash = normalized.lastIndexOf('/');
    const name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    const dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  private normalizeForContains(input: string): string {
    return input.trim().toLowerCase().replace(/[^0-9a-z一-龥]+/g, '');
  }

  private previewLine(lrc: string): string {
    const text = lrc.trim();
    if (text.length === 0) {
      return '';
    }
    for (const raw of text.split('\n')) {
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

  private formatMs(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${`${m}`.padStart(2, '0')}:${`${s}`.padStart(2, '0')}`;
  }

  private async applyItem(item: LyricSearchRowItem): Promise<void> {
    const lrc = item.lrc.trim();
    if (lrc.length === 0) {
      ToastUtil.show(L10n.operationFailed);
      return;
    }
    this.state.selectingId = item.id;
    try {
      const ok = await MusicListApiService.setLyric(this.params.musicPath, lrc);
      if (!ok) {
        ToastUtil.show(L10n.operationFailed);
        return;
      }
      this.params.onApplied(lrc);
      ToastUtil.show(L10n.t('operation_success'));
      this.params.onResult(undefined);
    } finally {
      this.state.selectingId = '';
    }
  }

  build() {
    Column() {
      Row() {
        Text(L10n.t('music_search_lyric'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([AppTheme.current().onSurface])
          .padding(6)
          .onClick(() => {
            this.params.onResult(undefined);
          })
      }
      .width('100%')
      .padding({ bottom: 10 })

      Row({ space: 8 }) {
        TextInput({ text: this.state.keyword, placeholder: L10n.t('search') })
          .fontSize(14)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.state.keyword = v;
          })
          .onSubmit((): void => {
            void this.doSearch();
          })
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(20)
          .fontColor([AppTheme.current().primary])
          .padding(8)
          .onClick(() => {
            void this.doSearch();
          })
      }
      .width('100%')

      if (this.state.loading) {
        Column() {
          LoadingProgress()
            .width(26)
            .height(26)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      } else if (this.state.results.length === 0) {
        Column() {
          Text(L10n.t('no_data'))
            .fontSize(14)
            .fontColor(AppTheme.current().subText)
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.state.results, (item: LyricSearchRowItem) => {
            ListItem() {
              Column() {
                Row({ space: 8 }) {
                  if (this.isHighMatch(item)) {
                    Text(L10n.t('music_lyric_high_match', '高匹配度'))
                      .fontSize(11)
                      .fontColor(AppTheme.current().onSurface)
                      .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.6) })
                      .borderRadius(6)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  }
                  Text(item.title.trim().length > 0 ? item.title.trim() : item.id)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(AppTheme.current().onSurface)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')

                Text(this.metaLine(item))
                  .fontSize(12)
                  .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 2 })

                Row() {
                  Text(this.previewLine(item.lrc))
                    .fontSize(12)
                    .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(this.state.selectingId === item.id ? '' : L10n.t('select'))
                    .fontSize(14)
                    .fontColor(AppTheme.current().primary)
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .onClick(() => {
                      void this.applyItem(item);
                    })
                }
                .width('100%')
                .margin({ top: 2 })
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .border({ width: { bottom: 0.5 }, color: AppTheme.current().divider })
            }
          }, (item: LyricSearchRowItem) => item.id)
        }
        .width('100%')
        .height(360)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding(16)
  }

  private trackDurationMs(): number {
    return MusicPlayService.getInstance().durationMs;
  }

  private isHighMatch(item: LyricSearchRowItem): boolean {
    const durationMatch = item.durationMs > 0 &&
      Math.abs(item.durationMs - this.trackDurationMs()) <= 5000;
    if (!durationMatch) {
      return false;
    }
    const fileStemNorm = this.normalizeForContains(this.fileStem(this.params.musicPath));
    const titleNorm = this.normalizeForContains(item.title);
    return titleNorm.length > 0 && fileStemNorm.length > 0 && fileStemNorm.includes(titleNorm);
  }

  private metaLine(item: LyricSearchRowItem): string {
    const parts: string[] = [];
    if (item.artist.trim().length > 0) {
      parts.push(item.artist.trim());
    }
    if (item.album.trim().length > 0) {
      parts.push(item.album.trim());
    }
    if (item.durationMs > 0) {
      parts.push(this.formatMs(item.durationMs));
    }
    return parts.join(' · ');
  }
}

// ===== 全屏播放页 =====

/**
 * 音乐全屏播放页（对齐 Flutter MusicPlayCtrlFullScreenSheet 移动端形态）：
 * 模糊封面背景 + 唱片/歌词双态 + 底部控制条 + 播放队列抽屉 + 歌词搜索 + 文件属性。
 */
@ComponentV2
export struct MusicPlayerPage {
  @Param param: MusicPlayerPageParam = new MusicPlayerPageParam();
  @Param popPage: () => void = (): void => {
  };

  private svc: MusicPlayService = MusicPlayService.getInstance();
  /** 主题变化刷新计数 */
  @Local themeTick: number = 0;
  @Local statusBarHeight: number = 0;
  @Local navigationBarHeight: number = 0;
  @Local showLyrics: boolean = false;
  @Local favoriteLoading: boolean = false;
  @Local coverUrlLarge: string = '';
  @Local bodyHeight: number = 0;
  @Local bodyWidth: number = 0;
  private coverToken: number = 0;
  private retryTimer: number = -1;
  private themeListener: (data: string) => void = (_data: string): void => {
    this.themeTick++;
  };

  aboutToAppear(): void {
    this.setFullScreen(true);
    this.fetchSafeAreas();
    AppEventBus.on(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.showLyrics = PreferencesStore.getInstance().getBool(CacheKeys.MUSIC_FULL_SCREEN_SHOW_LYRICS, false);
    this.resolveCover();
  }

  aboutToDisappear(): void {
    AppEventBus.off(ThemeManager.EVENT_THEME_CHANGED, this.themeListener);
    this.clearRetryTimer();
    // 返回目标是音乐主页（常规页）：必须恢复避让布局
    this.setFullScreen(false);
  }

  private setFullScreen(full: boolean): void {
    const w = WindowStore.getMainWindow();
    if (w !== undefined) {
      w.setWindowLayoutFullScreen(full);
    }
  }

  private scheduleFullScreenRetry(): void {
    this.clearRetryTimer();
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.setFullScreen(true);
    }, 120);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private fetchSafeAreas(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    // 钳制到合理范围，防止转场/布局切换瞬间返回异常值导致页面错乱
    this.statusBarHeight = Math.min(Math.max(px2vp(top.topRect.height), 0), 140);
    const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    this.navigationBarHeight = Math.min(Math.max(px2vp(bottom.bottomRect.height), 0), 60);
  }

  private currentItem(): MusicListItem | undefined {
    const idx = this.svc.currentIndex;
    if (idx < 0 || idx >= this.svc.playlist.length) {
      return undefined;
    }
    return this.svc.playlist[idx];
  }

  private resolveCover(): void {
    const item = this.currentItem();
    if (item === undefined || item.hasInnerCover !== 1) {
      this.coverUrlLarge = '';
      return;
    }
    const coverPath = item.coverFilePath();
    if (coverPath.trim().length === 0) {
      this.coverUrlLarge = '';
      return;
    }
    const token = ++this.coverToken;
    ApiUrls.getMusicCoverUrl(coverPath, 1200).then((u: string): void => {
      if (token === this.coverToken) {
        this.coverUrlLarge = u;
      }
    }).catch((_e: Object): void => {
      if (token === this.coverToken) {
        this.coverUrlLarge = '';
      }
    });
  }

  private setShowLyrics(v: boolean): void {
    if (this.showLyrics === v) {
      return;
    }
    this.showLyrics = v;
    PreferencesStore.getInstance().setBool(CacheKeys.MUSIC_FULL_SCREEN_SHOW_LYRICS, v);
  }

  private canIndexActions(): boolean {
    const item = this.currentItem();
    if (item === undefined) {
      return false;
    }
    return item.id > 0 && !item.isFromFile &&
      item.showType.trim().toLowerCase() !== 'file_browser';
  }

  private async toggleFavorite(): Promise<void> {
    const item = this.currentItem();
    if (item === undefined || this.favoriteLoading || item.id <= 0) {
      return;
    }
    const next = !item.isFavorite;
    this.favoriteLoading = true;
    try {
      const ok = next ? await MusicListApiService.addFavorite(item.id)
        : await MusicListApiService.removeFavorite(item.id);
      if (!ok) {
        ToastUtil.show(L10n.operationFailed);
        return;
      }
      item.isFavorite = next;
    } finally {
      this.favoriteLoading = false;
    }
  }

  private async addToPlayList(): Promise<void> {
    const item = this.currentItem();
    if (item === undefined || item.id <= 0) {
      return;
    }
    const listId = await pickMusicPlayListId();
    if (listId <= 0) {
      return;
    }
    const res = await PlayListApiService.addIndexes(listId, [item.id]);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
  }

  private showQueueSheet(): void {
    const params = new MusicQueueSheetParams();
    params.svc = this.svc;
    SheetUtil.present<MusicQueueSheetParams>(params, wrapBuilder(musicQueueSheetBuilder));
  }

  private showLyricSearchDialog(): void {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const p = new LyricSearchDialogParams();
    p.musicPath = item.resolvePlayablePath();
    p.title = item.displayTitle;
    p.artist = item.artist.trim();
    p.onApplied = (lrc: string): void => {
      this.svc.applyLyricOverride(item.resolvePlayablePath(), lrc);
    };
    DialogUtil.openCustom<LyricSearchDialogParams>(p, wrapBuilder(musicLyricSearchDialogBuilder));
  }

  private async showProperties(): Promise<void> {
    const item = this.currentItem();
    if (item === undefined) {
      return;
    }
    const filePath = item.resolvePlayablePath();
    if (filePath.trim().length === 0) {
      return;
    }
    const data: MusicFileAttributes | undefined = await MusicFileApiService.getAttributes(filePath);
    if (data === undefined) {
      DialogUtil.showErrorDialog(L10n.t('get_file_property_failed'));
      return;
    }
    const lines: string[] = [
      `${L10n.t('location')}: ${data.path}`,
      `${L10n.t('file_name')}: ${data.name}`,
      `${L10n.t('total_size')}: ${FileFormat.formatSize(data.size)}`,
      `${L10n.t('create_time')}: ${FileFormat.formatMtime(data.birthtime)}`,
      `${L10n.t('modified_at')}: ${FileFormat.formatMtime(data.mtime)}`
    ];
    DialogUtil.showInfoDialog(L10n.t('property'), lines.join('\n'));
  }

  private loopIcon(): Resource {
    switch (this.svc.loopMode) {
      case MusicLoopMode.listLoop:
        return $r('sys.symbol.repeat');
      case MusicLoopMode.singleLoop:
        return $r('sys.symbol.repeat_1');
      case MusicLoopMode.shuffle:
        return $r('sys.symbol.shuffle');
      default:
        return $r('sys.symbol.list_number');
    }
  }

  private cycleLoopMode(): void {
    const order = MusicLoopModes.ORDER;
    const current = this.svc.loopMode === MusicLoopMode.sequence ? MusicLoopModes.SEQUENCE
      : this.svc.loopMode === MusicLoopMode.listLoop ? MusicLoopModes.LIST_LOOP
        : this.svc.loopMode === MusicLoopMode.singleLoop ? MusicLoopModes.SINGLE_LOOP
          : MusicLoopModes.SHUFFLE;
    const idx = order.indexOf(current);
    const next = order[(idx + 1) % order.length];
    const mode = next === MusicLoopModes.LIST_LOOP ? MusicLoopMode.listLoop
      : next === MusicLoopModes.SINGLE_LOOP ? MusicLoopMode.singleLoop
        : next === MusicLoopModes.SHUFFLE ? MusicLoopMode.shuffle : MusicLoopMode.sequence;
    void this.svc.setLoopMode(mode);
  }

  private formatMs(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const mm = `${m}`.padStart(2, '0');
    const ss = `${s}`.padStart(2, '0');
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  private downloadProgressText(): string {
    const item = this.currentItem();
    if (item === undefined || !this.svc.isDownloading) {
      return '';
    }
    const hash = this.svc.downloadingFileHash.trim();
    if (hash.length === 0 || hash !== item.fileHash.trim()) {
      return '';
    }
    const pct = Math.round(Math.min(Math.max(this.svc.downloadProgress, 0), 1) * 100);
    return `${pct}%`;
  }

  build() {
    NavDestination() {
      Stack() {
        // 模糊封面背景（opacity 0.2 + blur 50）+ 黑色 15% 遮罩
        Stack() {
          if (this.coverUrlLarge.length > 0) {
            AppImage({ url: this.coverUrlLarge, showLoadingSpin: false })
          } else {
            Image($rawfile('music/icons/default_cover.jpg'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
          }
        }
        .width('100%')
        .height('100%')
        .blur(50)
        .opacity(0.2)

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#26000000')

        Column() {
          this.Header()
          Column() {
            if (this.showLyrics) {
              this.LyricsBlock()
            } else {
              this.DiscBlock()
            }
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_o: Area, n: Area) => {
            this.bodyWidth = Number(n.width);
            this.bodyHeight = Number(n.height);
          })

          this.BottomBar()
        }
        .width('100%')
        .height('100%')
        .opacity(this.themeTick >= 0 ? 1 : 1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppTheme.current().pageBg)
    }
    .hideTitleBar(true)
    .onShown((): void => {
      this.setFullScreen(true);
      this.scheduleFullScreenRetry();
      // 全屏布局生效后重新取避让区（aboutToAppear 时窗口可能尚未完成布局切换）
      this.fetchSafeAreas();
    })
    .onHidden((): void => {
      this.clearRetryTimer();
    })
    .onBackPressed((): boolean => {
      this.popPage();
      return true;
    })
  }

  @Builder
  private Header() {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_down'))
        .fontSize(28)
        .fontColor([AppTheme.current().onSurface])
        .padding(4)
        .onClick(() => {
          this.popPage();
        })
      Blank()
    }
    .width('100%')
    .height(60)
    .padding({ left: 16, right: 16, top: this.statusBarHeight + 12 })
  }

  /** 唱片区：大唱片 + 动作行（收藏/换碟/属性/队列） */
  @Builder
  private DiscBlock() {
    Column() {
      Blank()
      MusicDiscWithNeedle({
        isPlaying: this.svc.isPlaying,
        coverUrl: this.coverUrlLarge,
        discAsset: this.svc.discAsset,
        boxSize: this.discBoxSize(),
        onTap: (): void => {
          this.setShowLyrics(true);
        }
      })
      Row({ space: 10 }) {
        if (this.canIndexActions()) {
          if (this.favoriteLoading) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color(AppTheme.current().onSurface)
          } else {
            SymbolGlyph(this.svc.currentItem !== undefined && this.svc.currentItem!.isFavorite
              ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(22)
              .fontColor([this.svc.currentItem !== undefined && this.svc.currentItem!.isFavorite
                ? '#E53935' : AppTheme.withAlpha(AppTheme.current().onSurface, 0.85)])
              .onClick(() => {
                void this.toggleFavorite();
              })
          }
        }
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise_clock'))
          .fontSize(22)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.85)])
          .onClick(() => {
            void this.svc.nextDiscStyle();
          })
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(22)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.85)])
          .onClick(() => {
            void this.showProperties();
          })
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(22)
          .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.85)])
          .onClick(() => {
            this.showQueueSheet();
          })
      }
      .height(48)
      .margin({ top: 10 })
      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 0, bottom: 8 })
  }

  private discBoxSize(): number {
    const byWidth = Math.max(0, this.bodyWidth - 36);
    const byHeight = Math.max(0, this.bodyHeight - 58);
    const v = Math.min(520, byWidth, byHeight);
    // 首帧 onAreaChange 未回传（bodyWidth/bodyHeight 为 0）时兜底，避免唱片尺寸 0 完全不可见
    return v > 0 ? v : 320;
  }

  /** 歌词区（对齐 LyricBlock 移动端居中形态） */
  @Builder
  private LyricsBlock() {
    Stack() {
      Column() {
        Text(this.svc.currentItem !== undefined ? this.svc.currentItem!.displayTitle : '')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.92))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        this.MetaLine(L10n.t('music_label_album'),
          this.svc.currentItem !== undefined ? this.svc.currentItem!.album.trim() : '')
        this.MetaLine(L10n.t('music_label_singer'),
          this.svc.currentItem !== undefined ? this.svc.currentItem!.artist.trim() : '')
        Row() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(15)
              .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.65)])
            Text(L10n.t('music_search_lyric'))
              .fontSize(13)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
          }
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(18)
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.45) })
          .onClick(() => {
            this.showLyricSearchDialog();
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 14, bottom: 12 })

        MusicLyricsView({
          lyrics: this.svc.currentLyrics,
          positionMs: this.svc.positionMs,
          centerMode: true,
          onSeekLine: (t: number): void => {
            this.svc.seekTo(t);
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24, bottom: 8 })

      // 右下角小唱片：点击返回唱片视图
      MusicDiscCover({
        coverPath: this.svc.currentItem !== undefined ? this.svc.currentItem!.coverFilePath() : '',
        isPlaying: this.svc.isPlaying,
        discAsset: this.svc.discAsset,
        outerSize: 50,
        innerSize: 34,
        onTap: (): void => {
          this.setShowLyrics(false);
        }
      })
        .position({ x: this.bodyWidth - 62, y: this.bodyHeight - 62 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private MetaLine(label: string, value: string) {
    if (value.trim().length > 0) {
      Text(`${label}: ${value}`)
        .fontSize(14)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.65))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 8 })
    }
  }

  /** 底部控制条（对齐 BottomBar 移动端：标题行 + 进度条 + 控制行） */
  @Builder
  private BottomBar() {
    // 高度由内容自然撑开（Stack 不设高度时子组件 height('100%') 会参照整页解析，导致控制条占满全屏）
    Stack() {
      Column() {
        // 标题行
        Column() {
          Text(this.svc.currentItem !== undefined ? this.svc.currentItem!.displayTitle : '')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: 8 }) {
            if (this.downloadProgressText().length > 0) {
              Text(this.downloadProgressText())
                .fontSize(12)
                .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
            }
            if (this.subtitleText().length > 0) {
              Text(this.subtitleText())
                .fontSize(12)
                .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')
          .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 10, bottom: 6 })

        // 进度条 + 时间标签
        Column() {
          Slider({
            value: Math.min(this.svc.positionMs, this.svc.durationMs > 0 ? this.svc.durationMs : 1),
            min: 0,
            max: this.svc.durationMs > 0 ? this.svc.durationMs : 1,
            style: SliderStyle.OutSet
          })
            .selectedColor(AppTheme.current().primary)
            .trackColor(AppTheme.withAlpha(AppTheme.current().divider, 0.42))
            .blockColor(AppTheme.current().primary)
            .trackThickness(4)
            .trackBorderRadius(2)
            .width('100%')
            .enabled(this.svc.durationMs > 0)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End) {
                this.svc.seekTo(Math.round(value));
              }
            })
          Row() {
            Text(this.formatMs(this.svc.positionMs))
              .fontSize(12)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.7))
            Blank()
            Text(this.formatMs(this.svc.durationMs))
              .fontSize(12)
              .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.7))
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        // 控制行
        Row({ space: 22 }) {
          SymbolGlyph(this.loopIcon())
            .fontSize(22)
            .fontColor([AppTheme.current().onSurface])
            .onClick(() => {
              this.cycleLoopMode();
            })
          SymbolGlyph($r('sys.symbol.backward_end_fill'))
            .fontSize(28)
            .fontColor([AppTheme.current().onSurface])
            .onClick(() => {
              void this.svc.playPrevious(false);
            })
          SymbolGlyph(this.svc.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_circle_fill'))
            .fontSize(54)
            .fontColor([AppTheme.current().onSurface])
            .onClick(() => {
              if (this.svc.isPlaying) {
                void this.svc.pause();
              } else {
                void this.svc.play();
              }
            })
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(28)
            .fontColor([AppTheme.current().onSurface])
            .onClick(() => {
              void this.svc.playNext(false);
            })
          if (this.canIndexActions()) {
            SymbolGlyph($r('sys.symbol.plus_circle'))
              .fontSize(22)
              .fontColor([AppTheme.current().onSurface])
              .onClick(() => {
                void this.addToPlayList();
              })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: 12, right: 12, top: 6, bottom: 10 + this.navigationBarHeight })
      }
      .width('100%')
    }
    .width('100%')
    .backgroundColor('#26000000')
    .border({ width: { top: 0.8 }, color: '#0FFFFFFF' })
  }

  private subtitleText(): string {
    const item = this.currentItem();
    if (item === undefined || item.isSeries) {
      return '';
    }
    if (item.artist.trim().length > 0) {
      return item.artist.trim();
    }
    return item.album.trim();
  }
}
