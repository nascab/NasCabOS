import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { DialogUtil } from '../../common/DialogUtil';
import { AppImage } from '../../common/components/AppImage';
import { SheetHandle, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';
import { ToastUtil } from '../../common/ToastUtil';
import { VideoAlbumItem, VideoAlbumPreviewItem } from '../models/VideoModels';
import { VideoAlbumApiService } from '../service/VideoApiServices';
import { VideoHomeItemBean } from '../models/VideoModels';
import { VideoUtils } from '../utils/VideoItemUtils';

/**
 * 相册选择弹层（对齐 Flutter VideoAlbumSelectDialog）：
 * 列出自己拥有的自建相册（2 列卡片 + 预览图），点击选中并回传；
 * 空列表时提供"创建相册"入口。
 */
export class VideoAlbumSelectSheetParams extends SheetParamsBase {
  initialSelectedId: number = 0;
  onSelected: (albumId: number) => void = (_albumId: number): void => {
  };
}

/** 打开相册选择弹层（对齐 VideoAlbumSelectDialog.show） */
export function presentAlbumSelectSheet(initialSelectedId: number,
  onSelected: (albumId: number) => void): void {
  const p = new VideoAlbumSelectSheetParams();
  p.initialSelectedId = initialSelectedId;
  p.onSelected = onSelected;
  SheetUtil.present(p, wrapBuilder(AlbumSelectSheetContent));
}

@Builder
function AlbumSelectSheetContent(p: VideoAlbumSelectSheetParams) {
  AlbumSelectSheetInner({ p: p })
}

/** 相册预览图（对齐 _previewUrls：以 firstFilePath/fullPath 构建海报缩略图） */
@ComponentV2
struct AlbumPreviewImage {
  @Param fullpath: string = '';
  @Param firstFilePath: string = '';
  @Local imageUrl: string = '';

  aboutToAppear(): void {
    const item = new VideoHomeItemBean();
    item.firstFilePath = this.firstFilePath;
    item.fullPath = this.fullpath;
    VideoUtils.getPosterUrl(item, 500).then((url: string) => {
      this.imageUrl = url;
    });
  }

  build() {
    Stack() {
      if (this.imageUrl.length > 0) {
        AppImage({ url: this.imageUrl, objectFit: ImageFit.Cover })
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.08))
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(8)
    .clip(true)
  }
}

/** 相册选择卡片（对齐 _AlbumSelectCard） */
@ComponentV2
struct AlbumSelectCard {
  @Param album: VideoAlbumItem = new VideoAlbumItem();
  @Param checked: boolean = false;
  @Param onSelect: () => void = (): void => {
  };

  build() {
    Column() {
      Row({ space: 6 }) {
        Text(this.album.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.checked) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(18)
            .fontColor([AppTheme.current().primary])
        }
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8 })

      Row({ space: 6 }) {
        ForEach(this.album.previews.slice(0, 4), (pv: VideoAlbumPreviewItem) => {
          AlbumPreviewImage({ fullpath: pv.fullpath, firstFilePath: pv.firstFilePath })
            .layoutWeight(1)
            .height('100%')
        }, (pv: VideoAlbumPreviewItem, idx: number) => `${idx}_${pv.fullpath}`)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 10, right: 10, top: 6, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(12)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.05))
    .border({
      width: this.checked ? 2 : 1,
      color: this.checked ? AppTheme.current().primary
        : AppTheme.withAlpha(AppTheme.current().onSurface, 0.08)
    })
    .onClick(() => {
      this.onSelect();
    })
  }
}

/** 相册选择弹层内部组件（维护加载/列表状态） */
@ComponentV2
struct AlbumSelectSheetInner {
  @Param p: VideoAlbumSelectSheetParams = new VideoAlbumSelectSheetParams();
  @Local loading: boolean = true;
  @Local items: VideoAlbumItem[] = [];

  aboutToAppear(): void {
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const res = await new VideoAlbumApiService().listAlbums(1, 100, '', 'create_time', 'desc', 4);
      if (res.success && res.data !== undefined) {
        this.items = res.data.items.filter((e: VideoAlbumItem) => e.isOwner);
      } else {
        this.items = [];
      }
    } finally {
      this.loading = false;
    }
  }

  /** 创建相册（对齐 _openCreateAlbum：输入名称 → 创建 → 直接选中） */
  private openCreateAlbum(): void {
    DialogUtil.showInputDialog(
      L10n.t('create', '创建'),
      L10n.t('name', '名称'))
      .then((r: string | boolean | number | undefined): void => {
        if (typeof r !== 'string' || r.trim().length === 0) {
          return;
        }
        void this.createAlbum(r.trim());
      });
  }

  private async createAlbum(name: string): Promise<void> {
    const res = await new VideoAlbumApiService().createAlbum(name, false);
    if (!res.success) {
      const msg = typeof res.message === 'string' && res.message.length > 0
        ? res.message : L10n.t('operation_failed', '操作失败');
      DialogUtil.showInfoDialog(L10n.t('tip', '提示'), msg);
      return;
    }
    const id = typeof res.data !== 'undefined' && res.data !== null
      ? Number(res.data['id'] ?? 0) : 0;
    if (id <= 0) {
      DialogUtil.showInfoDialog(L10n.t('tip', '提示'),
        L10n.t('operation_failed', '操作失败'));
      return;
    }
    ToastUtil.show(L10n.t('operation_success', '操作成功'));
    this.p.close();
    this.p.onSelected(id);
  }

  @Builder
  EmptyBody() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.rectangle_stack'))
        .fontSize(40)
        .fontColor([AppTheme.current().hint])
      Button(L10n.t('create', '创建'))
        .fontSize(14)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .height(38)
        .onClick(() => {
          this.openCreateAlbum();
        })
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
  }

  @Builder
  GridBody() {
    Scroll() {
      Column() {
        Grid() {
          ForEach(this.items, (album: VideoAlbumItem) => {
            GridItem() {
              AlbumSelectCard({
                album: album,
                checked: this.p.initialSelectedId > 0 && album.id === this.p.initialSelectedId,
                onSelect: (): void => {
                  this.p.close();
                  this.p.onSelected(album.id);
                }
              })
            }
            .height(170)
          }, (album: VideoAlbumItem) => `${album.id}_${album.name}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
        .padding(12)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .width('100%')
    .constraintSize({ maxHeight: 460 })
  }

  build() {
    Column() {
      SheetHandle()
      Text(L10n.t('video_album_select', '选择相册'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
        .width('100%')
        .padding({ left: 20, right: 20, top: 4 })
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(AppTheme.current().primary)
        }
        .width('100%')
        .padding({ top: 32, bottom: 32 })
      } else if (this.items.length === 0) {
        this.EmptyBody()
      } else {
        this.GridBody()
      }
      Text(L10n.t('cancel', '取消'))
        .fontSize(15)
        .fontColor(AppTheme.current().primary)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 12, bottom: 24 })
        .onClick(() => {
          this.p.close();
        })
    }
    .width('100%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}
