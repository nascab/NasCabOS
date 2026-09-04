import { L10n } from '../../../core/localization/L10n';
import { RecoverPasswordViewModel } from './RecoverPasswordViewModel';
import { AuthBackground, AuthButton, AuthHeader, AuthTextField, AuthTheme, ConfirmDialogView, DialogOverlay } from '../common/AuthUi';

/** 密码恢复界面，对应 Flutter RecoverView */
@ComponentV2
export struct RecoverPasswordView {
  @Param onBack: () => void = () => {
  };
  @Local vm: RecoverPasswordViewModel = new RecoverPasswordViewModel();

  aboutToAppear(): void {
    this.vm.onBack = () => this.onBack();
  }

  build() {
    Stack() {
      AuthBackground()

      Column() {
        Column() {
          AuthHeader({
            title: L10n.recoverTitle,
            showBack: true,
            onBack: () => this.vm.goBack()
          })

          // 帮助入口（对应 Flutter 头部 actions 中的帮助按钮）
          Row() {
            Blank()
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.questionmark_circle_fill'))
                .fontSize(16)
                .fontColor([AuthTheme.textMain])
              Text(L10n.tip)
                .fontSize(13)
                .fontColor(AuthTheme.textMain)
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(AuthTheme.inputBg)
            .borderRadius(14)
            .margin({ right: 16, top: 4 })
            .onClick(() => {
              this.vm.confirmDialog.showInfo(L10n.tip, L10n.authRecoverTip);
            })
          }
          .width('100%')

          Scroll() {
            Column() {
              // 用户名输入框（输入框尾部提供"找回"按钮）
              AuthTextField({
                label: L10n.username,
                text: this.vm.username,
                error: this.vm.usernameError,
                onChange: (v: string) => {
                  this.vm.username = v;
                  this.vm.usernameError = '';
                },
                suffix: () => {
                  Button(L10n.recoverButton)
                    .height(44)
                    .backgroundColor(AuthTheme.inputBg)
                    .fontColor(AuthTheme.primary)
                    .enabled(!this.vm.isLoading)
                    .onClick(() => {
                      void this.vm.fetchRecoverInfo();
                    })
                }
              })

              // 密保问题与后续组件，仅在成功获取找回信息后显示
              if (this.vm.hasRecoverInfo) {
                Text(L10n.authRecoverSecurityQuestionLabel)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AuthTheme.textSecondary)
                  .width('100%')
                  .margin({ top: 16 })
                Text(this.vm.securityQuestion)
                  .fontSize(14)
                  .fontColor(AuthTheme.textMain)
                  .width('100%')
                  .padding(12)
                  .margin({ top: 8 })
                  .borderRadius(8)
                  .backgroundColor(AuthTheme.questionBg)
                  .border({ width: 1, color: AuthTheme.divider })

                // 密保答案
                AuthTextField({
                  label: L10n.recoverAnswerLabel,
                  text: this.vm.answer,
                  error: this.vm.answerError,
                  onChange: (v: string) => {
                    this.vm.answer = v;
                    this.vm.answerError = '';
                  }
                })

                // 新密码
                AuthTextField({
                  label: L10n.recoverNewPasswordLabel,
                  text: this.vm.newPassword,
                  isPassword: true,
                  error: this.vm.newPasswordError,
                  onChange: (v: string) => {
                    this.vm.newPassword = v;
                    this.vm.newPasswordError = '';
                  }
                })

                // 提交按钮
                Column() {
                  AuthButton({
                    label: L10n.recoverButton,
                    loading: this.vm.isLoading,
                    action: () => {
                      void this.vm.handleRecover();
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
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

      // 对话框遮罩：放在外层 Stack 顶层，避免与卡片并列布局被挤出屏幕
      if (this.vm.confirmDialog.visible) {
        DialogOverlay() {
          ConfirmDialogView({ state: this.vm.confirmDialog })
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}
