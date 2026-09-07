import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { BorderedIconButton } from '../../../common/components/BorderedIconButton';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { TimelineController } from '../../controllers/TimelineController';
import { TimelinePathItem } from '../../models/PhotoModels';

/**
 * 照片筛选底部弹层（对齐 Flutter AppPhotoTimelineView._showFilterSheet）：
 * 文件类型单选 + 来源目录多选 + 重置。
 */
export function showPhotoTimelineFilterSheet(ctrl: TimelineController): void {
  const p = new PhotoFilterSheetParams();
  p.ctrl = ctrl;
  SheetUtil.present(p, wrapBuilder(PhotoFilterSheetContent));
}

class PhotoFilterSheetParams extends SheetParamsBase {
  ctrl: TimelineController = new TimelineController();
}

@Builder
function PhotoFilterSheetContent(p: PhotoFilterSheetParams) {
  PhotoFilterSheetInner({ p: p })
}

@ComponentV2
struct PhotoFilterSheetInner {
  @Param p: PhotoFilterSheetParams = new PhotoFilterSheetParams();

  build() {
    Column() {
      // 头部：标题 + 重置 + 关闭
      Row() {
        Text(L10n.t('filter', '筛选'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.current().onSurface)
          .layoutWeight(1)
        Text(L10n.t('reset', '重置'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            void this.p.ctrl.clearSourcePathSelection(false);
            this.p.ctrl.setFileType('all');
            this.p.close();
          })
        BorderedIconButton({
          icon: $r('sys.symbol.xmark'),
          onTap: (): void => {
            this.p.close();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 12, bottom: 8 })

      Divider()
        .color(AppTheme.current().divider)
        .height(1)

      Scroll() {
        Column() {
          Text(L10n.t('photo_timeline_filter_file_type', '文件类型'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 8 })

          this.RadioRow('all', L10n.t('all', '全部'))
          this.RadioRow('photo', L10n.t('timeline_photos', '照片'))
          this.RadioRow('video', L10n.t('timeline_videos', '视频'))
          this.RadioRow('livephoto', L10n.t('timeline_live_photos', '实况'))

          Text(L10n.t('photo_timeline_filter_source', '来源'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.current().onSurface)
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 8 })

          if (this.p.ctrl.availablePaths.length === 0) {
            Text(L10n.t('no_path', '暂无路径'))
              .fontSize(14)
              .fontColor(AppTheme.current().onSurface)
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 12 })
          } else {
            ForEach(this.p.ctrl.availablePaths, (item: TimelinePathItem): void => {
              this.PathCheckRow(item.path)
            }, (item: TimelinePathItem): string => item.path)
          }
          Blank().height(12)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Auto)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)
    }
    .constraintSize({ maxHeight: '75%' })
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }

  @Builder
  RadioRow(value: string, label: string) {
    Row({ space: 12 }) {
      Column() {
        if (this.p.ctrl.fileType === value) {
          Column()
            .width(10)
            .height(10)
            .borderRadius(5)
            .backgroundColor(AppTheme.current().primary)
        }
      }
      .width(20)
      .height(20)
      .borderRadius(10)
      .border({ width: 2, color: this.p.ctrl.fileType === value
        ? AppTheme.current().primary : AppTheme.current().hint })
      .justifyContent(FlexAlign.Center)
      Text(label)
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      this.p.ctrl.setFileType(value);
    })
  }

  @Builder
  PathCheckRow(path: string) {
    Row({ space: 12 }) {
      CircleCheckbox({
        value: this.p.ctrl.selectedPaths.indexOf(path) >= 0,
        boxSize: 20,
        onChanged: (checked: boolean): void => {
          void this.p.ctrl.setSourcePathSelected(path, checked);
        }
      })
      Text(path)
        .fontSize(15)
        .fontColor(AppTheme.current().onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      void this.p.ctrl.setSourcePathSelected(path, this.p.ctrl.selectedPaths.indexOf(path) < 0);
    })
  }
}
