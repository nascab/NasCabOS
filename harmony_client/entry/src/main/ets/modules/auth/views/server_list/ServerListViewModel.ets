import { ServerInfo } from '../../models/ServerInfo';
import { AuthService } from '../../AuthService';
import { LoginResponse, ServerStatusResponse } from '../../models/LoginResponse';
import { ServerStorageService } from '../../../../core/storage/ServerStorageService';
import { APIClient } from '../../../../core/network/APIClient';
import { NetworkConfig } from '../../../../core/network/NetworkConfig';
import { ConnectChannelManager } from '../../../../core/network/ConnectChannelManager';
import { UdpBroadcastListener } from '../../../../core/network/UdpBroadcastListener';
import { P2PService } from '../../../../p2p/P2PService';
import { P2pIcePreference } from '../../../../p2p/P2pProtocol';
import { L10n } from '../../../../core/localization/L10n';
import { PreferencesStore } from '../../../../core/storage/PreferencesStore';
import { CacheKeys } from '../../../../core/storage/CacheKeys';
import { JsonCodec, ServerStatusJson, UdpDiscoveryJson } from '../../../../common/JsonTypes';
import { ConfirmDialogState, InputDialogState, RemotePrefDialogState, TwofaDialogState } from '../common/AuthUi';

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

/** 直连候选地址（对齐 Flutter handleServerTap 中的 directCandidates 元组） */
class DirectCandidate {
  url: string = '';
  /** 局域网兜底候选需校验返回 serverId 与目标服务器一致 */
  requireServerIdMatch: boolean = false;

  constructor(url: string, requireServerIdMatch: boolean) {
    this.url = url;
    this.requireServerIdMatch = requireServerIdMatch;
  }
}

/** LAN 探测命中结果 */
class TapLanHit {
  url: string = '';
  status: ServerStatusResponse | undefined = undefined;

  constructor(url: string, status: ServerStatusResponse | undefined) {
    this.url = url;
    this.status = status;
  }
}

/** 竞速结果：kind 取值 lan/p2p/fail/cancel */
class TapRaceOutcome {
  kind: string = 'fail';
  url: string = '';
  status: ServerStatusResponse | undefined = undefined;
  error: Object | undefined = undefined;

  constructor(kind: string) {
    this.kind = kind;
  }
}

/** 可一次性完成的异步信号（ArkTS 版 Completer<void>） */
class DeferredSignal {
  readonly promise: Promise<void>;
  private resolver: () => void = () => {
  };
  private settled: boolean = false;

  constructor() {
    this.promise = new Promise<void>((resolve: () => void) => {
      this.resolver = resolve;
    });
  }

  resolve(): void {
    if (!this.settled) {
      this.settled = true;
      this.resolver();
    }
  }
}

/** 可一次性完成的带值异步信号（ArkTS 版 Completer<T>） */
class Deferred<T> {
  readonly promise: Promise<T>;
  private resolver: (value: T) => void = (_v: T) => {
  };
  private settled: boolean = false;

  constructor() {
    this.promise = new Promise<T>((resolve: (value: T) => void) => {
      this.resolver = resolve;
    });
  }

  get isSettled(): boolean {
    return this.settled;
  }

  resolve(value: T): void {
    if (!this.settled) {
      this.settled = true;
      this.resolver(value);
    }
  }
}

@ObservedV2
export class ServerListViewModel {
  @Trace savedServers: ServerInfo[] = [];
  @Trace discoveredServers: ServerInfo[] = [];
  @Trace localServer: ServerInfo | undefined = undefined;
  @Trace showCreateAdminView: boolean = false;
  @Trace selectedServer: ServerInfo | undefined = undefined;
  @Trace isTapConnecting: boolean = false;
  /** 当前点击登录的服务器：登录中对话框展示其信息（对齐 Flutter _tappingServerItem，不清空供二次密码/2FA 复用） */
  @Trace tappingServer: ServerInfo | undefined = undefined;

  readonly confirmDialog: ConfirmDialogState = new ConfirmDialogState();
  readonly privacyDialog: ConfirmDialogState = new ConfirmDialogState();
  /** 「如何获取配对码」帮助弹窗（需叠在配对码对话框上方） */
  readonly helpDialog: ConfirmDialogState = new ConfirmDialogState();
  readonly passwordDialog: InputDialogState = new InputDialogState();
  readonly editPairCodeDialog: InputDialogState = new InputDialogState();
  readonly twofaDialog: TwofaDialogState = new TwofaDialogState();
  /** 远程连接偏好选择对话框（对齐 Flutter _buildRemoteConnectPrefDialog） */
  readonly remotePrefDialog: RemotePrefDialogState = new RemotePrefDialogState();

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
  /** 点击登录取消信号（对齐 Flutter _tapCancelCompleter） */
  private tapCancelled: boolean = false;
  private tapCancelSignal: DeferredSignal | undefined = undefined;
  /** 冷启动自动登录仅执行一次（对齐 Flutter _launchAutoLoginHandled） */
  private static launchAutoLoginHandled: boolean = false;

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
    await this.tryAutoLoginOnLaunch();
  }

  /// 冷启动自动登录：仅执行一次，复用 handleServerTap 完成通道选择与登录
  /// （对齐 Flutter _tryAutoLoginOnLaunch）
  private async tryAutoLoginOnLaunch(): Promise<void> {
    if (ServerListViewModel.launchAutoLoginHandled) {
      return;
    }
    ServerListViewModel.launchAutoLoginHandled = true;
    let target: ServerInfo | undefined = undefined;
    for (const s of this.savedServers) {
      if (s.autoLoginOnStartup) {
        target = s;
        break;
      }
    }
    if (target === undefined || target.isAutoScanned) {
      return;
    }
    const token = (target.accessToken ?? '').trim();
    if (token.length === 0) {
      return;
    }
    if (!target.hasPairCode() && !target.hasDirectUrl()) {
      return;
    }
    try {
      await this.handleServerTap(target);
    } catch (_e) {
      // 自动登录失败静默处理，用户可手动重试
    }
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

  /// 处理服务器点击事件（对齐 Flutter handleServerTap）
  /// 有配对码时：局域网直连探测与 P2P 建连并行竞速，先成功者胜；
  /// 无配对码时：按直连候选逐试。
  async handleServerTap(server: ServerInfo): Promise<void> {
    if (this.tapLocked) {
      return;
    }
    this.tapLocked = true;
    this.tapCancelled = false;
    this.tapCancelSignal = new DeferredSignal();
    this.tappingServer = server;
    this.isTapConnecting = true;
    // 用户连接流程占用通道：期间后台重检避让，避免与本次建连/探测抢 baseUrl 或断开连接
    ConnectChannelManager.beginUserFlow();
    try {
      const pairCode = (server.pairCode ?? '').trim();
      const hasPairCode = pairCode.length > 0;
      const hasDirectUrl = server.hasDirectUrl() && server.serverUrl.trim() !== NetworkConfig.P2P_BASE_URL;
      const p2p = P2PService.getInstance();

      // ── 直连候选（serverUrl 优先，lanIpv4 兜底，兜底候选需校验 serverId）──
      // 蜂窝网络下不跳过私网 IP：组网软件（Tailscale/ZeroTier 等）会在蜂窝下经虚拟网卡直连；
      // 不可达时 800ms 探测超时由并行 P2P 建连掩盖，不增加总耗时
      const candidates: DirectCandidate[] = [];
      if (hasDirectUrl) {
        const primary = server.serverUrl.trim();
        candidates.push(new DirectCandidate(primary, false));
        if (hasPairCode) {
          const lan = (server.lanIpv4 ?? '').trim();
          if (lan.length > 0) {
            const lanUrl = `http://${lan}:${this.resolveHttpPort(server)}`;
            if (normalizeUrl(lanUrl) !== normalizeUrl(primary)) {
              candidates.push(new DirectCandidate(lanUrl, true));
            }
          }
        }
      }

      let status: ServerStatusResponse | undefined = undefined;
      let usingP2p = false;

      if (candidates.length > 0 && hasPairCode) {
        // Phase 1+2 并行：LAN 直连探测用 checkServerStatusAt 独立请求（不动全局 baseUrl），
        // 与 P2P 建连内部 setBaseUrl 无竞争；LAN 可达约 0.8s 内胜出，
        // LAN 不可达时 P2P 已并行建连，省去原串行流程的双段等待
        const p2pReusable = p2p.isReusableFor(pairCode);
        const outcome = await this.raceLanAndP2p(server, candidates, p2pReusable);
        if (outcome.kind === 'cancel' || this.tapCancelled) {
          return;
        }
        if (outcome.kind === 'p2p') {
          usingP2p = true;
          if (!APIClient.getInstance().isP2pMode) {
            APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
          }
          status = await this.checkP2pStatusRacingCancel();
          if (this.tapCancelled) {
            return;
          }
        } else if (outcome.kind === 'lan') {
          APIClient.getInstance().setBaseUrl(outcome.url);
          status = outcome.status;
        } else {
          if (outcome.error !== undefined) {
            throw new Error(ServerListViewModel.errorMessage(outcome.error));
          }
          this.showError(L10n.serverConnectFail);
          return;
        }
      } else if (candidates.length > 0) {
        // 仅直连（无配对码）：独立探测，胜者设为全局 baseUrl
        if (!p2p.isReusableFor(pairCode) && !p2p.isConnectInFlightFor(pairCode)) {
          p2p.disconnect();
        }
        for (const c of candidates) {
          if (this.tapCancelled) {
            return;
          }
          const s = await this.checkStatusAtRacingCancel(c.url, 2000);
          if (this.tapCancelled) {
            return;
          }
          if (s !== undefined && s.success && s.isNasCabServer
            && (!c.requireServerIdMatch || this.matchServerId(s, server))) {
            APIClient.getInstance().setBaseUrl(c.url);
            status = s;
            break;
          }
        }
      } else if (hasPairCode) {
        // 仅 P2P（无可用直连地址，如蜂窝网络 + 私有 IP）
        usingP2p = true;
        if (p2p.isReusableFor(pairCode)) {
          // 复用同码就绪连接，跳过断开与全量重建
          if (!APIClient.getInstance().isP2pMode) {
            APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
          }
        } else {
          // 同配对码建连进行中（如配对码添加流程）：不断开，经建连队列等待其完成后短路复用
          if (!p2p.isConnectInFlightFor(pairCode)) {
            p2p.disconnect();
          }
          await this.ensureP2pConnected(server);
          if (this.tapCancelled) {
            return;
          }
          if (!APIClient.getInstance().isP2pMode) {
            APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
          }
        }
        status = await this.checkP2pStatusRacingCancel();
        if (this.tapCancelled) {
          return;
        }
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
      // 用户主动取消：静默收尾，不弹错误框（P2P 断连会抛 p2p_connect_stale 等）
      if (this.tapCancelled) {
        return;
      }
      this.showError(L10n.serverStatusCheckFailedWithError(ServerListViewModel.errorMessage(e)));
    } finally {
      ConnectChannelManager.endUserFlow();
      this.tapLocked = false;
      // 保留 tappingServer：密码/2FA 二次提交时登录中对话框仍需展示同一服务器信息
      this.isTapConnecting = false;
    }
  }

  /// LAN 探测与 P2P 建连并行竞速（对齐 Flutter handleServerTap Phase1+2 settle 逻辑）
  private async raceLanAndP2p(server: ServerInfo, candidates: DirectCandidate[],
    p2pReusable: boolean): Promise<TapRaceOutcome> {
    const p2p = P2PService.getInstance();
    const decided = new Deferred<TapRaceOutcome>();
    let lanWinUrl = '';
    let lanWinStatus: ServerStatusResponse | undefined = undefined;
    let lanDone = false;
    let p2pDone = p2pReusable;
    let p2pFailed = false;
    let p2pError: Object | undefined = undefined;
    let p2pWon = false;
    /** LAN 已命中：此后 P2P 建连不得再重试，否则会在登录成功后把 baseUrl 抢回 P2P */
    let lanWon = false;

    const settle = (): void => {
      if (decided.isSettled) {
        return;
      }
      if (lanWinUrl.length > 0) {
        decided.resolve(new TapRaceOutcome('lan')); // LAN 命中即胜（可复用 P2P 保留，LAN 优先）
      } else if (lanDone) {
        // LAN 已结束且未命中：P2P 就绪则胜，双败则收尾
        if (p2pReusable || (p2pDone && !p2pFailed)) {
          p2pWon = true;
          decided.resolve(new TapRaceOutcome('p2p'));
        } else if (p2pDone && p2pFailed) {
          decided.resolve(new TapRaceOutcome('fail'));
        }
      } else if (!p2pReusable && p2pDone && !p2pFailed) {
        // LAN 尚未出结果而 P2P 先连上：谁先通用谁
        p2pWon = true;
        decided.resolve(new TapRaceOutcome('p2p'));
      }
    };

    // LAN 探测任务：逐候选独立请求（800ms/个，失败不抛）
    this.probeLanCandidates(server, candidates).then((hit: TapLanHit | undefined) => {
      if (hit !== undefined) {
        lanWinUrl = hit.url;
        lanWinStatus = hit.status;
        lanWon = true;
      }
      lanDone = true;
      settle();
    }).catch(() => {
      lanDone = true;
      settle();
    });

    // P2P 建连任务（已可复用则无需启动；在途同码经建连队列排队短路）
    if (!p2pReusable) {
      this.ensureP2pConnected(server, (): boolean => lanWon).then(() => {
        p2pFailed = !p2p.isConnected;
        p2pDone = true;
        settle();
      }).catch((e: Object) => {
        p2pError = e;
        p2pFailed = true;
        p2pDone = true;
        settle();
      });
    } else {
      settle();
    }

    const signal = this.tapCancelSignal;
    const outcome = signal === undefined ? await decided.promise
      : await Promise.race<TapRaceOutcome>([
        decided.promise,
        signal.promise.then((): TapRaceOutcome => new TapRaceOutcome('cancel'))
      ]);

    if (outcome.kind === 'cancel') {
      return outcome;
    }
    if (p2pWon) {
      outcome.kind = 'p2p';
    } else if (lanWinUrl.length > 0) {
      outcome.kind = 'lan';
      outcome.url = lanWinUrl;
      outcome.status = lanWinStatus;
      // LAN 胜：作废在途 P2P 建连；已就绪的同码 P2P 连接保留，供后续复用
      if (!p2p.isConnected) {
        p2p.disconnect();
      }
    } else {
      outcome.kind = 'fail';
      outcome.error = p2pError;
    }
    return outcome;
  }

  /// 逐候选探测 LAN 直连（800ms/个），命中即返回
  private async probeLanCandidates(server: ServerInfo,
    candidates: DirectCandidate[]): Promise<TapLanHit | undefined> {
    for (const c of candidates) {
      if (this.tapCancelled) {
        return undefined;
      }
      try {
        const s = await this.authService.checkServerStatusAt(c.url, 800);
        if (s.success && s.isNasCabServer && (!c.requireServerIdMatch || this.matchServerId(s, server))) {
          return new TapLanHit(c.url, s);
        }
      } catch (_e) {
        // 候选不可达，继续下一个
      }
    }
    return undefined;
  }

  /// checkServerStatus 与取消信号竞速：取消后立即返回 undefined；
  /// 对在途请求挂 catch 防止取消后失败成为未处理拒绝
  private async checkStatusRacingCancel(timeoutMs: number): Promise<ServerStatusResponse | undefined> {
    const work = this.authService.checkServerStatus(timeoutMs);
    work.catch(() => {
    });
    const signal = this.tapCancelSignal;
    if (signal === undefined) {
      return work;
    }
    return Promise.race<ServerStatusResponse | undefined>([
      work,
      signal.promise.then((): undefined => undefined)
    ]);
  }

  /// P2P 建连后首次探测：5G/中继的冷通道未预热，首个请求易超时或丢失，
  /// 单次 3s 探测会直接判失败（第二次点击因复用热通道才成功）。
  /// 首次 5s，失败后隔 600ms 再试一次 4s；取消仍即时生效。
  private async checkP2pStatusRacingCancel(): Promise<ServerStatusResponse | undefined> {
    let status = await this.checkStatusRacingCancel(5000);
    if (this.tapCancelled) {
      return undefined;
    }
    if (status !== undefined && status.success && status.isNasCabServer) {
      return status;
    }
    await ServerListViewModel.sleep(600);
    if (this.tapCancelled) {
      return undefined;
    }
    status = await this.checkStatusRacingCancel(4000);
    return status;
  }

  /// checkServerStatusAt 与取消信号竞速（用于仅直连分支）
  private async checkStatusAtRacingCancel(url: string, timeoutMs: number): Promise<ServerStatusResponse | undefined> {
    const work = this.authService.checkServerStatusAt(url, timeoutMs);
    work.catch(() => {
    });
    const signal = this.tapCancelSignal;
    if (signal === undefined) {
      return work;
    }
    return Promise.race<ServerStatusResponse | undefined>([
      work,
      signal.promise.then((): undefined => undefined)
    ]);
  }

  /// 取消本次登录：置取消标志、放行各等待点，并作废在途 P2P 建连。
  /// 仅当 P2P 与本次登录相关（在途建连或当前正走 P2P）时才断开，避免误伤其他连接
  cancelTap(): void {
    if (this.tapCancelled) {
      return;
    }
    this.tapCancelled = true;
    const signal = this.tapCancelSignal;
    if (signal !== undefined) {
      signal.resolve();
    }
    const server = this.tappingServer;
    const p2p = P2PService.getInstance();
    if (server !== undefined && server.hasPairCode()) {
      const code = (server.pairCode ?? '').trim();
      if (p2p.isConnectInFlightFor(code) || APIClient.getInstance().isP2pMode) {
        p2p.disconnect();
      }
    }
    this.isTapConnecting = false;
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

  /// 遇到 P2P_DEVICE_OFFLINE 时重试，设备可能处于重连信令服务器的短暂窗口期。
  /// shouldStop 返回 true 时立即终止重试（如 LAN 直连竞速已胜出，P2P 不应再建连）。
  private async ensureP2pConnected(server: ServerInfo, shouldStop?: () => boolean): Promise<void> {
    const code = (server.pairCode ?? '').trim();
    if (code.length === 0) {
      throw new Error(L10n.serverPairCodeEmpty);
    }
    const maxRetries = 3;
    const retryDelayMs = 1500;
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      if (shouldStop !== undefined && shouldStop()) {
        throw new Error('p2p_connect_cancelled');
      }
      try {
        await P2PService.getInstance().connectByPairCode(code);
        return;
      } catch (e) {
        const msg = ServerListViewModel.errorMessage(e);
        if (this.tapCancelled) {
          throw new Error(msg);
        }
        // LAN 已胜出时断开 P2P 会让在途建连抛 p2p_connect_stale，
        // 此时不能按「代际失效」重试，否则 P2P 建连成功后会抢走 baseUrl
        if (shouldStop !== undefined && shouldStop()) {
          throw new Error(msg);
        }
        if (msg.includes('P2P_DEVICE_OFFLINE') && attempt < maxRetries) {
          await ServerListViewModel.sleep(retryDelayMs);
          continue;
        }
        // 建连被后台通道重检等并发操作打断（代际失效）：立即重试，不把内部标记暴露给用户
        if (msg.includes('p2p_connect_stale') && attempt < maxRetries) {
          continue;
        }
        throw new Error(ServerListViewModel.errorMessage(e));
      }
    }
  }

  /// 处理菜单选择（对齐 Flutter PopupMenu 项）
  handleMenuSelection(action: string, serverItem: ServerInfo): void {
    if (action === 'edit_pair_code') {
      this.showEditPairCodeDialog(serverItem);
    } else if (action === 'edit') {
      this.goToAddServerView(serverItem);
    } else if (action === 'remote_pref') {
      this.showRemoteConnectPref(serverItem);
    } else if (action === 'move_to_top') {
      void this.moveServerToTop(serverItem);
    } else if (action === 'toggle_auto_login') {
      void this.toggleAutoLogin(serverItem);
    } else if (action === 'delete') {
      this.showDeleteConfirmDialog(serverItem);
    }
  }

  /// 远程连接偏好设置：直连优先 / 中继优先（对齐 Flutter showRemoteConnectPref）
  /// 偏好随服务器条目持久化，此后所有 null 偏好建连（点击服务器、自动重连、Failover）
  /// 都会在 connectByPairCode 入口按此偏好解析；若当前正以 P2P 连接该服务器，则立即按新偏好断开重建
  private showRemoteConnectPref(serverItem: ServerInfo): void {
    const code = (serverItem.pairCode ?? '').trim();
    if (code.length === 0) {
      return;
    }
    this.remotePrefDialog.show(serverItem.p2pRelayPreferred, (relayPreferred: boolean) => {
      // 未改变选择：仅关窗返回
      if (relayPreferred === serverItem.p2pRelayPreferred) {
        return;
      }
      serverItem.p2pRelayPreferred = relayPreferred;
      void this.applyRemotePrefChange(serverItem, code, relayPreferred);
    });
  }

  private async applyRemotePrefChange(serverItem: ServerInfo, code: string,
    relayPreferred: boolean): Promise<void> {
    // 1) 在已保存列表中按身份定位更新，然后整体落盘并刷新 UI
    try {
      const saved = ServerStorageService.getInstance().loadServers();
      let persisted = false;
      for (const s of saved) {
        if (this.isSameIdentity(s, serverItem)) {
          s.p2pRelayPreferred = relayPreferred;
          persisted = true;
          break;
        }
      }
      if (persisted) {
        await ServerStorageService.getInstance().saveServers(saved);
      }
    } catch (_e) {
    }
    await this.refreshSavedServers();

    // 2) 当前正以 P2P 连接该服务器：立即按新偏好断开重建（同码就绪连接会被短路复用，必须先断开）
    const api = APIClient.getInstance();
    const p2p = P2PService.getInstance();
    if (api.isP2pMode && p2p.pairCode.trim() === code) {
      try {
        await p2p.disconnect();
        await p2p.connectByPairCode(code,
          relayPreferred ? P2pIcePreference.RELAY_ONLY : P2pIcePreference.AUTO);
      } catch (_e) {
        // 重建期间瞬时失败属预期
      }
    }
  }

  /// 移动到列表顶部（对齐 Flutter server_menu_move_to_top）
  private async moveServerToTop(serverItem: ServerInfo): Promise<void> {
    const list = this.savedServers.slice();
    const idx = list.findIndex((s: ServerInfo) => this.isSameIdentity(s, serverItem));
    if (idx <= 0) {
      return;
    }
    const target = list.splice(idx, 1)[0];
    list.unshift(target);
    await ServerStorageService.getInstance().saveServers(list);
    await this.refreshSavedServers();
  }

  /// 启动时自动登录开关（全局互斥：开启一台会关闭其他所有，对齐 Flutter）
  private async toggleAutoLogin(serverItem: ServerInfo): Promise<void> {
    const enable = !serverItem.autoLoginOnStartup;
    const list = this.savedServers;
    for (const s of list) {
      const same = this.isSameIdentity(s, serverItem);
      if (same) {
        s.autoLoginOnStartup = enable;
      } else if (enable) {
        // 全局互斥：开启一台时关闭其他所有
        s.autoLoginOnStartup = false;
      }
    }
    await ServerStorageService.getInstance().saveServers(list);
    await this.refreshSavedServers();
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
      this.pairConnectError = ServerListViewModel.formatPairConnectError(e);
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
      const stack = e instanceof Error ? (e.stack ?? '') : `${e}`;
      console.error(`[LOGIN] loginToServer error: ${ServerListViewModel.errorMessage(e)}\n${stack}`);
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

    // 登录成功且当前走 P2P 时，后台探测直连并尝试从中继无缝升级为直连（提升连接效率）
    if (APIClient.getInstance().isP2pMode) {
      ConnectChannelManager.scheduleP2pDirectUpgrade();
    }

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

  /// 配对码建连异常转可读文案（对齐 Flutter ApiController.formatP2pConnectError）：
  /// 配对码对应服务端不在线时信令返回 HTTP 404/403 或裸状态码，不能直接展示给用户
  private static formatPairConnectError(e: Object): string {
    const msg = ServerListViewModel.errorMessage(e).trim();
    if (/^\d{3}$/.test(msg) || msg.includes('pair_session_http_')
      || msg.includes('pair_session_invalid') || msg.includes('pair_ws_url_invalid')
      || msg.includes('p2p_') || msg.includes('P2P_DEVICE_OFFLINE')) {
      return L10n.serverConnectFail;
    }
    return msg.length > 0 ? msg : L10n.serverConnectFail;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise((resolve: () => void) => setTimeout(resolve, ms));
  }
}
