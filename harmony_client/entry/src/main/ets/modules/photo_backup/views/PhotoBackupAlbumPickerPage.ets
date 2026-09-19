import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { AppEventBus } from '../../../common/AppEventBus';
import { LanguageService } from '../../../core/localization/LanguageService';
import { PageScaffold } from '../../../common/PageScaffold';
import { PhotoAlbumService } from '../services/PhotoAlbumService';
import { PhotoAlbumInfo } from '../models/PhotoBackupModels';
import { PhotoBackupAlbumPickerPageParam } from '../router/PhotoBackupRoutes';

/**
 * 相册选择页（对齐 Flutter showPhotoBackupAlbumPicker / _PhotoBackupAlbumPickerPage）：
 * 2 列网格相册卡片（封面 + 名称 + 数量），点击选回来源表单。
 */
@ComponentV2
export struct PhotoBackupAlbumPickerPage {
  @Param param: PhotoBackupAlbumPickerPageParam = new PhotoBackupAlbumPickerPageParam();
  @Param popPage: () => void = (): void => {
  };

  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local albums: PhotoAlbumInfo[] = [];
  /** 封面加载失败的相册 id 集合（降级为占位图标） */
  @Local brokenCovers: Set<string> = new Set<string>();
  /** 依赖 localeBump：切换语言后触发整页刷新 */
  @Local localeBump: number = 0;
  private localeListener: (data: string) => void = (_data: string): void => {
    this.localeBump++;
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  aboutToAppear(): void {
    AppEventBus.on(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
    void this.load();
  }

  aboutToDisappear(): void {
    AppEventBus.off(LanguageService.EVENT_LOCALE_CHANGED, this.localeListener);
  }

  /** 加载相册列表（对齐 Flutter _preparePaths：权限 → 枚举 → 排序） */
  private async load(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const granted = await PhotoAlbumService.requestPermission();
      if (!granted) {
        this.errorText = L10n.t('photo_library_permission_missing', '缺少相册访问权限');
        return;
      }
      this.albums = await PhotoAlbumService.listAlbums();
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : `${e}`;
    } finally {
      this.loading = false;
    }
  }

  build() {
    PageScaffold({
      title: L10n.t('photo_album_select', '选择相册'),
      showBack: true,
      onBack: (): void => {
        this.popPage();
      },
      content: (): void => {
        this.PageContent()
      }
    })
  }

  @Builder
  PageContent() {
    Column() {
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.palette().primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column() {
          Text(this.errorText)
            .fontSize(14)
            .fontColor(this.palette().error)
            .textAlign(TextAlign.Center)
            .padding(24)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.albums.length === 0) {
        Column() {
          Text(L10n.t('photo_album_empty', '暂无相册'))
            .fontSize(14)
            .fontColor(this.palette().subText)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Grid() {
          ForEach(this.albums, (album: PhotoAlbumInfo) => {
            GridItem() {
              AlbumGridTile({
                album: album,
                broken: this.brokenCovers.has(album.id),
                onPick: (): void => {
                  this.param.onPicked(album);
                  this.popPage();
                },
                onCoverBroken: (): void => {
                  const next = new Set<string>(this.brokenCovers);
                  next.add(album.id);
                  this.brokenCovers = next;
                }
              })
            }
          }, (album: PhotoAlbumInfo): string => `${album.id}_${album.name.length}_${album.count}`
            + `_${this.brokenCovers.has(album.id)}_${this.localeBump}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .padding({ left: 12, right: 12, top: 8, bottom: 24 })
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.current().pageBg)
    .opacity(this.localeBump >= 0 ? 1 : 1)
  }
}

/** 相册网格卡片（对齐 Flutter _AlbumGridTile：封面 + 名称 + 数量） */
@ComponentV2
struct AlbumGridTile {
  @Require @Param album: PhotoAlbumInfo;
  @Param broken: boolean = false;
  @Param onPick: () => void = (): void => {
  };
  @Param onCoverBroken: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      // 封面区（占满剩余空间；封面缺失/加载失败时显示占位图标）
      Stack() {
        if (!this.broken && this.album.coverUri.length > 0) {
          Image(this.album.coverUri)
            .objectFit(ImageFit.Cover)
            .width('100%')
            .height('100%')
            .onError((): void => {
              this.onCoverBroken();
            })
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.picture'))
              .fontSize(40)
              .fontColor([this.palette().hint])
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.palette().inputFill)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)

      // 信息区：名称 + 数量
      Column({ space: 2 }) {
        Text(this.album.name)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${this.album.count}`)
          .fontSize(12)
          .fontColor(this.palette().subText)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(12)
    .clip(true)
    .backgroundColor(AppTheme.withAlpha(this.palette().surfaceBg, 0.35))
    .border({ width: 1, color: this.palette().divider })
    .onClick((): void => {
      this.onPick();
    })
  }
}
