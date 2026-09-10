import { DialogParamsBase, DialogUtil, DialogResult } from '../../../common/DialogUtil';
import { AppTheme } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { TerminalUiConfig } from '../models/TerminalModels';

const TAG = 'TerminalColorPicker';

/** 颜色选择弹窗参数（对齐 Flutter 终端设置中的选色 AlertDialog） */
export class TerminalColorPickerParams extends DialogParamsBase {
  title: string = '';
  initialColor: string = '';
}

/** 预设颜色（对齐 Flutter _presetColors，主题色取当前色板） */
function presetColors(): string[] {
  const t = AppTheme.current();
  return [
    t.primary, t.secondary, '#FFFFFF', '#000000', '#E6E6E6', '#0B0B0B',
    '#9E9E9E', '#78909C', '#F44336', '#FF9800', '#FFC107', '#FFEB3B',
    '#CDDC39', '#4CAF50', '#009688', '#00BCD4', '#03A9F4', '#2196F3',
    '#3F51B5', '#9C27B0', '#E91E63', '#795548'
  ];
}

@ComponentV2
struct TerminalColorPickerDialog {
  @Param p: TerminalColorPickerParams = new TerminalColorPickerParams();
  @Local text: string = '';
  @Local preview: string = '';

  aboutToAppear(): void {
    this.text = this.p.initialColor;
    this.preview = this.normalize(this.text);
  }

  private normalize(raw: string): string {
    return TerminalUiConfig.parseColorWithFallback(raw, this.p.initialColor);
  }

  private confirm(): void {
    this.p.onResult(this.preview);
  }

  build() {
    Column() {
      Text(this.p.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Row({ space: 12 }) {
        // 预览色块
        Column()
          .width(32)
          .height(32)
          .borderRadius(8)
          .backgroundColor(this.preview)
          .border({ width: 1, color: AppTheme.current().divider })
        TextInput({ text: this.text, placeholder: L10n.t('terminal_color_hint', '#RRGGBB 或 #AARRGGBB') })
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .placeholderColor(AppTheme.current().hint)
          .backgroundColor(AppTheme.current().inputFill)
          .borderRadius(8)
          .border({ width: 1, color: AppTheme.current().inputBorder })
          .height(40)
          .layoutWeight(1)
          .onChange((v: string): void => {
            this.text = v;
            this.preview = this.normalize(v);
          })
      }
      .margin({ top: 14 })
      .width('100%')

      // 预设色网格
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(presetColors(), (color: string) => {
          Column()
            .width(32)
            .height(32)
            .borderRadius(8)
            .backgroundColor(color)
            .border({ width: 1, color: AppTheme.current().divider })
            .margin({ right: 8, top: 8 })
            .onClick((): void => {
              this.text = color;
              this.preview = color;
            })
        }, (color: string): string => color)
      }
      .width('100%')
      .margin({ top: 14 })

      Row({ space: 8 }) {
        Button(L10n.t('cancel', '取消'))
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick((): void => {
            this.p.onResult(undefined);
          })
        Button(L10n.t('ok', '确定'))
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .onClick((): void => {
            this.confirm();
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(AppTheme.current().surfaceBg)
    .borderRadius(24)
    .width('80%')
    .constraintSize({ minWidth: 300 })
  }
}

const terminalColorPickerBuilder: WrappedBuilder<[TerminalColorPickerParams]> =
  wrapBuilder(TerminalColorPickerBuilderFn);

@Builder
function TerminalColorPickerBuilderFn(params: TerminalColorPickerParams) {
  TerminalColorPickerDialog({ p: params })
}

/**
 * 弹出颜色选择弹窗；确定返回归一化 hex（#RRGGBB/#AARRGGBB），取消/遮罩返回 undefined。
 */
export function showTerminalColorPicker(title: string, initialHex: string): Promise<string | undefined> {
  return new Promise<string | undefined>((resolve: (v: string | undefined) => void) => {
    const p = new TerminalColorPickerParams();
    p.title = title;
    p.initialColor = initialHex;
    try {
      DialogUtil.openCustom<TerminalColorPickerParams>(p, terminalColorPickerBuilder, true,
        (r: DialogResult | undefined): void => {
          resolve(typeof r === 'string' && r.length > 0 ? r : undefined);
        });
    } catch (e) {
      console.error(`${TAG} show failed: ${e}`);
      resolve(undefined);
    }
  });
}
