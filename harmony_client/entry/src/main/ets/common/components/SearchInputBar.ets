import { AppTheme, ThemePalette } from '../../core/theme/AppTheme';

/**
 * 常驻展开的搜索输入栏（对齐 Flutter CustomExpandableSearchBar defaultExpanded 分支）：
 * 搜索图标 + 输入框 + 清除按钮，边框圆角样式。
 */
@ComponentV2
export struct SearchInputBar {
  @Param hintText: string = '';
  @Param text: string = '';
  /** 输入变化回调 */
  @Param onChanged: (value: string) => void = (_v: string) => {
  };
  /** 点击清除回调 */
  @Param onClear: () => void = () => {
  };

  build() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([this.palette().onSurface])
      TextInput({ text: this.text, placeholder: this.hintText })
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .placeholderColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.6))
        .placeholderFont({ size: 14 })
        .backgroundColor('#00000000')
        .border({ width: 0 })
        .padding(0)
        .layoutWeight(1)
        .height(30)
        .onChange((v: string) => {
          this.onChanged(v);
        })
      if (this.text.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(15)
          .fontColor([this.palette().onSurface])
          .onClick(() => {
            this.onClear();
          })
      }
    }
    .width('100%')
    .height(36)
    .padding({ left: 8, right: 8 })
    .borderRadius(10)
    .border({ width: 1, color: this.palette().divider })
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }
}
