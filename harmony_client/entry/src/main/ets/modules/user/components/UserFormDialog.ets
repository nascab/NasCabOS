import { AppTheme, ThemePalette } from '../../../core/theme/AppTheme';
import { L10n } from '../../../core/localization/L10n';
import { DialogUtil, DialogParamsBase } from '../../../common/DialogUtil';
import { UserManagementController } from '../controllers/UserManagementController';
import { UserProfile } from '../models/UserModels';

/** 用户表单弹窗参数（对齐 Flutter CustomUserFormDialog：user 非空为编辑，否则为创建） */
export class UserFormDialogParams extends DialogParamsBase {
  isEdit: boolean = false;
  user: UserProfile | undefined = undefined;
}

/** 打开用户表单弹窗（创建传 undefined，编辑传用户）；提交成功后 onClosed(true) */
export function openUserFormDialog(user: UserProfile | undefined,
  onClosed: (ok: boolean) => void): void {
  const p = new UserFormDialogParams();
  p.isEdit = user !== undefined;
  if (user !== undefined) {
    p.user = user;
  }
  DialogUtil.openCustom(p, wrapBuilder(UserFormDialogContent), true,
    (r: boolean | number | string | undefined): void => {
      onClosed(r === true);
    });
}

@Builder
function UserFormDialogContent(p: UserFormDialogParams) {
  UserFormDialogInner({ p: p })
}

/** 表单字段（独立组件以保证 text/error 的 V2 响应式刷新） */
@ComponentV2
struct FormFieldInput {
  @Param label: string = '';
  @Param text: string = '';
  @Param placeholder: string = '';
  @Param error: string = '';
  @Param isPassword: boolean = false;
  @Param onChange: (v: string) => void = (_v: string): void => {
  };

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  build() {
    Column({ space: 6 }) {
      Text(this.label)
        .fontSize(13)
        .fontColor(this.palette().subText)
      TextInput({ text: this.text, placeholder: this.placeholder })
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .fontSize(14)
        .fontColor(this.palette().onSurface)
        .placeholderColor(AppTheme.withAlpha(AppTheme.current().onSurface, 0.5))
        .backgroundColor(this.palette().inputFill)
        .borderRadius(8)
        .border({ width: 1, color: this.palette().inputBorder })
        .height(42)
        .width('100%')
        .onChange((v: string): void => {
          this.onChange(v);
        })
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(12)
          .fontColor(this.palette().error)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

/** 表单内部组件（维护输入与校验状态，对齐 CustomUserFormController 校验规则） */
@ComponentV2
struct UserFormDialogInner {
  @Param p: UserFormDialogParams = new UserFormDialogParams();
  @Local usernameText: string = '';
  @Local passwordText: string = '';
  @Local phoneText: string = '';
  @Local remarkText: string = '';
  @Local usernameError: string = '';
  @Local passwordError: string = '';
  @Local phoneError: string = '';
  @Local remarkError: string = '';
  @Local submitting: boolean = false;
  ctrl: UserManagementController = UserManagementController.getInstance();

  aboutToAppear(): void {
    // 编辑时回填（对齐 CustomUserFormController.onInit）
    if (this.p.isEdit && this.p.user !== undefined) {
      this.usernameText = this.p.user.username;
      this.phoneText = this.p.user.phone;
      this.remarkText = this.p.user.userRemark;
    }
  }

  private palette(): ThemePalette {
    return AppTheme.current();
  }

  /** 对齐 validateUsername：空 → input_please */
  private validateUsername(v: string): string {
    return v.length === 0 ? L10n.inputPlease : '';
  }

  /** 对齐 validatePassword：编辑时空串放行；长度 < 6 → auth_password_too_short */
  private validatePassword(v: string): string {
    if (this.p.isEdit && v.length === 0) {
      return '';
    }
    return v.length < 6
      ? L10n.t('auth_password_too_short', '密码长度不能小于6位') : '';
  }

  /** 对齐 validatePhone：非空且 > 32 位 → user_mgmt_field_length_invalid */
  private validatePhone(v: string): string {
    const t = v.trim();
    if (t.length === 0) {
      return '';
    }
    return t.length > 32
      ? L10n.t('user_mgmt_field_length_invalid', '长度不符合要求') : '';
  }

  /** 对齐 validateRemark：非空且 > 500 位 → user_mgmt_field_length_invalid */
  private validateRemark(v: string): string {
    const t = v.trim();
    if (t.length === 0) {
      return '';
    }
    return t.length > 500
      ? L10n.t('user_mgmt_field_length_invalid', '长度不符合要求') : '';
  }

  private hasError(): boolean {
    this.usernameError = this.validateUsername(this.usernameText);
    this.passwordError = this.validatePassword(this.passwordText);
    this.phoneError = this.validatePhone(this.phoneText);
    this.remarkError = this.validateRemark(this.remarkText);
    return this.usernameError.length > 0 || this.passwordError.length > 0
      || this.phoneError.length > 0 || this.remarkError.length > 0;
  }

  /** 对齐 submitForm：编辑走 updateUser（密码空则不传），创建走 createUser */
  private async submitForm(): Promise<void> {
    if (this.hasError()) {
      return;
    }
    const username = this.usernameText.trim();
    const password = this.passwordText.trim();
    const phone = this.phoneText.trim();
    const remark = this.remarkText.trim();
    this.submitting = true;
    try {
      let ok = false;
      if (this.p.isEdit && this.p.user !== undefined) {
        ok = await this.ctrl.updateUser(this.p.user.id, username,
          password.length > 0 ? password : undefined, undefined, remark, phone);
      } else {
        ok = await this.ctrl.createUser(username, password, remark, phone);
      }
      if (ok) {
        this.p.onResult(true);
      }
    } finally {
      this.submitting = false;
    }
  }

  build() {
    Column() {
      Text(this.p.isEdit
        ? L10n.t('user_mgmt_edit', '修改用户')
        : L10n.t('user_mgmt_create', '创建用户'))
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().onSurface)

      Column({ space: 14 }) {
        FormFieldInput({
          label: L10n.t('username', '用户名'),
          text: this.usernameText,
          placeholder: L10n.inputPlease,
          error: this.usernameError,
          isPassword: false,
          onChange: (v: string): void => {
            this.usernameText = v;
            this.usernameError = this.validateUsername(v);
          }
        })
        FormFieldInput({
          label: this.p.isEdit
            ? L10n.t('user_mgmt_new_password', '新密码')
            : L10n.t('password', '密码'),
          text: this.passwordText,
          placeholder: this.p.isEdit ? L10n.t('user_mgmt_optional_hint', '选填')
            : L10n.inputPlease,
          error: this.passwordError,
          isPassword: true,
          onChange: (v: string): void => {
            this.passwordText = v;
            this.passwordError = this.validatePassword(v);
          }
        })
        FormFieldInput({
          label: L10n.t('user_mgmt_phone_label', '电话（选填）'),
          text: this.phoneText,
          placeholder: L10n.t('user_mgmt_optional_hint', '选填'),
          error: this.phoneError,
          isPassword: false,
          onChange: (v: string): void => {
            this.phoneText = v;
            this.phoneError = this.validatePhone(v);
          }
        })
        FormFieldInput({
          label: L10n.t('user_mgmt_remark_label', '备注（选填）'),
          text: this.remarkText,
          placeholder: L10n.t('user_mgmt_optional_hint', '选填'),
          error: this.remarkError,
          isPassword: false,
          onChange: (v: string): void => {
            this.remarkText = v;
            this.remarkError = this.validateRemark(v);
          }
        })
      }
      .margin({ top: 16 })
      .width('100%')

      Row({ space: 8 }) {
        Button(L10n.cancel)
          .fontSize(14)
          .fontColor(this.palette().primary)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick(() => {
            this.p.onResult(undefined);
          })
        Button(L10n.save)
          .fontSize(14)
          .fontColor(this.palette().buttonText)
          .backgroundColor(this.palette().buttonBg)
          .height(36)
          .opacity(this.submitting ? 0.5 : 1)
          .onClick(() => {
            void this.submitForm();
          })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 18 })
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .backgroundColor(this.palette().surfaceBg)
    .borderRadius(24)
    .width('84%')
    .constraintSize({ maxWidth: 420 })
  }
}
