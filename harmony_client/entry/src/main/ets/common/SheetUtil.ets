import { ComponentContent, promptAction } from '@kit.ArkUI';
import { UIContext, PromptAction } from '@ohos.arkui.UIContext';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme } from '../core/theme/AppTheme';

const DOMAIN = 0x0000;

/** 底部弹层参数基类：内容通过 close() 关闭；onDismissed 在弹层关闭（含点遮罩/返回键）后触发一次 */
export class SheetParamsBase {
  close: () => void = () => {
  };
  onDismissed: () => void = () => {
  };
}

/**
 * 底部弹层工具类（对齐 Flutter showModalBottomSheet / Get.bottomSheet）：
 * ComponentContent + openCustomDialog（底部对齐、可上滑圆角面板），统一管理关闭与回调。
 * 使用前需调用 SheetUtil.init(uiContext)。
 */
export class SheetUtil {
  private static uiContext: UIContext | undefined = undefined;

  static init(uiContext: UIContext): void {
    SheetUtil.uiContext = uiContext;
  }

  private static prompt(): PromptAction {
    if (!SheetUtil.uiContext) {
      throw new Error('SheetUtil not initialized');
    }
    return SheetUtil.uiContext.getPromptAction();
  }

  /** 打开底部弹层；内容中调用 params.close() 关闭 */
  static present<T extends SheetParamsBase>(params: T, builderFn: WrappedBuilder<[T]>): void {
    let closed = false;
    const closeOnce = (): void => {
      if (closed) {
        return;
      }
      closed = true;
      params.onDismissed();
    };
    try {
      const content = new ComponentContent<T>(SheetUtil.uiContext!, builderFn, params);
      params.close = (): void => {
        SheetUtil.closeContent(content);
      };
      const options: promptAction.BaseDialogOptions = {
        isModal: true,
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        transition: SheetUtil.defaultTransition(),
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
          closeOnce();
        }
      };
      SheetUtil.prompt().openCustomDialog(content, options).catch((e: Object): void => {
        hilog.error(DOMAIN, 'NasCab', 'openCustomSheet failed: %{public}s', JSON.stringify(e));
        closeOnce();
      });
    } catch (e) {
      hilog.error(DOMAIN, 'NasCab', 'present sheet failed: %{public}s', JSON.stringify(e));
      closeOnce();
    }
  }

  private static closeContent<T extends Object>(content: ComponentContent<T>): void {
    try {
      SheetUtil.prompt().closeCustomDialog(content);
    } catch (_e) {
      // 弹层可能已关闭
    }
  }

  private static defaultTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: 1000 }).animation({ duration: 250, curve: Curve.Friction }),
      TransitionEffect.translate({ y: 1000 }).animation({ duration: 200, curve: Curve.Friction })
    );
  }

  /** 弹层面板容器样式（供各 sheet 内容复用） */
  static panelBg(): string {
    return AppTheme.current().surfaceBg;
  }
}

/** 弹层顶部拖拽指示条 */
@ComponentV2
export struct SheetHandle {
  build() {
    Column()
      .width(40)
      .height(4)
      .borderRadius(2)
      .backgroundColor(AppTheme.current().divider)
      .margin({ top: 8, bottom: 8 })
  }
}

/** 弹层内标准列表项（图标 + 标题，对齐 Flutter ListTile） */
@ComponentV2
export struct SheetListItem {
  @Param icon: Resource = $r('sys.symbol.plus');
  @Param showIcon: boolean = true;
  @Param title: string = '';
  @Param titleColor: string = '';
  @Param iconColor: string = '';
  @Param showCheck: boolean = false;
  @Param checked: boolean = false;
  @Param onSelect: () => void = () => {
  };

  build() {
    Row({ space: 14 }) {
      if (this.showIcon) {
        SymbolGlyph(this.icon)
          .fontSize(22)
          .fontColor([this.iconColor.length > 0 ? this.iconColor : AppTheme.current().onSurface])
      }
      Text(this.title)
        .fontSize(15)
        .fontColor(this.titleColor.length > 0 ? this.titleColor : AppTheme.current().onSurface)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.showCheck && this.checked) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([AppTheme.current().primary])
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 13, bottom: 13 })
    .onClick(() => {
      this.onSelect();
    })
  }
}
