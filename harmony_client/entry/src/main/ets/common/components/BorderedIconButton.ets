import { AppTheme } from '../../core/theme/AppTheme';

/**
 * 带边框的圆形图标按钮（对齐 Flutter CustomBorderedIconButton）：
 * 支持 active 高亮（主色边框+浅主色背景）、禁用态。
 */
@ComponentV2
export struct BorderedIconButton {
  @Param icon: Resource = $r('sys.symbol.plus');
  @Param isEnabled: boolean = true;
  @Param active: boolean = false;
  /** 移动端默认 36（Flutter size 32 + 4） */
  @Param btnSize: number = 36;
  @Param iconSize: number = 18;
  @Param corner: number = 10;
  @Param strokeColor: string = '';
  @Param iconColor: string = '';
  @Param fillColor: string = '';
  @Param onTap: () => void = () => {
  };

  build() {
    Column() {
      SymbolGlyph(this.icon)
        .fontSize(this.iconSize)
        .fontColor([this.effectiveIconColor()])
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height(this.btnSize)
    .width(this.btnSize)
    .borderRadius(this.corner)
    .backgroundColor(this.effectiveBg())
    .border({
      width: 1,
      color: this.isEnabled ? this.effectiveBorderColor() : AppTheme.current().hint
    })
    .opacity(this.isEnabled ? 1 : 0.45)
    .onClick(() => {
      if (this.isEnabled) {
        this.onTap();
      }
    })
  }

  private effectiveBorderColor(): string {
    if (this.strokeColor.length > 0) {
      return this.strokeColor;
    }
    return this.active ? AppTheme.current().primary : AppTheme.current().divider;
  }

  private effectiveIconColor(): string {
    if (this.iconColor.length > 0) {
      return this.iconColor;
    }
    return this.active ? AppTheme.current().primary : AppTheme.current().onSurface;
  }

  private effectiveBg(): string {
    if (this.fillColor.length > 0) {
      return this.fillColor;
    }
    if (this.active) {
      // primary 10% 透明
      return AppTheme.withAlpha(AppTheme.current().primary, 0.10);
    }
    return '#00000000';
  }
}
