import { L10n } from '../../../core/localization/L10n';

/**
 * 认证模块主题色统一引用层。
 * 颜色定义在 resources/base/element/color.json 与 resources/dark/element/color.json。
 * 与 Flutter 一致：认证模块所有页面强制使用 darkTheme，因此浅色/深色模式下取值相同（固定暗色）。
 */
export class AuthTheme {
  /** 页面脚手架背景，对应 scaffoldBackgroundColor */
  static readonly pageBg: Resource = $r('app.color.auth_scaffold_bg');
  /** 认证中心半透明卡片，对应 scaffoldBackgroundColor.withValues(alpha:0.6) */
  static readonly cardBg: Resource = $r('app.color.auth_card_bg');
  /** 对话框/嵌套表面色，对应 colorScheme.surface */
  static readonly dialogBg: Resource = $r('app.color.auth_surface');
  /** 密保问题容器背景，对应 surface.withValues(alpha:0.5) */
  static readonly questionBg: Resource = $r('app.color.auth_question_bg');
  /** 嵌套卡片（服务器列表项/添加按钮），对应 CustomColors.nestedCardColor */
  static readonly nestedCard: Resource = $r('app.color.auth_nested_card');
  /** 主题主色，对应 colorScheme.primary */
  static readonly primary: Resource = $r('app.color.auth_primary');
  /** 主色 60% 透明，对应 primary.withValues(alpha:0.6) */
  static readonly primary60: Resource = $r('app.color.auth_primary_60');
  /** 次要强调色（本机标签），对应 colorScheme.secondary */
  static readonly secondary: Resource = $r('app.color.auth_secondary');
  /** 按钮背景，对应 elevatedButtonTheme.backgroundColor */
  static readonly buttonBg: Resource = $r('app.color.auth_button_bg');
  /** 按钮禁用背景，对应 disabledBackgroundColor */
  static readonly buttonDisabledBg: Resource = $r('app.color.auth_button_disabled_bg');
  /** 按钮禁用文字，对应 disabledForegroundColor */
  static readonly buttonDisabledText: Resource = $r('app.color.auth_button_disabled_text');
  /** 主要文字，对应 colorScheme.onSurface */
  static readonly textMain: Resource = $r('app.color.auth_text_main');
  /** 次要文字，对应 onSurface.withValues(alpha:0.7) */
  static readonly textSecondary: Resource = $r('app.color.auth_text_secondary');
  /** 提示文字，对应 onSurface.withValues(alpha:0.6) */
  static readonly textHint: Resource = $r('app.color.auth_text_hint');
  /** 错误色，对应 colorScheme.error */
  static readonly errorColor: Resource = $r('app.color.auth_error');
  /** 分割线，对应 dividerColor */
  static readonly divider: Resource = $r('app.color.auth_divider');
  /** 输入框背景，对应 inputDecorationTheme.fillColor */
  static readonly inputBg: Resource = $r('app.color.auth_input_bg');
  /** 输入框边框，对应 inputDecorationTheme border */
  static readonly inputBorder: Resource = $r('app.color.auth_input_border');
  /** 遮罩（黑色 35%），对应 DialogUtil 遮罩 */
  static readonly mask: Resource = $r('app.color.auth_mask');
}

/** 通用确认/信息对话框状态 */
@ObservedV2
export class ConfirmDialogState {
  @Trace visible: boolean = false;
  @Trace title: string = '';
  @Trace message: string = '';
  @Trace confirmText: string = L10n.ok;
  @Trace cancelText: string = L10n.cancel;
  onConfirm: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  showInfo(title: string, message: string, onConfirm?: () => void): void {
    this.title = title;
    this.message = message;
    this.confirmText = L10n.ok;
    this.cancelText = '';
    this.onConfirm = onConfirm ?? (() => {
    });
    this.visible = true;
  }

  showError(message: string, title: string): void {
    this.showInfo(title, message);
  }

  showConfirm(title: string, message: string, onConfirm: () => void, confirmText: string = L10n.ok,
    cancelText: string = L10n.cancel): void {
    this.title = title;
    this.message = message;
    this.confirmText = confirmText;
    this.cancelText = cancelText;
    this.onConfirm = onConfirm;
    this.visible = true;
  }

  close(): void {
    this.visible = false;
  }
}

/** 带输入框的对话框状态（密码输入 / 配对码输入） */
@ObservedV2
export class InputDialogState {
  @Trace visible: boolean = false;
  @Trace title: string = '';
  @Trace message: string = '';
  @Trace hint: string = '';
  @Trace input: string = '';
  @Trace error: string = '';
  onConfirm: (value: string) => void = (_value: string) => {
  };

  show(title: string, message: string, hint: string, initialValue: string, onConfirm: (value: string) => void): void {
    this.title = title;
    this.message = message;
    this.hint = hint;
    this.input = initialValue;
    this.error = '';
    this.onConfirm = onConfirm;
    this.visible = true;
  }

  close(): void {
    this.visible = false;
  }
}

/** 双重验证对话框状态 */
@ObservedV2
export class TwofaDialogState {
  @Trace visible: boolean = false;
  @Trace code: string = '';
  @Trace error: string = '';
  onVerify: (code: string) => void = (_code: string) => {
  };

  show(onVerify: (code: string) => void): void {
    this.code = '';
    this.error = '';
    this.onVerify = onVerify;
    this.visible = true;
  }

  close(): void {
    this.visible = false;
  }
}

/**
 * 认证页面头部，对应 Flutter CustomAuthHeader。
 * 结构：返回按钮（可选）+ 图标（可选，无 logo）+ 标题/副标题 + 右侧操作，底部带分割线。
 */
@ComponentV2
export struct AuthHeader {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param icon: Resource | undefined = undefined;
  @Param showBack: boolean = false;
  @Param onBack: () => void = () => {
  };

  build() {
    Column() {
      Row() {
        if (this.showBack) {
          // 40x40 热区承载点击，图标 24x24
          Row() {
            Image($r('sys.media.ohos_ic_back'))
              .width(24)
              .height(24)
              .fillColor(AuthTheme.textMain)
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .margin({ right: 8 })
          .onClick(() => this.onBack())
        }
        if (this.icon !== undefined) {
          SymbolGlyph(this.icon)
            .fontSize(24)
            .fontColor([AuthTheme.textMain])
            .margin({ right: 12 })
        }
        Column() {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AuthTheme.textMain)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(12)
              .fontColor(AuthTheme.textSecondary)
              .margin({ top: 4 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 20 })

      // 分割线，对应 CustomDivider
      Divider()
        .color(AuthTheme.divider)
        .strokeWidth(1)
        .margin({ left: 20, right: 20 })
    }
    .width('100%')
  }
}

/** 登录背景图（对应 Flutter BackgroundController.loginBgUrl），沉浸式延伸至状态栏与导航栏 */
@ComponentV2
export struct AuthBackground {
  build() {
    Image($r('app.media.login_bg'))
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

/** 根据服务器平台返回图标资源，对应 Flutter ServerItemView._getPlatformIcon */
export function platformIconResource(platform: string): Resource {
  switch (platform.toLowerCase()) {
    case 'darwin':
      return $r('app.media.server_mac');
    case 'win32':
      return $r('app.media.server_windows');
    default:
      return $r('app.media.server_linux');
  }
}

/** 配对码展示脱敏，对应 Flutter _maskPairCode */
export function maskPairCode(code: string): string {
  const s = code.trim();
  if (s.length === 0) {
    return s;
  }
  if (s.length <= 2) {
    return '*'.repeat(s.length);
  }
  const left = Math.floor((s.length - 2) / 2);
  const right = left + 2;
  return `${s.substring(0, left)}**${s.substring(right)}`;
}

/**
 * 通用操作按钮（风格统一封装）。
 * variant：
 * - primary：实心主色底 + 白字（对应 Flutter ElevatedButton）
 * - outlined：透明底 + 描边 + 主文字色
 * - text：透明底 + 主色文字（对应 Flutter TextButton）
 * - danger：透明底 + 红色文字（删除等危险操作）
 */
@ComponentV2
export struct ActionButton {
  @Param label: string = '';
  @Param variant: string = 'primary';
  @Param isEnabled: boolean = true;
  @Param btnHeight: number = 40;
  @Param action: () => void = () => {
  };

  build() {
    Button(this.label)
      .height(this.btnHeight)
      // 各 variant 统一水平内边距
      .padding({ left: 16, right: 16 })
      .backgroundColor(!this.isEnabled ? AuthTheme.buttonDisabledBg
        : this.variant === 'primary' ? AuthTheme.buttonBg : Color.Transparent)
      .fontColor(!this.isEnabled ? AuthTheme.buttonDisabledText
        : this.variant === 'primary' ? Color.White
          : this.variant === 'outlined' ? AuthTheme.textMain
            : this.variant === 'danger' ? AuthTheme.errorColor : AuthTheme.primary)
      // outlined 灰描边；danger 红描边
      .border(this.variant === 'outlined' ? { width: 1, color: AuthTheme.inputBorder }
        : this.variant === 'danger' ? { width: 1, color: AuthTheme.errorColor } : { width: 0 })
      .enabled(this.isEnabled)
      .onClick(() => this.action())
  }
}

/** 对话框文字按钮（ActionButton 的 text 变体特化） */
@ComponentV2
export struct DialogTextButton {
  @Param label: string = '';
  @Param action: () => void = () => {
  };

  build() {
    ActionButton({
      label: this.label,
      variant: 'text',
      btnHeight: 36,
      action: this.action
    })
  }
}

/** 通用确认/信息对话框渲染，对应 Flutter DialogUtil.createAlertDialog */
@ComponentV2
export struct ConfirmDialogView {
  @Param state: ConfirmDialogState = new ConfirmDialogState();

  build() {
    Column() {
      Text(this.state.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
      Text(this.state.message)
        .fontSize(14)
        .fontColor(AuthTheme.textMain)
        .margin({ top: 12 })
        .constraintSize({ maxHeight: 300 })
        .maxLines(20)
        .textOverflow({ overflow: TextOverflow.Clip })
      Row({ space: 12 }) {
        if (this.state.cancelText.length > 0) {
          DialogTextButton({
            label: this.state.cancelText,
            action: () => {
              this.state.close();
              this.state.onCancel();
            }
          })
        }
        DialogTextButton({
          label: this.state.confirmText,
          action: () => {
            this.state.close();
            this.state.onConfirm();
          }
        })
      }
      .margin({ top: 20 })
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .width('80%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .borderRadius(12)
    .backgroundColor(AuthTheme.dialogBg)
  }
}

/** 输入框对话框渲染 */
@ComponentV2
export struct InputDialogView {
  @Param state: InputDialogState = new InputDialogState();
  @Param isPassword: boolean = false;

  private submit(): void {
    if (this.state.input.trim().length === 0) {
      this.state.error = this.state.hint.length > 0 ? this.state.hint : L10n.tip;
      return;
    }
    this.state.onConfirm(this.state.input);
  }

  build() {
    Column() {
      Text(this.state.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
      if (this.state.message.length > 0) {
        Text(this.state.message)
          .fontSize(14)
          .fontColor(AuthTheme.textMain)
          .margin({ top: 12 })
      }
      TextInput({ placeholder: this.state.hint, text: this.state.input })
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .showPasswordIcon(false)
        .width('100%')
        .margin({ top: 16 })
        .backgroundColor(AuthTheme.inputBg)
        .border({ width: 1, color: AuthTheme.inputBorder })
        .borderRadius(8)
        .fontColor(AuthTheme.textMain)
        .placeholderColor(AuthTheme.textHint)
        .onChange((v: string) => {
          this.state.input = v;
          this.state.error = '';
        })
        .onSubmit(() => this.submit())
      if (this.state.error.length > 0) {
        Text(this.state.error)
          .fontSize(12)
          .fontColor(AuthTheme.errorColor)
          .width('100%')
          .margin({ top: 6 })
      }
      Row({ space: 12 }) {
        DialogTextButton({ label: L10n.cancel, action: () => this.state.close() })
        DialogTextButton({ label: L10n.ok, action: () => this.submit() })
      }
      .margin({ top: 20 })
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .width('80%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .borderRadius(12)
    .backgroundColor(AuthTheme.dialogBg)
  }
}

/** 双重验证对话框渲染，对应 Flutter TwofaCodeDialog */
@ComponentV2
export struct TwofaDialogView {
  @Param state: TwofaDialogState = new TwofaDialogState();
  @Param onInfo: (title: string, message: string) => void = (_t: string, _m: string) => {
  };

  private verify(): void {
    const code = this.state.code.trim();
    if (code.length === 0) {
      this.state.error = L10n.auth2faCodeRequired;
      return;
    }
    this.state.onVerify(code);
  }

  build() {
    Column() {
      Text(L10n.auth2faTitle)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
      Text(L10n.auth2faCodeLabel)
        .fontSize(14)
        .fontColor(AuthTheme.textSecondary)
        .margin({ top: 12 })
        .width('100%')
      TextInput({ placeholder: L10n.auth2faCodeHint, text: this.state.code })
        .type(InputType.Number)
        .width('100%')
        .margin({ top: 8 })
        .backgroundColor(AuthTheme.inputBg)
        .border({ width: 1, color: AuthTheme.inputBorder })
        .borderRadius(8)
        .fontColor(AuthTheme.textMain)
        .placeholderColor(AuthTheme.textHint)
        .onChange((v: string) => {
          this.state.code = v;
          this.state.error = '';
        })
        .onSubmit(() => this.verify())
      if (this.state.error.length > 0) {
        Text(this.state.error)
          .fontSize(12)
          .fontColor(AuthTheme.errorColor)
          .width('100%')
          .margin({ top: 6 })
      }
      Text(L10n.auth2faCannotVerify)
        .fontSize(12)
        .fontColor(AuthTheme.primary)
        .margin({ top: 8 })
        .onClick(() => {
          this.onInfo(L10n.auth2faCannotVerify, L10n.auth2faCannotVerifyHint);
        })
      Row({ space: 12 }) {
        DialogTextButton({ label: L10n.cancel, action: () => this.state.close() })
        DialogTextButton({ label: L10n.auth2faVerifyButton, action: () => this.verify() })
      }
      .margin({ top: 20 })
      .justifyContent(FlexAlign.End)
      .width('100%')
    }
    .width('80%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .borderRadius(12)
    .backgroundColor(AuthTheme.dialogBg)
  }
}

/** 全屏半透明遮罩容器，用于承载对话框 */
@ComponentV2
export struct DialogOverlay {
  @Builder
  dialogContent() {
  }

  @BuilderParam content: () => void = this.dialogContent;

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AuthTheme.mask)
      this.content()
    }
    .width('100%')
    .height('100%')
  }
}

/** 主操作按钮，对应 Flutter CustomButton（ElevatedButton 主题） */
@ComponentV2
export struct AuthButton {
  @Param label: string = '';
  @Param loading: boolean = false;
  @Param action: () => void = () => {
  };

  build() {
    Button(this.loading ? ' ' : this.label)
      .width('100%')
      .height(44)
      .backgroundColor(this.loading ? AuthTheme.buttonDisabledBg : AuthTheme.buttonBg)
      // 对应 Flutter ElevatedButton foregroundColor: Colors.white
      .fontColor(this.loading ? AuthTheme.buttonDisabledText : Color.White)
      .enabled(!this.loading)
      .onClick(() => this.action())
  }
}

/** 带标签的输入框行（含校验错误显示），对应 Flutter CustomTextField */
@ComponentV2
export struct AuthTextField {
  @Param label: string = '';
  @Param text: string = '';
  @Param hint: string = '';
  @Param isPassword: boolean = false;
  @Param error: string = '';
  @Param fieldEnabled: boolean = true;
  /** 输入框背景透明（如添加服务器页的半透明卡片上使用） */
  @Param transparent: boolean = false;
  @Param onChange: (value: string) => void = (_v: string) => {
  };
  /** 自定义尾部内容（如"找回"按钮），传空则不显示 */
  @BuilderParam suffix: () => void = this.emptyBuilder;
  @Builder emptyBuilder() {
  }
  /** 密码可见性（仅 isPassword 时生效） */
  @Local passwordVisible: boolean = false;

  build() {
    Column() {
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(13)
          .fontColor(AuthTheme.textSecondary)
          .width('100%')
          .margin({ top: 16, bottom: 6 })
      }
      Row({ space: 8 }) {
        if (this.isPassword) {
          // 显示/隐藏图标叠放在输入框内部右侧
          Stack({ alignContent: Alignment.End }) {
            TextInput({ placeholder: this.hint, text: this.text })
              .width('100%')
              .height(44)
              .type(this.passwordVisible ? InputType.Normal : InputType.Password)
              .showPasswordIcon(false)
              .backgroundColor(this.transparent ? Color.Transparent : AuthTheme.inputBg)
              .border({ width: 1, color: AuthTheme.inputBorder })
              .borderRadius(8)
              .fontColor(AuthTheme.textMain)
              .placeholderColor(AuthTheme.textHint)
              .enabled(this.fieldEnabled)
              .padding({ left: 12, right: 46 })
              .onChange((v: string) => this.onChange(v))
            // 图标表示当前状态：明文显示时睁眼，隐藏时斜眼（与 Flutter 一致）
            SymbolGlyph(this.passwordVisible ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
              .fontSize(22)
              .fontColor([AuthTheme.textMain])
              .margin({ right: 12 })
              .onClick(() => {
                this.passwordVisible = !this.passwordVisible;
              })
          }
          .layoutWeight(1)
        } else {
          TextInput({ placeholder: this.hint, text: this.text })
            .layoutWeight(1)
            .height(44)
            .backgroundColor(this.transparent ? Color.Transparent : AuthTheme.inputBg)
            .border({ width: 1, color: AuthTheme.inputBorder })
            .borderRadius(8)
            .fontColor(AuthTheme.textMain)
            .placeholderColor(AuthTheme.textHint)
            .enabled(this.fieldEnabled)
            .onChange((v: string) => this.onChange(v))
          this.suffix()
        }
      }
      .width('100%')
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(12)
          .fontColor(AuthTheme.errorColor)
          .width('100%')
          .margin({ top: 6 })
      }
    }
    .width('100%')
  }
}
