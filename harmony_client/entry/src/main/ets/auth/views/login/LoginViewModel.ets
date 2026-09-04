import { common } from '@kit.AbilityKit';
import { L10n } from '../../../core/localization/L10n';
import { AuthService } from '../../AuthService';
import { LoginResponse, ServerStatusResponse } from '../../models/LoginResponse';
import { ServerInfo } from '../../models/ServerInfo';
import { ServerStorageService } from '../../../core/storage/ServerStorageService';
import { APIClient } from '../../../core/network/APIClient';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { P2PService } from '../../../p2p/P2PService';
import { JsonCodec, ServerStatusJson } from '../../../common/JsonTypes';
import { ConfirmDialogState, InputDialogState, TwofaDialogState } from '../common/AuthUi';
import { validatePairCodeText } from '../server_list/ServerListViewModel';
import { ServerListViewModel } from '../server_list/ServerListViewModel';

/** 打开系统浏览器访问外部链接 */
export function openExternalUrl(context: common.UIAbilityContext, url: string): void {
  try {
    context.openLink(url);
  } catch (_e) {
    // 打开失败时静默处理
  }
}

/**
 * 登录视图模型，对应 Flutter LoginController。
 * 配对码连接成功后显示账号密码登录；支持 2FA、初始化管理员跳转。
 */
@ObservedV2
export class LoginViewModel {
  @Trace username: string = '';
  @Trace password: string = '';
  @Trace pairCodeInput: string = '';
  @Trace isLoading: boolean = false;
  @Trace welcomeTitle: string = '';
  @Trace showPairCodeInput: boolean = false;
  @Trace isPairCodeConnecting: boolean = false;
  @Trace connectedHostName: string = '';

  // 字段校验错误
  @Trace usernameError: string = '';
  @Trace passwordError: string = '';
  @Trace pairFieldError: string = '';

  readonly confirmDialog: ConfirmDialogState = new ConfirmDialogState();
  readonly passwordDialog: InputDialogState = new InputDialogState();
  readonly twofaDialog: TwofaDialogState = new TwofaDialogState();

  /** 承载创建管理员视图的容器 VM（复用 AdminCreateView） */
  readonly adminListVm: ServerListViewModel = new ServerListViewModel();

  /** 登录成功后由页面注入：跳转主页 */
  onLoginSuccess: () => void = () => {
  };

  private authService: AuthService = AuthService.getInstance();
  private loginInProgress: boolean = false;

  get showOnlyPairCode(): boolean {
    return this.showPairCodeInput && this.connectedHostName.length === 0;
  }

  get headerTitle(): string {
    return this.welcomeTitle.length > 0 ? this.welcomeTitle : L10n.authWelcomeTitle;
  }

  /** 页面初始化：探测服务器初始化状态（未创建管理员时引导创建） */
  async init(): Promise<void> {
    try {
      const status = await this.authService.checkServerStatus();
      if (!status.success || !status.isNasCabServer) {
        return;
      }
      this.checkInitStatus(status);
    } catch (_e) {
      // 忽略初始化探测失败
    }
  }

  /** 根据服务器状态判断是否需要引导创建管理员 */
  private checkInitStatus(status: ServerStatusResponse): void {
    const data = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
    if (data.hasSuperAdmin === true) {
      return;
    }
    this.showInitConfirm(data);
  }

  /** 弹出初始化确认框，确认后进入创建管理员视图 */
  private showInitConfirm(data: ServerStatusJson): void {
    const serverItemForInit = new ServerInfo();
    serverItemForInit.serverId = data.serverId ?? '';
    serverItemForInit.serverUrl = APIClient.getInstance().baseUrl;
    serverItemForInit.serverName = 'NasCabServer';
    serverItemForInit.serverHost = LoginViewModel.hostOf(serverItemForInit.serverUrl);
    serverItemForInit.serverPortHttp = data.httpPort !== undefined ? `${data.httpPort}` : '';
    serverItemForInit.serverPortHttps = data.httpsPort !== undefined ? `${data.httpsPort}` : '';
    serverItemForInit.serverHostName = data.hostname ?? 'unknown';
    serverItemForInit.serverPlatform = data.platform ?? 'unknown';
    this.confirmDialog.showConfirm(L10n.serverInit, L10n.serverInitContent, () => {
      this.goToAdminCreate(serverItemForInit);
    }, L10n.ok, '');
  }

  /** 配对码连接 P2P 服务器，成功后显示账号密码登录 */
  async connectP2pByPairCode(): Promise<void> {
    if (this.isPairCodeConnecting) {
      return;
    }
    const code = this.pairCodeInput.trim();
    const validationError = validatePairCodeText(code);
    if (validationError.length > 0) {
      this.pairFieldError = validationError;
      return;
    }

    this.isPairCodeConnecting = true;
    this.pairFieldError = '';
    try {
      await P2PService.getInstance().connectByPairCode(code);
      if (!APIClient.getInstance().isP2pMode) {
        APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
      }
      const status = await this.authService.checkServerStatus(5000);
      if (!status.success || !status.isNasCabServer) {
        this.showError(L10n.serverConnectFail);
        return;
      }
      const data = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
      const hostname = (data.hostname ?? '').trim();
      this.connectedHostName = hostname.length > 0 ? hostname : 'unknown';
      this.checkInitStatus(status);
    } catch (e) {
      this.showError(LoginViewModel.errorMessage(e));
    } finally {
      this.isPairCodeConnecting = false;
    }
  }

  /** 处理登录 */
  async handleLogin(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (!this.validate()) {
      return;
    }
    this.isLoading = true;
    try {
      const status = await this.authService.checkServerStatus();
      if (!status.isNasCabServer) {
        this.showError(L10n.serverConnectFail);
        return;
      }
      const data = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
      if (data.hasSuperAdmin !== true) {
        this.showInitConfirm(data);
        return;
      }

      const serverItem = new ServerInfo();
      serverItem.serverId = data.serverId ?? `${Date.now()}`;
      serverItem.serverUrl = APIClient.getInstance().baseUrl;
      serverItem.serverName = 'NasCabServer';
      serverItem.serverHost = LoginViewModel.hostOf(serverItem.serverUrl);
      serverItem.serverHostName = data.hostname ?? 'unknown';
      serverItem.serverPlatform = data.platform ?? 'unknown';
      serverItem.username = this.username;
      serverItem.password = this.password;
      await this.loginToServer(serverItem);
    } finally {
      this.isLoading = false;
    }
  }

  /** 登录到服务器 */
  async loginToServer(serverItem: ServerInfo, passwordOverride?: string): Promise<void> {
    if (this.loginInProgress) {
      return;
    }
    this.loginInProgress = true;
    if (passwordOverride !== undefined) {
      serverItem.password = passwordOverride;
    }
    try {
      const url = serverItem.serverUrl.trim();
      if (url.length > 0) {
        APIClient.getInstance().setBaseUrl(url);
      }
      const loginResult = await this.authService.loginToServer(serverItem);
      if (loginResult.success) {
        if (loginResult.twoFactorRequired === true && loginResult.tempToken && loginResult.tempToken.length > 0) {
          this.isLoading = false;
          this.twofaDialog.show((code: string) => {
            void this.submitTwoFactor(serverItem, loginResult.tempToken!, code);
          });
          return;
        }
        await this.handleLoginSuccess(serverItem, loginResult);
      } else if (loginResult.code === 999) {
        // 密码错误，弹出带输入框的密码输入框
        this.isLoading = false;
        this.passwordDialog.show(
          L10n.authPasswordError,
          L10n.authPasswordErrorMessage,
          L10n.authPasswordHint,
          '',
          (newPassword: string) => {
            void this.loginToServer(serverItem, newPassword);
          }
        );
      } else {
        this.showError(`${loginResult.message ?? ''}`);
      }
    } catch (e) {
      this.showError(`${L10n.authLoginFailure}: ${LoginViewModel.errorMessage(e)}`);
    } finally {
      this.loginInProgress = false;
      this.isLoading = false;
    }
  }

  /** 提交 2FA 验证码 */
  private async submitTwoFactor(serverItem: ServerInfo, tempToken: string, code: string): Promise<void> {
    try {
      const verifyResult = await this.authService.verifyTwoFactorLogin(tempToken, code);
      if (!verifyResult.success) {
        this.showError(verifyResult.message ?? L10n.authLoginFailure);
        return;
      }
      await this.handleLoginSuccess(serverItem, verifyResult);
    } catch (e) {
      this.showError(`${L10n.authLoginFailure}: ${LoginViewModel.errorMessage(e)}`);
    }
  }

  /** 登录成功处理：更新服务器信息、持久化、跳转主页 */
  private async handleLoginSuccess(serverItem: ServerInfo, loginResult: LoginResponse): Promise<void> {
    serverItem.accessToken = loginResult.accessToken;
    serverItem.serverId = loginResult.serverId ?? 'unknown';
    serverItem.serverPlatform = loginResult.platform ?? 'unknown';
    serverItem.serverHostName = loginResult.hostname ?? 'unknown';
    const ch = (loginResult.customHostname ?? '').trim();
    serverItem.customHostname = ch.length > 0 ? ch : undefined;
    serverItem.refreshToken = loginResult.refreshToken;
    serverItem.serverPortHttp = loginResult.httpPort ?? '';
    serverItem.serverPortHttps = loginResult.httpsPort ?? '';
    const pair = (loginResult.pairCode ?? '').trim();
    if (pair.length > 0) {
      serverItem.pairCode = pair;
    }
    const lan = (loginResult.lanIpv4 ?? '').trim();
    if (lan.length > 0) {
      serverItem.lanIpv4 = lan;
      serverItem.lanHttpPort = loginResult.httpPort ?? '';
      serverItem.lanHttpsPort = loginResult.httpsPort ?? '';
    }
    serverItem.isP2p = serverItem.serverUrl.trim().length === 0 && (serverItem.pairCode ?? '').trim().length > 0;
    await ServerStorageService.getInstance().addServer(serverItem);

    this.authService.applyLoginSuccess(serverItem, loginResult);
    P2PService.getInstance().disconnect();
    this.onLoginSuccess();
  }

  /** 忘记密码：打开官网帮助页，对应 Flutter LoginController.goToRecover */
  goToForgotPasswordHelp(context: common.UIAbilityContext): void {
    openExternalUrl(context, `${NetworkConfig.WEBSITE_BASE_URL}/others/helpFindPwd.html`);
  }

  /** 显示创建管理员视图（复用 AdminCreateView） */
  private goToAdminCreate(serverItem: ServerInfo): void {
    this.adminListVm.selectedServer = serverItem;
    this.adminListVm.showCreateAdminView = true;
  }

  private validate(): boolean {
    let valid = true;
    if (this.username.trim().length === 0) {
      this.usernameError = L10n.serverAddUsernameRequired;
      valid = false;
    } else {
      this.usernameError = '';
    }
    if (this.password.length === 0) {
      this.passwordError = L10n.serverAddPasswordRequired;
      valid = false;
    } else {
      this.passwordError = '';
    }
    return valid;
  }

  private showError(message: string): void {
    this.confirmDialog.showError(message, L10n.authLoginFailure);
  }

  private static hostOf(url: string): string {
    const m = /^[a-zA-Z]+:\/\/([^/:?#]+)/.exec(url.trim());
    return m ? m[1] : '';
  }

  private static errorMessage(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return `${e}`;
  }
}
