import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { showOptionPickSheet, PickOption } from '../../../common/components/OptionPickSheet';
import { BookCollectionController } from '../controllers/BookControllers';
import { BookCollectionItem } from '../models/BookModels';
import { BookAlbumCard, BookPreviewCoverSpec } from '../components/BookAlbumCard';
import {
  showBookCollectionCreateDialog, showBookCollectionEditDialog,
  confirmDeleteBookCollection, showBookCollectionPathHelp
} from '../components/BookCollectionDialogs';
import { BookSubListPageParam } from '../router/BookRoutes';

/**
 * 合集视图（对齐 Flutter AppBookCollectionView，移动端嵌入书主页 tab2）：
 * 顶栏（主页/搜索/排序/新建）+ 单列大卡片网格（预览横条 + 底部标题栏 + 左上路径帮助），
 * 卡片 more：打开 / 编辑 / 删除。
 */
@ComponentV2
export struct BookCollectionView {
  @Param statusBarHeight: number = 0;
  @Param ctrl: BookCollectionController = new BookCollectionController();
  @Param popPage: () => void = (): void => {
  };
  /** 视口宽度（网格列数） */
  @Local viewWidth: number = 0;

  aboutToAppear(): void {
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private gridColumnCount(): number {
    const w = this.viewWidth;
    if (w <= 0 || w < 750) {
      return 1;
    }
    return Math.min(6, Math.max(2, Math.floor(w / 250)));
  }

  private columnsTemplate(): string {
    const n = this.gridColumnCount();
    const parts: string[] = [];
    for (let i = 0; i < n; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  private openDetail(item: BookCollectionItem): void {
    const p = new BookSubListPageParam();
    p.collectionId = item.id;
    p.title = item.name;
    NavUtil.push(AppRouter.BOOK_SUB_LIST, p);
  }

  private showItemMore(item: BookCollectionItem): void {
    const options: PickOption[] = [
      new PickOption('open', L10n.t('open', '打开')),
      new PickOption('edit', L10n.t('edit', '编辑')),
      new PickOption('delete', L10n.t('delete', '删除'))
    ];
    showOptionPickSheet(item.name, options, '', (key: string): void => {
      if (key === 'open') {
        this.openDetail(item);
      } else if (key === 'edit') {
        showBookCollectionEditDialog(this.ctrl, item);
      } else if (key === 'delete') {
        void confirmDeleteBookCollection(this.ctrl, item);
      }
    });
  }

  private showSortSheet(): void {
    const entries: PickOption[] = [
      new PickOption('create_time_desc', L10n.t('create_time_desc', '添加时间 ↓')),
      new PickOption('create_time_asc', L10n.t('create_time_asc', '添加时间 ↑')),
      new PickOption('name_asc', L10n.t('name_asc', '名称 ↑')),
      new PickOption('name_desc', L10n.t('name_desc', '名称 ↓'))
    ];
    const current = `${this.ctrl.sortField}_${this.ctrl.sortOrder}`;
    showOptionPickSheet(L10n.t('sort', '排序'), entries, current, (key: string): void => {
      if (key === 'create_time_desc') {
        this.ctrl.setSort('create_time', 'desc');
      } else if (key === 'create_time_asc') {
        this.ctrl.setSort('create_time', 'asc');
      } else if (key === 'name_asc') {
        this.ctrl.setSort('name', 'asc');
      } else if (key === 'name_desc') {
        this.ctrl.setSort('name', 'desc');
      }
    });
  }

  private coversOf(item: BookCollectionItem): BookPreviewCoverSpec[] {
    const out: BookPreviewCoverSpec[] = [];
    for (const b of item.previews) {
      out.push(BookPreviewCoverSpec.fromCollectionPreview(b));
    }
    return out;
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.house'),
        btnSize: 36,
        iconSize: 18,
        corner: 18,
        onTap: (): void => {
          this.popPage();
        }
      })
      Column() {
        SearchInputBar({
          hintText: L10n.t('book_list_search_hint', '搜索名称'),
          text: this.ctrl.keyword,
          onChanged: (v: string): void => {
            this.ctrl.onSearchChanged(v);
          },
          onClear: (): void => {
            this.ctrl.clearSearch();
          }
        })
      }
      .layoutWeight(1)

      BorderedIconButton({
        icon: $r('sys.symbol.sort'),
        btnSize: 36,
        iconSize: 18,
        corner: 18,
        active: !(this.ctrl.sortField === 'create_time' && this.ctrl.sortOrder === 'desc'),
        onTap: (): void => {
          this.showSortSheet();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.plus'),
        btnSize: 36,
        iconSize: 18,
        corner: 18,
        onTap: (): void => {
          showBookCollectionCreateDialog(this.ctrl);
        }
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
  }

  build() {
    Column() {
      Column() {
        this.TopBar()
      }
      .width('100%')
      .padding({ top: this.statusBarHeight })
      .backgroundColor(AppTheme.current().surfaceBg)

      Column() {
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
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
          .width('100%')
          .height('100%')
        } else {
          Scroll() {
            Column() {
              Grid() {
                ForEach(this.ctrl.items, (item: BookCollectionItem) => {
                  GridItem() {
                    BookAlbumCard({
                      covers: this.coversOf(item),
                      title: item.name,
                      showInfo: true,
                      onOpen: (): void => {
                        this.openDetail(item);
                      },
                      onMore: (): void => {
                        this.showItemMore(item);
                      },
                      onInfo: (): void => {
                        showBookCollectionPathHelp(item.pathList);
                      }
                    })
                      .aspectRatio(this.gridColumnCount() === 1 ? 1.45 : 0.65)
                  }
                }, (item: BookCollectionItem): string => `${item.id}_${item.name}`)
              }
              .columnsTemplate(this.columnsTemplate())
              .columnsGap(12)
              .rowsGap(12)
              .width('100%')

              Column()
                .width('100%')
                .height(92)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .onAreaChange((_o: Area, n: Area) => {
              this.viewWidth = n.width as number - 32;
            })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .onReachEnd(() => {
            void this.ctrl.loadMore();
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}
