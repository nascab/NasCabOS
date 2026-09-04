import { common } from '@kit.AbilityKit';
import { L10n } from '../../../core/localization/L10n';
import { LoginViewModel, openExternalUrl } from './LoginViewModel';
import { AdminCreateView } from '../admin_create/AdminCreateView';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import {
  AuthBackground,
  AuthButton,
  AuthHeader,
  AuthTextField,
  AuthTheme,
  ConfirmDialogView,
  DialogOverlay,
  DialogTextButton,
  InputDialogView,
  TwofaDialogView
} from '../common/AuthUi';

/**
 * 登录页，对应 Flutter LoginView。
 * 配对码连接成功后显示账号密码登录；底部为隐私政策/用户协议链接。
 */
@ComponentV2
export struct LoginPage {
  @Param showPairCodeInput: boolean = false;
  @Param onNavigateHome: () => void = () => {
  };
  @Local vm: LoginViewModel = new LoginViewModel();

  aboutToAppear(): void {
    this.vm.onLoginSuccess = () => this.onNavigateHome();
    this.vm.showPairCodeInput = this.showPairCodeInput;
    void this.vm.init();
  }

  build() {
    Stack() {
      AuthBackground()

      Column() {
        // 创建管理员视图（服务器未初始化时）
        if (this.vm.adminListVm.showCreateAdminView) {
          AdminCreateView({
            listVm: this.vm.adminListVm,
            onBack: () => {
              this.vm.adminListVm.showCreateAdminView = false;
            }
          })
        } else {
          // 登录卡片
          Column() {
            AuthHeader({
              title: this.vm.headerTitle,
              subtitle: this.vm.connectedHostName.length > 0
                ? L10n.authConnectedHost(this.vm.connectedHostName) : ''
            })

            Scroll() {
              Column() {
                // 配对码输入（对应 Flutter showPairCodeInput）
                if (this.vm.showPairCodeInput) {
                  AuthTextField({
                    label: L10n.authPairCodeLabel,
                    text: this.vm.pairCodeInput,
                    error: this.vm.pairFieldError,
                    onChange: (v: string) => {
                      this.vm.pairCodeInput = v;
                    },
                    suffix: () => {
                      if (this.vm.isPairCodeConnecting) {
                        LoadingProgress()
                          .width(24)
                          .height(24)
                          .color(AuthTheme.primary)
                          .margin({ left: 8 })
                      } else {
                        Button(L10n.authPairCodeConnect)
                          .height(44)
                          .backgroundColor(AuthTheme.inputBg)
                          .fontColor(AuthTheme.primary)
                          .onClick(() => {
                            void this.vm.connectP2pByPairCode();
                          })
                      }
                    }
                  })
                }

                // 账号密码登录（连接成功后显示）
                if (!this.vm.showOnlyPairCode) {
                  AuthTextField({
                    label: L10n.username,
                    text: this.vm.username,
                    error: this.vm.usernameError,
                    onChange: (v: string) => {
                      this.vm.username = v;
                      this.vm.usernameError = '';
                    }
                  })

                  AuthTextField({
                    label: L10n.password,
                    text: this.vm.password,
                    isPassword: true,
                    error: this.vm.passwordError,
                    onChange: (v: string) => {
                      this.vm.password = v;
                      this.vm.passwordError = '';
                    }
                  })

                  // 忘记密码
                  Row() {
                    Blank()
                    Text(L10n.authForgotPassword)
                      .fontSize(12)
                      .fontColor(AuthTheme.primary)
                      .margin({ top: 12 })
                      .onClick(() => {
                        const context = getContext(this) as common.UIAbilityContext;
                        this.vm.goToForgotPasswordHelp(context);
                      })
                  }
                  .width('100%')

                  // 登录按钮
                  Column() {
                    AuthButton({
                      label: L10n.authLoginButton,
                      loading: this.vm.isLoading,
                      action: () => {
                        void this.vm.handleLogin();
                      }
                    })
                  }
                  .margin({ top: 24 })
                }
              }
              .width('100%')
              .padding(20)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Auto)
            .align(Alignment.Top)
          }
          .width('92%')
          .constraintSize({ maxWidth: 520, maxHeight: '85%' })
          .backgroundColor(AuthTheme.cardBg)
          .borderRadius(16)
          .clip(true)
        }

        // 底部链接：隐私政策 · 用户协议
        this.FooterLinks()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

      // 对话框遮罩
      if (this.vm.confirmDialog.visible) {
        DialogOverlay() {
          ConfirmDialogView({ state: this.vm.confirmDialog })
        }
      }
      if (this.vm.passwordDialog.visible) {
        DialogOverlay() {
          InputDialogView({ state: this.vm.passwordDialog, isPassword: true })
        }
      }
      if (this.vm.twofaDialog.visible) {
        DialogOverlay() {
          TwofaDialogView({
            state: this.vm.twofaDialog,
            onInfo: (title: string, message: string) => {
              this.vm.confirmDialog.showInfo(title, message);
            }
          })
        }
      }
      if (this.vm.adminListVm.confirmDialog.visible) {
        DialogOverlay() {
          ConfirmDialogView({ state: this.vm.adminListVm.confirmDialog })
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  FooterLinks() {
    Row() {
      Text(L10n.authPrivacyPolicy)
        .fontSize(12)
        .fontColor(AuthTheme.textMain)
        .onClick(() => {
          const context = getContext(this) as common.UIAbilityContext;
          openExternalUrl(context,
            `${NetworkConfig.WEBSITE_BASE_URL}/others/privacy.html?language=${L10n.currentLanguageCode}`);
        })
      Text('·')
        .fontSize(12)
        .fontColor(AuthTheme.textSecondary)
        .margin({ left: 8, right: 8 })
      Text(L10n.authUserAgreement)
        .fontSize(12)
        .fontColor(AuthTheme.textMain)
        .onClick(() => {
          const context = getContext(this) as common.UIAbilityContext;
          openExternalUrl(context,
            `${NetworkConfig.WEBSITE_BASE_URL}/others/agreement.html?language=${L10n.currentLanguageCode}`);
        })
    }
    .margin({ top: 12, bottom: 16 })
  }
}
