import { TerminalController } from '../controllers/TerminalController';
import { TerminalLine, cursorGlyph } from '../models/TerminalModels';

/**
 * 终端输出视图：
 * - List + LazyForEach 虚拟化渲染已提交行（最多 10000 行滚动缓冲）
 * - 最后一行（未换行的实时行）固定渲染在列表下方，并按配置渲染闪烁光标
 * - 仍在底部附近时新输出自动滚动到底，用户上翻查看历史时不打断
 */
@ComponentV2
export struct TerminalOutputView {
  @Require @Param ctrl: TerminalController;
  @Local atBottom: boolean = true;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.scrollIfNeeded();
  }

  /** 输出变化后贴底滚动（延迟一帧等 LazyForEach 完成布局） */
  @Monitor('ctrl.liveText', 'ctrl.revision')
  onOutputChanged(): void {
    this.scrollIfNeeded();
  }

  private scrollIfNeeded(): void {
    if (!this.atBottom) {
      return;
    }
    setTimeout((): void => {
      try {
        this.scroller.scrollEdge(Edge.Bottom);
      } catch (_e) {
        // 尚未挂载时忽略
      }
    }, 30);
  }

  private lineColor(line: TerminalLine): string {
    if (line.color.length > 0) {
      return line.color;
    }
    return this.ctrl.uiConfig.foreground;
  }

  build() {
    Column() {
      List({ scroller: this.scroller, space: 0 }) {
        LazyForEach(this.ctrl.source, (line: TerminalLine) => {
          ListItem() {
            Text(line.text.length > 0 ? line.text : ' ')
              .fontSize(this.ctrl.uiConfig.fontSize)
              .lineHeight(this.ctrl.uiConfig.fontSize * this.ctrl.uiConfig.lineHeight)
              .fontFamily('monospace')
              .fontColor(this.lineColor(line))
              .fontWeight(line.bold ? FontWeight.Bold : FontWeight.Normal)
              .copyOption(CopyOptions.InApp)
              .width('100%')
          }
        }, (line: TerminalLine, idx: number): string =>
          `${idx}_${this.ctrl.uiConfig.fontSize}_${this.ctrl.uiConfig.lineHeight}_${this.ctrl.uiConfig.foreground}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .enableScrollInteraction(true)
      .onScrollIndex((start: number, end: number): void => {
        const total = this.ctrl.source.totalCount();
        this.atBottom = end >= total - 1;
        if (start < 0 || end < 0) {
          this.atBottom = true;
        }
      })

      // 实时行 + 光标
      Row() {
        Text(this.ctrl.liveText.length > 0 ? this.ctrl.liveText : ' ')
          .fontSize(this.ctrl.uiConfig.fontSize)
          .lineHeight(this.ctrl.uiConfig.fontSize * this.ctrl.uiConfig.lineHeight)
          .fontFamily('monospace')
          .fontColor(this.ctrl.liveColor.length > 0
            ? this.ctrl.liveColor : this.ctrl.uiConfig.foreground)
          .fontWeight(this.ctrl.liveBold ? FontWeight.Bold : FontWeight.Normal)
          .copyOption(CopyOptions.InApp)
          .constraintSize({ maxWidth: '100%' })
        if (this.ctrl.connected || this.ctrl.connecting) {
          Text(cursorGlyph(this.ctrl.uiConfig.cursorStyle))
            .fontSize(this.ctrl.uiConfig.fontSize)
            .lineHeight(this.ctrl.uiConfig.fontSize * this.ctrl.uiConfig.lineHeight)
            .fontFamily('monospace')
            .fontColor(this.ctrl.uiConfig.cursor)
            .opacity(this.ctrl.cursorVisible ? 1 : 0)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.ctrl.uiConfig.background)
  }
}
