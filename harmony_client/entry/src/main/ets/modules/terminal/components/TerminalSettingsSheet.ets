import { L10n } from '../../../core/localization/L10n';
import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TerminalController } from '../controllers/TerminalController';
import { TerminalUiConfig, TERMINAL_DEFAULT_FG, TERMINAL_DEFAULT_BG, cursorGlyph } from '../models/TerminalModels';
import { showTerminalColorPicker } from './TerminalColorPicker';

const TAG = 'TerminalSettingsSheet';

class TerminalSettingsSheetParams extends SheetParamsBase {
  ctrl: TerminalController = TerminalController.getInstance();
  onSaved: () => void = (): void => {
  };
}

/**
 * 终端设置底部弹层（对齐 Flutter _TerminalSettingsSheet）：
 * 字体/背景/光标颜色 + 字号/行高滑杆 + 光标样式 + 光标闪烁，改动实时生效，取消回滚快照。
 */
@ComponentV2
export struct TerminalSettingsSheet {
  @Param params: TerminalSettingsSheetParams = new TerminalSettingsSheetParams();
  @Local foregroundText: string = '';
  @Local backgroundText: string = '';
  @Local cursorText: string = '';
  @Local fontSize: number = 14;
  @Local lineHeight: number = 1.0;
  @Local cursorStyle: string = 'block';
  @Local cursorBlink: boolean = true;

  aboutToAppear(): void {
    const cfg = this.params.ctrl.uiConfig;
    this.foregroundText = cfg.foreground;
    this.backgroundText = cfg.background;
    this.cursorText = cfg.cursor;
    this.fontSize = cfg.fontSize;
    this.lineHeight = cfg.lineHeight;
    this.cursorStyle = cfg.cursorStyle;
    this.cursorBlink = cfg.cursorBlink;
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  private buildConfig(): TerminalUiConfig {
    const fg = TerminalUiConfig.parseColor(this.foregroundText);
    const bg = TerminalUiConfig.parseColor(this.backgroundText);
    const cursor = TerminalUiConfig.parseColor(this.cursorText);
    return new TerminalUiConfig(
      fg.length > 0 ? fg : TERMINAL_DEFAULT_FG,
      bg.length > 0 ? bg : TERMINAL_DEFAULT_BG,
      cursor.length > 0 ? cursor : TERMINAL_DEFAULT_FG,
      this.fontSize,
      this.lineHeight,
      'RobotoMono',
      this.cursorStyle,
      this.cursorBlink);
  }

  private apply(): void {
    this.params.ctrl.setUiConfig(this.buildConfig());
  }

  private resetDefaults(): void {
    const d = TerminalUiConfig.defaults();
    this.foregroundText = d.foreground;
    this.backgroundText = d.background;
    this.cursorText = d.cursor;
    this.fontSize = d.fontSize;
    this.lineHeight = d.lineHeight;
    this.cursorStyle = d.cursorStyle;
    this.cursorBlink = d.cursorBlink;
    this.apply();
  }

  private async save(): Promise<void> {
    this.apply();
    await this.params.ctrl.saveUiConfig();
    this.params.onSaved();
    this.params.close();
  }

  private async pickColor(target: string): Promise<void> {
    const current = target === 'foreground' ? this.foregroundText
      : target === 'background' ? this.backgroundText : this.cursorText;
    const picked = await showTerminalColorPicker(
      L10n.t('terminal_pick_color', '选择颜色'), current);
    if (picked === undefined) {
      return;
    }
    if (target === 'foreground') {
      this.foregroundText = picked;
    } else if (target === 'background') {
      this.backgroundText = picked;
    } else {
      this.cursorText = picked;
    }
    this.apply();
  }

  /** 颜色行：标签 + hex 输入 + 预览（点击弹出选色弹窗） */
  @Builder
  ColorRow(label: string, value: string, target: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().onSurface)
        .width(76)
      TextInput({ text: value, placeholder: L10n.t('terminal_color_hint', '#RRGGBB 或 #AARRGGBB') })
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .placeholderColor(this.palette().hint)
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: this.palette().inputBorder })
        .height(38)
        .layoutWeight(1)
        .onChange((v: string): void => {
          if (target === 'foreground') {
            this.foregroundText = v;
          } else if (target === 'background') {
            this.backgroundText = v;
          } else {
            this.cursorText = v;
          }
          this.apply();
        })
      Column()
        .width(28)
        .height(28)
        .borderRadius(6)
        .backgroundColor(TerminalUiConfig.parseColorWithFallback(value, TERMINAL_DEFAULT_FG))
        .border({ width: 1, color: this.palette().divider })
        .onClick((): void => {
          void this.pickColor(target);
        })
    }
    .width('100%')
  }

  @Builder
  CursorStyleChip(value: string, label: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.cursorStyle === value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.cursorStyle === value ? this.palette().buttonText : this.palette().onSurface)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(8)
      .backgroundColor(this.cursorStyle === value
        ? this.palette().primary : this.palette().inputFill)
      .onClick((): void => {
        this.cursorStyle = value;
        this.apply();
      })
  }

  build() {
    Column() {
      // 头部：标题 + 恢复默认 + 取消 + 保存
      Row({ space: 8 }) {
        Text(L10n.t('terminal_settings_title', '终端设置'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().onSurface)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(L10n.t('terminal_restore_defaults', '恢复默认'))
          .fontSize(14)
          .fontColor(this.palette().primary)
          .onClick((): void => {
            this.resetDefaults();
          })
        Text(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(this.palette().primary)
          .margin({ left: 8 })
          .onClick((): void => {
            this.params.close();
          })
        Button(L10n.t('save', '保存'))
          .fontSize(13)
          .fontColor(this.palette().buttonText)
          .backgroundColor(this.palette().primary)
          .height(30)
          .padding({ left: 12, right: 12 })
          .margin({ left: 8 })
          .onClick((): void => {
            void this.save();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 12 })

      Divider()
        .color(this.palette().divider)
        .strokeWidth(1)

      Scroll() {
        Column({ space: 14 }) {
          this.ColorRow(L10n.t('terminal_font_color', '字体颜色'), this.foregroundText, 'foreground')
          this.ColorRow(L10n.t('terminal_bg_color', '背景颜色'), this.backgroundText, 'background')
          this.ColorRow(L10n.t('terminal_cursor_color', '光标颜色'), this.cursorText, 'cursor')

          // 字号
          Text(L10n.t('terminal_font_size', '字体大小（@px）',
            L10n.paramsOf('px', `${this.fontSize}`)))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .width('100%')
          Slider({ value: this.fontSize, min: 8, max: 24, step: 1, style: SliderStyle.OutSet })
            .selectedColor(this.palette().primary)
            .trackColor(this.palette().divider)
            .width('100%')
            .onChange((value: number, _mode: SliderChangeMode): void => {
              const next = Math.round(value);
              if (next !== this.fontSize) {
                this.fontSize = next;
                this.apply();
              }
            })

          // 行高
          Text(L10n.t('terminal_line_height', '行高（@value）',
            L10n.paramsOf('value', this.lineHeight.toFixed(2))))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .width('100%')
          Slider({ value: this.lineHeight, min: 0.8, max: 2.0, step: 0.05, style: SliderStyle.OutSet })
            .selectedColor(this.palette().primary)
            .trackColor(this.palette().divider)
            .width('100%')
            .onChange((value: number, _mode: SliderChangeMode): void => {
              const next = Math.round(value * 100) / 100;
              if (next !== this.lineHeight) {
                this.lineHeight = next;
                this.apply();
              }
            })

          // 光标样式
          Text(L10n.t('terminal_cursor_style', '光标样式'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onSurface)
            .width('100%')
          Row({ space: 8 }) {
            this.CursorStyleChip('block', L10n.t('terminal_cursor_block', '方块'))
            this.CursorStyleChip('underline', L10n.t('terminal_cursor_underline', '下划线'))
            this.CursorStyleChip('bar', L10n.t('terminal_cursor_bar', '竖线'))
            // 当前样式预览
            Text(cursorGlyph(this.cursorStyle))
              .fontSize(20)
              .fontColor(TerminalUiConfig.parseColorWithFallback(this.cursorText, TERMINAL_DEFAULT_FG))
              .margin({ left: 4 })
          }
          .width('100%')

          // 光标闪烁
          Row() {
            Text(L10n.t('terminal_cursor_blink', '光标闪烁'))
              .fontSize(14)
              .fontColor(this.palette().onSurface)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.cursorBlink })
              .selectedColor(this.palette().primary)
              .onChange((isOn: boolean): void => {
                this.cursorBlink = isOn;
                this.apply();
              })
          }
          .width('100%')

          Row().height(8)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 520 })
      .padding({ left: 18, right: 18, top: 14 })
      .align(Alignment.Top)

      Row().height(14)
    }
    .width('100%')
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius({ topLeft: 18, topRight: 18 })
  }
}

const terminalSettingsSheetBuilder: WrappedBuilder<[TerminalSettingsSheetParams]> =
  wrapBuilder(TerminalSettingsSheetBuilderFn);

@Builder
function TerminalSettingsSheetBuilderFn(params: TerminalSettingsSheetParams) {
  TerminalSettingsSheet({ params: params })
}

/**
 * 弹出终端设置弹层（对齐 Flutter _openSettings）：取消/遮罩关闭时回滚到打开前快照。
 */
export function showTerminalSettingsSheet(ctrl: TerminalController): void {
  const snapshot = JSON.stringify(ctrl.uiConfig.toJson());
  let saved = false;
  const p = new TerminalSettingsSheetParams();
  p.ctrl = ctrl;
  p.onSaved = (): void => {
    saved = true;
  };
  p.onDismissed = (): void => {
    if (!saved) {
      ctrl.restoreFromJsonString(snapshot);
    }
  };
  try {
    SheetUtil.present<TerminalSettingsSheetParams>(p, terminalSettingsSheetBuilder);
  } catch (e) {
    hilog.error(0x0000, TAG, 'showTerminalSettingsSheet failed: %{public}s', JSON.stringify(e));
  }
}
