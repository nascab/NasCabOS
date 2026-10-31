import { AppTheme, ThemePalette } from '../../core/theme/AppTheme';

/**
 * 常驻展开的搜索输入栏（对齐 Flutter CustomExpandableSearchBar defaultExpanded 分支）：
 * 搜索图标 + 输入框 + 清除按钮，边框圆角样式。
 */
@ComponentV2
export struct SearchInputBar {
  @Param hintText: string = '';
  @Param text: string = '';
  /** 前景色（图标/文字/占位/边框）：用于深色标题栏等场景，空则跟随主题 onSurface */
  @Param fgColor: string = '';
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
        .fontColor([this.effectiveFg()])
      TextInput({ text: this.text, placeholder: this.hintText })
        .fontSize(14)
        .fontColor(this.effectiveFg())
        .placeholderColor(AppTheme.withAlpha(this.effectiveFg(), 0.6))
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
          .fontColor([this.effectiveFg()])
          .onClick(() => {
            this.onClear();
          })
      }
    }
    .width('100%')
    .height(36)
    .padding({ left: 8, right: 8 })
    .borderRadius(10)
    .border({ width: 1, color: this.fgColor.length > 0 ? AppTheme.withAlpha(this.fgColor, 0.35) : this.palette().divider })
  }

  private effectiveFg(): string {
    return this.fgColor.length > 0 ? this.fgColor : this.palette().onSurface;
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }
}
