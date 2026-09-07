import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import { DialogUtil } from '../../../common/DialogUtil';
import { CircleCheckbox } from '../../../common/components/CircleCheckbox';
import { TimelineController } from '../../controllers/TimelineController';
import { PhotoDateUtil } from '../../utils/PhotoDateUtil';

/**
 * 照片时间线日期头（对齐 Flutter PhotoTimelineItemDate）：
 * 圆形勾选 + 日期 + 星期几 + 地点/拍摄设备副标题（点击查看详情）。
 */
@ComponentV2
export struct PhotoTimelineDateHeader {
  @Param date: string = '';
  @Param ctrl: TimelineController = new TimelineController();

  build() {
    Row() {
      CircleCheckbox({
        value: this.ctrl.isDateSelected(this.date),
        onChanged: (_c: boolean): void => {
          this.ctrl.toggleDateSelection(this.date);
        }
      })
      Column({ space: 2 }) {
        Row({ space: 8 }) {
          Text(this.date)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.current().onSurface)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          Text(PhotoDateUtil.weekdayFromDate(this.date))
            .fontSize(10)
            .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.75))
            .maxLines(1)
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')

        this.DateSubtitle()
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 6 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4, bottom: 2 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  DateSubtitle() {
    Row({ space: 15 }) {
      if (this.geo().length > 0) {
        Text(`${L10n.t('timeline_date_location', '地点')}: ${this.geo()}`)
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          .maxLines(1)
      }
      if (this.camera().length > 0) {
        Text(`${L10n.t('timeline_date_camera', '拍摄设备')}: ${this.camera()}`)
          .fontSize(12)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
          .maxLines(1)
      }
    }
    .width('100%')
    .visibility(this.hasInfo() ? Visibility.Visible : Visibility.None)
    .onClick(() => {
      DialogUtil.showInfoDialog(
        this.date,
        this.dialogContent(),
        L10n.t('confirm', '确认'));
    })
  }

  private geo(): string {
    return (this.ctrl.getDateInfo(this.date)?.geo ?? '').trim();
  }

  private camera(): string {
    return (this.ctrl.getDateInfo(this.date)?.camera ?? '').trim();
  }

  private hasInfo(): boolean {
    return this.geo().length > 0 || this.camera().length > 0;
  }

  private dialogContent(): string {
    const locationLabel = L10n.t('timeline_date_location', '地点');
    const cameraLabel = L10n.t('timeline_date_camera', '拍摄设备');
    const rows: string[] = [];
    if (this.geo().length > 0) {
      rows.push(`${locationLabel}: ${this.geo()}`);
    }
    if (this.camera().length > 0) {
      rows.push(`${cameraLabel}: ${this.camera()}`);
    }
    if (rows.length === 0) {
      return L10n.t('no_data', '暂无数据');
    }
    return rows.join('\n');
  }
}
