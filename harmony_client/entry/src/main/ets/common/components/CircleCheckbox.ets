import { AppTheme, ThemePalette } from '../../core/theme/AppTheme';

/**
 * 圆形勾选框（对齐 Flutter CustomCheckbox 默认圆形样式）：
 * 选中时主色填充 + 白色对勾，未选中时灰色圆边框。
 */
@ComponentV2
export struct CircleCheckbox {
  @Param value: boolean = false;
  /** 尺寸（Flutter Checkbox 视觉尺寸约 22） */
  @Param boxSize: number = 22;
  @Param onChanged: (checked: boolean) => void = (_checked: boolean) => {
  };

  build() {
    Column() {
      if (this.value) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(this.boxSize * 0.6)
          .fontColor(['#FFFFFF'])
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width(this.boxSize)
    .height(this.boxSize)
    .borderRadius(this.boxSize / 2)
    .border({
      width: 2,
      color: this.value ? this.palette().primary : '#A3A3A3'
    })
    .backgroundColor(this.value ? this.palette().primary : '#00000000')
    .onClick(() => {
      this.onChanged(!this.value);
    })
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }
}
