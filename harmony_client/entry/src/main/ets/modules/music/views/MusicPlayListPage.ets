import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { AppImage } from '../../../common/components/AppImage';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { MusicPlaylistController } from '../controllers/MusicLibraryControllers';
import { PlayListItem, MusicListItem } from '../models/MusicModels';
import { MusicSubListPageParam } from '../router/MusicRoutes';

/**
 * 歌单列表页（对齐 Flutter PlayListListView 移动端）：
 * 顶栏（搜索 + 排序 + 创建）+ 单列横向卡片（四联封面 + 底部名称栏 + 更多）+
 * 底部加载更多；创建/重命名输入弹窗、删除确认。
 */
@ComponentV2
export struct MusicPlayListPage {
  ctrl: MusicPlaylistController = new MusicPlaylistController();

  aboutToAppear(): void {
    this.ctrl = new MusicPlaylistController();
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private openList(item: PlayListItem): void {
    const p = new MusicSubListPageParam();
    p.keyType = 'playlist';
    p.name = item.name;
    p.listId = item.id;
    NavUtil.push(AppRouter.MUSIC_SUB_LIST, p);
  }

  private showActions(item: PlayListItem): void {
    const options: PickOption[] = [
      new PickOption('open', L10n.t('open', '打开')),
      new PickOption('rename', L10n.t('rename', '重命名')),
      new PickOption('delete', L10n.t('delete', '删除'))
    ];
    showOptionPickSheet(item.name, options, '', (key: string): void => {
      if (key === 'open') {
        this.openList(item);
      } else if (key === 'rename') {
        this.showRenameDialog(item);
      } else if (key === 'delete') {
        this.confirmDelete(item);
      }
    });
  }

  private showCreateDialog(): void {
    DialogUtil.showInputDialog(L10n.t('create', '创建'), '', '',
      L10n.ok, L10n.cancel, (v: string): string | undefined => {
        return v.trim().length === 0 ? L10n.t('name_cannot_be_empty', '名称不能为空') : undefined;
      }).then((r: DialogResult | undefined) => {
      if (typeof r === 'string' && r.trim().length > 0) {
        void this.ctrl.createList(r.trim());
      }
    });
  }

  private showRenameDialog(item: PlayListItem): void {
    DialogUtil.showInputDialog(L10n.t('rename', '重命名'), '', item.name,
      L10n.ok, L10n.cancel, (v: string): string | undefined => {
        return v.trim().length === 0 ? L10n.t('name_cannot_be_empty', '名称不能为空') : undefined;
      }).then((r: DialogResult | undefined) => {
      if (typeof r === 'string' && r.trim().length > 0 && r.trim() !== item.name) {
        void this.ctrl.updateList(item.id, r.trim());
      }
    });
  }

  private confirmDelete(item: PlayListItem): void {
    DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      `${L10n.t('confirm_delete', '确认删除')}[${item.name}]`, (): void => {
        void this.ctrl.deleteList(item.id);
      });
  }

  private showSortSheet(): void {
    const options: PickOption[] = [
      new PickOption('name_asc', L10n.t('name_asc', '名称升序')),
      new PickOption('name_desc', L10n.t('name_desc', '名称降序')),
      new PickOption('create_time_asc', L10n.t('create_time_asc', '创建时间升序')),
      new PickOption('create_time_desc', L10n.t('create_time_desc', '创建时间降序'))
    ];
    const selected = `${this.ctrl.sortBy}_${this.ctrl.sortOrder}`;
    showOptionPickSheet(L10n.t('sort', '排序'), options, selected, (key: string): void => {
      const idx = key.lastIndexOf('_');
      if (idx <= 0) {
        return;
      }
      this.ctrl.setSort(key.substring(0, idx), key.substring(idx + 1));
    });
  }

  private isSortActive(): boolean {
    return this.ctrl.keyword.trim().length > 0 || this.ctrl.sortBy !== 'create_time' || this.ctrl.sortOrder !== 'desc';
  }

  build() {
    Column() {
      // 顶栏（对齐 AppPlayListTopBar）
      Row({ space: 10 }) {
        SearchInputBar({
          hintText: L10n.t('music_playlist_search_hint'),
          text: this.ctrl.keyword,
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
          active: this.isSortActive(),
          onTap: (): void => {
            this.showSortSheet();
          }
        })

        BorderedIconButton({
          icon: $r('sys.symbol.plus'),
          onTap: (): void => {
            this.showCreateDialog();
          }
        })
      }
      .width('100%')
      .height(60)
      .padding({ left: 12, right: 12 })
      .border({ width: { bottom: 1 }, color: AppTheme.current().divider })
      .backgroundColor(AppTheme.current().surfaceBg)

      // 内容
      if (this.ctrl.isLoading && this.ctrl.items.length === 0) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.ctrl.items.length === 0) {
        Column() {
          EmptyState({ message: L10n.t('no_data') })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.ctrl.items, (item: PlayListItem) => {
            ListItem() {
              MusicPlayListCard({
                item: item,
                onOpen: (): void => {
                  this.openList(item);
                },
                onMore: (): void => {
                  this.showActions(item);
                }
              })
            }
          }, (item: PlayListItem) => `${item.id}_${item.name}`)

          ListItem() {
            this.ListFooter()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 6, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          void this.ctrl.loadMore();
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ListFooter() {
    Column() {
      if (this.ctrl.isLoading && this.ctrl.items.length > 0) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(AppTheme.current().primary)
          .padding(12)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('music_playlist_no_more'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .padding(12)
      } else {
        Text(L10n.t('music_playlist_load_more'))
          .fontSize(13)
          .fontColor(AppTheme.current().primary)
          .padding(12)
          .onClick(() => {
            void this.ctrl.loadMore();
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}

// ===== 歌单卡片（对齐 PlayListListCard） =====

@ComponentV2
export struct MusicPlayListCard {
  @Param item: PlayListItem = new PlayListItem();
  @Param onOpen: () => void = (): void => {
  };
  @Param onMore: () => void = (): void => {
  };

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 四联封面（对齐 _buildPreviewGrid）
      Row({ space: 1 }) {
        ForEach(this.item.previews.slice(0, 4), (m: MusicListItem) => {
          MusicPlayListPreviewCover({ music: m })
        }, (m: MusicListItem) => `${m.id}_${m.filename}`)

        if (this.item.previews.length === 0) {
          Image($rawfile('music/icons/default_cover.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
      }
      .width('100%')
      .height('100%')

      // 底部名称栏
      Row() {
        Text(this.item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(18)
          .fontColor(['#FFFFFF'])
          .padding(6)
          .onClick(() => {
            this.onMore();
          })
      }
      .width('100%')
      .height(46)
      .padding({ left: 12, right: 6 })
      .backgroundColor('rgba(0,0,0,0.45)')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onOpen();
      })
    }
    .width('100%')
    .aspectRatio(1.8)
    .borderRadius(12)
    .clip(true)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.06))
    .onClick(() => {
      this.onOpen();
    })
  }
}

/** 预览封面单元（对齐 buildCover/fallbackCover） */
@ComponentV2
struct MusicPlayListPreviewCover {
  @Param music: MusicListItem = new MusicListItem();

  @Local private url: string = '';
  private token: number = 0;

  aboutToAppear(): void {
    this.resolve();
  }

  aboutToDisappear(): void {
    this.token++;
  }

  @Monitor('music')
  onMusicChange(): void {
    this.resolve();
  }

  private coverPath(): string {
    if (this.music.isSeries) {
      return this.music.firstFilePath.trim();
    }
    const full = this.music.fullPath.trim();
    if (full.length > 0) {
      return full;
    }
    const base = this.music.path.trim();
    const name = this.music.filename.trim();
    if (base.length > 0 && name.length > 0) {
      return `${base}/${name}`;
    }
    return base;
  }

  private resolve(): void {
    if (this.music.hasInnerCover !== 1) {
      this.url = '';
      return;
    }
    const p = this.coverPath();
    if (p.length === 0) {
      this.url = '';
      return;
    }
    const t = ++this.token;
    ApiUrls.getMusicCoverUrl(p, 500).then((u: string): void => {
      if (t === this.token) {
        this.url = u;
      }
    }).catch((_e: Object): void => {
      if (t === this.token) {
        this.url = '';
      }
    });
  }

  private fallbackAsset(): string {
    const raw = this.music.genre.trim().toLowerCase();
    const parts = raw.split(/[\/,;|]/).map((e: string): string => e.trim());
    const head = parts.length > 0 ? parts[0] : '';
    const normalized = head.replace(/[^a-z0-9]/g, '');
    const genres = ['blues', 'classical', 'country', 'gospel', 'hiphop', 'pop', 'rock'];
    const id = Math.abs(this.music.id);
    if (normalized.length > 0 && genres.indexOf(normalized) >= 0) {
      const idx = (id % 6) + 1;
      return `music/covers/${normalized}${idx}.jpg`;
    }
    const idx = (id % 20) + 1;
    return `music/covers/other${idx}.jpg`;
  }

  build() {
    Stack() {
      if (this.url.length > 0) {
        AppImage({ url: this.url, showLoadingSpin: false })
      } else {
        Image($rawfile(this.fallbackAsset()))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
    }
    .layoutWeight(1)
    .height('100%')
  }
}
