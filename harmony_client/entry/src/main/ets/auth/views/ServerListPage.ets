import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { L10n } from '../../core/localization/L10n';
import { AppRouter } from '../../router/AppRouter';
import { ServerInfo } from '../models/ServerInfo';
import { ServerListViewModel, validatePairCodeText } from './server_list/ServerListViewModel';
import { scanPairCodeQr } from './server_list/PairCodeScanner';
import { AdminCreateView } from './admin_create/AdminCreateView';
import {
  ActionButton,
  AuthBackground,
  AuthHeader,
  AuthTheme,
  ConfirmDialogView,
  DialogOverlay,
  DialogTextButton,
  InputDialogView,
  TwofaDialogView,
  maskPairCode,
  platformIconResource
} from './common/AuthUi';

/**
 * 服务器列表页，对应 Flutter ServerListView。
 * 添加服务器为独立 Navigation 页面；创建管理员为就地切换。
 */
@ComponentV2
export struct ServerListPage {
  @Local vm: ServerListViewModel = new ServerListViewModel();
  @Local isRefreshing: boolean = false;
  @Param onNavigateHome: () => void = () => {
  };
  @Param pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.vm.onLoginSuccess = () => this.onNavigateHome();
    // 打开添加服务器独立页面（预填服务器通过 vm.selectedServer 传递）
    this.vm.onOpenAddServer = (_server: ServerInfo | undefined) => {
      this.pageStack.pushPathByName(AppRouter.SERVER_ADD, this.vm);
    };
    this.vm.onExitApp = () => {
      try {
        (getContext(this) as common.UIAbilityContext).terminateSelf();
      } catch (_e) {
        // 忽略退出失败
      }
    };
    void this.vm.init();
  }

  aboutToDisappear(): void {
    this.vm.destroy();
  }

  build() {
    Stack() {
      AuthBackground()

      Column() {
        // 根据变量 构建合适的view
        if (this.vm.showCreateAdminView) {
          AdminCreateView({
            listVm: this.vm,
            onBack: () => {
              this.vm.showCreateAdminView = false;
            }
          })
        } else {
          this.ServerListCard()
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      // 服务器详情 bottom sheet
      .bindSheet(this.vm.showServerSheet, this.ServerSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: false,
        showClose: false,
        backgroundColor: AuthTheme.dialogBg,
        onWillDismiss: (_action: SheetDismiss) => {
          // 返回键/点击遮罩/下滑都关闭
          this.vm.closeServerSheet();
        }
      })

      // 点击服务器的加载遮罩
      if (this.vm.isTapConnecting) {
        this.LoadingOverlay()
      }

      // 对话框遮罩
      if (this.vm.privacyDialog.visible) {
        DialogOverlay() {
          ConfirmDialogView({ state: this.vm.privacyDialog })
        }
      }
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
      if (this.vm.editPairCodeDialog.visible) {
        DialogOverlay() {
          InputDialogView({ state: this.vm.editPairCodeDialog })
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
      if (this.vm.pairDialogVisible) {
        DialogOverlay() {
          this.PairCodeDialog()
        }
      }
      // 配对码帮助信息：渲染在配对码对话框之后（Stack 最上层），否则会被遮挡
      if (this.vm.helpDialog.visible) {
        DialogOverlay() {
          ConfirmDialogView({ state: this.vm.helpDialog })
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SheetInfoRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor(AuthTheme.textSecondary)
        .width(80)
      Text(value)
        .fontSize(14)
        .fontColor(AuthTheme.textMain)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  /** 服务器详情底部面板：信息展示 + 操作按钮（删除为红色） */
  @Builder
  ServerSheet() {
    Column() {
      Text(this.vm.sheetServer?.serverName ?? '')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
        .width('100%')

      Column() {
        this.SheetInfoRow(L10n.serverAddProtocol,
          this.vm.sheetServer?.isP2p === true ? 'P2P'
            : (this.vm.sheetServer?.serverUrl ?? '').startsWith('https') ? 'HTTPS' : 'HTTP')
        this.SheetInfoRow(L10n.serverAddAddressLabel,
          this.vm.sheetServer?.isP2p === true ? (this.vm.sheetServer?.pairCode ?? '') : (this.vm.sheetServer?.serverUrl ?? ''))
        this.SheetInfoRow(L10n.username, this.vm.sheetServer?.username ?? '')
      }
      .margin({ top: 16 })
      .width('100%')
      .padding(16)
      .backgroundColor(AuthTheme.nestedCard)
      .borderRadius(12)

      // 按钮统一靠右排列，宽度自适应（内边距一致）
      Row({ space: 12 }) {
        ActionButton({
          label: L10n.authPairCodeConnect,
          variant: 'primary',
          action: () => {
            const target = this.vm.sheetServer;
            this.vm.closeServerSheet();
            if (target !== undefined) {
              void this.vm.handleServerTap(target);
            }
          }
        })
        ActionButton({
          label: L10n.edit,
          variant: 'outlined',
          action: () => {
            const target = this.vm.sheetServer;
            this.vm.closeServerSheet();
            if (target !== undefined) {
              this.vm.handleMenuSelection('edit', target);
            }
          }
        })
        ActionButton({
          label: L10n.delete,
          variant: 'danger',
          action: () => {
            const target = this.vm.sheetServer;
            this.vm.closeServerSheet();
            if (target !== undefined) {
              this.vm.handleMenuSelection('delete', target);
            }
          }
        })
      }
      .justifyContent(FlexAlign.End)
      .margin({ top: 16 })
      .width('100%')
    }
    .padding(20)
    .width('100%')
  }

  @Builder
  LoadingOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AuthTheme.mask)
      Row({ space: 14 }) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color(AuthTheme.primary)
        Text(L10n.authLoginLoading)
          .fontSize(14)
          .fontColor(AuthTheme.textMain)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .borderRadius(12)
      .backgroundColor(AuthTheme.dialogBg)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ServerListCard() {
    Column() {
      AuthHeader({
        title: L10n.serverListTitle,
        // 云朵图标，对应 Flutter Icons.cloud_done
        icon: $r('sys.symbol.checkmark_icloud_fill')
      })

      Refresh({ refreshing: this.isRefreshing !! }) {
        Scroll() {
          Column() {
            // 已保存的服务器区域
            this.ServerSection(L10n.serverSaved, true)
            // 自动发现的服务器区域
            if (this.vm.discoveredServers.length > 0) {
              this.ServerSection(L10n.serverScanned, false)
            }
          }
          .width('100%')
        }
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
      .onRefreshing(() => {
        this.isRefreshing = true;
        // 下拉刷新：重新加载已保存服务器并重新扫描局域网
        this.vm.refreshAll().finally(() => {
          this.isRefreshing = false;
        });
      })
      .layoutWeight(1)
      .width('100%')
    }
    // 全屏覆盖，对应 Flutter 手机端半透明卡片
    .width('100%')
    .height('100%')
    .backgroundColor(AuthTheme.cardBg)
    // 背景色延伸到状态栏/导航栏后面，实现完全沉浸（内容仍在安全区内）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  ServerSection(title: string, isSaved: boolean) {
    // 已保存服务器为空时不显示区域标题（添加入口仍保留）
    if (!isSaved || this.vm.savedServers.length > 0) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AuthTheme.textSecondary)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })
    }

    if (isSaved) {
      ForEach(this.vm.savedServers, (server: ServerInfo) => {
        Column() {
          this.ServerItem(server)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 4 })
      }, (server: ServerInfo) => `saved-${JSON.stringify(server)}`)

      // 添加服务器按钮
      Column() {
        this.AddServerItem($r('sys.symbol.plus'), L10n.addServer, (): void => {
          this.vm.goToAddServerView(undefined);
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })

      // 使用配对码添加服务器
      Column() {
        this.AddServerItem($r('sys.symbol.qrcode'), L10n.serverAddByPairCodeTitle, (): void => {
          this.vm.openPairCodeDialog();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })
    } else {
      ForEach(this.vm.discoveredServers, (server: ServerInfo) => {
        Column() {
          this.ServerItem(server)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 4 })
      }, (server: ServerInfo) => `disc-${JSON.stringify(server)}`)
    }
  }

  @Builder
  ServerItem(server: ServerInfo) {
    Row() {
      Image(platformIconResource(server.serverPlatform))
        .width(50)
        .height(50)

      Column() {
        Row({ space: 6 }) {
          if (server.isLocalServer) {
            // 本机 提示标签，对应 Flutter CustomTag（secondary 背景 + 白色文字）
            Text(L10n.serverLocalServer)
              .fontSize(10)
              .fontColor(Color.White)
              .backgroundColor(AuthTheme.secondary)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
          Text(server.displayHostName +
          (server.serverName.length > 0 ? ` (${server.serverName})` : ''))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(AuthTheme.textMain)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Text(server.isP2p ? 'P2P' : server.serverUrl)
          .fontSize(14)
          .fontColor(AuthTheme.textSecondary)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (server.hasPairCode()) {
          Text(L10n.serverPairCodeDisplay(maskPairCode(server.pairCode ?? '')))
            .fontSize(14)
            .fontColor(AuthTheme.textSecondary)
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        if (server.username !== undefined && server.username.length > 0) {
          Text(`${L10n.username}:${server.username}`)
            .fontSize(14)
            .fontColor(AuthTheme.textSecondary)
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      if (server.isAutoScanned) {
        // 自动发现的服务器显示选择箭头
        Image($r('sys.media.ohos_ic_public_arrow_right'))
          .width(16)
          .height(16)
          .fillColor(AuthTheme.textSecondary)
          .margin({ right: 6 })
      } else {
        // 已保存的服务器显示竖向三点菜单，点击弹出底部详情面板
        Column({ space: 3 }) {
          Circle()
            .width(3.5)
            .height(3.5)
            .fill(AuthTheme.textSecondary)
          Circle()
            .width(3.5)
            .height(3.5)
            .fill(AuthTheme.textSecondary)
          Circle()
            .width(3.5)
            .height(3.5)
            .fill(AuthTheme.textSecondary)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 9, right: 9, top: 11, bottom: 11 })
        .margin({ right: 6 })
        .onClick(() => {
          this.vm.openServerSheet(server);
        })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AuthTheme.nestedCard)
    .borderRadius(12)
    .onClick(() => {
      void this.vm.handleServerTap(server);
    })
  }

  @Builder
  AddServerItem(icon: Resource, title: string, onTap: () => void) {
    Row() {
      // 图标容器：主题主色 60% 透明，对应 Flutter AddServerItemView
      Column() {
        SymbolGlyph(icon)
          .fontSize(32)
          .fontColor([Color.White])
      }
      .width(50)
      .height(50)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(AuthTheme.primary60)
      .borderRadius(8)

      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
        .layoutWeight(1)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(AuthTheme.nestedCard)
    .borderRadius(12)
    .onClick(() => onTap())
  }

  @Builder
  PairCodeDialog() {
    Column() {
      Text(L10n.serverAddByPairCodeTitle)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
      Text(L10n.serverAddByPairCodeContent)
        .fontSize(14)
        .fontColor(AuthTheme.textMain)
        .margin({ top: 12 })
        .width('100%')

      // 配对码输入框：透明背景，扫码图标位于输入框内部右侧
      Stack({ alignContent: Alignment.End }) {
        TextInput({ text: this.vm.pairCodeInput })
          .width('100%')
          .height(44)
          .enabled(!this.vm.pairConnecting)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: AuthTheme.inputBorder })
          .borderRadius(8)
          .fontColor(AuthTheme.textMain)
          .placeholderColor(AuthTheme.textHint)
          .placeholderFont({ size: 14 })
          .padding({ left: 12, right: 46 })
          .onChange((v: string) => {
            this.vm.onPairCodeInputChange(v);
          })
        SymbolGlyph($r('sys.symbol.qrcode'))
          .fontSize(22)
          .fontColor([AuthTheme.textMain])
          .margin({ right: 12 })
          .enabled(!this.vm.pairConnecting)
          .onClick(() => {
            this.scanQr();
          })
      }
      .width('100%')
      .margin({ top: 12 })

      if (this.vm.pairFieldError.length > 0) {
        Text(this.vm.pairFieldError)
          .fontSize(12)
          .fontColor(AuthTheme.errorColor)
          .width('100%')
          .margin({ top: 6 })
      }

      if (this.vm.pairConnecting) {
        Row({ space: 12 }) {
          LoadingProgress().width(22).height(22).color(AuthTheme.primary)
          Text(L10n.serverConnecting)
            .fontSize(14)
            .fontColor(AuthTheme.textMain)
        }
        .width('100%')
        .margin({ top: 16 })
      }

      if (!this.vm.pairConnecting && this.vm.pairConnectError.length > 0) {
        Text(this.vm.pairConnectError)
          .fontSize(12)
          .fontColor(AuthTheme.errorColor)
          .width('100%')
          .margin({ top: 8 })
      }

      Text(L10n.serverPairCodeHowLink)
        .fontSize(14)
        .fontColor(this.vm.pairConnecting ? AuthTheme.textSecondary : AuthTheme.primary)
        .width('100%')
        .margin({ top: 10 })
        .enabled(!this.vm.pairConnecting)
        .onClick(() => this.vm.showPairCodeHelp())

      Row({ space: 12 }) {
        DialogTextButton({
          label: L10n.cancel,
          action: () => this.vm.closePairCodeDialog()
        })
        DialogTextButton({
          label: L10n.ok,
          action: () => {
            void this.vm.submitPairCode();
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
    .borderRadius(16)
    .backgroundColor(AuthTheme.dialogBg)
  }

  private scanQr(): void {
    const context = getContext(this) as common.UIAbilityContext;
    scanPairCodeQr(context)
      .then((value: string) => {
        const v = value.trim();
        if (v.length === 0) {
          return;
        }
        const err = validatePairCodeText(v);
        if (err.length === 0) {
          this.vm.onPairCodeInputChange(v);
          this.vm.pairFieldError = '';
          return;
        }
        promptAction.showToast({ message: L10n.serverPairCodeScanInvalid });
      })
      .catch(() => {
        promptAction.showToast({ message: L10n.serverPairCodeScanInvalid });
      });
  }
}
