import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { AppImage } from '../../../common/components/AppImage';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import {
  MusicAlbumArtistController, AlbumArtistSortBy, AlbumArtistSortOrder
} from '../controllers/MusicLibraryControllers';
import { MusicListItem, MusicListPathItem } from '../models/MusicModels';
import { MusicSubListPageParam } from '../router/MusicRoutes';
import { pickMusicPlayListId } from '../components/MusicPlayListSelectSheet';

/**
 * 专辑/艺人分组列表页（对齐 Flutter AlbumArtistListPage 移动端）：
 * 顶栏（搜索 + 排序 + 来源）+ 自适应网格卡片（封面/角标/名称/歌曲数）+
 * 右侧字母索引 + 底部加载更多。
 */
@ComponentV2
export struct MusicAlbumArtistPage {
  /** album / artist */
  @Param keyType: string = 'album';

  ctrl: MusicAlbumArtistController = new MusicAlbumArtistController(this.keyType);
  @Local private gridWidth: number = 0;

  private static readonly LETTERS: string[] = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '#'
  ];

  aboutToAppear(): void {
    this.ctrl = new MusicAlbumArtistController(this.keyType);
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private openSubList(name: string): void {
    const p = new MusicSubListPageParam();
    p.keyType = this.keyType;
    p.name = name;
    NavUtil.push(AppRouter.MUSIC_SUB_LIST, p);
  }

  /** 分组长按菜单（对齐 Flutter onLongPress 菜单：打开 / 加入歌单） */
  private async addToPlayList(item: MusicListItem): Promise<void> {
    const listId = await pickMusicPlayListId();
    if (listId > 0) {
      await this.ctrl.addToPlayList(item.filename, this.keyType.trim().toLowerCase() === 'artist',
        item.musicCount, listId);
    }
  }

  private gridColumns(): number {
    // onAreaChange 返回的是含 padding 的组件宽度，需扣除（左16+右28）对齐 Flutter crossAxisExtent
    const maxWidth = this.gridWidth > 0 ? this.gridWidth : 360;
    const content = Math.max(0, maxWidth - 44);
    const n = Math.floor(content / 150);
    return Math.min(Math.max(n, 2), 10);
  }

  private gridColumnsTemplate(): string {
    const n = this.gridColumns();
    const arr: string[] = [];
    for (let i = 0; i < n; i++) {
      arr.push('1fr');
    }
    return arr.join(' ');
  }

  private selectedLetter(): string {
    const raw = this.ctrl.searchText.trim();
    if (raw.length === 1 && (/^[a-zA-Z]$/.test(raw) || raw === '#')) {
      return raw.toUpperCase();
    }
    return '';
  }

  build() {
    Column() {
      this.TopBar()

      Stack() {
        if (this.ctrl.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.ctrl.items.length === 0) {
          Column() {
            EmptyState({ message: L10n.t('no_data') })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Grid() {
                ForEach(this.ctrl.items, (item: MusicListItem) => {
                  GridItem() {
                    MusicAlbumArtistCard({
                      item: item,
                      badgeLabel: this.ctrl.badgeLabel,
                      onTap: (): void => {
                        this.openSubList(item.filename);
                      },
                      onAddToPlayList: (): void => {
                        void this.addToPlayList(item);
                      }
                    })
                  }
                }, (item: MusicListItem) => `${item.showType}_${item.filename}`)
              }
              .columnsTemplate(this.gridColumnsTemplate())
              .columnsGap(4)
              .rowsGap(4)
              .width('100%')
              .padding({ left: 16, right: 28, top: 8, bottom: 20 })
              .onAreaChange((_o: Area, n: Area) => {
                this.gridWidth = Number(n.width);
              })

              this.GridFooter()
            }
            .width('100%')
          }
          .scrollBar(BarState.Auto)
          .width('100%')
          .height('100%')
          .onReachEnd(() => {
            void this.ctrl.loadMore(true);
          })

          // 字母索引（右侧垂直居中，对齐 CustomLetterFilter）
          this.LetterFilter()
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  /** 顶栏（对齐 AppAlbumArtistListTopBar） */
  @Builder
  TopBar() {
    Row({ space: 10 }) {
      SearchInputBar({
        hintText: this.keyType.trim().toLowerCase() === 'artist'
          ? L10n.t('music_artist_list_search_hint') : L10n.t('music_album_list_search_hint'),
        text: this.ctrl.searchText,
        onChanged: (v: string): void => {
          this.ctrl.onSearchChanged(v);
        },
        onClear: (): void => {
          this.ctrl.clearSearch();
        }
      })
      .layoutWeight(1)

      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
        active: this.ctrl.sortBy !== AlbumArtistSortBy.count || this.ctrl.sortOrder !== AlbumArtistSortOrder.desc,
        onTap: (): void => {
          this.showSortSheet();
        }
      })

      BorderedIconButton({
        icon: $r('sys.symbol.grid'),
        active: this.ctrl.selectedPaths.length > 0,
        onTap: (): void => {
          this.showSourceSheet();
        }
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 12, right: 12 })
    .border({ width: { bottom: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  private showSortSheet(): void {
    const options: PickOption[] = [
      new PickOption('count_desc', L10n.t('music_key_list_sort_count_desc', '歌曲数量 ↓')),
      new PickOption('count_asc', L10n.t('music_key_list_sort_count_asc', '歌曲数量 ↑')),
      new PickOption('name_asc', L10n.t('name_asc', '名称升序')),
      new PickOption('name_desc', L10n.t('name_desc', '名称降序'))
    ];
    const sel = `${this.ctrl.sortBy === AlbumArtistSortBy.count ? 'count' : 'name'}_${this.ctrl.sortOrder === AlbumArtistSortOrder.asc ? 'asc' : 'desc'}`;
    showOptionPickSheet(L10n.t('sort', '排序'), options, sel, (key: string): void => {
      const idx = key.lastIndexOf('_');
      if (idx <= 0) {
        return;
      }
      const by = key.substring(0, idx) === 'count' ? AlbumArtistSortBy.count : AlbumArtistSortBy.name;
      const order = key.substring(idx + 1) === 'asc' ? AlbumArtistSortOrder.asc : AlbumArtistSortOrder.desc;
      this.ctrl.setSort(by, order);
    });
  }

  /** 字母索引（选中字母高亮，点击过滤，再点取消） */
  @Builder
  LetterFilter() {
    Column() {
      ForEach(MusicAlbumArtistPage.LETTERS, (letter: string) => {
        Text(letter)
          .fontSize(10)
          .fontWeight(this.selectedLetter() === letter ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedLetter() === letter
            ? AppTheme.current().primary : AppTheme.current().subText)
          .width(18)
          .height(15)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            if (this.selectedLetter() === letter) {
              this.ctrl.setSearchImmediate('');
            } else {
              this.ctrl.setSearchImmediate(letter);
            }
          })
      }, (letter: string) => letter)
    }
    .width(20)
    .borderRadius(10)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, 0.9))
    .padding({ top: 5, bottom: 5 })
    .position({ x: '100%', y: '50%' })
    .markAnchor({ x: '100%', y: '50%' })
    .margin({ right: 4 })
  }

  /** 底部加载更多（对齐 AlbumArtistListFooter） */
  @Builder
  GridFooter() {
    Column() {
      if (this.ctrl.loadingMore) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(AppTheme.current().primary)
          .padding(12)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('music_list_no_more'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .padding(12)
      } else if (this.ctrl.autoLoadFailed) {
        Text(L10n.t('music_list_load_more'))
          .fontSize(13)
          .fontColor(AppTheme.current().primary)
          .padding(12)
          .onClick(() => {
            void this.ctrl.loadMore(false);
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 来源筛选弹层（对齐 AlbumArtistListSourcePanel） */
  private showSourceSheet(): void {
    const p = new AlbumArtistSourceSheetParams();
    p.ctrl = this.ctrl;
    SheetUtil.present<AlbumArtistSourceSheetParams>(p, wrapBuilder(AlbumArtistSourceSheetContent));
  }
}

// ===== 来源筛选弹层（对齐 AlbumArtistListSourcePanel） =====

class AlbumArtistSourceSheetParams extends SheetParamsBase {
  ctrl: MusicAlbumArtistController | undefined = undefined;
}

@Builder
function AlbumArtistSourceSheetContent(p: AlbumArtistSourceSheetParams) {
  AlbumArtistSourceSheetInner({ p: p })
}

@ComponentV2
struct AlbumArtistSourceSheetInner {
  @Param p: AlbumArtistSourceSheetParams = new AlbumArtistSourceSheetParams();

  private toggle(path: string): void {
    if (this.p.ctrl === undefined) {
      return;
    }
    this.p.ctrl.togglePath(path);
  }

  build() {
    Column() {
      SheetHandle()
      Row() {
        Text(L10n.t('source', '来源'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        Text(L10n.t('reset', '重置'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .onClick(() => {
            if (this.p.ctrl === undefined) {
              return;
            }
            this.p.ctrl.selectedPaths = [];
            void this.p.ctrl.refreshList(false);
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 10 })

      Divider().color(AppTheme.current().divider)

      List({ space: 0 }) {
        ForEach(this.p.ctrl !== undefined ? this.p.ctrl.availablePaths : [], (it: MusicListPathItem) => {
          ListItem() {
            Row({ space: 8 }) {
              CircleCheckbox({
                value: this.p.ctrl !== undefined && this.p.ctrl.selectedPaths.includes(it.path),
                onChanged: (_v: boolean): void => {
                  this.toggle(it.path);
                }
              })
              Text(it.path)
                .fontSize(13)
                .fontColor(AppTheme.current().onSurface)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              SymbolGlyph(it.valid ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.xmark_circle_fill'))
                .fontSize(16)
                .fontColor([it.valid ? '#4CAF50' : '#E53935'])
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => {
              this.toggle(it.path);
            })
          }
        }, (it: MusicListPathItem): string => it.path)
      }
      .width('100%')
      .height(260)
      .scrollBar(BarState.Auto)
      .padding({ bottom: 16 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

// ===== 分组卡片（对齐 AlbumArtistItemCard） =====

@ComponentV2
export struct MusicAlbumArtistCard {
  @Param item: MusicListItem = new MusicListItem();
  @Param badgeLabel: string = '';
  @Param onTap: () => void = (): void => {
  };
  @Param onAddToPlayList: () => void = (): void => {
  };

  @Local private url: string = '';
  private token: number = 0;

  aboutToAppear(): void {
    this.resolve();
  }

  aboutToDisappear(): void {
    this.token++;
  }

  @Monitor('item')
  onItemChange(): void {
    this.resolve();
  }

  private resolve(): void {
    const p = this.item.firstFilePath.trim();
    if (p.length === 0) {
      this.url = '';
      return;
    }
    const t = ++this.token;
    ApiUrls.getMusicCoverUrl(p, 200).then((u: string): void => {
      if (t === this.token) {
        this.url = u;
      }
    }).catch((_e: Object): void => {
      if (t === this.token) {
        this.url = '';
      }
    });
  }

  /** 对齐 Flutter _pickFallbackCoverAsset：seed=名称哈希 → other1-20 */
  private fallbackAsset(): string {
    const name = this.item.filename;
    let seed = 0;
    for (let i = 0; i < name.length; i++) {
      seed = (seed * 31 + name.charCodeAt(i)) | 0;
    }
    const idx = (Math.abs(seed) % 20) + 1;
    return `music/covers/other${idx}.jpg`;
  }

  private get subtitle(): string {
    return `${Math.max(0, this.item.musicCount)}首`;
  }

  build() {
    Column() {
      Stack() {
        if (this.url.length > 0) {
          AppImage({ url: this.url, showLoadingSpin: false })
        } else {
          Image($rawfile(this.fallbackAsset()))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }

        if (this.badgeLabel.trim().length > 0) {
          Text(this.badgeLabel)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor('rgba(0,0,0,0.55)')
            .position({ x: '100%', y: 0 })
            .markAnchor({ x: '100%' })
            .margin({ top: 6, right: 6 })
        }
      }
      .width('96%')
      .aspectRatio(1)
      .borderRadius(10)
      .clip(true)
      .onClick(() => {
        this.onTap();
      })
      .gesture(LongPressGesture({ repeat: false }).onAction(() => {
        this.showCardMenu();
      }))

      Text(this.item.filename)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })

      Text(this.subtitle)
        .fontSize(11)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .maxLines(1)
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 长按菜单（打开 / 加入歌单，对齐移动端 onLongPress 菜单） */
  private showCardMenu(): void {
    const options: PickOption[] = [
      new PickOption('open', L10n.t('open', '打开')),
      new PickOption('add', L10n.t('add_to_play_list', '添加到歌单'))
    ];
    showOptionPickSheet(this.item.filename, options, '', (key: string): void => {
      if (key === 'open') {
        this.onTap();
      } else if (key === 'add') {
        this.onAddToPlayList();
      }
    });
  }
}
