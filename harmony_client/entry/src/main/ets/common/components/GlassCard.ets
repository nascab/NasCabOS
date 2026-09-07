import { AppTheme } from '../../core/theme/AppTheme';

@Builder
function GlassCardEmpty() {
}

/**
 * 通用玻璃卡片（对齐 Flutter CustomGlassCard）：
 * surface 半透明背景 + 细边框 + 圆角 + 可选点击。设置页/AI 概览页等大量复用。
 */
@ComponentV2
export struct GlassCard {
  @BuilderParam content: () => void = GlassCardEmpty;
  /** 内边距（避免与组件内置 padding 属性重名） */
  @Param padValue: number | Padding = 16;
  @Param cornerRadius: number = 16;
  /** 背景不透明度（对齐 Flutter opacity 0.55） */
  @Param bgOpacity: number = 0.55;
  @Param onCardTap: () => void = (): void => {
  };

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.padValue)
    .backgroundColor(AppTheme.withAlpha(AppTheme.current().surfaceBg, this.bgOpacity))
    .borderRadius(this.cornerRadius)
    .border({
      width: 1,
      color: AppTheme.withAlpha(AppTheme.current().onSurface, 0.06)
    })
    .onClick(() => {
      this.onCardTap();
    })
  }
}
