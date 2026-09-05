import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';

/**
 * 空状态占位（对齐 Flutter CustomEmptyState）：no_data 图 + 提示文案。
 */
@ComponentV2
export struct EmptyState {
  @Param message: string = '';
  @Param imagePath: ResourceStr = $rawfile('icons/no_data.png');
  @Param iconSize: number = 120;

  build() {
    Column() {
      Image(this.imagePath)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .draggable(false)
      Text(this.message.length > 0 ? this.message : L10n.t('no_data', '暂无数据'))
        .fontSize(14)
        .fontColor(AppTheme.current().hint)
        .textAlign(TextAlign.Center)
        .margin({ top: 10 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
