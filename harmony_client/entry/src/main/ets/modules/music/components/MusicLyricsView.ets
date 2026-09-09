import { L10n } from '../../../core/localization/L10n';
import { AppTheme } from '../../../core/theme/AppTheme';
import {
  ParsedLyricLine, LyricWordSpan, parseLyricText, findActiveLyricIndex, wordHighlightProgress
} from './MusicLyricsParser';

/**
 * 歌词滚动视图（对齐 Flutter LyricView / DynamicLyricView）：
 * 逐行歌词自动滚动居中，当前行高亮（逐字模式按词渐亮），点击行跳转播放进度。
 * positionMs 由父组件随播放进度传入。
 */
@ComponentV2
export struct MusicLyricsView {
  @Param lyrics: string = '';
  @Param positionMs: number = 0;
  /** 居中模式（手机全屏歌词页） */
  @Param centerMode: boolean = true;
  @Param onSeekLine: (timeMs: number) => void = (_t: number): void => {
  };

  @Local private lines: ParsedLyricLine[] = [];
  @Local private activeIndex: number = -1;
  private scroller: ListScroller = new ListScroller();
  private lastScrolled: number = -2;

  aboutToAppear(): void {
    this.reload();
  }

  @Monitor('lyrics')
  onLyricsChange(): void {
    this.lastScrolled = -2;
    this.reload();
  }

  @Monitor('positionMs')
  onPositionChange(): void {
    this.updateActive();
  }

  private reload(): void {
    this.lines = parseLyricText(this.lyrics);
    this.activeIndex = findActiveLyricIndex(this.lines, this.positionMs);
    this.ensureVisible(true);
  }

  private updateActive(): void {
    const idx = findActiveLyricIndex(this.lines, this.positionMs);
    if (idx !== this.activeIndex) {
      this.activeIndex = idx;
      this.ensureVisible(false);
    }
  }

  private ensureVisible(immediate: boolean): void {
    const idx = this.activeIndex >= 0 ? this.activeIndex : 0;
    if (this.lines.length === 0 || idx === this.lastScrolled) {
      return;
    }
    // 延迟到布局完成后再滚动
    setTimeout((): void => {
      if (idx >= this.lines.length) {
        return;
      }
      this.lastScrolled = idx;
      try {
        this.scroller.scrollToIndex(idx, !immediate, ScrollAlign.CENTER);
      } catch (_e) {
        // 列表尚未布局完成时忽略
      }
    }, immediate ? 80 : 40);
  }

  build() {
    if (this.lines.length === 0) {
      Column() {
        Text(L10n.t('music_no_lyric'))
          .fontSize(18)
          .lineHeight(27)
          .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.75))
      }
      .width('100%')
      .height('100%')
      .alignItems(this.centerMode ? HorizontalAlign.Center : HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    } else {
      List({ scroller: this.scroller, space: 0 }) {
        ForEach(this.lines, (line: ParsedLyricLine, index: number) => {
          ListItem() {
            Column() {
              this.LineText(line, index)
              if (line.translation.trim().length > 0) {
                Text(line.translation)
                  .fontSize(16)
                  .lineHeight(24)
                  .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface,
                    index === this.activeIndex ? 0.55 : 0.38))
                  .textAlign(this.centerMode ? TextAlign.Center : TextAlign.Start)
                  .margin({ top: 10 })
                  .width('100%')
              }
            }
            .width('100%')
            .alignItems(this.centerMode ? HorizontalAlign.Center : HorizontalAlign.Start)
            .padding({ top: 10, bottom: 10 })
            .onClick(() => {
              this.onSeekLine(line.timeMs);
            })
          }
        }, (line: ParsedLyricLine) => `${line.timeMs}_${line.text}`)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .padding({ top: 64, bottom: 20 })
    }
  }

  @Builder
  private LineText(line: ParsedLyricLine, index: number) {
    if (index === this.activeIndex && line.words !== undefined && line.words.length > 0) {
      // 逐字高亮行
      Text() {
        ForEach(line.words, (w: LyricWordSpan, wi: number) => {
          Span(w.text)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.wordColor(line, w, wi))
        })
      }
      .width('100%')
      .textAlign(this.centerMode ? TextAlign.Center : TextAlign.Start)
    } else if (index === this.activeIndex) {
      Text(line.text)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .textAlign(this.centerMode ? TextAlign.Center : TextAlign.Start)
        .width('100%')
    } else {
      Text(line.text)
        .fontSize(18)
        .lineHeight(28)
        .fontColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.4))
        .textAlign(this.centerMode ? TextAlign.Center : TextAlign.Start)
        .width('100%')
    }
  }

  private wordColor(line: ParsedLyricLine, w: LyricWordSpan, wi: number): string {
    const nextStart = wi + 1 < line.words!.length ? line.words![wi + 1].start : -1;
    const p = wordHighlightProgress(this.positionMs, w.start, w.end, nextStart);
    // 白色 36% → 100% 渐变（对齐 Color.lerp(inactiveActiveLineColor, highlightColor, p)）
    const alpha = 0.36 + 0.64 * p;
    return AppTheme.withAlpha('#FFFFFF', alpha);
  }
}
