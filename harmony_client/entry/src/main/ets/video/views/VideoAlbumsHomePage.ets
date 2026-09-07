import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { NavUtil } from '../../common/NavUtil';
import { AppRouter } from '../../router/AppRouter';
import { DialogUtil } from '../../common/DialogUtil';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import {
  VideoAlbumItem, VideoAlbumOverviewResult, VideoAlbumPreviewItem,
  VideoCollectionItem, VideoSmartAlbumItem
} from '../models/VideoModels';
import {
  VideoAlbumApiService, VideoCollectionApiService, VideoSmartAlbumApiService
} from '../service/VideoApiServices';
import { VideoAlbumListPageParam, VideoAlbumVideosPageParam,
  VideoCollectionListPageParam, VideoSmartAlbumListPageParam } from '../router/VideoRoutes';
import { VideoSmartAlbumTooltipUtil } from '../utils/VideoItemUtils';
import { VideoAlbumCard } from '../components/VideoAlbumCard';

/** 相册条目操作弹层参数（打开/编辑/删除，三种相册共用） */
class AlbumActionSheetParams extends SheetParamsBase {
  onOpen: () => void = (): void => {
  };
  onEdit: () => void = (): void => {
  };
  onDelete: () => void = (): void => {
  };
}

@Builder
function AlbumActionSheetContent(p: AlbumActionSheetParams) {
  Column() {
    SheetHandle()
    SheetListItem({
      icon: $r('sys.symbol.eye'),
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
    Blank().height(24)
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
}

/**
 * 影音相册主页（对齐 Flutter AppVideoAlbumsHomePage）：
 * 自建相册/智能相册/照片合集三个横向卡片区（预览条卡片 + 长按更多操作），
 * 标题行可进入对应列表页；支持下拉刷新与删除联动。
 */
@ComponentV2
export struct VideoAlbumsHomePage {
  @Local loading: boolean = false;
  @Local albums: VideoAlbumItem[] = [];
  @Local smartAlbums: VideoSmartAlbumItem[] = [];
  @Local collections: VideoCollectionItem[] = [];
  @Local listWidth: number = 0;
  @Local tick: number = 0;

  aboutToAppear(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.tick++;
    try {
      const res = await new VideoAlbumApiService().getAlbumOverview(10);
      const data: VideoAlbumOverviewResult | undefined = res.data;
      if (!res.success || data === undefined) {
        return;
      }
      this.albums = data.albums.slice(0, 10);
      this.smartAlbums = data.smartAlbums.slice(0, 10);
      this.collections = data.collections.slice(0, 10);
    } finally {
      this.loading = false;
      this.tick++;
    }
  }

  /** 卡片尺寸（对齐 Flutter horizontalList 宽度估算公式） */
  private cardSize(): [number, number] {
    const width = this.listWidth > 0 ? this.listWidth : 360;
    const padding = 20;
    const spacing = 15;
    const estimated = (width - padding * 2 - spacing) / 2.2;
    const baseWidth = Math.min(Math.max(estimated, 160), 260);
    const baseCardWidth = Math.min(Math.max(baseWidth * 1.5, 240), 420);
    const itemWidth = Math.min(Math.max(baseWidth * 1.6, 240), 460);
    const itemHeight = Math.min(Math.max((baseCardWidth / 1.6) * 1.1, 200), 360);
    return [itemWidth, itemHeight];
  }

  build() {
    Stack() {
      Refresh({ refreshing: false }) {
        Scroll() {
          Column() {
            this.SectionTitle(L10n.t('video_custom_album_title', '自建相册'), (): void => {
              NavUtil.push(AppRouter.VIDEO_ALBUM_LIST, new VideoAlbumListPageParam());
            })
            if (this.albums.length > 0) {
              this.CardRow(this.albums.length, (idx: number): void => {
                this.showAlbumActions(this.albums[idx]);
              }, (idx: number): VideoAlbumCardOptions => {
                const album = this.albums[idx];
                const opt = new VideoAlbumCardOptions();
                opt.title = album.name;
                opt.titleIcon = $r('sys.symbol.video');
                opt.previews = album.previews;
                opt.onTap = (): void => {
                  this.openAlbumVideos(album.id, 0, 0, album.name);
                };
                return opt;
              })
            } else if (this.loading) {
              this.LoadingRow()
            } else {
              this.NoDataHint()
            }

            this.SectionTitle(L10n.t('video_smart_album_title', '智能相册'), (): void => {
              NavUtil.push(AppRouter.VIDEO_SMART_ALBUM_LIST, new VideoSmartAlbumListPageParam());
            })
            if (this.smartAlbums.length > 0) {
              this.CardRow(this.smartAlbums.length, (idx: number): void => {
                this.showSmartAlbumActions(this.smartAlbums[idx]);
              }, (idx: number): VideoAlbumCardOptions => {
                const album = this.smartAlbums[idx];
                const opt = new VideoAlbumCardOptions();
                opt.title = album.name;
                opt.titleIcon = $r('sys.symbol.funnel');
                opt.previews = album.previews;
                opt.showTopLeftIcon = true;
                opt.onTopLeftTap = (): void => {
                  const tip = VideoSmartAlbumTooltipUtil.buildTooltip(album.filterContent);
                  DialogUtil.showInfoDialog(album.name,
                    tip.trim().length > 0 ? tip : L10n.t('no_data', '暂无数据'));
                };
                opt.onTap = (): void => {
                  this.openAlbumVideos(0, album.id, 0, album.name);
                };
                return opt;
              })
            } else if (this.loading) {
              this.LoadingRow()
            } else {
              this.NoDataHint()
            }

            this.SectionTitle(L10n.t('video_collection_title', '照片合集'), (): void => {
              NavUtil.push(AppRouter.VIDEO_COLLECTION_LIST, new VideoCollectionListPageParam());
            })
            if (this.collections.length > 0) {
              this.CardRow(this.collections.length, (idx: number): void => {
                this.showCollectionActions(this.collections[idx]);
              }, (idx: number): VideoAlbumCardOptions => {
                const collection = this.collections[idx];
                const opt = new VideoAlbumCardOptions();
                opt.title = collection.name;
                opt.titleIcon = $r('sys.symbol.rectangle_stack');
                opt.previews = collection.previews;
                opt.showTopLeftIcon = true;
                opt.onTopLeftTap = (): void => {
                  const paths = collection.pathList.map((e: string) => e.trim())
                    .filter((e: string) => e.length > 0);
                  const content = paths.length === 0
                    ? L10n.t('no_path', '无路径')
                    : `${L10n.t('path', '路径')}:\n${paths.join('\n')}`;
                  DialogUtil.showInfoDialog(collection.name, content);
                };
                opt.onTap = (): void => {
                  this.openAlbumVideos(0, 0, collection.id, collection.name);
                };
                return opt;
              })
            } else if (this.loading) {
              this.LoadingRow()
            } else {
              this.NoDataHint()
            }

            Column().width('100%').height(70)
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .onAppear(() => {
          // 触发宽度测量（onAreaChange 兜底）
        })
      }
      .onStateChange((state: RefreshStatus) => {
        if (state === RefreshStatus.Refresh) {
          void this.load();
        }
      })
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().cardBg)
    .onAreaChange((_o: Area, n: Area) => {
      this.listWidth = Number(n.width);
    })
    .opacity(this.tick >= 0 ? 1 : 1)
  }

  /** 打开相册视频列表页（对齐 AppVideoAlbumVideosPage.album/.smartAlbum/.collection） */
  private openAlbumVideos(albumId: number, smartAlbumId: number, collectionId: number,
    name: string): void {
    const param = new VideoAlbumVideosPageParam();
    param.albumId = albumId;
    param.smartAlbumId = smartAlbumId;
    param.collectionId = collectionId;
    param.title = name;
    NavUtil.push(AppRouter.VIDEO_ALBUM_VIDEOS, param);
  }

  private showAlbumActions(album: VideoAlbumItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumVideos(album.id, 0, 0, album.name);
    };
    p.onEdit = (): void => {
      const param = new VideoAlbumListPageParam();
      param.initialEditId = album.id;
      NavUtil.push(AppRouter.VIDEO_ALBUM_LIST, param);
    };
    p.onDelete = (): void => {
      this.confirmDelete(`${L10n.t('delete', '删除')} "${album.name}" ?`, (): Promise<void> => {
        return new VideoAlbumApiService().deleteAlbum(album.id).then((_r) => {
        });
      });
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  private showSmartAlbumActions(album: VideoSmartAlbumItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumVideos(0, album.id, 0, album.name);
    };
    p.onEdit = (): void => {
      const param = new VideoSmartAlbumListPageParam();
      param.initialEditId = album.id;
      NavUtil.push(AppRouter.VIDEO_SMART_ALBUM_LIST, param);
    };
    p.onDelete = (): void => {
      this.confirmDelete(`${L10n.t('delete', '删除')} "${album.name}" ?`, (): Promise<void> => {
        return new VideoSmartAlbumApiService().deleteSmartAlbum(album.id).then((_r) => {
        });
      });
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  private showCollectionActions(collection: VideoCollectionItem): void {
    const p = new AlbumActionSheetParams();
    p.onOpen = (): void => {
      this.openAlbumVideos(0, 0, collection.id, collection.name);
    };
    p.onEdit = (): void => {
      const param = new VideoCollectionListPageParam();
      param.initialEditId = collection.id;
      NavUtil.push(AppRouter.VIDEO_COLLECTION_LIST, param);
    };
    p.onDelete = (): void => {
      this.confirmDelete(`${L10n.t('delete', '删除')} "${collection.name}" ?`, (): Promise<void> => {
        return new VideoCollectionApiService().deleteCollection(collection.id).then((_r) => {
        });
      });
    };
    SheetUtil.present(p, wrapBuilder(AlbumActionSheetContent));
  }

  private confirmDelete(message: string, action: () => Promise<void>): void {
    DialogUtil.showConfirmDialog(L10n.t('tip', '提示'), message, (): void => {
      action().then((): void => {
        void this.load();
      });
    });
  }

  @Builder
  SectionTitle(title: string, onTap: () => void) {
    Row({ space: 15 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([AppTheme.withAlpha(AppTheme.current().onSurface, 0.65)])
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  CardRow(count: number, onMore: (idx: number) => void, buildOptions: (idx: number) => VideoAlbumCardOptions) {
    Scroll() {
      Row({ space: 15 }) {
        ForEach(Array.from({ length: count }, (_v: undefined, i: number) => i), (idx: number) => {
          Column() {
            VideoAlbumCard({
              title: buildOptions(idx).title,
              titleIcon: buildOptions(idx).titleIcon,
              showTopLeftIcon: buildOptions(idx).showTopLeftIcon,
              onTopLeftTap: buildOptions(idx).onTopLeftTap,
              previews: buildOptions(idx).previews,
              onTap: buildOptions(idx).onTap,
              onMore: (): void => {
                onMore(idx);
              }
            })
          }
          .width(this.cardSize()[0])
          .height(this.cardSize()[1])
        }, (idx: number) => `${idx}`)
      }
      .alignItems(VerticalAlign.Top)
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(this.cardSize()[1])
  }

  @Builder
  LoadingRow() {
    Column() {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(AppTheme.current().primary)
    }
    .width('100%')
    .padding({ top: 12, bottom: 16 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  NoDataHint() {
    Text(L10n.t('no_data', '暂无数据'))
      .fontSize(14)
      .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 20, bottom: 20, left: 16, right: 16 })
  }
}

/** 卡片构造选项（@Builder 内传参辅助类） */
class VideoAlbumCardOptions {
  title: string = '';
  titleIcon: Resource = $r('sys.symbol.video');
  showTopLeftIcon: boolean = false;
  onTopLeftTap: () => void = (): void => {
  };
  previews: VideoAlbumPreviewItem[] = [];
  onTap: () => void = (): void => {
  };
}
