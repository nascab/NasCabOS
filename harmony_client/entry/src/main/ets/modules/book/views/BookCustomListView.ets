import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { ToastUtil } from '../../../common/ToastUtil';
import { DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { BookCustomListController } from '../controllers/BookControllers';
import { BookCustomListItem } from '../models/BookModels';
import { BookAlbumCard, BookPreviewCoverSpec } from '../components/BookAlbumCard';
import { BookSubListPageParam } from '../router/BookRoutes';

/**
 * 自建书单视图（对齐 Flutter AppBookCustomListView，移动端嵌入书主页 tab1）：
 * 顶栏（主页/搜索/排序/新建）+ 单列大卡片网格（预览横条 + 底部标题栏），
 * 卡片 more：重命名 / 删除；点击进入书单子列表。
 */
@ComponentV2
export struct BookCustomListView {
  @Param statusBarHeight: number = 0;
  @Param ctrl: BookCustomListController = new BookCustomListController();
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

  private openDetail(item: BookCustomListItem): void {
    const p = new BookSubListPageParam();
    p.listId = item.id;
    p.title = item.name;
    NavUtil.push(AppRouter.BOOK_SUB_LIST, p);
  }

  private showItemMore(item: BookCustomListItem): void {
    const options: PickOption[] = [
      new PickOption('rename', L10n.t('rename', '重命名')),
      new PickOption('delete', L10n.t('delete', '删除'))
    ];
    showOptionPickSheet('', options, '', (key: string): void => {
      if (key === 'rename') {
        this.showRenameDialog(item);
      } else if (key === 'delete') {
        void this.confirmDelete(item);
      }
    });
  }

  private showCreateDialog(): void {
    DialogUtil.showInputDialog(L10n.t('create', '创建'), '', '',
      L10n.t('confirm', '确认'), L10n.t('cancel', '取消'))
      .then((r: DialogResult | undefined): void => {
        if (typeof r === 'string') {
          const name = r.trim();
          if (name.length === 0) {
            ToastUtil.show(L10n.operationFailed);
            return;
          }
          void this.ctrl.createList(name);
        }
      });
  }

  private showRenameDialog(item: BookCustomListItem): void {
    DialogUtil.showInputDialog(L10n.t('rename', '重命名'), '', item.name,
      L10n.t('confirm', '确认'), L10n.t('cancel', '取消'))
      .then((r: DialogResult | undefined): void => {
        if (typeof r === 'string') {
          const name = r.trim();
          if (name.length === 0) {
            ToastUtil.show(L10n.operationFailed);
            return;
          }
          void this.ctrl.updateList(item.id, name);
        }
      });
  }

  private async confirmDelete(item: BookCustomListItem): Promise<void> {
    const ok = await DialogUtil.showConfirmDialog(L10n.t('delete', '删除'),
      `${L10n.t('delete', '删除')}: ${item.name} ?`);
    if (ok !== true) {
      return;
    }
    const deleted = await this.ctrl.deleteList(item.id);
    if (!deleted) {
      ToastUtil.show(L10n.operationFailed);
    }
  }

  private coversOf(item: BookCustomListItem): BookPreviewCoverSpec[] {
    const out: BookPreviewCoverSpec[] = [];
    for (const b of item.previews) {
      out.push(BookPreviewCoverSpec.fromBookItem(b));
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
        active: !(this.ctrl.sortBy === 'create_time' && this.ctrl.sortOrder === 'desc'),
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
          this.showCreateDialog();
        }
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
  }

  private showSortSheet(): void {
    const entries: PickOption[] = [
      new PickOption('create_time_desc', L10n.t('create_time_desc', '添加时间 ↓')),
      new PickOption('create_time_asc', L10n.t('create_time_asc', '添加时间 ↑')),
      new PickOption('name_asc', L10n.t('name_asc', '名称 ↑')),
      new PickOption('name_desc', L10n.t('name_desc', '名称 ↓'))
    ];
    const current = `${this.ctrl.sortBy}_${this.ctrl.sortOrder}`;
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
                ForEach(this.ctrl.items, (item: BookCustomListItem) => {
                  GridItem() {
                    BookAlbumCard({
                      covers: this.coversOf(item),
                      title: item.name,
                      onOpen: (): void => {
                        this.openDetail(item);
                      },
                      onMore: (): void => {
                        this.showItemMore(item);
                      }
                    })
                      .aspectRatio(this.gridColumnCount() === 1 ? 1.55 : 0.65)
                  }
                }, (item: BookCustomListItem): string => `${item.id}_${item.name}`)
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
