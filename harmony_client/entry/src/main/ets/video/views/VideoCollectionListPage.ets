import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil, DialogParamsBase, DialogResult } from '../../common/DialogUtil';
import { PageScaffold } from '../../common/PageScaffold';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { BorderedIconButton } from '../../common/components/BorderedIconButton';
import { EmptyState } from '../../common/components/EmptyState';
import { PickOption, showOptionPickSheet } from '../../common/components/OptionPickSheet';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { pickTargetFolderViaSheet } from '../../files/views/FolderPickerSheet';
import { VideoCollectionItem } from '../models/VideoModels';
import { VideoAlbumVideosPageParam, VideoCollectionListPageParam } from '../router/VideoRoutes';
import { VideoCollectionListController } from '../controllers/VideoAlbumListControllers';
import { VideoAlbumCard } from '../components/VideoAlbumCard';

/**
 * 照片合集列表页（对齐 Flutter AppVideoCollectionListPage 移动端版式）：
 * 顶栏（搜索/排序/创建）+ 自适应网格卡片（左上信息角标查看路径）+
 * 底部加载更多；创建/编辑弹窗含名称 + 多选路径列表（文件夹选择器）。
 */

// ===== 创建/编辑弹窗（对齐 Flutter _showCreateDialog/_showEditDialog） =====

class CollectionEditDialogParams extends DialogParamsBase {
  title: string = '';
  initialName: string = '';
  initialPaths: string[] = [];
  confirmText: string = '';
  onConfirm: (name: string, paths: string[]) => void = (_n: string, _p: string[]): void => {
  };
}

@Builder
function CollectionEditDialogContent(p: CollectionEditDialogParams) {
  CollectionEditDialogInner({ p: p })
}

@ComponentV2
struct CollectionEditDialogInner {
  @Param p: CollectionEditDialogParams = new CollectionEditDialogParams();
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

  /** 选择路径（多选文件夹，追加去重，对齐 Flutter showFolderPickerBottomSheet） */
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
    }, true);
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
      Row() {
        Text(this.p.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
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

      // 选择路径按钮
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

      // 已选路径列表（最高 220，可滚动）
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

      // 操作按钮
      Row({ space: 8 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText.length > 0 ? this.p.confirmText : L10n.t('ok', '确定'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(this.canSubmit ? AppTheme.current().buttonBg
            : AppTheme.withAlpha(AppTheme.current().onSurface, 0.2))
          .opacity(this.canSubmit ? 1 : 0.6)
          .height(36)
          .onClick(() => {
            this.submit();
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .width('100%')
    .borderRadius(16)
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

// ===== 页面本体 =====

class CollectionActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function CollectionActionSheetContent(p: CollectionActionSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.plus_square_on_square'),
      title: L10n.t('open', '打开'),
      onSelect: (): void => {
        p.close();
        p.onOpen();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.square_and_pencil'),
      title: L10n.t('edit', '编辑'),
      onSelect: (): void => {
        p.close();
        p.onEdit();
      }
    })
    SheetListItem({
      icon: $r('sys.symbol.trash'),
      title: L10n.t('delete', '删除'),
      onSelect: (): void => {
        p.close();
        p.onDelete();
      }
    })
  }
  .width('100%')
  .padding({ bottom: 24 })
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

@ComponentV2
export struct VideoCollectionListPage {
  @Param param: VideoCollectionListPageParam = new VideoCollectionListPageParam();
  @Param popPage: () => void = (): void => {
  };
  ctrl: VideoCollectionListController = new VideoCollectionListController();
  @Local gridWidth: number = 0;
  @Local columns: number = 1;
  @Local itemHeight: number = 200;
  private didAutoEdit: boolean = false;
  private didAutoOpenCreate: boolean = false;

  aboutToAppear(): void {
    this.ctrl.init();
    if (this.param.autoOpenCreate && !this.didAutoOpenCreate) {
      this.didAutoOpenCreate = true;
      this.showCreateDialog();
    }
    this.tryAutoEdit(0);
  }

  /** 自适应列数与卡片高度（对齐 Flutter crossAxisCount + childAspectRatio） */
  private updateGridMetrics(): void {
    if (this.gridWidth <= 0) {
      return;
    }
    const count = this.gridWidth <= 750 ? 1
      : Math.min(Math.max(Math.floor(this.gridWidth / 240), 2), 6);
    this.columns = count;
    const gaps = 10 * (count - 1) + 24;
    const cardWidth = (this.gridWidth - gaps) / count;
    const ratio = count === 1 ? 2.3 : 1.25;
    this.itemHeight = cardWidth / ratio;
  }

  private openAlbumVideos(collection: VideoCollectionItem): void {
    const p = new VideoAlbumVideosPageParam();
    p.collectionId = collection.id;
    p.title = collection.name;
    NavUtil.push(AppRouter.VIDEO_ALBUM_VIDEOS, p);
  }

  private openSearch(): void {
    DialogUtil.showInputDialog(L10n.t('search', '搜索'), '', this.ctrl.keyword)
      .then((r: DialogResult | undefined) => {
        if (typeof r === 'string') {
          this.ctrl.onSearchChanged(r.trim());
        }
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

  private showCreateDialog(): void {
    const p = new CollectionEditDialogParams();
    p.title = L10n.t('photo_create_collection', '创建合集');
    p.initialName = '';
    p.initialPaths = [];
    p.confirmText = L10n.t('create', '创建');
    p.onConfirm = (name: string, paths: string[]): void => {
      void this.ctrl.createCollection(name, paths);
    };
    DialogUtil.openCustom(p, wrapBuilder(CollectionEditDialogContent));
  }

  private showEditDialog(collection: VideoCollectionItem): void {
    const p = new CollectionEditDialogParams();
    p.title = L10n.t('edit', '编辑');
    p.initialName = collection.name;
    p.initialPaths = collection.pathList.slice();
    p.confirmText = L10n.t('ok', '确定');
    p.onConfirm = (name: string, paths: string[]): void => {
      void this.ctrl.updateCollection(collection.id, name, paths);
    };
    DialogUtil.openCustom(p, wrapBuilder(CollectionEditDialogContent));
  }

  private confirmDelete(collection: VideoCollectionItem): void {
    DialogUtil.showConfirmDialog(L10n.t('tip', '提示'),
      `${L10n.t('delete', '删除')} "${collection.name}" ?`, (): void => {
        void this.ctrl.deleteCollection(collection.id);
      });
  }

  private showActions(collection: VideoCollectionItem): void {
    const p = new CollectionActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumVideos(collection);
    };
    p.onEdit = (): void => {
      this.showEditDialog(collection);
    };
    p.onDelete = (): void => {
      this.confirmDelete(collection);
    };
    SheetUtil.present(p, wrapBuilder(CollectionActionSheetContent));
  }

  /** 左上信息角标：展示路径列表（对齐 Flutter onTopLeftTap） */
  private showPathTip(collection: VideoCollectionItem): void {
    const paths = collection.pathList.map((e: string): string => e.trim())
      .filter((e: string): boolean => e.length > 0);
    const content = paths.length === 0
      ? L10n.t('no_path', '无路径')
      : `${L10n.t('path', '路径')}:\n${paths.join('\n')}`;
    DialogUtil.showInfoDialog(collection.name, content);
  }

  /** 轮询等待列表加载后自动打开编辑弹窗（最多 10 次） */
  private tryAutoEdit(retries: number): void {
    if (this.didAutoEdit || this.param.initialEditId <= 0) {
      return;
    }
    for (const collection of this.ctrl.items) {
      if (collection.id === this.param.initialEditId) {
        this.didAutoEdit = true;
        this.showEditDialog(collection);
        return;
      }
    }
    if (retries < 10) {
      setTimeout((): void => {
        this.tryAutoEdit(retries + 1);
      }, 300);
    }
  }

  /** 底部加载区 */
  @Builder
  FooterView() {
    Row() {
      if (this.ctrl.isLoading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(AppTheme.current().subText)
      } else if (!this.ctrl.hasMore) {
        Text(L10n.t('no_more', '没有更多了'))
          .fontSize(13)
          .fontColor(AppTheme.current().subText)
      } else {
        Button(L10n.t('load_more', '加载更多'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .borderRadius(18)
          .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.25) })
          .onClick(() => {
            void this.ctrl.loadMore();
          })
      }
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .padding({ top: 4, bottom: 16 })
  }

  build() {
    PageScaffold({
      title: L10n.t('video_collection_title', '照片合集'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      actions: (): void => {
        this.TitleActions()
      },
      content: (): void => {
        this.ListContent()
      }
    })
  }

  @Builder
  TitleActions() {
    Row({ space: 8 }) {
      BorderedIconButton({
        icon: $r('sys.symbol.magnifyingglass'),
        onTap: (): void => {
          this.openSearch();
        }
      })
      BorderedIconButton({
        icon: $r('sys.symbol.slider_horizontal_2'),
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
  }

  @Builder
  ListContent() {
    Column() {
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
        EmptyState({ message: L10n.t('no_data', '暂无数据') })
      } else {
        Scroll() {
          Column() {
            Grid() {
              ForEach(this.ctrl.items, (collection: VideoCollectionItem) => {
                GridItem() {
                  Column() {
                    VideoAlbumCard({
                      title: collection.name,
                      titleIcon: $r('sys.symbol.rectangle_stack'),
                      showTopLeftIcon: true,
                      previews: collection.previews,
                      onTopLeftTap: (): void => {
                        this.showPathTip(collection);
                      },
                      onTap: (): void => {
                        this.openAlbumVideos(collection);
                      },
                      onMore: (): void => {
                        this.showActions(collection);
                      }
                    })
                  }
                  .width('100%')
                  .height(this.itemHeight)
                }
              }, (collection: VideoCollectionItem): string => `${collection.id}`)
            }
            .columnsTemplate(this.columns > 1 ? this.columnsTemplate() : '1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
            .height(this.calcGridHeight())
            .padding({ left: 12, right: 12, top: 12 })

            this.FooterView()
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area): void => {
      this.gridWidth = Number(n.width);
      this.updateGridMetrics();
    })
    .backgroundColor(AppTheme.current().cardBg)
  }

  /** 生成 columnsTemplate（如 '1fr 1fr 1fr'） */
  private columnsTemplate(): string {
    const parts: string[] = [];
    for (let i = 0; i < this.columns; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  /** 网格高度 = 行数 × 行高 + 行间距（对齐 SliverGrid 布局） */
  private calcGridHeight(): number {
    const rows = Math.ceil(this.ctrl.items.length / this.columns);
    return rows * this.itemHeight + Math.max(rows - 1, 0) * 10;
  }
}
