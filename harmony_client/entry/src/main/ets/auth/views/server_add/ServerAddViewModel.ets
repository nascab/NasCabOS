import { ServerInfo } from '../../models/ServerInfo';
import { AuthService } from '../../AuthService';
import { LoginResponse } from '../../models/LoginResponse';
import { ServerStorageService } from '../../../core/storage/ServerStorageService';
import { APIClient } from '../../../core/network/APIClient';
import { NetworkConfig } from '../../../core/network/NetworkConfig';
import { L10n } from '../../../core/localization/L10n';
import { JsonCodec, ServerStatusJson } from '../../../common/JsonTypes';
import { P2PService } from '../../../p2p/P2PService';
import { ConfirmDialogState, TwofaDialogState } from '../common/AuthUi';
import { ServerListViewModel } from '../server_list/ServerListViewModel';

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
export class ServerAddViewModel {
  @Trace serverName: string = 'NasCabServer';
  @Trace serverUrl: string = '';
  @Trace username: string = '';
  @Trace password: string = '';
  @Trace protocol: string = 'http';
  @Trace needInputPwdEveryTime: boolean = false;
  @Trace isLoading: boolean = false;

  readonly confirmDialog: ConfirmDialogState = new ConfirmDialogState();
  readonly twofaDialog: TwofaDialogState = new TwofaDialogState();

  /** 返回回调，由视图注入父组件 onBack（双保险：goBack 同时回退列表状态） */
  onExit: () => void = () => {
  };

  prefillServerInfo: ServerInfo | undefined = undefined;
  private authService: AuthService = AuthService.getInstance();
  private listVm: ServerListViewModel;

  constructor(listVm: ServerListViewModel) {
    this.listVm = listVm;
    this.prefillServerInfo = listVm.selectedServer;
    this.initializeFromPrefill();
  }

  get isP2pMode(): boolean {
    return this.prefillServerInfo?.isP2p === true;
  }

  private initializeFromPrefill(): void {
    const serverInfo = this.prefillServerInfo;
    if (serverInfo === undefined) {
      this.serverName = 'NasCabServer';
      return;
    }
    if (serverInfo.isP2p) {
      this.protocol = 'http';
      this.serverName = serverInfo.serverName.length > 0 ? serverInfo.serverName : 'P2P';
      this.serverUrl = '';
      this.username = serverInfo.username ?? '';
      this.password = serverInfo.password ?? '';
      this.needInputPwdEveryTime = serverInfo.requirePasswordEveryLogin;
      return;
    }
    // 解析 scheme/host/port
    const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^/:?#]+)(?::(\d+))?/.exec(serverInfo.serverUrl.trim());
    this.protocol = m && m[1] ? m[1].toLowerCase() : 'http';
    const hostPort = m && m[2] ? (m[3] ? `${m[2]}:${m[3]}` : `${m[2]}`) : serverInfo.serverUrl.trim();
    this.serverName = serverInfo.serverName;
    this.serverUrl = hostPort;
    this.username = serverInfo.username ?? '';
    this.password = serverInfo.password ?? '';
    this.needInputPwdEveryTime = serverInfo.requirePasswordEveryLogin;
  }

  toggleProtocol(newProtocol: string): void {
    this.protocol = newProtocol;
  }

  toggleNeedInputPwdEveryTime(value: boolean): void {
    this.needInputPwdEveryTime = value;
  }

  goBack(): void {
    // 通过视图注入的回调返回（pop 回服务器列表），无需确认
    this.onExit();
  }

  /// 处理表单提交
  async handleSubmit(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (this.serverName.trim().length === 0) {
      this.showError(L10n.serverAddNameRequired);
      return;
    }
    if (!this.isP2pMode && this.serverUrl.trim().length === 0) {
      this.showError(L10n.serverAddAddressRequired);
      return;
    }
    if (!this.isP2pMode && !/^[a-zA-Z0-9.-]+(:\d+)?$/.test(this.serverUrl.trim())) {
      this.showError(L10n.serverAddAddressInvalid);
      return;
    }
    if (this.username.trim().length === 0) {
      this.showError(L10n.serverAddUsernameRequired);
      return;
    }
    if (this.password.length === 0) {
      this.showError(L10n.serverAddPasswordRequired);
      return;
    }

    this.isLoading = true;
    try {
      const serverInfo = this.buildServerInfo();

      // 检查是否为NasCab服务器
      if (this.isP2pMode) {
        const code = (serverInfo.pairCode ?? '').trim();
        if (code.length === 0) {
          this.showError(L10n.serverPairCodeEmpty);
          return;
        }
        await P2PService.getInstance().connectByPairCode(code);
        if (!APIClient.getInstance().isP2pMode) {
          APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
        }
      } else {
        APIClient.getInstance().setBaseUrl(serverInfo.serverUrl);
      }
      const serverStatus = await this.authService.checkServerStatus(10000);
      if (!serverStatus.isNasCabServer) {
        this.showError(L10n.serverAddInvalidServer);
        return;
      }
      const statusData = serverStatus.serverData
        ? JsonCodec.parse<ServerStatusJson>(serverStatus.serverData)
        : new ServerStatusJson();
      serverInfo.serverId = statusData.serverId ?? serverInfo.serverId;
      serverInfo.serverPortHttp = statusData.httpPort !== undefined ? `${statusData.httpPort}` : serverInfo.serverPortHttp;
      serverInfo.serverPortHttps = statusData.httpsPort !== undefined ? `${statusData.httpsPort}` : serverInfo.serverPortHttps;
      serverInfo.serverHostName = statusData.hostname ?? serverInfo.serverHostName;
      serverInfo.serverPlatform = statusData.platform ?? serverInfo.serverPlatform;

      // 调用登录API
      const loginResult = await this.authService.loginToServer(serverInfo);

      if (!loginResult.success) {
        this.showError(loginResult.message ?? L10n.authLoginFailure);
        return;
      }

      if (loginResult.twoFactorRequired === true && loginResult.tempToken && loginResult.tempToken.length > 0) {
        this.isLoading = false;
        this.twofaDialog.show((code: string) => {
          void this.submitTwoFactor(serverInfo, loginResult.tempToken!, code);
        });
        return;
      }

      await this.handleLoginSuccess(serverInfo, loginResult);
    } catch (e) {
      this.showError(L10n.serverAddFailure);
    } finally {
      this.isLoading = false;
    }
  }

  private buildServerInfo(): ServerInfo {
    if (this.isP2pMode) {
      const prefill = this.prefillServerInfo;
      const serverInfo = new ServerInfo();
      serverInfo.serverId = (prefill?.serverId ?? '').trim();
      serverInfo.serverUrl = (prefill?.serverUrl ?? '').trim();
      serverInfo.userInputUrl = (prefill?.userInputUrl ?? '').trim();
      serverInfo.serverName = this.serverName;
      serverInfo.serverHostName = this.serverName;
      serverInfo.serverPlatform = 'unknown';
      serverInfo.isP2p = (prefill?.serverUrl ?? '').trim().length === 0;
      serverInfo.pairCode = (prefill?.pairCode ?? '').trim();
      serverInfo.username = this.username;
      serverInfo.password = this.password;
      serverInfo.requirePasswordEveryLogin = this.needInputPwdEveryTime;
      return serverInfo;
    }
    const fullServerUrl = `${this.protocol}://${this.serverUrl.trim()}`;
    const serverInfo = new ServerInfo();
    // 编辑模式下保留原服务器 serverId（对齐 Flutter 端编辑逻辑），后续状态检查/登录响应可覆盖
    serverInfo.serverId = (this.prefillServerInfo?.serverId ?? '').trim();
    serverInfo.serverUrl = fullServerUrl;
    serverInfo.userInputUrl = fullServerUrl;
    serverInfo.serverName = this.serverName;
    serverInfo.serverHost = ServerAddViewModel.extractHostFromUrl(fullServerUrl);
    serverInfo.serverPortHttp = ServerAddViewModel.extractPortFromUrl(fullServerUrl);
    serverInfo.serverHostName = this.serverName;
    serverInfo.serverPlatform = 'unknown';
    serverInfo.username = this.username;
    serverInfo.password = this.password;
    serverInfo.requirePasswordEveryLogin = this.needInputPwdEveryTime;
    return serverInfo;
  }

  private async submitTwoFactor(serverInfo: ServerInfo, tempToken: string, code: string): Promise<void> {
    try {
      const verifyResult = await this.authService.verifyTwoFactorLogin(tempToken, code);
      if (!verifyResult.success) {
        this.showError(verifyResult.message ?? L10n.authLoginFailure);
        return;
      }
      await this.handleLoginSuccess(serverInfo, verifyResult);
    } catch (e) {
      this.showError(`${L10n.authLoginFailure}`);
    }
  }

  private async handleLoginSuccess(serverInfo: ServerInfo, loginResult: LoginResponse): Promise<void> {
    const pair = (loginResult.pairCode ?? '').trim();
    const mergedPair = pair.length > 0 ? pair : (serverInfo.pairCode ?? '');
    const lan = (loginResult.lanIpv4 ?? '').trim();
    let refreshedUrl = serverInfo.serverUrl;
    if (lan.length > 0 && serverInfo.serverUrl.trim().length === 0) {
      refreshedUrl = buildLanServerUrl(lan, loginResult.httpPort, loginResult.httpsPort);
    }
    const preservedInputUrl = (serverInfo.userInputUrl ?? '').trim();
    const identityUrl = preservedInputUrl.length > 0
      ? serverInfo.userInputUrl
      : (mergedPair.trim().length === 0 && refreshedUrl.trim().length > 0 ? refreshedUrl : serverInfo.userInputUrl);

    const updatedServerInfo = new ServerInfo();
    // 优先保留提交时状态检查获取的 serverId，避免登录响应缺失 serverId 导致身份 key 漂移、编辑保存变成追加记录
    updatedServerInfo.serverId = serverInfo.serverId.trim().length > 0
      ? serverInfo.serverId
      : (loginResult.serverId ?? '');
    updatedServerInfo.serverUrl = refreshedUrl;
    updatedServerInfo.userInputUrl = identityUrl;
    updatedServerInfo.lanIpv4 = lan.length > 0 ? lan : serverInfo.lanIpv4;
    updatedServerInfo.lanHttpPort = loginResult.httpPort ?? serverInfo.lanHttpPort;
    updatedServerInfo.lanHttpsPort = loginResult.httpsPort ?? serverInfo.lanHttpsPort;
    updatedServerInfo.serverName = serverInfo.serverName;
    updatedServerInfo.serverHost = serverInfo.serverHost;
    updatedServerInfo.serverPortHttp = loginResult.httpPort ?? '9000';
    updatedServerInfo.serverPortHttps = loginResult.httpsPort ?? '9443';
    updatedServerInfo.serverPlatform = loginResult.platform ?? 'unknown';
    updatedServerInfo.serverHostName = loginResult.hostname ?? 'unknown';
    updatedServerInfo.isP2p = refreshedUrl.trim().length === 0 && mergedPair.trim().length > 0;
    updatedServerInfo.pairCode = mergedPair;
    updatedServerInfo.username = serverInfo.username;
    updatedServerInfo.password = serverInfo.requirePasswordEveryLogin ? '' : serverInfo.password;
    updatedServerInfo.requirePasswordEveryLogin = serverInfo.requirePasswordEveryLogin;
    updatedServerInfo.lastLoginTime = Date.now();

    if (this.prefillServerInfo !== undefined) {
      // 编辑模式：先删除旧记录（含同身份的重复条目），再创建新记录
      const store = ServerStorageService.getInstance();
      await store.removeServer(this.prefillServerInfo);
      await store.addServer(updatedServerInfo);
    } else {
      await ServerStorageService.getInstance().addServer(updatedServerInfo);
    }
    this.showSuccessDialog();
  }

  private static extractHostFromUrl(url: string): string {
    const m = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/:?#]+)/.exec(url.trim());
    return m && m[1] ? m[1] : url;
  }

  private static extractPortFromUrl(url: string): string {
    const m = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/:?#]+:(\d+)/.exec(url.trim());
    return m && m[1] ? m[1] : '80';
  }

  private showSuccessDialog(): void {
    this.confirmDialog.showInfo(L10n.serverAddSuccess, L10n.serverAddSuccessMessage, () => {
      void this.listVm.refreshSavedServers();
      this.goBack();
    });
  }

  private showError(message: string): void {
    this.confirmDialog.showError(message, L10n.serverAddFailure);
  }
}
