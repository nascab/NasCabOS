import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { SheetUtil, SheetParamsBase, SheetHandle } from '../../../common/SheetUtil';
import { DialogUtil } from '../../../common/DialogUtil';
import { ToastUtil } from '../../../common/ToastUtil';
import { AppImage } from '../../../common/components/AppImage';
import { BookCustomListItem } from '../models/BookModels';
import { BookCustomListApiService, BookListApiService } from '../services/BookApiServices';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'BookListSelect';

/** 书单选择弹层参数（对齐 Flutter 选择书单对话框） */
class BookListSelectParams extends SheetParamsBase {
  onSelect: (listId: number) => void = (_listId: number): void => {
  };
  /** 空列表时显示创建入口 */
  allowCreate: boolean = true;
}

/**
 * 书单选择底部弹层：列出书单，点击返回所选书单 id；
 * 空列表可快捷创建（对齐 Flutter 多选加入书单的选择对话框）。
 */
@ComponentV2
struct BookListSelectSheet {
  @Param params: BookListSelectParams = new BookListSelectParams();
  @Local items: BookCustomListItem[] = [];
  @Local loading: boolean = false;
  private page: number = 1;
  private pageSize: number = 30;
  private hasMore: boolean = true;

  aboutToAppear(): void {
    void this.reload();
  }

  private async reload(): Promise<void> {
    this.page = 1;
    this.loading = true;
    try {
      const res = await BookCustomListApiService.listLists(1, this.pageSize, undefined, 'create_time', 'desc');
      if (res.success && res.data !== undefined) {
        this.items = res.data.items;
        this.hasMore = res.data.pagination.hasNextPage;
      }
    } finally {
      this.loading = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loading || !this.hasMore) {
      return;
    }
    this.loading = true;
    try {
      const nextPage = this.page + 1;
      const res = await BookCustomListApiService.listLists(nextPage, this.pageSize, undefined, 'create_time', 'desc');
      if (res.success && res.data !== undefined) {
        this.page = nextPage;
        this.items = this.items.concat(res.data.items);
        this.hasMore = res.data.pagination.hasNextPage;
      }
    } finally {
      this.loading = false;
    }
  }

  private async createList(): Promise<void> {
    const picked = await DialogUtil.showInputDialog(L10n.t('create', '创建'), L10n.t('name', '名称'), '',
      L10n.t('ok'), L10n.cancel);
    const name = typeof picked === 'string' ? picked.trim() : '';
    if (name.length === 0) {
      return;
    }
    DialogUtil.showLoading(L10n.t('loading'));
    const res = await BookCustomListApiService.createList(name);
    DialogUtil.dismissLoading(true);
    if (res.success && res.data !== undefined && res.data.id > 0) {
      const listId = res.data.id;
      this.params.close();
      this.params.onSelect(listId);
      return;
    }
    ToastUtil.show(L10n.operationFailed);
  }

  /** 预览封面：取第一个 preview 的 fileHash tiny；无则占位 */
  @Builder
  PreviewThumb(item: BookCustomListItem) {
    Stack() {
      if (item.previews.length > 0 && item.previews[0].fileHash.trim().length > 0) {
        AppImage({ url: BookListApiService.buildTinyUrl(item.previews[0].fileHash, 500), showLoadingSpin: false })
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.book'))
            .fontSize(18)
            .fontColor([AppTheme.current().subText])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
      }
    }
    .width(44)
    .height(44)
    .borderRadius(8)
    .clip(true)
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('book_list_select', '选择书单'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .margin({ top: 4, bottom: 8 })

      if (this.items.length === 0 && !this.loading) {
        Column({ space: 12 }) {
          Text(L10n.t('no_data'))
            .fontSize(14)
            .fontColor(AppTheme.current().subText)
          if (this.params.allowCreate) {
            Text(L10n.t('create'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(AppTheme.current().primary)
              .onClick(() => {
                this.createList();
              })
          }
        }
        .width('100%')
        .padding({ top: 24, bottom: 48 })
      } else {
        List() {
          ForEach(this.items, (it: BookCustomListItem) => {
            ListItem() {
              Row({ space: 12 }) {
                this.PreviewThumb(it)
                Column() {
                  Text(it.name)
                    .fontSize(15)
                    .fontColor(AppTheme.current().onSurface)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${it.previews.length}`)
                    .fontSize(12)
                    .fontColor(AppTheme.current().subText)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(14)
                  .fontColor([AppTheme.current().hint])
              }
              .width('100%')
              .height(60)
              .padding({ left: 16, right: 16 })
              .onClick(() => {
                const listId = it.id;
                if (listId <= 0) {
                  return;
                }
                this.params.close();
                this.params.onSelect(listId);
              })
            }
          }, (it: BookCustomListItem) => `${it.id}`)
          ListItem() {
            if (this.hasMore) {
              Text(this.loading ? L10n.t('loading') : L10n.t('book_list_load_more', '加载更多'))
                .fontSize(13)
                .fontColor(AppTheme.current().subText)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 8, bottom: 12 })
                .onClick(() => {
                  this.loadMore();
                })
            }
          }
        }
        .width('100%')
        .height(320)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .padding({ bottom: 24 })
  }
}

/** 弹出书单选择，返回所选书单 id（取消返回 0） */
export async function pickBookCustomListId(): Promise<number> {
  return new Promise<number>((resolve: (v: number) => void) => {
    const p = new BookListSelectParams();
    p.onSelect = (listId: number): void => {
      resolve(listId);
    };
    p.onDismissed = (): void => {
      resolve(0);
    };
    try {
      SheetUtil.present<BookListSelectParams>(p, bookListSelectBuilder);
    } catch (e) {
      hilog.error(0x0000, TAG, 'pickBookList present failed: %{public}s', JSON.stringify(e));
      resolve(0);
    }
  });
}

const bookListSelectBuilder: WrappedBuilder<[BookListSelectParams]> = wrapBuilder(BookListSelectBuilderFn);

@Builder
function BookListSelectBuilderFn(params: BookListSelectParams) {
  BookListSelectSheet({ params: params });
}
