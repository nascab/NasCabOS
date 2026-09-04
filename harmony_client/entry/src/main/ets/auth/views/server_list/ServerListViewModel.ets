import { ServerInfo } from '../../models/ServerInfo';
import { AuthService } from '../../AuthService';
import { LoginResponse, ServerStatusResponse } from '../../models/LoginResponse';
import { ServerStorageService } from '../../../core/storage/ServerStorageService';
import { APIClient } from '../../../core/network/APIClient';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { UdpBroadcastListener } from '../../../core/network/UdpBroadcastListener';
import { P2PService } from '../../../p2p/P2PService';
import { L10n } from '../../../core/localization/L10n';
import { PreferencesStore } from '../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../core/storage/CacheKeys';
import { JsonCodec, ServerStatusJson, UdpDiscoveryJson } from '../../../common/JsonTypes';
import { ConfirmDialogState, InputDialogState, TwofaDialogState } from '../common/AuthUi';

/** 配对码文本校验，对应 Flutter ApiController.validatePairCodeText */
export function validatePairCodeText(code: string): string {
  const s = code.trim();
  if (s.length === 0) {
    return L10n.serverPairCodeEmpty;
  }
  if (s.length < 4 || s.length > 32) {
    return L10n.serverPairCodeInvalid;
  }
  return '';
}

/** 标准化 URL 用于比较（去除末尾斜杠、统一小写） */
function normalizeUrl(url: string): string {
  const input = url.trim().toLowerCase();
  return input.replace(/\/+$/, '');
}

function isPrivateIpv4(host: string): boolean {
  const s = host.trim();
  const m = /^(\d{1,3}\.){3}\d{1,3}$/.test(s);
  if (!m) {
    return false;
  }
  const parts = s.split('.');
  if (parts.length !== 4) {
    return false;
  }
  const a = Number(parts[0]);
  const b = Number(parts[1]);
  for (let i = 0; i < parts.length; i++) {
    const v = Number(parts[i]);
    if (Number.isNaN(v) || v < 0 || v > 255) {
      return false;
    }
  }
  if (a === 10) {
    return true;
  }
  if (a === 172 && b >= 16 && b <= 31) {
    return true;
  }
  if (a === 192 && b === 168) {
    return true;
  }
  return a === 127;
}

function isUrlPrivateLan(url: string): boolean {
  const m = /^[a-zA-Z]+:\/\/([^/:?#]+)/.exec(url.trim());
  if (!m) {
    return false;
  }
  return isPrivateIpv4(m[1]);
}

function buildLanServerUrl(lanIpv4: string, httpPort?: string, httpsPort?: string): string {
  const lan = lanIpv4.trim();
  if (lan.length === 0) {
    return '';
  }
  const hp = (httpPort ?? '').trim();
  const hs = (httpsPort ?? '').trim();
  const port = hp.length > 0 ? hp : (hs.length > 0 ? hs : '9000');
  return `http://${lan}:${port}`;
}

@ObservedV2
export class ServerListViewModel {
  @Trace savedServers: ServerInfo[] = [];
  @Trace discoveredServers: ServerInfo[] = [];
  @Trace localServer: ServerInfo | undefined = undefined;
  @Trace showCreateAdminView: boolean = false;
  @Trace selectedServer: ServerInfo | undefined = undefined;
  @Trace isTapConnecting: boolean = false;
  /** 服务器详情 bottom sheet */
  @Trace showServerSheet: boolean = false;
  @Trace sheetServer: ServerInfo | undefined = undefined;

  openServerSheet(server: ServerInfo): void {
    this.sheetServer = server;
    this.showServerSheet = true;
  }

  closeServerSheet(): void {
    this.showServerSheet = false;
  }

  readonly confirmDialog: ConfirmDialogState = new ConfirmDialogState();
  readonly privacyDialog: ConfirmDialogState = new ConfirmDialogState();
  /** 「如何获取配对码」帮助弹窗（需叠在配对码对话框上方） */
  readonly helpDialog: ConfirmDialogState = new ConfirmDialogState();
  readonly passwordDialog: InputDialogState = new InputDialogState();
  readonly editPairCodeDialog: InputDialogState = new InputDialogState();
  readonly twofaDialog: TwofaDialogState = new TwofaDialogState();

  // 配对码连接对话框
  @Trace pairDialogVisible: boolean = false;
  @Trace pairCodeInput: string = '';
  @Trace pairFieldError: string = '';
  @Trace pairConnectError: string = '';
  @Trace pairConnecting: boolean = false;

  private udpListener: UdpBroadcastListener = new UdpBroadcastListener();
  private authService: AuthService = AuthService.getInstance();
  private tapLocked: boolean = false;
  private initFlowStarted: boolean = false;

  /** 登录成功后由页面注入：跳转主页 */
  onLoginSuccess: () => void = () => {
  };
  /** 隐私政策不同意的处理（退出应用），由页面注入 */
  onExitApp: () => void = () => {
  };

  async init(): Promise<void> {
    if (this.initFlowStarted) {
      return;
    }
    this.initFlowStarted = true;
    const consented = await this.ensurePrivacyConsent();
    if (!consented) {
      this.onExitApp();
      return;
    }
    await this.initAfterPrivacyConsent();
  }

  destroy(): void {
    this.udpListener.stopListening();
  }

  private async ensurePrivacyConsent(): Promise<boolean> {
    const store = PreferencesStore.getInstance();
    if (store.getBool(CacheKeys.PRIVACY_CONSENT_ACCEPTED, false)) {
      return true;
    }
    return new Promise<boolean>((resolve) => {
      this.privacyDialog.title = L10n.privacyConsentTitle;
      this.privacyDialog.message =
        `${L10n.privacyConsentMessage1}\n\n${L10n.privacyConsentMessage2}\n\n${L10n.privacyConsentMessage3}`;
      this.privacyDialog.confirmText = L10n.privacyConsentAgree;
      this.privacyDialog.cancelText = L10n.privacyConsentDisagree;
      this.privacyDialog.onConfirm = () => {
        void store.setBool(CacheKeys.PRIVACY_CONSENT_ACCEPTED, true);
        resolve(true);
      };
      this.privacyDialog.onCancel = () => {
        resolve(false);
      };
      this.privacyDialog.visible = true;
    });
  }

  private async initAfterPrivacyConsent(): Promise<void> {
    await this.loadSavedServers();
    await this.startUdpListening();
    await this.checkLocalNasCabServerStatus();
  }

  private isSameIdentity(left: ServerInfo, right: ServerInfo): boolean {
    const lid = left.serverId.trim();
    const rid = right.serverId.trim();
    if (lid.length > 0 && rid.length > 0) {
      return lid === rid;
    }
    return left.uniqueKey === right.uniqueKey;
  }

  // 添加“本机”标识，本机服务器排在前面
  private addLocalSignToServerList(serverList: ServerInfo[]): void {
    for (let i = 0; i < serverList.length; i++) {
      const server = serverList[i];
      server.isLocalServer = this.localServer !== undefined && server.serverId === this.localServer.serverId;
    }
    serverList.sort((a: ServerInfo, b: ServerInfo): number => {
      if (a.isLocalServer && !b.isLocalServer) {
        return -1;
      }
      if (!a.isLocalServer && b.isLocalServer) {
        return 1;
      }
      return 0;
    });
  }

  /// 探测 127.0.0.1 本机服务，检测本机是否启用了nascab服务
  async checkLocalNasCabServerStatus(): Promise<void> {
    try {
      const status = await this.authService.checkServerStatusAt(NetworkConfig.LOCALHOST_BASE_URL, 2000);
      if (status.isNasCabServer) {
        const data = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
        const local = new ServerInfo();
        local.serverId = data.serverId ?? '';
        local.serverUrl = NetworkConfig.LOCALHOST_BASE_URL;
        local.serverName = 'LocalHost';
        local.serverHost = '127.0.0.1';
        local.serverPortHttp = data.httpPort !== undefined ? `${data.httpPort}` : '9000';
        local.serverPortHttps = data.httpsPort !== undefined ? `${data.httpsPort}` : '9443';
        local.serverHostName = data.hostname ?? 'localhost';
        local.serverPlatform = data.platform ?? 'unknown';
        local.isAutoScanned = true;
        this.localServer = local;
        this.addLocalSignToServerList(this.savedServers);
        this.addLocalSignToServerList(this.discoveredServers);
      }
    } catch (_e) {
      this.localServer = undefined;
    }
  }

  /// 处理发现的服务器
  private onServerDiscovered(info: UdpDiscoveryJson): void {
    try {
      const host = info.host ?? '';
      const httpPort = `${info.port ?? info.httpPort ?? '9000'}`;
      const serverItem = new ServerInfo();
      serverItem.serverId = info.serverId ?? '';
      serverItem.serverUrl = `http://${host}:${httpPort}`;
      serverItem.serverName = 'NasCabServer';
      serverItem.serverHost = host;
      serverItem.serverPortHttp = httpPort;
      serverItem.serverPortHttps = info.httpsPort !== undefined ? `${info.httpsPort}` : '';
      serverItem.serverHostName = info.hostname ?? host;
      serverItem.serverPlatform = info.platform ?? 'unknown';
      serverItem.isAutoScanned = true;

      let exists = false;
      for (const s of this.discoveredServers) {
        if (this.isSameIdentity(s, serverItem)) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        for (const s of this.savedServers) {
          if (this.isSameIdentity(s, serverItem)) {
            exists = true;
            break;
          }
        }
      }
      if (!exists) {
        const next = this.discoveredServers.slice();
        next.push(serverItem);
        this.discoveredServers = next;
        this.addLocalSignToServerList(this.discoveredServers);
      }
    } catch (_e) {
      // 忽略无法解析的广播
    }
  }

  /// 显示添加服务器界面（独立页面，由页面注入路由回调）
  onOpenAddServer: (server: ServerInfo | undefined) => void = (_server: ServerInfo | undefined) => {
  };

  goToAddServerView(server: ServerInfo | undefined): void {
    this.selectedServer = server;
    this.onOpenAddServer(server);
  }

  /// 显示创建管理员界面
  goToCreateAdminView(server: ServerInfo | undefined): void {
    this.selectedServer = server;
    this.showCreateAdminView = true;
  }

  /// 处理服务器点击事件
  /// 通道优先级：局域网直连 > P2P
  async handleServerTap(server: ServerInfo): Promise<void> {
    if (this.tapLocked) {
      return;
    }
    this.tapLocked = true;
    this.isTapConnecting = true;
    try {
      const hasPairCode = server.hasPairCode();
      const hasDirectUrl = server.hasDirectUrl() && server.serverUrl.trim() !== NetworkConfig.P2P_BASE_URL;

      let status: ServerStatusResponse | undefined = undefined;
      let usingP2p = false;

      // Phase 1: 局域网直连
      if (hasDirectUrl) {
        P2PService.getInstance().disconnect();
        APIClient.getInstance().setBaseUrl(server.serverUrl.trim());
        status = await this.authService.checkServerStatus(2000);

        // serverUrl 失败，尝试 lanIpv4
        if ((!status.success || !status.isNasCabServer) && hasPairCode) {
          const lan = (server.lanIpv4 ?? '').trim();
          const lanUrl = lan.length > 0 ? `http://${lan}:${this.resolveHttpPort(server)}` : '';
          const lanAlreadyTried = lanUrl.length > 0 && normalizeUrl(lanUrl) === normalizeUrl(server.serverUrl);
          if (lan.length > 0 && !lanAlreadyTried) {
            P2PService.getInstance().disconnect();
            APIClient.getInstance().setBaseUrl(lanUrl);
            const lanStatus = await this.authService.checkServerStatus(2000);
            if (this.matchServerId(lanStatus, server)) {
              status = lanStatus;
            }
          }
        }
      }

      // Phase 2: P2P 自动探测直连/中继
      if ((status === undefined || !status.success || !status.isNasCabServer) && hasPairCode) {
        usingP2p = true;
        P2PService.getInstance().disconnect();
        await this.ensureP2pConnected(server);
        if (!APIClient.getInstance().isP2pMode) {
          APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
        }
        status = await this.authService.checkServerStatus(3000);
      }

      if (status === undefined || !status.success || !status.isNasCabServer) {
        this.showError(L10n.serverConnectFail);
        return;
      }

      const statusData = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
      const hasSuperAdmin = statusData.hasSuperAdmin === true;
      if (!hasSuperAdmin) {
        this.confirmDialog.showConfirm(L10n.serverInit, L10n.serverInitContent, () => {
          this.goToCreateAdminView(server);
        });
        return;
      }

      if (server.isAutoScanned) {
        if (usingP2p) {
          server.serverId = statusData.serverId ?? server.serverId;
          server.serverHostName = statusData.hostname ?? server.serverHostName;
          server.serverPlatform = statusData.platform ?? server.serverPlatform;
          server.serverPortHttp = statusData.httpPort !== undefined ? `${statusData.httpPort}` : server.serverPortHttp;
          server.serverPortHttps = statusData.httpsPort !== undefined ? `${statusData.httpsPort}` : server.serverPortHttps;
        }
        this.goToAddServerView(server);
        return;
      }

      if (server.requirePasswordEveryLogin) {
        this.isTapConnecting = false;
        this.passwordDialog.show(
          L10n.serverLoginPasswordRequired,
          L10n.serverLoginPasswordRequiredMessage,
          L10n.authPasswordHint,
          '',
          (newPassword: string) => {
            const pwd = newPassword.trim();
            if (pwd.length === 0) {
              return;
            }
            this.isTapConnecting = true;
            void this.loginToServer(server, pwd, false);
          }
        );
        return;
      }

      await this.loginToServer(server, undefined, true);
    } catch (e) {
      this.showError(L10n.serverStatusCheckFailedWithError(ServerListViewModel.errorMessage(e)));
    } finally {
      this.tapLocked = false;
      this.isTapConnecting = false;
    }
  }

  /// 从 ServerInfo 解析 HTTP 端口（优先 httpPort，其次 httpsPort，默认 9000）
  private resolveHttpPort(server: ServerInfo): string {
    const httpPort = server.serverPortHttp.trim();
    if (httpPort.length > 0) {
      return httpPort;
    }
    const httpsPort = server.serverPortHttps.trim();
    if (httpsPort.length > 0) {
      return httpsPort;
    }
    return '9000';
  }

  /// 校验 checkServerStatus 返回的 serverId 是否与 serverItem 匹配
  private matchServerId(status: ServerStatusResponse, server: ServerInfo): boolean {
    if (!status.success || !status.isNasCabServer) {
      return false;
    }
    const data = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
    const statusServerId = (data.serverId ?? '').trim();
    const itemServerId = server.serverId.trim();
    if (statusServerId.length === 0 || itemServerId.length === 0) {
      return false;
    }
    return statusServerId === itemServerId;
  }

  /// 遇到 P2P_DEVICE_OFFLINE 时重试，设备可能处于重连信令服务器的短暂窗口期
  private async ensureP2pConnected(server: ServerInfo): Promise<void> {
    const code = (server.pairCode ?? '').trim();
    if (code.length === 0) {
      throw new Error(L10n.serverPairCodeEmpty);
    }
    const maxRetries = 3;
    const retryDelayMs = 1500;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await P2PService.getInstance().connectByPairCode(code);
        return;
      } catch (e) {
        const msg = ServerListViewModel.errorMessage(e);
        if (msg.includes('P2P_DEVICE_OFFLINE') && attempt < maxRetries) {
          await ServerListViewModel.sleep(retryDelayMs);
          continue;
        }
        throw new Error(ServerListViewModel.errorMessage(e));
      }
    }
  }

  /// 处理菜单选择
  handleMenuSelection(action: string, serverItem: ServerInfo): void {
    if (action === 'edit_pair_code') {
      this.showEditPairCodeDialog(serverItem);
    } else if (action === 'edit') {
      this.goToAddServerView(serverItem);
    } else if (action === 'delete') {
      this.showDeleteConfirmDialog(serverItem);
    }
  }

  private showEditPairCodeDialog(serverItem: ServerInfo): void {
    this.editPairCodeDialog.show(
      L10n.serverEditPairCodeTitle,
      L10n.serverEditPairCodeContent,
      '',
      (serverItem.pairCode ?? '').trim(),
      (value: string) => {
        const code = value.trim();
        const err = validatePairCodeText(code);
        if (err.length > 0) {
          this.confirmDialog.showInfo(L10n.tip, err);
          return;
        }
        serverItem.pairCode = code;
        void ServerStorageService.getInstance().addServer(serverItem).then(() => this.refreshSavedServers());
      }
    );
  }

  /// 显示删除确认对话框并删除服务器
  private showDeleteConfirmDialog(serverItem: ServerInfo): void {
    const serverName = serverItem.serverName.length > 0 ? serverItem.serverName : serverItem.serverHostName;
    this.confirmDialog.showConfirm(
      L10n.delete,
      L10n.serverDeleteConfirmMessage(serverName),
      () => {
        void ServerStorageService.getInstance().removeServer(serverItem).then(() => this.refreshSavedServers());
      },
      L10n.delete,
      L10n.cancel
    );
  }

  /// 打开配对码添加对话框
  openPairCodeDialog(): void {
    this.pairCodeInput = '';
    this.pairFieldError = '';
    this.pairConnectError = '';
    this.pairConnecting = false;
    this.pairDialogVisible = true;
  }

  closePairCodeDialog(): void {
    if (!this.pairConnecting) {
      this.pairDialogVisible = false;
    }
  }

  showPairCodeHelp(): void {
    // 独立的帮助弹窗（渲染在配对码对话框上层）
    this.helpDialog.showInfo(L10n.serverPairCodeHowTitle, L10n.serverPairCodeHowContent);
  }

  onPairCodeInputChange(value: string): void {
    this.pairCodeInput = value;
    this.pairFieldError = validatePairCodeText(value);
  }

  /// 配对码添加：在对话框内完成校验与连接，成功后进入添加服务器页
  async submitPairCode(): Promise<void> {
    if (this.pairConnecting) {
      return;
    }
    const code = this.pairCodeInput.trim();
    const validationError = validatePairCodeText(code);
    if (validationError.length > 0) {
      this.pairFieldError = validationError;
      return;
    }
    this.pairConnecting = true;
    this.pairFieldError = '';
    this.pairConnectError = '';
    try {
      await P2PService.getInstance().connectByPairCode(code);
      if (!APIClient.getInstance().isP2pMode) {
        APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
      }
      const status = await this.authService.checkServerStatus(20000);
      if (!status.success || !status.isNasCabServer) {
        this.pairConnectError = L10n.serverConnectFail;
        return;
      }
      const statusData = status.serverData ? JsonCodec.parse<ServerStatusJson>(status.serverData) : new ServerStatusJson();
      const serverId = statusData.serverId ?? '';
      // 优先使用已保存的同 serverId 服务器名称
      let preferredName = 'NasCabServer';
      const matches: ServerInfo[] = [];
      for (const s of this.savedServers) {
        if (s.serverId.trim().length > 0 && s.serverId === serverId) {
          matches.push(s);
        }
      }
      if (matches.length === 1) {
        preferredName = matches[0].serverName;
      }

      const candidate = new ServerInfo();
      candidate.serverId = serverId;
      candidate.serverUrl = '';
      candidate.serverName = preferredName;
      candidate.serverPortHttp = statusData.httpPort !== undefined ? `${statusData.httpPort}` : '';
      candidate.serverPortHttps = statusData.httpsPort !== undefined ? `${statusData.httpsPort}` : '';
      candidate.serverHostName = statusData.hostname ?? '';
      candidate.serverPlatform = statusData.platform ?? 'unknown';
      candidate.isP2p = true;
      candidate.pairCode = code;

      this.pairDialogVisible = false;
      this.goToAddServerView(candidate);
    } catch (e) {
      this.pairConnectError = ServerListViewModel.errorMessage(e);
    } finally {
      this.pairConnecting = false;
    }
  }

  /// 登录到服务器
  async loginToServer(serverItem: ServerInfo, passwordOverride?: string, persistPasswordOverride: boolean = true): Promise<void> {
    try {
      if (!APIClient.getInstance().isP2pMode) {
        const url = serverItem.serverUrl.trim();
        if (url.length > 0) {
          APIClient.getInstance().setBaseUrl(url);
        }
      }
      const persistPassword = persistPasswordOverride && !serverItem.requirePasswordEveryLogin;
      const loginResult = await this.authService.loginToServer(serverItem);
      if (loginResult.success) {
        if (loginResult.twoFactorRequired === true && loginResult.tempToken && loginResult.tempToken.length > 0) {
          this.isTapConnecting = false;
          this.twofaDialog.show((code: string) => {
            this.isTapConnecting = true;
            void this.submitTwoFactor(serverItem, loginResult.tempToken!, code, persistPassword);
          });
          return;
        }
        await this.handleLoginSuccess(serverItem, loginResult, persistPassword ? serverItem.password : '');
      } else if (loginResult.code === 999) {
        // 密码错误，弹出带输入框的密码输入框
        this.isTapConnecting = false;
        this.passwordDialog.show(
          L10n.authPasswordError,
          L10n.authPasswordErrorMessage,
          L10n.authPasswordHint,
          '',
          (newPassword: string) => {
            serverItem.password = newPassword;
            this.isTapConnecting = true;
            void this.loginToServer(serverItem, undefined, persistPasswordOverride);
          }
        );
      } else {
        this.showError(`${loginResult.message ?? ''}`);
      }
    } catch (e) {
      this.showError(`${L10n.authLoginFailure}: ${ServerListViewModel.errorMessage(e)}`);
    }
  }

  private async submitTwoFactor(serverItem: ServerInfo, tempToken: string, code: string,
    persistPassword: boolean): Promise<void> {
    try {
      const verifyResult = await this.authService.verifyTwoFactorLogin(tempToken, code);
      if (!verifyResult.success) {
        this.showError(verifyResult.message ?? L10n.authLoginFailure);
        return;
      }
      await this.handleLoginSuccess(serverItem, verifyResult, persistPassword ? serverItem.password : '');
    } catch (e) {
      this.showError(`${L10n.authLoginFailure}: ${ServerListViewModel.errorMessage(e)}`);
    } finally {
      this.isTapConnecting = false;
    }
  }

  private async handleLoginSuccess(serverItem: ServerInfo, loginResult: LoginResponse,
    passwordToPersist?: string): Promise<void> {
    serverItem.password = passwordToPersist !== undefined ? passwordToPersist : serverItem.password;
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
      const currentUrl = serverItem.serverUrl.trim();
      if (currentUrl.length === 0) {
        serverItem.serverUrl = buildLanServerUrl(lan, loginResult.httpPort, loginResult.httpsPort);
        if ((serverItem.pairCode ?? '').trim().length === 0 && (serverItem.userInputUrl ?? '').trim().length === 0) {
          serverItem.userInputUrl = serverItem.serverUrl;
        }
      }
    }
    serverItem.isP2p = serverItem.serverUrl.trim().length === 0 && (serverItem.pairCode ?? '').trim().length > 0;
    await ServerStorageService.getInstance().addServer(serverItem);
    await this.refreshSavedServers();

    this.authService.applyLoginSuccess(serverItem, loginResult);

    await this.stopUdpListening();
    this.onLoginSuccess();
  }

  /// 开始UDP监听
  async startUdpListening(): Promise<void> {
    this.udpListener.stopListening();
    this.udpListener.setOnServerDiscovered((info: UdpDiscoveryJson) => this.onServerDiscovered(info));
    await this.udpListener.startListening();
  }

  /// 停止UDP监听
  async stopUdpListening(): Promise<void> {
    this.udpListener.stopListening();
  }

  /// 加载已保存的服务器列表
  private async loadSavedServers(): Promise<void> {
    this.savedServers = ServerStorageService.getInstance().loadServers();
    this.addLocalSignToServerList(this.savedServers);
  }

  /// 刷新已保存的服务器列表（公共方法）
  async refreshSavedServers(): Promise<void> {
    await this.loadSavedServers();
    const next = this.discoveredServers.filter(
      (server: ServerInfo) => !this.savedServers.some((saved: ServerInfo) => this.isSameIdentity(saved, server))
    );
    this.discoveredServers = next;
  }

  /** 下拉刷新：重新加载已保存服务器，并重启局域网 UDP 扫描 */
  async refreshAll(): Promise<void> {
    await this.refreshSavedServers();
    await this.stopUdpListening();
    this.discoveredServers = [];
    await this.startUdpListening();
  }

  private showError(message: string): void {
    this.confirmDialog.showError(message, L10n.error);
  }

  private static errorMessage(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return `${e}`;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => setTimeout(resolve, ms));
  }
}
