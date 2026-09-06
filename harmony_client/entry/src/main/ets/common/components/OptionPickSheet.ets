import { L10n } from '../../core/localization/L10n';
import { AppTheme } from '../../core/theme/AppTheme';
import { SheetHandle, SheetListItem, SheetParamsBase, SheetUtil } from '../../common/SheetUtil';

export class PickOption {
  key: string = '';
  label: string = '';

  constructor(key: string, label: string) {
    this.key = key;
    this.label = label;
  }
}

class OptionPickSheetParams extends SheetParamsBase {
  title: string = '';
  options: PickOption[] = [];
  selectedKey: string = '';
  onPicked: (key: string) => void = (_k: string): void => {
  };
}

@Builder
function OptionPickSheetContent(p: OptionPickSheetParams) {
  OptionPickSheetInner({ p: p })
}

@ComponentV2
struct OptionPickSheetInner {
  @Param p: OptionPickSheetParams = new OptionPickSheetParams();

  build() {
    Column() {
      SheetHandle()
      if (this.p.title.length > 0) {
        Text(this.p.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.current().onSurface)
          .width('100%')
          .padding({ left: 20, right: 20, top: 6, bottom: 8 })
      }
      List({ space: 0 }) {
        ForEach(this.p.options, (opt: PickOption): void => {
          ListItem() {
            SheetListItem({
              showIcon: false,
              title: opt.label,
              showCheck: true,
              checked: opt.key === this.p.selectedKey,
              onSelect: (): void => {
                this.p.close();
                this.p.onPicked(opt.key);
              }
            })
          }
        }, (opt: PickOption): string => opt.key)
      }
      .width('100%')
      .constraintSize({ maxHeight: 380 })
      .scrollBar(BarState.Auto)
      .padding({ bottom: 20 })
    }
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor(AppTheme.current().surfaceBg)
  }
}

/**
 * 通用单选项底部弹层（对齐 Flutter showModalBottomSheet + ListTile 选择）。
 * 取消时 onPicked 不回调。
 */
export function showOptionPickSheet(title: string, options: PickOption[], selectedKey: string,
  onPicked: (key: string) => void): void {
  const p = new OptionPickSheetParams();
  p.title = title;
  p.options = options;
  p.selectedKey = selectedKey;
  p.onPicked = onPicked;
  SheetUtil.present(p, wrapBuilder(OptionPickSheetContent));
}

/** 常用文案快捷构造（L10n key + 中文兜底） */
export function l10nOption(key: string, fallback: string): PickOption {
  return new PickOption(key, L10n.t(key, fallback));
}
