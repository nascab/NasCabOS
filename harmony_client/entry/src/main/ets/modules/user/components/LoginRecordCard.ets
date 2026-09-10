import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { LoginRecord, formatUserTime } from '../models/UserModels';

/**
 * 登录记录卡片（对齐 Flutter CustomLoginRecordCard）：
 * 设备图标（移动端 phone / 其余 display）+ browser - device_info + 本地格式化时间。
 */
@ComponentV2
export struct LoginRecordCard {
  @Require @Param record: LoginRecord;

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph(this.record.isMobile()
          ? $r('sys.symbol.phone')
          : $r('sys.symbol.display'))
          .fontSize(20)
          .fontColor([AppTheme.withAlpha(this.palette().primary, 0.8)])
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.1))

      Column() {
        Text(`${this.record.browser} - ${this.record.deviceInfo}`)
          .fontSize(14)
          .fontColor(this.palette().onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(formatUserTime(this.record.createTimeRaw))
          .fontSize(12)
          .fontColor(this.palette().subText)
          .margin({ top: 4 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(12)
    .borderRadius(12)
    .backgroundColor(this.palette().cardBg)
    .border({ width: 1, color: AppTheme.withAlpha(this.palette().divider, 0.4) })
  }
}
