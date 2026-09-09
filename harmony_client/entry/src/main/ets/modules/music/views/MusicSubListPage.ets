import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { PageScaffold } from '../../../common/PageScaffold';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import {
  MusicSubListController, MusicSubListPayload, MusicSubListSortBy, MusicSubListSortOrder,
  subListSortByParam, parseSubListSortBy
} from '../controllers/MusicSubListController';
import { MusicSubListBody } from './MusicSubListBody';
import { MusicFloatingBar } from '../components/MusicFloatingBar';

/**
 * 音乐子列表页（对齐 Flutter MusicSubListMobilePage）：
 * 标题栏 + 头部行（播放全部 + 搜索 + 排序）+ 数据行列表 + 悬浮播放条。
 * embedded=true 时不带标题栏/悬浮条（历史 tab 内嵌音乐主页使用）。
 */
@ComponentV2
export struct MusicSubListPage {
  @Param payload: MusicSubListPayload = new MusicSubListPayload();
  /** 内嵌模式：无标题栏与悬浮条（历史 tab） */
  @Param embedded: boolean = false;
  /** 多选模式变化回调（主框架用于隐藏悬浮播放条） */
  @Param onMultiSelectChanged: (v: boolean) => void = (_v: boolean): void => {
  };

  ctrl: MusicSubListController = new MusicSubListController(this.payload);
  /** 悬浮条显示（多选模式隐藏，对齐 hidePlayerBar） */
  @Local private showFloatingBar: boolean = false;

  aboutToAppear(): void {
    this.ctrl = new MusicSubListController(this.payload);
    this.ctrl.onMultiSelectChanged = (v: boolean): void => {
      this.showFloatingBar = !v;
      this.onMultiSelectChanged(v);
    };
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private openFullscreen(): void {
    NavUtil.push(AppRouter.MUSIC_PLAYER, new Object());
  }

  private isSortActive(): boolean {
    return !(this.ctrl.sortBy === MusicSubListSortBy.filename && this.ctrl.sortOrder === MusicSubListSortOrder.asc);
  }

  /** 排序弹层（对齐 _SortButton _sortEntries） */
  private showSortSheet(): void {
    const options: PickOption[] = [];
    if (this.ctrl.isFavorite) {
      options.push(new PickOption('favorite_time_desc', L10n.t('music_list_sort_favorite_time_desc', '收藏时间 ↓')));
      options.push(new PickOption('favorite_time_asc', L10n.t('music_list_sort_favorite_time_asc', '收藏时间 ↑')));
    }
    options.push(new PickOption('filename_asc', L10n.t('music_list_sort_filename_asc', '文件名 ↑')));
    options.push(new PickOption('filename_desc', L10n.t('music_list_sort_filename_desc', '文件名 ↓')));
    options.push(new PickOption('title_asc', L10n.t('music_list_sort_title_asc', '标题 ↑')));
    options.push(new PickOption('title_desc', L10n.t('music_list_sort_title_desc', '标题 ↓')));
    options.push(new PickOption('duration_desc', L10n.t('music_list_sort_duration_desc', '时长 ↓')));
    options.push(new PickOption('duration_asc', L10n.t('music_list_sort_duration_asc', '时长 ↑')));
    options.push(new PickOption('ctime_desc', L10n.t('create_time_desc', '创建时间 ↓')));
    options.push(new PickOption('ctime_asc', L10n.t('create_time_asc', '创建时间 ↑')));

    const sel = `${subListSortByParam(this.ctrl.sortBy)}_${this.ctrl.sortOrder === MusicSubListSortOrder.asc ? 'asc' : 'desc'}`;
    showOptionPickSheet(L10n.t('sort', '排序'), options, sel, (key: string): void => {
      const idx = key.lastIndexOf('_');
      if (idx <= 0) {
        return;
      }
      const by = parseSubListSortBy(key.substring(0, idx));
      const order = key.substring(idx + 1) === 'asc' ? MusicSubListSortOrder.asc : MusicSubListSortOrder.desc;
      if (by !== undefined) {
        this.ctrl.setSort(by, order);
      }
    });
  }

  build() {
    if (this.embedded) {
      Column() {
        this.HeaderRow()
        MusicSubListBody({ ctrl: this.ctrl })
      }
      .width('100%')
      .height('100%')
    } else {
      PageScaffold({
        title: this.payload.name,
        showBack: true,
        onBack: (): void => {
          NavUtil.pop();
        },
        content: (): void => {
          this.PageContent()
        },
        overlayContent: (): void => {
          this.FloatingOverlay()
        }
      })
    }
  }

  @Builder
  PageContent() {
    Stack() {
      Column() {
        this.HeaderRow()
        MusicSubListBody({
          ctrl: this.ctrl,
          listBottomInset: this.showFloatingBar ? 92 : 0
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  /** 悬浮播放条（多选模式下隐藏，对齐 hidePlayerBar） */
  @Builder
  FloatingOverlay() {
    if (this.showFloatingBar) {
      Column() {
        MusicFloatingBar({
          onOpenFullscreen: (): void => {
            this.openFullscreen();
          },
          onOpenPlaylist: (): void => {
            NavUtil.push(AppRouter.MUSIC_PLAYER, new Object());
          }
        })
      }
      .width('100%')
      .position({ x: 0, y: '100%' })
      .markAnchor({ y: '100%' })
      .padding({ left: 12, right: 12, bottom: 24 })
    }
  }

  /** 头部行（对齐 MusicSubListMobilePageHeader）：播放全部 + 搜索 + 排序 */
  @Builder
  HeaderRow() {
    Row({ space: 8 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(20)
          .fontColor(['#FFFFFF'])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(AppTheme.current().primary)
      .justifyContent(FlexAlign.Center)
      .opacity(this.ctrl.items.length === 0 ? 0.5 : 1)
      .onClick(() => {
        if (this.ctrl.items.length > 0) {
          void this.ctrl.playAll();
        }
      })

      SearchInputBar({
        hintText: L10n.t('music_list_search_hint'),
        text: this.ctrl.searchText,
        onChanged: (v: string): void => {
          this.ctrl.onSearchChanged(v);
        },
        onClear: (): void => {
          this.ctrl.clearSearch();
        }
      })
      .layoutWeight(1)

      if (!this.ctrl.isHistory) {
        BorderedIconButton({
          icon: $r('sys.symbol.slider_horizontal_2'),
          active: this.isSortActive(),
          onTap: (): void => {
            this.showSortSheet();
          }
        })
      } else {
        BorderedIconButton({
          icon: $r('sys.symbol.slider_horizontal_2'),
          isEnabled: false
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .border({ width: { bottom: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}
