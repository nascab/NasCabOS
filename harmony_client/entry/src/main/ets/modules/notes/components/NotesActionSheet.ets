import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { SheetParamsBase, SheetUtil } from '../../../common/SheetUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'NotesActionSheet';

/** 操作项（key 由调用方定义，danger 显示红色；color 为前置色点 #RRGGBB，checked 显示对勾） */
export class NotesActionItem {
  key: string = '';
  label: string = '';
  danger: boolean = false;
  checked: boolean = false;
  color: string = '';

  constructor(key: string, label: string, danger: boolean = false, checked: boolean = false) {
    this.key = key;
    this.label = label;
    this.danger = danger;
    this.checked = checked;
  }
}

class NotesActionSheetParams extends SheetParamsBase {
  title: string = '';
  items: NotesActionItem[] = [];
  onSelected: (key: string) => void = (_key: string): void => {
  };
}

/**
 * 通用操作列表底部弹层（对齐 Flutter PopupMenu/showModalBottomSheet 列表选择样式）。
 * 笔记卡片菜单 / 编辑页更多菜单 / 标签过滤 / 图片操作共用。
 */
@ComponentV2
export struct NotesActionSheet {
  @Param params: NotesActionSheetParams = new NotesActionSheetParams();

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column() {
      // 拖拽指示条
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.palette().divider)
        .margin({ top: 10, bottom: 6 })

      if (this.params.title.length > 0) {
        Text(this.params.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ left: 18, right: 18, top: 6, bottom: 8 })
      }

      List() {
        ForEach(this.params.items, (item: NotesActionItem, index: number) => {
          ListItem() {
            Row({ space: 12 }) {
              if (item.color.length > 0) {
                Text()
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .backgroundColor(item.color)
                  .border({ width: 1, color: this.palette().divider })
              } else {
                Text()
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .border({ width: 1, color: this.palette().divider })
              }
              Text(item.label)
                .fontSize(15)
                .fontColor(item.danger ? this.palette().error : this.palette().onSurface)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.checked) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([this.palette().primary])
              }
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 13, bottom: 13 })
            .onClick(() => {
              this.params.onSelected(item.key);
              this.params.close();
            })
          }
        }, (item: NotesActionItem, index: number) => `${item.key}_${index}`)
      }
      .width('100%')
      .height(Math.min(this.params.items.length * 46 + 8, 380))
      .scrollBar(BarState.Off)

      Row()
        .height(10)
    }
    .width('100%')
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius({ topLeft: 18, topRight: 18 })
  }
}

const notesActionSheetBuilder: WrappedBuilder<[NotesActionSheetParams]> =
  wrapBuilder(NotesActionSheetBuilderFn);

@Builder
function NotesActionSheetBuilderFn(params: NotesActionSheetParams) {
  NotesActionSheet({ params: params })
}

/**
 * 弹出操作列表弹层；选中返回 key，取消/遮罩返回 ''（Promise 风格封装）。
 */
export function showNotesActionSheet(title: string, items: NotesActionItem[]): Promise<string> {
  return new Promise<string>((resolve: (v: string) => void) => {
    const p = new NotesActionSheetParams();
    p.title = title;
    p.items = items;
    p.onSelected = (key: string): void => {
      resolve(key);
    };
    p.onDismissed = (): void => {
      resolve('');
    };
    try {
      SheetUtil.present<NotesActionSheetParams>(p, notesActionSheetBuilder);
    } catch (e) {
      hilog.error(0x0000, TAG, 'showNotesActionSheet failed: %{public}s', JSON.stringify(e));
      resolve('');
    }
  });
}

// ===== 图片调整大小弹层（对齐 Flutter ImageResizer） =====

class NotesImageResizeParams extends SheetParamsBase {
  initialWidth: number = 0;
  initialHeight: number = 0;
  onConfirm: (width: number, height: number) => void = (_w: number, _h: number): void => {
  };
}

/**
 * 图片尺寸调整弹层（对齐 Flutter ImageResizer 样式：宽/高输入 + Resize 按钮）。
 */
@ComponentV2
export struct NotesImageResizeSheet {
  @Local widthText: string = '';
  @Local heightText: string = '';
  @Param params: NotesImageResizeParams = new NotesImageResizeParams();

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  aboutToAppear(): void {
    this.widthText = this.params.initialWidth > 0 ? `${Math.round(this.params.initialWidth)}` : '';
    this.heightText = this.params.initialHeight > 0 ? `${Math.round(this.params.initialHeight)}` : '';
  }

  private confirm(): void {
    const w = Number(this.widthText.trim());
    const h = Number(this.heightText.trim());
    this.params.onConfirm(
      Number.isFinite(w) && w > 0 ? w : 0,
      Number.isFinite(h) && h > 0 ? h : 0);
    this.params.close();
  }

  build() {
    Column({ space: 14 }) {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.palette().divider)
        .margin({ top: 10 })

      Text(L10n.t('resize'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().onSurface)

      Row({ space: 10 }) {
        TextInput({ text: this.widthText, placeholder: 'width' })
          .type(InputType.NUMBER_DECIMAL)
          .fontSize(15)
          .fontColor(this.palette().onSurface)
          .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.4))
          .height(42)
          .layoutWeight(1)
          .borderRadius(10)
          .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.05))
          .onChange((v: string): void => {
            this.widthText = v;
          })
        TextInput({ text: this.heightText, placeholder: 'height' })
          .type(InputType.NUMBER_DECIMAL)
          .fontSize(15)
          .fontColor(this.palette().onSurface)
          .placeholderColor(AppTheme.withAlpha(this.palette().onSurface, 0.4))
          .height(42)
          .layoutWeight(1)
          .borderRadius(10)
          .backgroundColor(AppTheme.withAlpha(this.palette().onSurface, 0.05))
          .onChange((v: string): void => {
            this.heightText = v;
          })
      }
      .width('100%')

      Button(L10n.t('resize'))
        .width('100%')
        .height(44)
        .fontSize(15)
        .type(ButtonType.Capsule)
        .backgroundColor(this.palette().primary)
        .fontColor(this.palette().buttonText)
        .onClick(() => {
          this.confirm();
        })

      Row()
        .height(10)
    }
    .width('100%')
    .padding({ left: 18, right: 18 })
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius({ topLeft: 18, topRight: 18 })
  }
}

const notesImageResizeBuilder: WrappedBuilder<[NotesImageResizeParams]> =
  wrapBuilder(NotesImageResizeBuilderFn);

@Builder
function NotesImageResizeBuilderFn(params: NotesImageResizeParams) {
  NotesImageResizeSheet({ params: params })
}

/** 弹出图片尺寸调整弹层（确认返回宽高，任一为 0 表示该项保持原值；取消返回 null） */
export function showNotesImageResizeSheet(initialWidth: number, initialHeight: number):
  Promise<[number, number] | null> {
  return new Promise<[number, number] | null>((resolve: (v: [number, number] | null) => void) => {
    const p = new NotesImageResizeParams();
    p.initialWidth = initialWidth;
    p.initialHeight = initialHeight;
    p.onConfirm = (w: number, h: number): void => {
      resolve([w, h]);
    };
    p.onDismissed = (): void => {
      resolve(null);
    };
    try {
      SheetUtil.present<NotesImageResizeParams>(p, notesImageResizeBuilder);
    } catch (e) {
      hilog.error(0x0000, TAG, 'showNotesImageResizeSheet failed: %{public}s', JSON.stringify(e));
      resolve(null);
    }
  });
}
