import { ServerInfo } from '../auth/models/ServerInfo';
import { AuthService } from '../auth/AuthService';
import { LoginResponse } from '../auth/models/LoginResponse';
import { ServerStorageService } from '../core/storage/ServerStorageService';
import { APIClient } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { UdpBroadcastListener } from '../core/network/UdpBroadcastListener';
import { P2PService } from '../p2p/P2PService';
import { L10n } from '../core/localization/L10n';
import { UdpDiscoveryJson } from '../common/JsonTypes';

@ObservedV2
export class ServerListViewModel {
  @Trace savedServers: ServerInfo[] = [];
  @Trace discoveredServers: ServerInfo[] = [];
  @Trace isConnecting: boolean = false;
  @Trace statusMessage: string = '';
  @Trace showAddDialog: boolean = false;
  @Trace showPasswordDialog: boolean = false;
  @Trace showTwofaDialog: boolean = false;
  @Trace addUrl: string = '';
  @Trace addPairCode: string = '';
  @Trace passwordInput: string = '';
  @Trace twofaCode: string = '';
  @Trace pendingServer: ServerInfo | undefined = undefined;
  @Trace pendingTempToken: string = '';

  private udpListener: UdpBroadcastListener = new UdpBroadcastListener();
  private authService: AuthService = AuthService.getInstance();

  async init(): Promise<void> {
    this.savedServers = ServerStorageService.getInstance().loadServers();
    this.udpListener.setOnServerDiscovered((info) => this.onServerDiscovered(info));
    await this.udpListener.startListening();
  }

  destroy(): void {
    this.udpListener.stopListening();
  }

  private onServerDiscovered(info: UdpDiscoveryJson): void {
    const host = info.host ?? '';
    const httpPort = `${info.port ?? info.httpPort ?? '9000'}`;
    const httpsPort = `${info.httpsPort ?? '9443'}`;
    const server = new ServerInfo();
    server.serverUrl = `http://${host}:${httpPort}`;
    server.serverHost = host;
    server.serverPortHttp = httpPort;
    server.serverPortHttps = httpsPort;
    server.serverName = info.name ?? info.hostname ?? host;
    server.serverHostName = info.hostname ?? host;
    server.serverPlatform = info.platform ?? 'linux';
    server.isAutoScanned = true;
    server.isLocalServer = true;
    server.serverId = info.serverId ?? '';

    const key = server.uniqueKey;
    let exists = false;
    for (let i = 0; i < this.discoveredServers.length; i++) {
      if (this.discoveredServers[i].uniqueKey === key) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      const next = this.discoveredServers.slice();
      next.push(server);
      this.discoveredServers = next;
    }
  }

  async connectServer(server: ServerInfo): Promise<boolean> {
    this.pendingServer = server;
    if (server.requirePasswordEveryLogin || !server.password) {
      this.passwordInput = server.password ?? '';
      this.showPasswordDialog = true;
      return false;
    }
    return this.performConnect(server);
  }

  async submitPassword(): Promise<boolean> {
    if (!this.pendingServer) {
      return false;
    }
    this.pendingServer.password = this.passwordInput;
    this.showPasswordDialog = false;
    return this.performConnect(this.pendingServer);
  }

  async submitTwofa(): Promise<boolean> {
    if (!this.pendingServer || this.pendingTempToken.length === 0) {
      return false;
    }
    this.isConnecting = true;
    const result = await this.authService.verifyTwoFactorLogin(this.pendingTempToken, this.twofaCode);
    this.isConnecting = false;
    if (!result.success) {
      this.statusMessage = result.message ?? L10n.authLoginFailure;
      return false;
    }
    this.showTwofaDialog = false;
    return this.handleLoginSuccess(this.pendingServer, result);
  }

  private async performConnect(server: ServerInfo): Promise<boolean> {
    this.isConnecting = true;
    this.statusMessage = L10n.connecting;
    try {
      if (server.hasPairCode() && !server.hasDirectUrl()) {
        await P2PService.getInstance().connectByPairCode(server.pairCode!.trim());
      } else if (server.serverUrl.trim().length > 0) {
        APIClient.getInstance().setBaseUrl(server.serverUrl.trim());
      } else {
        this.statusMessage = '无效的服务器配置';
        return false;
      }

      const status = await this.authService.checkServerStatus(8000);
      if (!status.success || !status.isNasCabServer) {
        this.statusMessage = status.message ?? '不是 NasCab 服务器';
        return false;
      }

      const login = await this.authService.loginToServer(server);
      if (login.twoFactorRequired === true && login.tempToken) {
        this.pendingTempToken = login.tempToken;
        this.showTwofaDialog = true;
        return false;
      }
      if (!login.success && !login.accessToken) {
        this.statusMessage = login.message ?? L10n.authLoginFailure;
        return false;
      }
      return this.handleLoginSuccess(server, login);
    } catch (e) {
      this.statusMessage = e instanceof Error ? e.message : `${e}`;
      return false;
    } finally {
      this.isConnecting = false;
    }
  }

  private async handleLoginSuccess(server: ServerInfo, login: LoginResponse): Promise<boolean> {
    this.authService.applyLoginSuccess(server, login);
    if (!server.hasDirectUrl() && server.hasPairCode()) {
      server.isP2p = true;
      server.serverUrl = NetworkConfig.P2P_BASE_URL;
    }
    await ServerStorageService.getInstance().addServer(server);
    await ServerStorageService.getInstance().saveLastSelected(server);
    this.savedServers = ServerStorageService.getInstance().loadServers();
    this.statusMessage = '';
    return true;
  }

  async addManualServer(): Promise<boolean> {
    const server = new ServerInfo();
    const url = this.addUrl.trim();
    const code = this.addPairCode.trim();
    if (url.length > 0) {
      server.serverUrl = url.startsWith('http') ? url : `http://${url}`;
      server.serverName = url;
      server.serverHost = url;
      server.serverHostName = url;
    } else if (code.length > 0) {
      server.pairCode = code;
      server.serverName = `P2P ${code.substring(0, 4)}***`;
      server.isP2p = true;
    } else {
      this.statusMessage = '请输入地址或配对码';
      return false;
    }
    server.serverPortHttp = '9000';
    server.serverPortHttps = '9443';
    server.serverPlatform = 'linux';
    server.username = 'admin';
    this.showAddDialog = false;
    this.addUrl = '';
    this.addPairCode = '';
    return this.connectServer(server);
  }
}
