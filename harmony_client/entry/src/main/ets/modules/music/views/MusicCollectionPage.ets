import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { NavUtil } from '../../../common/NavUtil';
import { AppRouter } from '../../../router/AppRouter';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { SearchInputBar } from '../../../common/components/SearchInputBar';
import { EmptyState } from '../../../common/components/EmptyState';
import { AppImage } from '../../../common/components/AppImage';
import { PickOption, showOptionPickSheet } from '../../../common/components/OptionPickSheet';
import { MusicCollectionController } from '../controllers/MusicLibraryControllers';
import { MusicCollectionItem, MusicCollectionPreviewItem } from '../models/MusicModels';
import { MusicSubListPageParam } from '../router/MusicRoutes';
import { pickTargetFolderViaSheet } from '../../../files/views/FolderPickerSheet';

/**
 * 音乐合集列表页（对齐 Flutter MusicCollectionListView 移动端）：
 * 顶栏（搜索 + 排序 + 创建）+ 单列横向卡片（四联封面 + 底部名称/更多）+
 * 底部加载更多；创建/编辑弹窗（名称 + 多选目录，sourceType=music）。
 */
@ComponentV2
export struct MusicCollectionPage {
  ctrl: MusicCollectionController = new MusicCollectionController();
  /** 状态栏高度（vp）：嵌入音乐主页（沉浸全屏布局）时顶栏用它避让 */
  @Param statusBarHeight: number = 0;
  @Local private refreshing: boolean = false;

  aboutToAppear(): void {
    this.ctrl = new MusicCollectionController();
    this.ctrl.onInit();
  }

  aboutToDisappear(): void {
    this.ctrl.onClose();
  }

  private openCollection(item: MusicCollectionItem): void {
    const p = new MusicSubListPageParam();
    p.keyType = 'collection';
    p.name = item.name;
    p.collectionId = item.id;
    NavUtil.push(AppRouter.MUSIC_SUB_LIST, p);
  }

  private showActions(item: MusicCollectionItem): void {
    const options: PickOption[] = [
      new PickOption('open', L10n.t('open', '打开')),
      new PickOption('edit', L10n.t('edit', '编辑')),
      new PickOption('delete', L10n.t('delete', '删除'))
    ];
    showOptionPickSheet(item.name, options, '', (key: string): void => {
      if (key === 'open') {
        this.openCollection(item);
      } else if (key === 'edit') {
        this.showEditDialog(item);
      } else if (key === 'delete') {
        this.confirmDelete(item);
      }
    });
  }

  private showCreateDialog(): void {
    const p = new MusicCollectionEditDialogParams();
    p.title = L10n.t('music_create_collection');
    p.alertText = L10n.t('music_create_collection_alert');
    p.initialName = '';
    p.initialPaths = [];
    p.confirmText = L10n.t('create', '创建');
    p.onConfirm = (name: string, paths: string[]): void => {
      void this.ctrl.createCollection(name, paths);
    };
    DialogUtil.openCustom(p, wrapBuilder(MusicCollectionEditDialogContent));
  }

  private showEditDialog(item: MusicCollectionItem): void {
    const p = new MusicCollectionEditDialogParams();
    p.title = L10n.t('edit', '编辑');
    p.alertText = '';
    p.initialName = item.name;
    p.initialPaths = item.pathList.slice();
    p.confirmText = L10n.t('ok', '确定');
    p.onConfirm = (name: string, paths: string[]): void => {
      void this.ctrl.updateCollection(item.id, name, paths);
    };
    DialogUtil.openCustom(p, wrapBuilder(MusicCollectionEditDialogContent));
  }

  private confirmDelete(item: MusicCollectionItem): void {
    DialogUtil.showConfirmDialog(L10n.t('need_confirm', '需要确认'),
      `${L10n.t('confirm_delete', '确认删除')}[${item.name}]`, (): void => {
        void this.ctrl.deleteCollection(item.id);
      });
  }

  private showSortSheet(): void {
    const options: PickOption[] = [
      new PickOption('name_asc', L10n.t('name_asc', '名称升序')),
      new PickOption('name_desc', L10n.t('name_desc', '名称降序')),
      new PickOption('create_time_asc', L10n.t('create_time_asc', '创建时间升序')),
      new PickOption('create_time_desc', L10n.t('create_time_desc', '创建时间降序'))
    ];
    const selected = `${this.ctrl.sortField}_${this.ctrl.sortOrder}`;
    showOptionPickSheet(L10n.t('sort', '排序'), options, selected, (key: string): void => {
      const idx = key.lastIndexOf('_');
      if (idx <= 0) {
        return;
      }
      this.ctrl.setSort(key.substring(0, idx), key.substring(idx + 1));
    });
  }

  private isSortActive(): boolean {
    return this.ctrl.keyword.trim().length > 0 || this.ctrl.sortField !== 'create_time' || this.ctrl.sortOrder !== 'desc';
  }

  build() {
    Column() {
      // 顶栏（对齐 AppMusicCollectionTopBar）
      Row({ space: 10 }) {
        SearchInputBar({
          hintText: L10n.t('search', '搜索'),
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
      .height(60 + this.statusBarHeight)
      .padding({ left: 12, right: 12, top: this.statusBarHeight })
      .border({ width: { bottom: 1 }, color: AppTheme.current().divider })
      .backgroundColor(AppTheme.current().surfaceBg)

      // 内容（Refresh 包裹，支持下拉刷新）
      Refresh({ refreshing: this.refreshing }) {
      if (this.ctrl.isLoading && this.ctrl.items.length === 0) {
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
        List({ space: 12 }) {
          ForEach(this.ctrl.items, (item: MusicCollectionItem) => {
            ListItem() {
              MusicCollectionCard({
                item: item,
                onOpen: (): void => {
                  this.openCollection(item);
                },
                onMore: (): void => {
                  this.showActions(item);
                }
              })
            }
          }, (item: MusicCollectionItem) => `${item.id}_${item.name}`)

          ListItem() {
            this.ListFooter()
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          void this.ctrl.loadMore();
        })
      }
      }
      .onRefreshing(() => {
        this.refreshing = true;
        this.ctrl.refreshCollections().finally(() => {
          this.refreshing = false;
        });
      })
      .width('100%')
      .layoutWeight(1)
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
        Text(L10n.t('no_more', '没有更多'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
          .padding(12)
      } else {
        Text(L10n.t('load_more', '加载更多'))
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

// ===== 合集卡片（对齐 MusicCollectionCard） =====

@ComponentV2
export struct MusicCollectionCard {
  @Param item: MusicCollectionItem = new MusicCollectionItem();
  @Param onOpen: () => void = (): void => {
  };
  @Param onMore: () => void = (): void => {
  };

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: 1 }) {
        ForEach(this.item.previews.slice(0, 4), (e: MusicCollectionPreviewItem) => {
          MusicCollectionPreviewCover({ preview: e })
        }, (e: MusicCollectionPreviewItem) => `${e.id}_${e.path}`)

        if (this.item.previews.length === 0) {
          Image($rawfile('music/icons/default_cover.jpg'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
      }
      .width('100%')
      .height('100%')

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

/** 合集预览封面单元（对齐 coverForPreview：无内嵌封面一律 default_cover） */
@ComponentV2
struct MusicCollectionPreviewCover {
  @Param preview: MusicCollectionPreviewItem = new MusicCollectionPreviewItem();

  @Local private url: string = '';
  private token: number = 0;

  aboutToAppear(): void {
    this.resolve();
  }

  aboutToDisappear(): void {
    this.token++;
  }

  @Monitor('preview')
  onPreviewChange(): void {
    this.resolve();
  }

  private resolve(): void {
    if (this.preview.hasInnerCover !== 1) {
      this.url = '';
      return;
    }
    const p = (this.preview.showType === 'series' ? this.preview.firstFilePath : this.preview.fullPath).trim();
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

  build() {
    Stack() {
      if (this.url.length > 0) {
        AppImage({ url: this.url, showLoadingSpin: false })
      } else {
        Image($rawfile('music/icons/default_cover.jpg'))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
    }
    .layoutWeight(1)
    .height('100%')
  }
}

// ===== 创建/编辑弹窗（对齐 MusicCollectionDialogs） =====

class MusicCollectionEditDialogParams extends DialogParamsBase {
  title: string = '';
  alertText: string = '';
  initialName: string = '';
  initialPaths: string[] = [];
  confirmText: string = '';
  onConfirm: (name: string, paths: string[]) => void = (_n: string, _p: string[]): void => {
  };
}

@Builder
function MusicCollectionEditDialogContent(p: MusicCollectionEditDialogParams) {
  MusicCollectionEditDialogInner({ p: p })
}

@ComponentV2
struct MusicCollectionEditDialogInner {
  @Param p: MusicCollectionEditDialogParams = new MusicCollectionEditDialogParams();
  @Local name: string = '';
  @Local paths: string[] = [];
  @Local canSubmit: boolean = false;

  aboutToAppear(): void {
    this.name = this.p.initialName;
    this.paths = this.p.initialPaths.slice();
    this.recomputeCanSubmit();
  }

  private recomputeCanSubmit(): void {
    this.canSubmit = this.name.trim().length > 0 && this.paths.length > 0;
  }

  /** 选择路径（多选文件夹，sourceType=music，追加去重） */
  private choosePath(): void {
    pickTargetFolderViaSheet('', (selected: string[]): void => {
      if (selected.length === 0) {
        return;
      }
      let changed = false;
      for (const path of selected) {
        const v = path.trim();
        if (v.length > 0 && !this.paths.includes(v)) {
          this.paths.push(v);
          changed = true;
        }
      }
      if (changed) {
        this.paths = this.paths.slice();
        this.recomputeCanSubmit();
      }
    }, true, 'music');
  }

  private removePath(idx: number): void {
    if (idx < 0 || idx >= this.paths.length) {
      return;
    }
    this.paths.splice(idx, 1);
    this.paths = this.paths.slice();
    this.recomputeCanSubmit();
  }

  private submit(): void {
    if (this.name.trim().length === 0 || this.paths.length === 0) {
      return;
    }
    this.p.onConfirm(this.name.trim(), this.paths.slice());
    this.p.onResult(undefined);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text(this.p.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        if (this.p.alertText.length > 0) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(18)
            .fontColor([AppTheme.current().hint])
            .onClick(() => {
              DialogUtil.showInfoDialog(this.p.title, this.p.alertText);
            })
        }
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().hint])
          .onClick(() => {
            this.p.onResult(undefined);
          })
      }
      .width('100%')

      TextInput({ text: this.name })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderFont({ size: 14 })
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 16 })
        .width('100%')
        .onChange((v: string): void => {
          this.name = v;
          this.recomputeCanSubmit();
        })

      Button() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.folder'))
            .fontSize(16)
            .fontColor([AppTheme.current().buttonText])
          Text(L10n.t('choose_path', '选择路径'))
            .fontSize(14)
            .fontColor(AppTheme.current().buttonText)
        }
      }
      .backgroundColor(AppTheme.current().buttonBg)
      .height(40)
      .width('100%')
      .margin({ top: 12 })
      .onClick(() => {
        this.choosePath();
      })

      if (this.paths.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.paths, (path: string, idx: number) => {
              Row({ space: 8 }) {
                Text(path)
                  .fontSize(13)
                  .fontColor(AppTheme.current().onSurface)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(16)
                  .fontColor([AppTheme.current().hint])
                  .onClick(() => {
                    this.removePath(idx);
                  })
              }
              .alignItems(VerticalAlign.Center)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(8)
              .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.15) })
              .width('100%')
              .margin({ top: idx > 0 ? 6 : 0 })
            }, (path: string, idx: number): string => `${idx}_${path}`)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 220 })
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
        .margin({ top: 12 })
        .width('100%')
      }

      // 操作区
      Row({ space: 10 }) {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText.length > 0 ? this.p.confirmText : L10n.ok)
          .fontSize(14)
          .fontColor(this.canSubmit ? AppTheme.current().buttonText : AppTheme.current().hint)
          .backgroundColor(this.canSubmit ? AppTheme.current().buttonBg
            : AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
          .height(40)
          .layoutWeight(1)
          .onClick(() => {
            if (this.canSubmit) {
              this.submit();
            }
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
    .width('92%')
  }
}
