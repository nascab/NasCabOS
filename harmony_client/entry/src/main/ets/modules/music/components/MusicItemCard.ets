import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { AppImage } from '../../../common/components/AppImage';
import { MusicListItem } from '../models/MusicModels';
import { MusicListApiService, PlayListApiService } from '../services/MusicApiServices';
import { MusicPlayService } from '../service/MusicPlayService';
import { MusicListController } from '../controllers/MusicListController';

/** 移动端操作弹层参数 */
class MusicItemSheetParams extends SheetParamsBase {
  controller: MusicListController | undefined = undefined;
  item: MusicListItem = new MusicListItem();
}

/**
 * 歌曲网格卡片（对齐 Flutter MusicItemCard 移动端形态）：
 * 封面（无内嵌封面按流派随机 fallback）+ 徽标/选择框 + 左下操作入口（弹层）
 * + 标题（当前播放高亮）+ 副标题。series 打开子列表，单曲点击播放。
 */
@ComponentV2
export struct MusicItemCard {
  @Param controller: MusicListController = new MusicListController();
  @Param item: MusicListItem = new MusicListItem();
  @Param selectionMode: boolean = false;
  @Param selected: boolean = false;
  @Param onToggleSelected: () => void = (): void => {
  };
  @Param onOpenSeries: (item: MusicListItem) => void = (_item: MusicListItem): void => {
  };

  @Local private coverUrl: string = '';
  @Local private favOptimistic: number = -1; // -1 跟随 item.isFavorite
  private svc: MusicPlayService = MusicPlayService.getInstance();
  private coverToken: number = 0;

  aboutToAppear(): void {
    this.loadCover();
  }

  aboutToDisappear(): void {
    this.coverToken++;
  }

  @Monitor('item')
  onItemChange(): void {
    this.favOptimistic = -1;
    this.loadCover();
  }

  private get isCurrent(): boolean {
    const cur = this.svc.currentItem;
    if (cur === undefined) {
      return false;
    }
    const a = cur.resolvePlayablePath().trim();
    const b = this.item.resolvePlayablePath().trim();
    return a.length > 0 && a === b;
  }

  private get effectiveFavorite(): boolean {
    if (this.favOptimistic >= 0) {
      return this.favOptimistic === 1;
    }
    return this.item.isFavorite;
  }

  private loadCover(): void {
    if (this.item.hasInnerCover !== 1) {
      this.coverUrl = '';
      return;
    }
    const p = this.item.coverFilePath();
    if (p.length === 0) {
      this.coverUrl = '';
      return;
    }
    const token = ++this.coverToken;
    ApiUrls.getMusicCoverUrl(p, 200).then((url: string): void => {
      if (token === this.coverToken) {
        this.coverUrl = url;
      }
    }).catch((_e: Object): void => {
      if (token === this.coverToken) {
        this.coverUrl = '';
      }
    });
  }

  private badgeLabel(): string {
    if (this.item.isSeries) {
      return L10n.t('series');
    }
    let ext = this.item.ext.trim();
    if (ext.length === 0) {
      const name = this.item.filename.trim();
      const i = name.lastIndexOf('.');
      ext = (i >= 0 && i < name.length - 1) ? name.substring(i + 1) : '';
    }
    ext = ext.replace(/\./g, '').trim();
    return ext.toUpperCase();
  }

  private fallbackAsset(): string {
    // 对齐 Flutter _pickFallbackCoverAsset：流派前 6 张，否则 other 1-20
    const raw = this.item.genre.trim().toLowerCase();
    const parts = raw.split(/[\/,;|]/).map((e: string): string => e.trim());
    const head = parts.length > 0 ? parts[0] : '';
    const normalized = head.replace(/[^a-z0-9]/g, '');
    const genres = ['blues', 'classical', 'country', 'gospel', 'hiphop', 'pop', 'rock'];
    const id = Math.abs(this.item.id);
    if (normalized.length > 0 && genres.indexOf(normalized) >= 0) {
      const idx = (id % 6) + 1;
      return `music/covers/${normalized}${idx}.jpg`;
    }
    const idx = (id % 20) + 1;
    return `music/covers/other${idx}.jpg`;
  }

  private subtitleText(): string {
    if (this.item.isSeries) {
      const cnt = this.item.musicCount;
      return `${cnt < 0 ? 0 : cnt}${L10n.t('music_series_count_suffix', '首')}`;
    }
    return this.item.displaySubtitle;
  }

  private openItem(): void {
    if (this.item.isSeries) {
      this.onOpenSeries(this.item);
      return;
    }
    const isCurrent = this.isCurrent;
    if (isCurrent) {
      if (this.svc.isPlaying) {
        this.svc.pause();
      } else {
        this.svc.play();
      }
      return;
    }
    const playable = this.controller.items.filter((e: MusicListItem): boolean => !e.isSeries);
    if (playable.length === 0) {
      return;
    }
    this.svc.playFromList(playable, this.item, true, this.controller.buildPagingQuery());
  }

  // ===== 操作弹层（对齐 AppItemActionSheet） =====

  private showActionSheet(): void {
    if (this.selectionMode) {
      return;
    }
    const p = new MusicItemSheetParams();
    p.controller = this.controller;
    p.item = this.item;
    SheetUtil.present<MusicItemSheetParams>(p, musicItemSheetBuilder);
  }

  private async toggleFavorite(): Promise<void> {
    const id = this.item.id;
    if (id <= 0 || this.favOptimistic === 2) {
      return;
    }
    const prev = this.effectiveFavorite;
    const next = !prev;
    this.favOptimistic = next ? 1 : 0;
    const ok = next
      ? await MusicListApiService.addFavorite(id)
      : await MusicListApiService.removeFavorite(id);
    if (!ok) {
      this.favOptimistic = prev ? 1 : 0;
      return;
    }
    this.favOptimistic = -1;
    this.controller.updateFavoriteState(id, next);
  }

  private async addToPlayList(): Promise<void> {
    const indexId = this.item.id;
    if (indexId <= 0 || this.controller === undefined) {
      return;
    }
    const listId = await this.controller.pickPlayListId();
    if (listId <= 0) {
      return;
    }
    const res = await PlayListApiService.addIndexes(listId, [indexId]);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
  }

  build() {
    Column() {
      Stack() {
        // 封面
        if (this.coverUrl.length > 0) {
          AppImage({ url: this.coverUrl, showLoadingSpin: false })
        } else {
          Image($rawfile(this.fallbackAsset()))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }

        // 播放中指示（对齐 SpinKitWave，移动端仅当前播放曲显示）
        if (!this.selectionMode && this.isCurrent && this.svc.isPlaying) {
          Column() {
            SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
              .fontSize(20)
              .fontColor(['#E6FFFFFF'])
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#33000000')
        }

        // 收藏按钮（常驻：已收藏或非多选模式）
        if (!this.selectionMode) {
          Column() {
            SymbolGlyph(this.effectiveFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(14)
              .fontColor([this.effectiveFavorite ? '#FF3B30' : AppTheme.current().onSurface])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor('#BF' + AppTheme.current().surfaceBg.replace('#', ''))
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.12) })
          .position({ x: 6, y: 4 })
          .onClick(() => {
            this.toggleFavorite();
          })
        }

        // 右上徽标（非多选模式）
        if (!this.selectionMode && this.badgeLabel().length > 0) {
          Text(this.badgeLabel())
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#8C000000')
            .borderRadius(6)
            .position({ x: '100%', y: 6 })
            .markAnchor({ x: '100%' })
            .margin({ right: 6 })
        }

        // 左下操作入口（移动端）
        if (!this.selectionMode) {
          Column() {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize(14)
              .fontColor([AppTheme.current().onSurface])
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.75))
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.12) })
          .position({ x: 6, y: '100%' })
          .markAnchor({ y: '100%' })
          .margin({ bottom: 6 })
          .onClick(() => {
            this.showActionSheet();
          })
        }

        // 右下选择框（多选模式）
        if (this.selectionMode) {
          Column() {
            Circle()
              .width(22)
              .height(22)
              .fill(this.selected ? AppTheme.current().primary : '#00000000')
              .stroke('#FFFFFF')
              .strokeWidth(2)
          }
          .position({ x: '100%', y: '100%' })
          .markAnchor({ x: '100%', y: '100%' })
          .onClick(() => {
            this.onToggleSelected();
          })
        }
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(10)
      .clip(true)

      Column() {
        Text(this.item.displayTitle)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .fontColor(this.isCurrent ? AppTheme.current().primary : AppTheme.current().onSurface)
        if (this.subtitleText().length > 0) {
          Text(this.subtitleText())
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
            .margin({ top: 4 })
        }
      }
      .width('100%')
      .height(46)
      .margin({ top: 6 })
    }
    .width('100%')
    .onClick(() => {
      if (this.selectionMode) {
        this.onToggleSelected();
      } else {
        this.openItem();
      }
    })
  }
}

/** 卡片操作弹层内容（对齐 AppItemActionSheet：头部 + 动作列表） */
@ComponentV2
struct MusicItemSheet {
  @Param params: MusicItemSheetParams = new MusicItemSheetParams();

  build() {
    Column() {
      SheetHandle()
      // 头部
      Row({ space: 12 }) {
        Text(this.params.item.displayTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      this.SheetAction($r('sys.symbol.doc_plaintext'), L10n.t('open'), false, (): void => {
        this.params.close();
        // 打开即播放（对齐 Flutter open）
        const ctrl = this.params.controller;
        const item = this.params.item;
        if (ctrl !== undefined && !item.isSeries) {
          const playable = ctrl.items.filter((e: MusicListItem): boolean => !e.isSeries);
          if (playable.length > 0) {
            MusicPlayService.getInstance().playFromList(playable, item, true, ctrl.buildPagingQuery());
          }
        }
      })
      Divider().color(AppTheme.current().divider).margin({ left: 16 })
      this.SheetAction($r('sys.symbol.heart_fill'), this.ItemFavLabel(), false, (): void => {
        const item = this.params.item;
        this.params.close();
        this.ToggleFav(item);
      })
      this.SheetAction($r('sys.symbol.music_note_list'), L10n.t('add_to_play_list'), false, (): void => {
        this.params.close();
        this.AddItemToPlayList();
      })
      Divider().color(AppTheme.current().divider).margin({ left: 16 })
      this.SheetAction($r('sys.symbol.trash_fill'), L10n.t('delete'), true, (): void => {
        this.params.close();
        this.DeleteItem();
      })
    }
    .width('100%')
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 24 })
  }

  private ItemFavLabel(): string {
    const ctrl = this.params.controller;
    const item = this.params.item;
    if (ctrl === undefined) {
      return L10n.t('favorites');
    }
    const fav = item.isFavorite;
    return fav ? L10n.t('unfavorite') : L10n.t('favorites');
  }

  private async ToggleFav(item: MusicListItem): Promise<void> {
    const ctrl = this.params.controller;
    const id = item.id;
    if (ctrl === undefined || id <= 0) {
      return;
    }
    const next = !item.isFavorite;
    const ok = next
      ? await MusicListApiService.addFavorite(id)
      : await MusicListApiService.removeFavorite(id);
    if (!ok) {
      return;
    }
    ctrl.updateFavoriteState(id, next);
  }

  private async AddItemToPlayList(): Promise<void> {
    const ctrl = this.params.controller;
    const item = this.params.item;
    if (ctrl === undefined) {
      return;
    }
    const listId = await ctrl.pickPlayListId();
    if (listId <= 0 || item.id <= 0) {
      return;
    }
    const res = await PlayListApiService.addIndexes(listId, [item.id]);
    if (res.success) {
      ToastUtil.show(L10n.t('operation_success'));
    } else {
      ToastUtil.show(res.message.length > 0 ? res.message : L10n.operationFailed);
    }
  }

  private async DeleteItem(): Promise<void> {
    const ctrl = this.params.controller;
    const item = this.params.item;
    if (ctrl === undefined) {
      return;
    }
    // 确认（回收站可选）内置于 MusicListController.deleteItem
    await ctrl.deleteItem(item);
  }

  @Builder
  private SheetAction(icon: Resource, label: string, danger: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([danger ? '#FF3B30' : AppTheme.current().onSurface])
      Text(label)
        .fontSize(15)
        .fontColor(danger ? '#FF3B30' : AppTheme.current().onSurface)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      onTap();
    })
  }
}

/** sheet builder（全局，供 SheetUtil.present 使用） */
const musicItemSheetBuilder: WrappedBuilder<[MusicItemSheetParams]> = wrapBuilder(MusicItemSheetBuilderFn);

@Builder
function MusicItemSheetBuilderFn(params: MusicItemSheetParams) {
  MusicItemSheet({ params: params });
}
