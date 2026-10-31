import { L10n } from '../../../../core/localization/L10n';
import { AppTheme } from '../../../../core/theme/AppTheme';
import { ApiUrls } from '../../../../core/network/ApiUrls';
import { ToastUtil } from '../../../../common/ToastUtil';
import { DialogUtil } from '../../../../common/DialogUtil';
import { NavUtil } from '../../../../common/NavUtil';
import { AppRouter } from '../../../../router/AppRouter';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../../../common/SheetUtil';
import { AppImage } from '../../../../common/components/AppImage';
import { TimelineController } from '../../controllers/TimelineController';
import { TimelinePhotoItem, TimelineDetectedFaceItem } from '../../models/PhotoModels';
import { AiFaceItem } from '../../models/PhotoAiModels';
import { PhotoAlbumItem } from '../../models/PhotoAlbumModels';
import { PhotoAlbumListPageParam } from '../album/PhotoAlbumListPage';

/**
 * 时间线多选底部操作栏（对齐 Flutter AppPhotoTimelineMultiSelectBottomBar 移动端）：
 * 收藏/下载/删除/更多（更多弹层含加入相册、移出相册、取消多选）。
 */
@ComponentV2
export struct PhotoMultiSelectBar {
  @Param ctrl: TimelineController = new TimelineController();

  build() {
    Column() {
      Row() {
        if (!this.ctrl.isFaceAlbum) {
          this.BarAction(
            this.ctrl.listType === 'favorite'
              ? $r('sys.symbol.heart')
              : $r('sys.symbol.heart_fill'),
            this.ctrl.listType === 'favorite'
              ? L10n.t('unfavorite', '取消收藏')
              : L10n.t('favorites', '收藏'),
            !this.disabled(),
            false,
            (): void => {
              void this.ctrl.favoriteSelected();
            })
        }
        this.BarAction(
          $r('sys.symbol.square_and_arrow_down'),
          L10n.t('download', '下载'),
          !this.disabled(),
          false,
          (): void => {
            void this.ctrl.downloadSelected();
          })
        if (this.ctrl.isFaceAlbum) {
          this.BarAction(
            $r('sys.symbol.plus_circle'),
            L10n.t('face_move_to_other_face', '移动到其他人脸'),
            !this.disabled(),
            false,
            (): void => {
              this.openMoveToFace();
            })
          this.BarAction(
            $r('sys.symbol.minus_circle'),
            L10n.t('face_remove_from_album', '移出人脸相册'),
            !this.disabled(),
            false,
            (): void => {
              void this.ctrl.removeSelectedFromFaceAlbum();
            })
        }
        this.BarAction(
          this.ctrl.isFaceAlbum ? $r('sys.symbol.more') : $r('sys.symbol.trash'),
          this.ctrl.isFaceAlbum ? L10n.t('more', '更多') : L10n.t('delete', '删除'),
          !this.disabled(),
          !this.ctrl.isFaceAlbum,
          (): void => {
            if (this.ctrl.isFaceAlbum) {
              this.showMoreSheet(true);
              return;
            }
            void this.ctrl.deleteSelected();
          })
        if (!this.ctrl.isFaceAlbum) {
          this.BarAction(
            $r('sys.symbol.more'),
            L10n.t('more', '更多'),
            !this.disabled(),
            false,
            (): void => {
              this.showMoreSheet(false);
            })
        }
      }
      .width('100%')
      .height(65)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .border({ width: { top: 1 }, color: AppTheme.current().divider })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  private disabled(): boolean {
    return this.ctrl.getSelectedPhotoItems().length === 0;
  }

  @Builder
  BarAction(icon: Resource, label: string, enabled: boolean, danger: boolean, onTap: () => void) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)
        .fontColor([enabled ? (danger ? AppTheme.current().error : AppTheme.current().onSurface)
          : AppTheme.withAlpha(AppTheme.current().onSurface, 0.3)])
      Text(label)
        .fontSize(11)
        .fontColor(enabled ? (danger ? AppTheme.current().error : AppTheme.current().onSurface)
          : AppTheme.withAlpha(AppTheme.current().onSurface, 0.3))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, bottom: 10 })
    .borderRadius(10)
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  private showMoreSheet(isFaceAlbum: boolean): void {
    if (this.disabled()) {
      return;
    }
    const ctrl = this.ctrl;
    const selected: TimelinePhotoItem[] = ctrl.getSelectedPhotoItems();
    const p = new MoreSheetParams();
    p.ctrl = ctrl;
    p.isFaceAlbum = isFaceAlbum;
    p.singlePhoto = selected.length === 1 ? selected[0] : undefined;
    p.onAddToAlbum = (): void => {
      this.openAddToAlbum();
    };
    p.onShowPhotoFaces = (photo: TimelinePhotoItem): void => {
      this.showPhotoDetectedFaces(photo);
    };
    SheetUtil.present(p, wrapBuilder(MoreSheetContent));
  }

  /**
   * 选择目标人脸并把选中照片移动过去
   * （对齐 Flutter moveSelectedToOtherFace + _pickTargetFaceForMove，移动本身不再二次确认）。
   */
  private openMoveToFace(): void {
    if (this.disabled()) {
      return;
    }
    const ctrl = this.ctrl;
    void ctrl.loadFaceMoveTargets().then((faces: AiFaceItem[]): void => {
      if (faces.length === 0) {
        void DialogUtil.showInfoDialog(L10n.t('tip', '提示'),
          L10n.t('face_move_target_empty', '没有其他可移动的人脸'));
        return;
      }
      const rows: FaceRowData[] = [];
      for (const face of faces) {
        const row = new FaceRowData();
        row.faceId = face.faceId;
        row.faceCount = face.faceCount;
        row.coverFileHash = face.coverFileHash;
        row.name = face.name;
        row.isHide = face.isHide;
        rows.push(row);
      }
      const p = new FaceListSheetParams();
      p.title = L10n.t('face_move_to_other_face', '移动到其他人脸');
      p.rows = rows;
      p.pickable = true;
      p.onPick = (row: FaceRowData): void => {
        p.close();
        void ctrl.moveSelectedToOtherFace(row.faceId);
      };
      SheetUtil.present(p, wrapBuilder(FaceListSheetContent));
    });
  }

  /** 查看单张照片中检测到的人脸（对齐 Flutter showPhotoDetectedFaces） */
  private showPhotoDetectedFaces(photo: TimelinePhotoItem): void {
    const fileHash = photo.fileHash.trim();
    if (fileHash.length === 0) {
      ToastUtil.show(L10n.t('operation_failed', '操作失败'));
      return;
    }
    const ctrl = this.ctrl;
    void ctrl.loadPhotoDetectedFaces(photo).then((faces: TimelineDetectedFaceItem[]): void => {
      const rows: FaceRowData[] = [];
      for (const face of faces) {
        const row = new FaceRowData();
        row.faceId = face.faceId;
        row.faceCount = face.faceCount;
        row.coverFileHash = fileHash;
        row.name = face.name;
        row.isHide = face.isHide;
        rows.push(row);
      }
      const p = new FaceListSheetParams();
      p.title = L10n.t('face_show_photo_faces', '查看照片人脸');
      p.rows = rows;
      p.pickable = false;
      SheetUtil.present(p, wrapBuilder(FaceListSheetContent));
    });
  }

  /** 打开相册选择页（选择模式），选定后把选中照片加入该相册（对齐 Flutter addToAlbumSelected） */
  private openAddToAlbum(): void {
    if (this.disabled()) {
      return;
    }
    const ctrl = this.ctrl;
    const param = new PhotoAlbumListPageParam();
    param.type = 'all';
    param.selectionMode = true;
    param.onSelected = (album: PhotoAlbumItem): void => {
      void ctrl.addSelectedToAlbum(album.id);
    };
    NavUtil.push(AppRouter.PHOTO_ALBUM_LIST, param);
  }
}

class MoreSheetParams extends SheetParamsBase {
  ctrl: TimelineController = new TimelineController();
  isFaceAlbum: boolean = false;
  singlePhoto: TimelinePhotoItem | undefined = undefined;
  onAddToAlbum: () => void = (): void => {
  };
  onShowPhotoFaces: (photo: TimelinePhotoItem) => void = (_p: TimelinePhotoItem): void => {
  };
}

@Builder
function MoreSheetContent(p: MoreSheetParams) {
  Column() {
    if (!p.isFaceAlbum) {
      SheetListItem({
        icon: p.ctrl.listType === 'favorite' ? $r('sys.symbol.heart') : $r('sys.symbol.heart_fill'),
        title: p.ctrl.listType === 'favorite'
          ? L10n.t('unfavorite', '取消收藏')
          : L10n.t('favorites', '收藏'),
        onSelect: (): void => {
          p.close();
          void p.ctrl.favoriteSelected();
        }
      })
    }
    if (p.isFaceAlbum && p.singlePhoto !== undefined) {
      SheetListItem({
        icon: $r('sys.symbol.person_crop_circle_fill'),
        title: L10n.t('face_show_photo_faces', '查看照片人脸'),
        onSelect: (): void => {
          p.close();
          const photo = p.singlePhoto;
          if (photo !== undefined) {
            p.onShowPhotoFaces(photo);
          }
        }
      })
    }
    SheetListItem({
      icon: $r('sys.symbol.plus'),
      title: L10n.t('add_to_album', '添加到相册'),
      onSelect: (): void => {
        p.close();
        p.onAddToAlbum();
      }
    })
    if (p.ctrl.albumId > 0) {
      SheetListItem({
        icon: $r('sys.symbol.minus_circle'),
        title: L10n.t('remove_from_album', '从相册移除'),
        onSelect: (): void => {
          p.close();
          void p.ctrl.removeFromAlbumSelected();
        }
      })
    }
    if (p.isFaceAlbum) {
      SheetListItem({
        icon: $r('sys.symbol.trash'),
        title: L10n.t('delete', '删除'),
        onSelect: (): void => {
          p.close();
          void p.ctrl.deleteSelected();
        }
      })
    }
    SheetListItem({
      icon: $r('sys.symbol.xmark'),
      title: L10n.t('cancel', '取消'),
      onSelect: (): void => {
        p.close();
        p.ctrl.exitMultiSelectMode();
      }
    })
  }
  .width('100%')
  .borderRadius({ topLeft: 16, topRight: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
  .padding({ bottom: 20 })
}

// ===== 人脸列表弹层（移动目标选择 / 查看照片人脸） =====

/** 人脸行数据（移动目标来自 AiFaceItem，查看照片人脸来自 TimelineDetectedFaceItem + 照片 fileHash） */
class FaceRowData {
  faceId: number = 0;
  faceCount: number = 0;
  coverFileHash: string = '';
  name: string = '';
  isHide: boolean = false;
}

class FaceListSheetParams extends SheetParamsBase {
  title: string = '';
  rows: FaceRowData[] = [];
  /** 是否可选择（true=移动目标选择；false=只读查看） */
  pickable: boolean = false;
  onPick: (row: FaceRowData) => void = (_r: FaceRowData): void => {
  };
}

@ComponentV2
struct FaceListRowItem {
  @Param row: FaceRowData = new FaceRowData();
  @Param avatarSize: number = 36;
  @Param onTap: (row: FaceRowData) => void = (_r: FaceRowData): void => {
  };
  @Local avatarUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用时重新解析头像地址 */
  @Monitor('row', 'row.faceId')
  onRowChange(): void {
    this.avatarUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const faceId = this.row.faceId;
    if (faceId <= 0) {
      return;
    }
    try {
      const url = await ApiUrls.getFaceImageUrl(faceId, 120, 85, this.row.coverFileHash);
      if (this.row.faceId === faceId) {
        this.avatarUrl = url;
      }
    } catch (_e) {
      this.avatarUrl = '';
    }
  }

  private displayName(): string {
    const name = this.row.name.trim();
    return name.length > 0 ? name : `(${L10n.t('face_unnamed', '未命名')})`;
  }

  private subtitle(): string {
    const base = L10n.t('total_count', '共 @count 张', L10n.paramsOf('count', `${this.row.faceCount}`));
    return this.row.isHide ? `${base} · ${L10n.t('face_action_hide', '已隐藏')}` : base;
  }

  build() {
    Row({ space: 12 }) {
      Stack() {
        if (this.avatarUrl.length > 0) {
          AppImage({ url: this.avatarUrl, imageRadius: this.avatarSize / 2 })
        } else {
          Image($rawfile('icons/no_data.png'))
            .width(this.avatarSize)
            .height(this.avatarSize)
            .objectFit(ImageFit.Cover)
            .borderRadius(this.avatarSize / 2)
            .draggable(false)
        }
      }
      .width(this.avatarSize)
      .height(this.avatarSize)
      .borderRadius(this.avatarSize / 2)
      .border({ width: 1, color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.08) })
      .clip(true)

      Column({ space: 4 }) {
        Text(this.displayName())
          .fontSize(15)
          .fontColor(AppTheme.current().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subtitle())
          .fontSize(12)
          .fontColor(AppTheme.current().hint)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      this.onTap(this.row);
    })
  }
}

@ComponentV2
struct FaceListSheetBody {
  @Param p: FaceListSheetParams = new FaceListSheetParams();
  @Local keyword: string = '';

  private filteredRows(): FaceRowData[] {
    const kw = this.keyword.trim().toLowerCase();
    if (kw.length === 0) {
      return this.p.rows;
    }
    const out: FaceRowData[] = [];
    for (const row of this.p.rows) {
      const name = row.name.trim().length > 0 ? row.name.trim() : L10n.t('face_unnamed', '未命名');
      if (name.toLowerCase().includes(kw) || `${row.faceId}`.includes(kw)) {
        out.push(row);
      }
    }
    return out;
  }

  build() {
    Column() {
      SheetHandle()
      if (this.p.title.length > 0) {
        Text(this.p.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 4 })
      }
      if (this.p.pickable) {
        TextInput({ text: this.keyword, placeholder: L10n.t('search', '搜索') })
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(40)
          .width('100%')
          .margin({ left: 16, right: 16, top: 4, bottom: 8 })
          .onChange((v: string): void => {
            this.keyword = v;
          })
      }
      if (this.filteredRows().length === 0) {
        Column() {
          Text(this.p.pickable
            ? L10n.t('no_data', '暂无数据')
            : L10n.t('face_photo_faces_empty', '照片中未检测到人脸'))
            .fontSize(14)
            .fontColor(AppTheme.current().hint)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.filteredRows(), (row: FaceRowData) => {
            ListItem() {
              FaceListRowItem({
                row: row,
                onTap: (r: FaceRowData): void => {
                  if (this.p.pickable) {
                    this.p.onPick(r);
                  }
                }
              })
            }
          }, (row: FaceRowData) => `${row.faceId}_${row.faceCount}`)
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: AppTheme.current().divider })
      }
      Blank().height(16)
    }
    .width('100%')
    .height(this.p.pickable ? 460 : 340)
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

@Builder
function FaceListSheetContent(p: FaceListSheetParams) {
  FaceListSheetBody({ p: p })
}
