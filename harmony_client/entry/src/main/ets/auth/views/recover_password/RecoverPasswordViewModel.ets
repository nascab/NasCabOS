import { L10n } from '../../../core/localization/L10n';
import { AuthService } from '../../AuthService';
import { ConfirmDialogState } from '../common/AuthUi';

/**
 * 找回密码视图模型，对应 Flutter RecoverPasswordController。
 */
@ObservedV2
export class RecoverPasswordViewModel {
  @Trace username: string = '';
  @Trace answer: string = '';
  @Trace newPassword: string = '';
  @Trace isLoading: boolean = false;
  @Trace securityQuestion: string = '';
  @Trace hasRecoverInfo: boolean = false;
  /** 用户名输入校验错误 */
  @Trace usernameError: string = '';
  /** 密保答案校验错误 */
  @Trace answerError: string = '';
  /** 新密码校验错误 */
  @Trace newPasswordError: string = '';

  /** 对话框状态（错误/成功提示共用） */
  readonly confirmDialog: ConfirmDialogState = new ConfirmDialogState();

  onBack: () => void = () => {
  };

  private authService: AuthService = AuthService.getInstance();

  /** 根据用户名获取找回密码信息 */
  async fetchRecoverInfo(): Promise<void> {
    const u = this.username.trim();
    if (u.length === 0) {
      this.showError(L10n.serverAddUsernameRequired);
      return;
    }
    this.isLoading = true;
    try {
      const result = await this.authService.getRecoverInfo(u);
      if (result.success && result.question) {
        this.securityQuestion = result.question;
        this.hasRecoverInfo = true;
        // 固定用户名，避免误改
        this.username = u;
      } else {
        this.hasRecoverInfo = false;
        this.showError(result.message ?? L10n.authRecoverInfoFailure);
      }
    } catch (_e) {
      this.hasRecoverInfo = false;
      this.showError(L10n.authRecoverInfoFailure);
    } finally {
      this.isLoading = false;
    }
  }

  /** 提交找回请求 */
  async handleRecover(): Promise<void> {
    if (!this.validate()) {
      return;
    }
    this.isLoading = true;
    try {
      const result = await this.authService.recoverAdminPassword(
        this.username,
        this.answer,
        this.newPassword
      );
      if (!result.success) {
        this.showError(result.message ?? L10n.recoverFailure);
        return;
      }
      this.showSuccessDialog();
    } catch (_e) {
      this.showError(L10n.recoverFailure);
    } finally {
      this.isLoading = false;
    }
  }

  goBack(): void {
    this.onBack();
  }

  private validate(): boolean {
    let valid = true;
    if (this.username.trim().length === 0) {
      this.usernameError = L10n.serverAddUsernameRequired;
      valid = false;
    } else {
      this.usernameError = '';
    }
    if (this.answer.trim().length === 0) {
      this.answerError = L10n.recoverAnswerRequired;
      valid = false;
    } else {
      this.answerError = '';
    }
    if (this.newPassword.length === 0) {
      this.newPasswordError = L10n.serverAddPasswordRequired;
      valid = false;
    } else if (this.newPassword.length < 6) {
      this.newPasswordError = L10n.authPasswordTooShort;
      valid = false;
    } else {
      this.newPasswordError = '';
    }
    return valid;
  }

  private showSuccessDialog(): void {
    this.confirmDialog.showInfo(L10n.recoverSuccess, L10n.recoverSuccessMessage, () => {
      this.goBack();
    });
  }

  private showError(message: string): void {
    this.confirmDialog.showError(message, L10n.recoverFailure);
  }
}
