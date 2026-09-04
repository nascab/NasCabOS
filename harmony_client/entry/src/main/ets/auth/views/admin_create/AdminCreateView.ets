import { L10n } from '../../../core/localization/L10n';
import { ServerListViewModel } from '../server_list/ServerListViewModel';
import { AdminCreateViewModel } from './AdminCreateViewModel';
import { AuthBackground, AuthButton, AuthHeader, AuthTextField, AuthTheme, ConfirmDialogView, DialogOverlay } from '../common/AuthUi';

/** 创建管理员界面，对应 Flutter AdminCreateView */
@ComponentV2
export struct AdminCreateView {
  @Param listVm: ServerListViewModel = new ServerListViewModel();
  @Param onBack: () => void = () => {
  };
  // 占位实例；aboutToAppear 中用真实的 listVm 重建（@Param 在字段初始化之后才赋值）
  @Local vm: AdminCreateViewModel = AdminCreateViewModel.createDefault(new ServerListViewModel());

  aboutToAppear(): void {
    this.vm = AdminCreateViewModel.createDefault(this.listVm);
  }

  build() {
    Stack() {
      AuthBackground()

      Column() {
        Column() {
          AuthHeader({
            title: L10n.adminCreateTitle,
            showBack: true,
            onBack: () => this.vm.goBack()
          })

          Scroll() {
            Column() {
              // 用户名
              AuthTextField({
                label: L10n.username,
                text: this.vm.username,
                onChange: (v: string) => {
                  this.vm.username = v;
                }
              })

              // 密码
              AuthTextField({
                label: L10n.password,
                text: this.vm.password,
                isPassword: true,
                onChange: (v: string) => {
                  this.vm.password = v;
                }
              })

              // 选择密保问题
              Text(L10n.adminCreateSecurityQuestionLabel)
                .fontSize(13)
                .fontColor(AuthTheme.textSecondary)
                .width('100%')
                .margin({ top: 16, bottom: 6 })
              Select(this.questionOptions())
                .selected(this.questionIndex())
                .value(this.questionDisplayValue())
                .fontColor(AuthTheme.textMain)
                .font({ size: 14 })
                .optionFontColor(AuthTheme.textMain)
                .optionBgColor(AuthTheme.dialogBg)
                .selectedOptionBgColor(AuthTheme.inputBg)
                .backgroundColor(AuthTheme.inputBg)
                .width('100%')
                .onSelect((index: number) => {
                  if (index < this.vm.predefinedQuestions.length) {
                    this.vm.toggleQuestionType(this.vm.predefinedQuestions[index]);
                  } else {
                    this.vm.toggleQuestionType(this.vm.customQuestionValue);
                  }
                })

              // 自定义问题输入
              if (this.vm.isCustomQuestion) {
                AuthTextField({
                  label: L10n.adminCreateSecurityQuestionCustom,
                  text: this.vm.securityQuestion,
                  onChange: (v: string) => {
                    this.vm.securityQuestion = v;
                  }
                })
              }

              // 密保答案
              AuthTextField({
                label: L10n.adminCreateSecurityAnswerLabel,
                text: this.vm.securityAnswer,
                onChange: (v: string) => {
                  this.vm.securityAnswer = v;
                }
              })

              // 提交按钮
              Column() {
                AuthButton({
                  label: L10n.adminCreateButton,
                  loading: this.vm.isLoading,
                  action: () => {
                    void this.vm.handleSubmit();
                  }
                })
              }
              .margin({ top: 32 })
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

  private questionOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const key of this.vm.predefinedQuestions) {
      options.push({ value: this.vm.getLocalizedQuestion(key) });
    }
    options.push({ value: L10n.adminCreateSecurityQuestionCustom });
    return options;
  }

  private questionIndex(): number {
    if (this.vm.isCustomQuestion) {
      return this.vm.predefinedQuestions.length;
    }
    return this.vm.predefinedQuestions.indexOf(this.vm.selectedQuestion);
  }

  private questionDisplayValue(): string {
    if (this.vm.selectedQuestion.length === 0) {
      return L10n.adminCreateSecurityQuestionLabel;
    }
    if (this.vm.isCustomQuestion) {
      return L10n.adminCreateSecurityQuestionCustom;
    }
    return this.vm.getLocalizedQuestion(this.vm.selectedQuestion);
  }
}
