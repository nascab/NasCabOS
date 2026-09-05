import { ComponentContent, promptAction } from '@kit.ArkUI';
import { UIContext, PromptAction } from '@ohos.arkui.UIContext';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { L10n } from '../core/localization/L10n';
import { AppTheme } from '../core/theme/AppTheme';

const DOMAIN = 0x0000;

/** 对话框结果值（对齐 Flutter DialogUtil 各方法返回语义） */
export type DialogResult = boolean | number | string | undefined;

type ResultCallback = (result: DialogResult) => void;

/** 所有弹窗参数基类：统一持有结果回调（点击按钮/遮罩时触发） */
export class DialogParamsBase {
  onResult: ResultCallback = (_r: DialogResult): void => {
  };
}

/** 带勾选的选项列表项（用于主题/语言等选择弹窗） */
export class SelectItem {
  label: string = '';
  icon: Resource | undefined = undefined;

  constructor(label: string, icon?: Resource) {
    this.label = label;
    if (icon !== undefined) {
      this.icon = icon;
    }
  }
}

// ===== 各弹窗参数对象（builder 与组件之间共享） =====

@ObservedV2
export class LoadingDialogParams extends DialogParamsBase {
  @Trace message: string = '';
}

export class SelectDialogParams extends DialogParamsBase {
  title: string = '';
  items: SelectItem[] = [];
  selectedIndex: number = -1;
}

export class ConfirmDialogParams extends DialogParamsBase {
  title: string = '';
  content: string = '';
  confirmText: string = '';
  cancelText: string = '';
}

export class ThreeButtonDialogParams extends DialogParamsBase {
  title: string = '';
  content: string = '';
  cancelText: string = '';
  option1Text: string = '';
  option2Text: string = '';
}

export class InfoDialogParams extends DialogParamsBase {
  title: string = '';
  content: string = '';
  buttonText: string = '';
}

export class PasswordInputDialogParams extends DialogParamsBase {
  title: string = '';
  message: string = '';
  confirmText: string = '';
  cancelText: string = '';
  hintText: string = '';
}

export class InputDialogParams extends DialogParamsBase {
  title: string = '';
  content: string = '';
  initialValue: string = '';
  confirmText: string = '';
  cancelText: string = '';
  validator: ((value: string) => string | undefined) | undefined = undefined;
}

// ===== 弹窗内容 builder =====

@Builder
function LoadingDialogContent(p: LoadingDialogParams) {
  Row({ space: 16 }) {
    LoadingProgress()
      .width(36)
      .height(36)
      .color(AppTheme.current().primary)
    Text(p.message)
      .fontSize(14)
      .fontColor(AppTheme.current().onSurface)
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .padding({ left: 20, right: 20, top: 16, bottom: 16 })
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius(12)
  .constraintSize({ maxWidth: 320 })
  .justifyContent(FlexAlign.Center)
}

@Builder
function SelectDialogContent(p: SelectDialogParams) {
  Column() {
    Text(p.title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
      .margin({ bottom: 8 })
    Scroll() {
      Column() {
        ForEach(p.items, (item: SelectItem, idx: number) => {
          Row({ space: 12 }) {
            if (item.icon !== undefined) {
              SymbolGlyph(item.icon)
                .fontSize(20)
                .fontColor([AppTheme.current().onSurface])
            }
            Text(item.label)
              .fontSize(15)
              .fontColor(AppTheme.current().onSurface)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (idx === p.selectedIndex) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(18)
                .fontColor([AppTheme.current().primary])
            }
          }
          .width('100%')
          .padding({ left: 4, right: 4, top: 12, bottom: 12 })
          .onClick(() => {
            p.onResult(idx);
          })
        }, (item: SelectItem, idx: number) => `${idx}_${item.label}`)
      }
      .width('100%')
    }
    .scrollBar(BarState.Off)
    .constraintSize({ maxHeight: 420 })
    .width('100%')
  }
  .padding(20)
  .backgroundColor(AppTheme.current().surfaceBg)
  .borderRadius(24)
  .width('80%')
  .constraintSize({ minWidth: 280 })
}

@Builder
function ConfirmDialogContent(p: ConfirmDialogParams) {
  Column() {
    Text(p.title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
    Text(p.content)
      .fontSize(14)
      .fontColor(AppTheme.current().onSurface)
      .margin({ top: 12 })
      .width('100%')
    Row({ space: 8 }) {
      Button(p.cancelText)
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .backgroundColor(Color.Transparent)
        .height(36)
        .onClick(() => {
          p.onResult(false);
        })
      Button(p.confirmText)
        .fontSize(14)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().buttonBg)
        .height(36)
        .onClick(() => {
          p.onResult(true);
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
  .constraintSize({ minWidth: 280 })
}

@Builder
function ThreeButtonDialogContent(p: ThreeButtonDialogParams) {
  Column() {
    Text(p.title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
    Text(p.content)
      .fontSize(14)
      .fontColor(AppTheme.current().onSurface)
      .margin({ top: 12 })
      .width('100%')
    Row({ space: 8 }) {
      Button(p.cancelText)
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .backgroundColor(Color.Transparent)
        .height(36)
        .onClick(() => {
          p.onResult(undefined);
        })
      Button(p.option1Text)
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .backgroundColor(Color.Transparent)
        .height(36)
        .onClick(() => {
          p.onResult(0);
        })
      Button(p.option2Text)
        .fontSize(14)
        .fontColor(AppTheme.current().buttonText)
        .backgroundColor(AppTheme.current().primary)
        .height(36)
        .onClick(() => {
          p.onResult(1);
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
  .constraintSize({ minWidth: 280 })
}

@Builder
function InfoDialogContent(p: InfoDialogParams) {
  Column() {
    Text(p.title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.current().onSurface)
    Scroll() {
      Column() {
        Text(p.content)
          .fontSize(14)
          .fontColor(AppTheme.current().onSurface)
          .copyOption(CopyOptions.InApp)
          .width('100%')
      }
      .width('100%')
    }
    .constraintSize({ maxHeight: 400 })
    .margin({ top: 12 })
    .width('100%')
    Row() {
      Button(p.buttonText)
        .fontSize(14)
        .fontColor(AppTheme.current().primary)
        .backgroundColor(Color.Transparent)
        .height(36)
        .onClick(() => {
          p.onResult(true);
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
  .constraintSize({ minWidth: 280 })
}

@Builder
function PasswordDialogContent(p: PasswordInputDialogParams) {
  PasswordInputInner({ p: p })
}

@Builder
function InputDialogContent(p: InputDialogParams) {
  InputDialogInner({ p: p })
}

/** 密码输入弹窗内部组件（维护输入状态） */
@ComponentV2
struct PasswordInputInner {
  @Param p: PasswordInputDialogParams = new PasswordInputDialogParams();
  @Local password: string = '';

  build() {
    Column() {
      Text(this.p.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Text(this.p.message)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .margin({ top: 12 })
        .width('100%')
      TextInput({ placeholder: this.p.hintText })
        .type(InputType.Password)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 16 })
        .width('100%')
        .onChange((v: string) => {
          this.password = v;
        })
      Row({ space: 8 }) {
        Button(this.p.cancelText)
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText)
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .enabled(this.password.trim().length > 0)
          .opacity(this.password.trim().length > 0 ? 1 : 0.4)
          .onClick(() => {
            this.p.onResult(this.password.trim());
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
    .constraintSize({ minWidth: 280 })
  }
}

/** 通用输入弹窗内部组件（维护输入与校验错误状态） */
@ComponentV2
struct InputDialogInner {
  @Param p: InputDialogParams = new InputDialogParams();
  @Local text: string = '';
  @Local errorText: string = '';

  aboutToAppear(): void {
    this.text = this.p.initialValue;
    this.errorText = '';
  }

  private confirm(): void {
    const value = this.text.trim();
    const err = this.p.validator !== undefined ? this.p.validator(value) : undefined;
    if (err === undefined) {
      this.p.onResult(value);
    } else {
      this.errorText = err;
    }
  }

  build() {
    Column() {
      Text(this.p.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.current().onSurface)
      Text(this.p.content)
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .margin({ top: 12 })
        .width('100%')
      TextInput({ text: this.text })
        .fontSize(14)
        .fontColor(AppTheme.current().onSurface)
        .placeholderColor(AppTheme.current().hint)
        .backgroundColor(AppTheme.current().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.current().inputBorder })
        .height(42)
        .margin({ top: 16 })
        .width('100%')
        .onChange((v: string) => {
          this.text = v;
          this.errorText = this.p.validator !== undefined ? (this.p.validator(v) ?? '') : '';
        })
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(AppTheme.current().error)
          .margin({ top: 6 })
          .width('100%')
      }
      Row({ space: 8 }) {
        Button(this.p.cancelText)
          .fontSize(14)
          .fontColor(AppTheme.current().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(this.p.confirmText)
          .fontSize(14)
          .fontColor(AppTheme.current().buttonText)
          .backgroundColor(AppTheme.current().buttonBg)
          .height(36)
          .onClick(() => {
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
    .constraintSize({ minWidth: 280 })
  }
}

/**
 * 统一弹窗工具类（对齐 Flutter DialogUtil）：
 * showLoading/dismissLoading（引用计数）、showErrorDialog、showInfoDialog、
 * showConfirmDialog、showConfirmThreeButtonsDialog、showSelectDialog、
 * showPasswordInputDialog、showInputDialog。
 * 使用前需在入口页调用 DialogUtil.init(uiContext)。
 * 实现方式：ComponentContent + PromptAction.openCustomDialog（官方推荐）。
 */
export class DialogUtil {
  private static uiContext: UIContext | undefined = undefined;
  private static loadingRefCount: number = 0;
  private static loadingOpen: boolean = false;
  private static loadingContent: ComponentContent<LoadingDialogParams> | undefined = undefined;
  private static loadingParams: LoadingDialogParams = new LoadingDialogParams();

  static init(uiContext: UIContext): void {
    DialogUtil.uiContext = uiContext;
  }

  private static ui(): UIContext {
    if (!DialogUtil.uiContext) {
      throw new Error('DialogUtil not initialized');
    }
    return DialogUtil.uiContext;
  }

  private static prompt(): PromptAction {
    return DialogUtil.ui().getPromptAction();
  }

  /**
   * 打开弹窗通用流程：绑定 params.onResult → 关闭弹窗 → resolve → 业务回调。
   * barrier 关闭（点遮罩/返回键）时以 undefined 结束。
   */
  private static present<T extends DialogParamsBase>(
    params: T,
    builderFn: WrappedBuilder<[T]>,
    barrierDismissible: boolean,
    resolve: (v: DialogResult | undefined) => void,
    onAction?: (v: DialogResult) => void
  ): void {
    let done: boolean = false;
    const finish = (v: DialogResult | undefined): void => {
      if (!done) {
        done = true;
        resolve(v);
      }
    };
    try {
      const content = new ComponentContent<T>(DialogUtil.ui(), builderFn, params);
      params.onResult = (r: DialogResult): void => {
        finish(r);
        DialogUtil.closeContent(content);
        if (onAction) {
          onAction(r);
        }
      };
      const options: promptAction.BaseDialogOptions = {
        isModal: true,
        autoCancel: barrierDismissible,
        alignment: DialogAlignment.Center,
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
          finish(undefined);
        }
      };
      DialogUtil.prompt().openCustomDialog(content, options).catch((e: Object): void => {
        hilog.error(DOMAIN, 'NasCab', 'openCustomDialog failed: %{public}s', JSON.stringify(e));
        finish(undefined);
      });
    } catch (e) {
      hilog.error(DOMAIN, 'NasCab', 'present dialog failed: %{public}s', JSON.stringify(e));
      finish(undefined);
    }
  }

  private static closeContent<T extends Object>(content: ComponentContent<T>): void {
    try {
      DialogUtil.prompt().closeCustomDialog(content);
    } catch (_e) {
      // 弹窗可能已关闭
    }
  }

  /** 显示加载弹窗（引用计数，重复调用仅更新文案） */
  static async showLoading(message: string = '', barrierDismissible: boolean = false): Promise<void> {
    DialogUtil.loadingRefCount++;
    DialogUtil.loadingParams.message = message.length > 0 ? message : L10n.loading;
    if (DialogUtil.loadingOpen) {
      return;
    }
    try {
      const content =
        new ComponentContent<LoadingDialogParams>(DialogUtil.ui(), wrapBuilder(LoadingDialogContent),
          DialogUtil.loadingParams);
      DialogUtil.loadingContent = content;
      DialogUtil.loadingOpen = true;
      const options: promptAction.BaseDialogOptions = {
        isModal: true,
        autoCancel: barrierDismissible,
        alignment: DialogAlignment.Center,
        maskColor: '#59000000',
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
          DialogUtil.loadingRefCount = 0;
          DialogUtil.loadingOpen = false;
          DialogUtil.loadingContent = undefined;
        }
      };
      await DialogUtil.prompt().openCustomDialog(content, options);
    } catch (e) {
      hilog.error(DOMAIN, 'NasCab', 'showLoading failed: %{public}s', JSON.stringify(e));
      DialogUtil.loadingOpen = false;
      DialogUtil.loadingContent = undefined;
    }
  }

  /** 关闭加载弹窗（引用计数；force 强制清零） */
  static async dismissLoading(force: boolean = false): Promise<void> {
    if (force) {
      DialogUtil.loadingRefCount = 0;
    } else if (DialogUtil.loadingRefCount > 0) {
      DialogUtil.loadingRefCount--;
    }
    if (DialogUtil.loadingRefCount > 0) {
      return;
    }
    const content = DialogUtil.loadingContent;
    DialogUtil.loadingContent = undefined;
    DialogUtil.loadingOpen = false;
    if (content) {
      DialogUtil.closeContent(content);
    }
  }

  /** 错误弹窗（单 OK 按钮） */
  static showErrorDialog(message: string, title: string = ''): Promise<DialogResult | undefined> {
    return DialogUtil.showInfoDialog(title.length > 0 ? title : L10n.error, message);
  }

  /** 信息提示弹窗（单按钮，内容长时可滚动、可复制） */
  static showInfoDialog(title: string, content: string,
    buttonText: string = '', onPressed?: () => void): Promise<DialogResult | undefined> {
    return new Promise<DialogResult | undefined>((resolve: (v: DialogResult | undefined) => void) => {
      const p = new InfoDialogParams();
      p.title = title;
      p.content = content;
      p.buttonText = buttonText.length > 0 ? buttonText : L10n.ok;
      DialogUtil.present(p, wrapBuilder(InfoDialogContent), true, resolve, (_r: DialogResult): void => {
        if (onPressed) {
          onPressed();
        }
      });
    });
  }

  /** 确认弹窗：确定 → true，取消/遮罩 → false/undefined */
  static showConfirmDialog(title: string, content: string,
    onConfirm?: () => void, confirmText: string = '', cancelText: string = '',
    barrierDismissible: boolean = true): Promise<DialogResult | undefined> {
    return new Promise<DialogResult | undefined>((resolve: (v: DialogResult | undefined) => void) => {
      const p = new ConfirmDialogParams();
      p.title = title;
      p.content = content;
      p.confirmText = confirmText.length > 0 ? confirmText : L10n.ok;
      p.cancelText = cancelText.length > 0 ? cancelText : L10n.cancel;
      DialogUtil.present(p, wrapBuilder(ConfirmDialogContent), barrierDismissible, resolve,
        (r: DialogResult): void => {
          if (r === true && onConfirm) {
            onConfirm();
          }
        });
    });
  }

  /** 三按钮确认弹窗：返回 0（选项1）/ 1（选项2）/ undefined（取消） */
  static showConfirmThreeButtonsDialog(title: string, content: string,
    onOption1?: () => void, onOption2?: () => void,
    cancelText: string = '', option1Text: string = '', option2Text: string = '',
    barrierDismissible: boolean = true): Promise<DialogResult | undefined> {
    return new Promise<DialogResult | undefined>((resolve: (v: DialogResult | undefined) => void) => {
      const p = new ThreeButtonDialogParams();
      p.title = title;
      p.content = content;
      p.cancelText = cancelText.length > 0 ? cancelText : L10n.cancel;
      p.option1Text = option1Text.length > 0 ? option1Text : L10n.ok;
      p.option2Text = option2Text.length > 0 ? option2Text : L10n.ok;
      DialogUtil.present(p, wrapBuilder(ThreeButtonDialogContent), barrierDismissible, resolve,
        (r: DialogResult): void => {
          if (r === 0 && onOption1) {
            onOption1();
          } else if (r === 1 && onOption2) {
            onOption2();
          }
        });
    });
  }

  /** 选项列表弹窗（带勾选，用于主题/语言选择）：返回选中下标 */
  static showSelectDialog(title: string, items: SelectItem[], selectedIndex: number,
    onSelect?: (index: number) => void,
    barrierDismissible: boolean = true): Promise<DialogResult | undefined> {
    return new Promise<DialogResult | undefined>((resolve: (v: DialogResult | undefined) => void) => {
      const p = new SelectDialogParams();
      p.title = title;
      p.items = items;
      p.selectedIndex = selectedIndex;
      DialogUtil.present(p, wrapBuilder(SelectDialogContent), barrierDismissible, resolve,
        (r: DialogResult): void => {
          if (typeof r === 'number' && onSelect) {
            onSelect(r);
          }
        });
    });
  }

  /** 密码输入弹窗：返回输入的密码或 undefined */
  static showPasswordInputDialogForResult(title: string, message: string,
    confirmText: string = '', cancelText: string = '',
    hintText: string = ''): Promise<DialogResult | undefined> {
    return new Promise<DialogResult | undefined>((resolve: (v: DialogResult | undefined) => void) => {
      const p = new PasswordInputDialogParams();
      p.title = title;
      p.message = message;
      p.confirmText = confirmText.length > 0 ? confirmText : L10n.ok;
      p.cancelText = cancelText.length > 0 ? cancelText : L10n.cancel;
      p.hintText = hintText.length > 0 ? hintText : L10n.inputPlease;
      DialogUtil.present(p, wrapBuilder(PasswordDialogContent), true, resolve);
    });
  }

  /** 密码输入弹窗（回调式） */
  static showPasswordInputDialog(title: string, message: string,
    onConfirm: (password: string) => void,
    confirmText: string = '', cancelText: string = '', hintText: string = ''): void {
    DialogUtil.showPasswordInputDialogForResult(title, message, confirmText, cancelText, hintText)
      .then((password: DialogResult | undefined): void => {
        if (typeof password === 'string' && password.trim().length > 0) {
          onConfirm(password);
        }
      });
  }

  /** 通用输入弹窗（带校验）：返回输入文本或 undefined */
  static showInputDialog(title: string, content: string,
    initialValue: string = '', confirmText: string = '', cancelText: string = '',
    validator?: (value: string) => string | undefined): Promise<DialogResult | undefined> {
    return new Promise<DialogResult | undefined>((resolve: (v: DialogResult | undefined) => void) => {
      const p = new InputDialogParams();
      p.title = title;
      p.content = content;
      p.initialValue = initialValue;
      p.confirmText = confirmText.length > 0 ? confirmText : L10n.ok;
      p.cancelText = cancelText.length > 0 ? cancelText : L10n.cancel;
      p.validator = validator;
      DialogUtil.present(p, wrapBuilder(InputDialogContent), true, resolve);
    });
  }
}
