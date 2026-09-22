import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { EmptyState } from '../../../common/components/EmptyState';
import { BookListItem } from '../models/BookModels';
import { bookCoverScale } from '../controllers/BookControllers';
import { BookItemCard } from './BookItemCard';

/**
 * 图书网格（对齐 Flutter BookListGrid 移动端布局）：
 * 用按“行”分组的 List 实现懒加载（仅构建可视行 + cachedCount 预渲染），
 * 底部 footer：加载中转圈 / 没有更多 / 失败重试按钮；触底自动 loadMore。
 * 切勿改回 Scroll > Column > Grid：同向外层 Scroll 会令 Grid 主轴高度无界，
 * 被迫一次性挂载全部卡片（数百本书同时建组件 + 请求封面）。
 */
@ComponentV2
export struct BookListGrid {
  @Param items: BookListItem[] = [];
  @Param loading: boolean = false;
  @Param loadingMore: boolean = false;
  @Param hasMore: boolean = false;
  @Param autoLoadFailed: boolean = false;
  @Param selectionMode: boolean = false;
  @Param selectedIds: Set<number> = new Set<number>();
  @Param isInCustomList: boolean = false;
  @Param onLoadMore: () => void = (): void => {
  };
  @Param onToggleSelected: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onToggleFavorite: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onMore: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  @Param onOpen: (item: BookListItem) => void = (_i: BookListItem): void => {
  };
  /** 内容宽度（vp，去左右 padding），onAreaChange 测量 */
  @Local contentWidth: number = 0;
  private lastLoadMoreAt: number = 0;

  private spacing(): number {
    return this.contentWidth < 520 ? 10 : 12;
  }

  private columnCount(): number {
    if (this.contentWidth <= 0) {
      return 3;
    }
    const narrow = this.contentWidth < 520;
    const baseWidth = (narrow ? 72 : 84) * 1.7;
    const desired = baseWidth * bookCoverScale.value;
    const n = Math.floor(this.contentWidth / desired);
    return Math.min(Math.max(n, 2), 12);
  }

  /** 按当前列数把卡片切成行（供懒加载 List 使用） */
  private rowChunks(): BookListItem[][] {
    const n = this.columnCount();
    const rows: BookListItem[][] = [];
    for (let i = 0; i < this.items.length; i += n) {
      rows.push(this.items.slice(i, i + n));
    }
    return rows;
  }

  build() {
    if (this.loading && this.items.length === 0) {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(AppTheme.current().primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.items.length === 0) {
      Column() {
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: this.spacing() }) {
        ForEach(this.rowChunks(), (row: BookListItem[]) => {
          ListItem() {
            Row({ space: this.spacing() }) {
              ForEach(row, (item: BookListItem) => {
                Column() {
                  BookItemCard({
                    item: item,
                    selectionMode: this.selectionMode,
                    selected: this.selectedIds.has(item.id),
                    isInCustomList: this.isInCustomList,
                    onToggleSelected: (i: BookListItem): void => {
                      this.onToggleSelected(i);
                    },
                    onToggleFavorite: (i: BookListItem): void => {
                      this.onToggleFavorite(i);
                    },
                    onMore: (i: BookListItem): void => {
                      this.onMore(i);
                    },
                    onOpen: (i: BookListItem): void => {
                      this.onOpen(i);
                    }
                  })
                }
                .layoutWeight(1)
              }, (item: BookListItem) => `${item.id}_${item.isFavorite ? 1 : 0}_${item.coverState}`)
            }
            .width('100%')
          }
        }, (row: BookListItem[], rowIdx: number): string =>
          `${rowIdx}_${row.map((e: BookListItem): number => e.id).join('-')}`)

        // footer：加载中转圈 / 没有更多 / 失败重试
        ListItem() {
          if (this.loadingMore) {
            Row() {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(AppTheme.current().primary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 12, bottom: 12 })
          } else if (!this.hasMore) {
            Text(L10n.t('book_list_no_more', '没有更多了'))
              .fontSize(12)
              .fontColor(AppTheme.current().hint)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 10 })
          } else if (this.autoLoadFailed) {
            Text(L10n.t('book_list_load_more', '加载更多'))
              .fontSize(13)
              .fontColor(AppTheme.current().primary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 10 })
              .onClick(() => {
                this.onLoadMore();
              })
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 16 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // 视口外预渲染 2 行，滑动时封面提前加载（Flutter cacheExtent 等价物）
      .cachedCount(2)
      .onAreaChange((_o: Area, n: Area) => {
        // 去掉左右 padding 的内容宽（onAreaChange 返回含 padding 的组件宽度）
        this.contentWidth = n.width as number - 32;
      })
      .onReachEnd((): void => {
        const now = Date.now();
        if (now - this.lastLoadMoreAt < 800) {
          return;
        }
        this.lastLoadMoreAt = now;
        if (this.hasMore && !this.loadingMore && !this.loading) {
          this.onLoadMore();
        }
      })
    }
  }
}
