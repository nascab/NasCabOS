import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { EmptyState } from '../../../common/components/EmptyState';
import { BookListItem } from '../models/BookModels';
import { bookCoverScale } from '../controllers/BookControllers';
import { BookItemCard } from './BookItemCard';

/**
 * 图书网格（对齐 Flutter BookListGrid 移动端布局）：
 * Scroll > Column > Grid + GridItem 项目已验证模式；列数按去 padding 内容宽计算；
 * 底部 footer：加载中转圈 / 没有更多 / 失败重试按钮；触底自动 loadMore。
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
  /** 底部额外留白（主界面悬浮 chips 条高度） */
  @Param bottomPadding: number = 92;
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

  build() {
    Scroll() {
      Column() {
        if (this.loading && this.items.length === 0) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(AppTheme.current().primary)
          }
          .width('100%')
          .margin({ top: 80 })
        } else if (this.items.length === 0) {
          Column() {
            EmptyState({ message: L10n.t('no_data', '暂无数据') })
          }
          .width('100%')
          .margin({ top: 80 })
        } else {
          Grid() {
            ForEach(this.items, (item: BookListItem) => {
              GridItem() {
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
            }, (item: BookListItem) => `${item.id}_${item.isFavorite ? 1 : 0}_${item.coverState}`)
          }
          .columnsTemplate(this.repeatTemplate())
          .columnsGap(this.spacing())
          .rowsGap(this.spacing())
          .width('100%')

          // footer
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

        // 底部留白（悬浮 chips / 多选栏）
        Column()
          .width('100%')
          .height(this.bottomPadding)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 0, bottom: 16 })
      .onAreaChange((_o: Area, n: Area) => {
        // 去掉左右 padding 的内容宽（onAreaChange 返回含 padding 的组件宽度）
        this.contentWidth = n.width as number - 32;
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .onDidScroll((): void => {
      // 触底自动加载（对齐 Flutter 距底 360 触发，节流 800ms）
      const now = Date.now();
      if (now - this.lastLoadMoreAt < 800) {
        return;
      }
      if (!this.hasMore || this.loadingMore || this.loading || this.autoLoadFailed) {
        return;
      }
      // Scroll 组件无暴露的可达底部距离，用接近底部近似：footer 节点渲染后由 footer 点击兜底，
      // 这里仅在内容不足一屏时自动补一页（与 Flutter autoLoad 行为对齐）
      if (this.items.length > 0 && this.items.length < 24) {
        this.lastLoadMoreAt = now;
        this.onLoadMore();
      }
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

  private repeatTemplate(): string {
    const n = this.columnCount();
    const arr: string[] = [];
    for (let i = 0; i < n; i++) {
      arr.push('1fr');
    }
    return arr.join(' ');
  }
}
