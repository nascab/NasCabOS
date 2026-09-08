import { AppTheme } from '../../../core/theme/AppTheme';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { AppImage } from '../../../common/components/AppImage';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { TimelineController } from '../../controllers/TimelineController';
import { TimelinePhotoItem } from '../../models/PhotoModels';
import { PhotoDateUtil } from '../../utils/PhotoDateUtil';

/**
 * 照片时间线网格单元（对齐 Flutter PhotoTimelineItem 移动端交互）：
 * 缩略图 cover/contain、视频时长角标、实况图标、raw 徽标、收藏、多选圆形勾选。
 */
@ComponentV2
export struct PhotoTimelineItem {
  @Param item: TimelinePhotoItem = new TimelinePhotoItem();
  @Param ctrl: TimelineController = new TimelineController();
  @Local tinyUrl: string = '';

  aboutToAppear(): void {
    void this.resolveUrl();
  }

  /** item 复用变化时重新解析缩略图地址 */
  @Monitor('item', 'item.fullpath')
  onItemChange(): void {
    this.tinyUrl = '';
    void this.resolveUrl();
  }

  private async resolveUrl(): Promise<void> {
    const path = this.item.fullpath;
    if (path.length === 0) {
      return;
    }
    try {
      const url = await ApiUrls.getTinyUrl(path);
      if (this.item.fullpath === path) {
        this.tinyUrl = url;
      }
    } catch (_e) {
      this.tinyUrl = '';
    }
  }

  build() {
    Stack() {
      if (this.tinyUrl.length > 0) {
        AppImage({
          url: this.tinyUrl,
          objectFit: this.ctrl.isCoverMode ? ImageFit.Cover : ImageFit.Contain,
          imageRadius: 4
        })
      } else {
        Image($rawfile('icons/no_data.png'))
          .width('100%')
          .height('100%')
          .objectFit(this.ctrl.isCoverMode ? ImageFit.Cover : ImageFit.Contain)
          .borderRadius(4)
          .draggable(false)
      }

      // 选中遮罩
      if (this.ctrl.isSelected(this.item.id)) {
        Column()
          .width('100%')
          .height('100%')
          .borderRadius(4)
          .backgroundColor(AppTheme.withAlpha(AppTheme.current().primary, 0.3))
          .border({ width: 2, color: AppTheme.current().primary })
      }

      // 顶部信息行：视频时长 / 实况图标 / raw 徽标
      Row() {
        Blank()
        if (this.item.type === 2) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(12)
              .fontColor(['#FFFFFF'])
            Text(PhotoDateUtil.formatDuration(this.item.duration))
              .fontSize(12)
              .fontColor('#FFFFFF')
          }
        } else if (this.item.isLvp === 1) {
          SymbolGlyph($r('sys.symbol.livephoto'))
            .fontSize(14)
            .fontColor(['#FFFFFF'])
            .shadow({ radius: 3, offsetX: 0, offsetY: 1, color: '#000000' })
        }
        if (this.item.rawShowExt.length > 0) {
          Text(this.item.rawShowExt)
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .padding({ left: 2, right: 2, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#99000000')
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 6 })
      .alignItems(VerticalAlign.Center)

      // 底部左侧收藏
      if (this.item.isFavorite && !this.ctrl.isMultiSelectMode) {
        SymbolGlyph(this.item.isFavorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
          .fontSize(20)
          .fontColor([this.item.isFavorite ? '#FF3B30' : '#FFFFFF'])
          .position({ x: 2, y: this.cellExtent() - 30 })
          .onClick(() => {
            void this.ctrl.toggleFavorite(this.item);
          })
      }

      // 底部右侧多选勾选
      if (this.showCheck()) {
        CircleCheckbox({
          value: this.ctrl.isSelected(this.item.id),
          uncheckedBorderColor: '#FFFFFF',
          onChanged: (_c: boolean): void => {
            this.ctrl.toggleSelection(this.item.id);
          }
        })
          .position({ x: this.cellExtent() - 28, y: this.cellExtent() - 28 })
      }
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .onClick(() => {
      if (this.ctrl.isMultiSelectMode) {
        this.ctrl.toggleSelection(this.item.id);
        return;
      }
      this.ctrl.openMedia(this.item);
    })
    .gesture(LongPressGesture({ duration: 500 })
      .onAction(() => {
        if (!this.ctrl.isMultiSelectMode) {
          this.ctrl.toggleSelection(this.item.id);
        }
      }))
  }

  private cellExtent(): number {
    return this.ctrl.cellExtent;
  }

  private showCheck(): boolean {
    return this.ctrl.isMultiSelectMode || this.ctrl.isSelected(this.item.id);
  }
}
