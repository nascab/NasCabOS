import { L10n } from '../../../core/localization/L10n';
import { ServerListViewModel } from '../server_list/ServerListViewModel';
import { ServerAddViewModel } from './ServerAddViewModel';
import { AuthBackground, AuthButton, AuthHeader, AuthTextField, AuthTheme, ConfirmDialogView, DialogOverlay, TwofaDialogView } from '../common/AuthUi';

/** 添加服务器独立页面（Navigation 目的地），对应 Flutter ServerAddView */
@ComponentV2
export struct ServerAddPage {
  @Param listVm: ServerListViewModel = new ServerListViewModel();
  @Param onBack: () => void = () => {
  };
  // 占位实例；aboutToAppear 中用真实的 listVm 重建（@Param 在字段初始化之后才赋值）
  @Local vm: ServerAddViewModel = new ServerAddViewModel(new ServerListViewModel());

  aboutToAppear(): void {
    this.vm = new ServerAddViewModel(this.listVm);
    // 注入返回回调（pop 回到服务器列表）
    this.vm.onExit = () => this.onBack();
  }

  build() {
    NavDestination() {
      Stack() {
        AuthBackground()

        Column() {
          Column() {
            AuthHeader({
              title: L10n.serverAdd,
              showBack: true,
              onBack: () => this.vm.goBack()
            })

            Scroll() {
              Column() {
                // 服务器名称
                AuthTextField({
                  label: L10n.serverAddNameLabel,
                  text: this.vm.serverName,
                  transparent: true,
                  onChange: (v: string) => {
                    this.vm.serverName = v;
                  }
                })

                if (this.vm.isP2pMode) {
                  AuthTextField({
                    label: L10n.serverPairCodeLabel,
                    text: this.vm.prefillServerInfo?.pairCode ?? '',
                    fieldEnabled: false,
                    transparent: true
                  })
                } else {
                  // 协议选择
                  Row({ space: 16 }) {
                    Text(L10n.serverAddProtocol)
                      .fontSize(14)
                      .fontColor(AuthTheme.textMain)
                    Row({ space: 6 }) {
                      Radio({ value: 'http', group: 'protocol' })
                        .checked(this.vm.protocol === 'http')
                        .onChange((isChecked: boolean) => {
                          if (isChecked) {
                            this.vm.toggleProtocol('http');
                          }
                        })
                      Text('HTTP').fontSize(14).fontColor(AuthTheme.textMain)
                    }
                    Row({ space: 6 }) {
                      Radio({ value: 'https', group: 'protocol' })
                        .checked(this.vm.protocol === 'https')
                        .onChange((isChecked: boolean) => {
                          if (isChecked) {
                            this.vm.toggleProtocol('https');
                          }
                        })
                      Text('HTTPS').fontSize(14).fontColor(AuthTheme.textMain)
                    }
                  }
                  .width('100%')
                  .margin({ top: 16 })

                  // 服务器地址
                  AuthTextField({
                    label: L10n.serverAddAddressLabel,
                    hint: L10n.serverAddAddressHint,
                    text: this.vm.serverUrl,
                    transparent: true,
                    onChange: (v: string) => {
                      this.vm.serverUrl = v;
                    }
                  })
                }

                // 用户名
                AuthTextField({
                  label: L10n.username,
                  text: this.vm.username,
                  transparent: true,
                  onChange: (v: string) => {
                    this.vm.username = v;
                  }
                })

                // 密码（白色显示/隐藏图标位于输入框内部右侧）
                AuthTextField({
                  label: L10n.password,
                  text: this.vm.password,
                  isPassword: true,
                  transparent: true,
                  onChange: (v: string) => {
                    this.vm.password = v;
                  }
                })

                // 每次登录都需要输入密码
                Row() {
                  Checkbox({ name: 'needPwd' })
                    .select(this.vm.needInputPwdEveryTime)
                    .selectedColor(AuthTheme.primary)
                    .onChange((value: boolean) => {
                      this.vm.toggleNeedInputPwdEveryTime(value);
                    })
                  Text(L10n.serverNeedInputPasswordEveryTime)
                    .fontSize(14)
                    .fontColor(AuthTheme.textMain)
                }
                .width('100%')
                .margin({ top: 8 })

                // 提交按钮
                Column() {
                  AuthButton({
                    label: L10n.serverAddButton,
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
          // 全屏覆盖，对应 Flutter 手机端半透明卡片
          .width('100%')
          .height('100%')
          .backgroundColor(AuthTheme.cardBg)
          // 背景色延伸到状态栏/导航栏后面，实现完全沉浸（内容仍在安全区内）
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)

        // 对话框：放在外层 Stack 顶层，避免与全屏卡片并列布局被挤出屏幕
        if (this.vm.confirmDialog.visible) {
          DialogOverlay() {
            ConfirmDialogView({ state: this.vm.confirmDialog })
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
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      // 系统返回手势/返回键，直接返回（无需确认）
      this.vm.goBack();
      return true;
    })
  }
}
