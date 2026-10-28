import { promptAction, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { L10n } from '../../../core/localization/L10n';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { SystemBars } from '../../../common/SystemBars';
import { WindowStore } from '../../../common/WindowStore';
import { AppRouter } from '../../../router/AppRouter';
import { LegalPageParam } from '../../pages/LegalPage';
import { ServerInfo } from '../models/ServerInfo';
import { ServerListViewModel, validatePairCodeText } from './server_list/ServerListViewModel';
import { scanPairCodeQr } from './server_list/PairCodeScanner';
import { AdminCreateView } from './admin_create/AdminCreateView';
import {
  AuthBackground,
  AuthHeader,
  AuthTheme,
  ConfirmDialogView,
  DialogOverlay,
  DialogTextButton,
  InputDialogView,
  RemotePrefDialogView,
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
  /** 状态栏高度（vp）：沉浸式布局下顶部内容避让（卡片背景仍顶格延伸） */
  @Local statusBarHeight: number = 0;
  /** 服务器更多菜单底部弹层是否显示 */
  @Local menuSheetVisible: boolean = false;
  /** 当前操作菜单的服务器（弹层头部展示其名称与地址） */
  @Local menuServer: ServerInfo | undefined = undefined;
  /** 弹层中选中的动作，待弹层关闭动画结束后执行 */
  private pendingMenuAction: string = '';
  @Param onNavigateHome: () => void = () => {
  };
  @Param pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.fetchStatusBarHeight();
    // 认证模块固定深色沉浸：全屏布局 + 透明系统栏白字，卡片手动 padding 仅避让一个状态栏高度。
    // fullscreen 必须为 true：与首页保持同一窗口模式，pop 返回时不发生布局模式切换
    // （false 会让系统在手动 padding 之外再叠加一层安全区，导致延迟下跳、顶部双倍空白）。
    // 登出清空导航栈回到本页时，本页作为样式栈底自动恢复（其他页面 deactivate 出栈）。
    SystemBars.activate(this, { colors: SystemBars.immersiveColors(), fullscreen: true });
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
    SystemBars.deactivate(this);
  }

  private fetchStatusBarHeight(): void {
    const w = WindowStore.getMainWindow();
    if (w === undefined) {
      return;
    }
    const area = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = px2vp(area.topRect.height);
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

      // 点击服务器的加载遮罩
      if (this.vm.isTapConnecting) {
        this.LoadingOverlay()
      }

      // 对话框遮罩
      if (this.vm.privacyDialog.visible) {
        DialogOverlay() {
          this.PrivacyConsentDialog()
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
      if (this.vm.remotePrefDialog.visible) {
        DialogOverlay() {
          RemotePrefDialogView({ state: this.vm.remotePrefDialog })
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
    // 服务器更多菜单：底部弹层（替代原悬浮菜单）
    .bindSheet(this.menuSheetVisible, this.ServerMenuSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: AuthTheme.dialogBg,
      onDisappear: (): void => {
        this.onServerMenuSheetDisappear();
      }
    })
  }

  /** 服务器 item 更多菜单底部弹层（替代原悬浮菜单）：
   *  头部展示当前服务器名称与地址，下接 编辑 / 远程连接偏好(有配对码) /
   *  移动到列表顶部(已保存>1) / 启动时自动登录(或取消) / 删除 */
  @Builder
  ServerMenuSheet() {
    Column() {
      if (this.menuServer !== undefined) {
        // 当前操作的服务器：图标 + 名称 + 地址
        Row({ space: 12 }) {
          Image(platformIconResource(this.menuServer!.serverPlatform))
            .width(40)
            .height(40)
            .objectFit(ImageFit.Contain)

          Column() {
            Text(this.sheetServerTitle(this.menuServer!))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(AuthTheme.textMain)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(this.sheetServerAddress(this.menuServer!))
              .fontSize(13)
              .fontColor(AuthTheme.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 20, right: 20, top: 4, bottom: 14 })

        Divider()
          .strokeWidth(0.6)
          .color(AuthTheme.dividerFaint)
          .margin({ left: 20, right: 20 })

        this.ServerMenuSheetItem($r('sys.symbol.square_and_pencil'), L10n.edit, AuthTheme.textMain, 'edit')
        if (this.menuServer!.hasPairCode()) {
          this.ServerMenuSheetItem($r('sys.symbol.slider_horizontal_2'), L10n.serverRemoteConnectPref,
            AuthTheme.textMain, 'remote_pref')
        }
        if (this.vm.savedServers.length > 1) {
          this.ServerMenuSheetItem($r('sys.symbol.arrow_up'), L10n.serverMoveToTop, AuthTheme.textMain, 'move_to_top')
        }
        this.ServerMenuSheetItem($r('sys.symbol.bolt'),
          this.menuServer!.autoLoginOnStartup ? L10n.serverAutoLoginCancel : L10n.serverAutoLogin,
          AuthTheme.textMain, 'toggle_auto_login')
        this.ServerMenuSheetItem($r('sys.symbol.trash'), L10n.delete, AuthTheme.errorColor, 'delete')
      }
      Blank().height(28)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(AuthTheme.dialogBg)
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  /** 底部弹层菜单项（图标 + 标题） */
  @Builder
  ServerMenuSheetItem(icon: Resource, title: string, color: Resource, action: string) {
    Row({ space: 14 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([color])
      Text(title)
        .fontSize(15)
        .fontColor(color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 14 })
    .onClick(() => this.onServerMenuSelect(action))
  }

  /** 弹层标题：主机名 + (自定义名称)，与列表项展示保持一致 */
  private sheetServerTitle(server: ServerInfo): string {
    const host = server.displayHostName.trim();
    const name = server.serverName.trim();
    if (host.length > 0) {
      return name.length > 0 ? `${host} (${name})` : host;
    }
    return name.length > 0 ? name : this.sheetServerAddress(server);
  }

  /** 弹层地址：P2P 服务器展示 P2P 标识，其余展示服务器地址 */
  private sheetServerAddress(server: ServerInfo): string {
    if (server.isP2p || server.serverUrl.trim().length === 0) {
      return 'P2P';
    }
    return server.serverUrl.trim();
  }

  /** 打开底部弹层，记录当前操作的服务器 */
  private openServerMenu(server: ServerInfo): void {
    this.menuServer = server;
    this.pendingMenuAction = '';
    this.menuSheetVisible = true;
  }

  /** 菜单项点击：先收起弹层，动画结束后再执行动作（避免对话框被弹层遮挡） */
  private onServerMenuSelect(action: string): void {
    this.pendingMenuAction = action;
    this.menuSheetVisible = false;
  }

  /** 弹层关闭（含下滑/点遮罩）后清理状态，并按需执行已选动作 */
  private onServerMenuSheetDisappear(): void {
    this.menuSheetVisible = false;
    const action = this.pendingMenuAction;
    const server = this.menuServer;
    this.pendingMenuAction = '';
    this.menuServer = undefined;
    if (action.length > 0 && server !== undefined) {
      this.vm.handleMenuSelection(action, server);
    }
  }

  /** 登录中对话框服务器展示名：自定义名称 → 主机名 → 地址 → 默认名（对齐 Flutter _serverDisplayName） */
  private tapDialogName(server: ServerInfo): string {
    const name = server.serverName.trim();
    if (name.length > 0) {
      return name;
    }
    const hostName = server.displayHostName.trim();
    if (hostName.length > 0) {
      return hostName;
    }
    const url = server.serverUrl.trim();
    return url.length > 0 ? url : 'NasCab Server';
  }

  /** 登录中对话框副标题：主机名 · 平台友好名（对齐 Flutter subtitle 拼接规则） */
  private tapDialogSubtitle(server: ServerInfo): string {
    const parts: string[] = [];
    const hostName = server.displayHostName.trim();
    if (hostName.length > 0) {
      parts.push(hostName);
    }
    const platform = server.platformFriendlyName.trim();
    if (platform.length > 0 && platform !== 'unknown') {
      parts.push(platform);
    }
    return parts.join(' · ');
  }

  /** 登录中对话框头部图标：本机→电脑，配对码→云，其余→服务器（对齐 Flutter computer/cloud/dns） */
  private tapDialogIcon(server: ServerInfo): Resource {
    if (server.isLocalServer) {
      return $r('sys.symbol.computer');
    }
    if (server.hasPairCode()) {
      return $r('sys.symbol.cloud');
    }
    return $r('sys.symbol.externaldrive');
  }

  /** 登录信息条目：小号标签在上，值在下（对齐 Flutter _buildLoginInfoItem） */
  @Builder
  LoginInfoItem(label: string, value: string, dimmed: boolean) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor(AuthTheme.textLabel)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(dimmed ? AuthTheme.textDimmed : AuthTheme.textMain)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 7, bottom: 7 })
  }

  /** 登录中对话框：展示当前登录服务器信息与登录进度（对齐 Flutter _showTapLoadingDialog） */
  @Builder
  TapLoadingDialog() {
    Column() {
      if (this.vm.tappingServer !== undefined) {
        // 头部：服务器图标 + 名称 + 主机名/平台
        Row() {
          Column() {
            SymbolGlyph(this.tapDialogIcon(this.vm.tappingServer!))
              .fontSize(24)
              .fontColor([AuthTheme.primary])
          }
          .width(42)
          .height(42)
          .borderRadius(12)
          .backgroundColor(AuthTheme.primary12)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Column() {
            Text(this.tapDialogName(this.vm.tappingServer!))
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(AuthTheme.textMain)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            if (this.tapDialogSubtitle(this.vm.tappingServer!).length > 0) {
              Text(this.tapDialogSubtitle(this.vm.tappingServer!))
                .fontSize(12)
                .fontColor(AuthTheme.textSubtitle)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: 3 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 12 })
        }
        .width('100%')

        // 服务器详细信息：地址 / 配对码 / 用户名（空值用「—」占位并弱化）
        Column() {
          this.LoginInfoItem(L10n.serverAddAddressLabel,
            this.vm.tappingServer!.serverUrl.trim().length > 0 ? this.vm.tappingServer!.serverUrl.trim() : '—',
            this.vm.tappingServer!.serverUrl.trim().length === 0)
          Divider()
            .strokeWidth(0.6)
            .color(AuthTheme.dividerFaint)
          this.LoginInfoItem(L10n.serverPairCodeLabel,
            (this.vm.tappingServer!.pairCode ?? '').trim().length > 0
              ? (this.vm.tappingServer!.pairCode ?? '').trim() : '—',
            (this.vm.tappingServer!.pairCode ?? '').trim().length === 0)
          if ((this.vm.tappingServer!.username ?? '').trim().length > 0) {
            Divider()
              .strokeWidth(0.6)
              .color(AuthTheme.dividerFaint)
            this.LoginInfoItem(L10n.username, (this.vm.tappingServer!.username ?? '').trim(), false)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(AuthTheme.surface45)
        .margin({ top: 16 })
      }

      // 登录进度
      Row() {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(AuthTheme.primary)
        Text(L10n.authLoginLoading)
          .fontSize(14)
          .fontColor(AuthTheme.textMain)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 10 })
      }
      .width('100%')
      .margin({ top: 12 })

      // 取消按钮单独一行横向居中（对齐 Flutter；右侧补 8 抵消卡片右内边距差）
      Row() {
        DialogTextButton({
          label: L10n.cancel,
          action: () => this.vm.cancelTap()
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ right: 8 })
      .margin({ top: 4 })
    }
    // 宽度取屏幕 80% 与 300 较小值（对齐 Flutter dialogWidth 规则）
    .width('80%')
    .constraintSize({ maxWidth: 300 })
    .padding({ left: 20, right: 12, top: 20, bottom: 8 })
    .borderRadius(18)
    .backgroundColor(AuthTheme.dialogBg)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LoadingOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AuthTheme.mask)
      this.TapLoadingDialog()
    }
    .width('100%')
    .height('100%')
  }

  /** 隐私政策提示对话框：正文 + 用户协议/隐私政策链接（对齐 Flutter _ensureAndroidPrivacyConsent） */
  @Builder
  PrivacyConsentDialog() {
    Column() {
      Text(this.vm.privacyDialog.title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(AuthTheme.textMain)
      Text(this.vm.privacyDialog.message)
        .fontSize(14)
        .fontColor(AuthTheme.textMain)
        .margin({ top: 12 })
        .constraintSize({ maxHeight: 300 })
        .maxLines(20)
        .textOverflow({ overflow: TextOverflow.Clip })
      // 法律文档入口：点击在应用内打开对应页面，隐私对话框保持可见
      Row({ space: 8 }) {
        Text(L10n.authUserAgreement)
          .fontSize(14)
          .fontColor(AuthTheme.primary)
          .padding({ top: 6, bottom: 6, right: 16 })
          .onClick(() => this.openLegal(L10n.authUserAgreement, 'agreement.html'))
        Text(L10n.authPrivacyPolicy)
          .fontSize(14)
          .fontColor(AuthTheme.primary)
          .padding({ top: 6, bottom: 6 })
          .onClick(() => this.openLegal(L10n.authPrivacyPolicy, 'privacy.html'))
      }
      .width('100%')
      .margin({ top: 12 })
      .justifyContent(FlexAlign.Start)
      Row({ space: 12 }) {
        DialogTextButton({
          label: this.vm.privacyDialog.cancelText,
          action: () => {
            this.vm.privacyDialog.close();
            this.vm.privacyDialog.onCancel();
          }
        })
        DialogTextButton({
          label: this.vm.privacyDialog.confirmText,
          action: () => {
            this.vm.privacyDialog.close();
            this.vm.privacyDialog.onConfirm();
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
    .alignItems(HorizontalAlign.Start)
  }

  /** 应用内打开用户协议/隐私政策（对齐 Flutter LegalDocumentOpener 的移动端 WebView 方式） */
  private openLegal(title: string, fileName: string): void {
    const param = new LegalPageParam();
    param.title = title;
    param.url = `${NetworkConfig.WEBSITE_BASE_URL}/others/${fileName}?language=${L10n.currentLanguageCode}`;
    this.pageStack.pushPathByName(AppRouter.LEGAL, param);
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
            this.ServerSection('server_saved', true)
            // 自动发现的服务器区域
            if (this.vm.discoveredServers.length > 0) {
              this.ServerSection('server_scanned', false)
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
    // 内容避让顶部状态栏：AuthHeader 自带 20vp 顶部内边距，这里补偿为状态栏 + 10vp
    .padding({ top: Math.max(this.statusBarHeight - 10, 0) })
    // 背景色延伸到状态栏/导航栏后面，实现完全沉浸（内容仍在安全区内）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  ServerSection(titleKey: string, isSaved: boolean) {
    // 已保存服务器为空时不显示区域标题（添加入口仍保留）
    if (!isSaved || this.vm.savedServers.length > 0) {
      Text(L10n.t(titleKey))
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
        this.AddServerItem($r('sys.symbol.plus'), 'server_add', (): void => {
          this.vm.goToAddServerView(undefined);
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })

      // 使用配对码添加服务器
      Column() {
        this.AddServerItem($r('sys.symbol.qrcode'), 'server_add_by_pair_code_title', (): void => {
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
        // mac 图标资源为 133x100 非正方形，Contain 完整显示避免左右被裁切（对齐 Flutter scaleDown）
        .objectFit(ImageFit.Contain)

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

        // 地址行：开启启动自动登录时左侧显示闪电标识（对齐 Flutter 地址行布局）
        Row({ space: 4 }) {
          if (server.autoLoginOnStartup) {
            SymbolGlyph($r('sys.symbol.bolt'))
              .fontSize(16)
              .fontColor([AuthTheme.primary])
          }
          Text(server.isP2p ? 'P2P' : server.serverUrl)
            .fontSize(14)
            .fontColor(AuthTheme.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 4 })

        if (server.hasPairCode()) {
          Text(L10n.serverPairCodeDisplay(maskPairCode(server.pairCode ?? '')))
            .fontSize(14)
            .fontColor(AuthTheme.textSecondary)
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          // 远程连接偏好信息行「远程连接偏好: P2P直连优先 / P2P中继优先」+ 内联编辑图标（对齐 Flutter）
          Row({ space: 4 }) {
            Text(`${L10n.serverRemoteConnectPref}: ${server.p2pRelayPreferred ? L10n.remotePrefRelayFirst : L10n.remotePrefDirectFirst}`)
              .fontSize(14)
              .fontColor(AuthTheme.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            // 内联编辑图标：点击打开远程连接偏好对话框（子组件 onClick 消费事件，不触发整项点击）
            SymbolGlyph($r('sys.symbol.pencil_line'))
              .fontSize(16)
              .fontColor([AuthTheme.textSecondary])
              .padding(4)
              .onClick(() => {
                this.vm.handleMenuSelection('remote_pref', server);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 4 })
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
        // 已保存的服务器显示竖向三点菜单，点击弹出更多菜单（对齐 Flutter PopupMenuButton）
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
          this.openServerMenu(server);
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
  AddServerItem(icon: Resource, titleKey: string, onTap: () => void) {
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

      // 绑定内解析语言key：切换语言后自动刷新（@Builder 按值传参不会随状态更新）
      Text(L10n.t(titleKey))
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
