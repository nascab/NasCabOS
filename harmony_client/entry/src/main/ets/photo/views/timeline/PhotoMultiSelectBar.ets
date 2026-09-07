import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { ToastUtil } from '../../../common/ToastUtil';
import { SheetListItem, SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { TimelineController } from '../../controllers/TimelineController';
import { TimelinePhotoItem } from '../../models/PhotoModels';

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
              ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
            })
          this.BarAction(
            $r('sys.symbol.minus_circle'),
            L10n.t('face_remove_from_album', '移出人脸相册'),
            !this.disabled(),
            false,
            (): void => {
              ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
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
    SheetUtil.present(p, wrapBuilder(MoreSheetContent));
  }
}

class MoreSheetParams extends SheetParamsBase {
  ctrl: TimelineController = new TimelineController();
  isFaceAlbum: boolean = false;
  singlePhoto: TimelinePhotoItem | undefined = undefined;
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
          ToastUtil.show(L10n.t('feature_coming_soon', '功能开发中'));
        }
      })
    }
    SheetListItem({
      icon: $r('sys.symbol.plus'),
      title: L10n.t('add_to_album', '添加到相册'),
      onSelect: (): void => {
        p.close();
        void p.ctrl.addToAlbumSelected();
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
