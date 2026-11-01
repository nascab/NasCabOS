import { http, connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { APIClient, HttpMethod } from './APIClient';
import { NetworkConfig } from './NetworkConfig';
import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';
import { ServerStorageService } from '../storage/ServerStorageService';
import { CurrentUserStore } from '../user/CurrentUserStore';
import { ServerInfo } from '../../modules/auth/models/ServerInfo';
import { P2PService } from '../../p2p/P2PService';
import { P2pIcePreference, P2pTransportKind } from '../../p2p/P2pProtocol';
import { DevConnectMode, DevConnectModeUtil } from './DevConnectMode';
import { HeaderMap } from '../../common/HeaderMap';
import { AppEventBus, EVENT_CONNECT_CHANNEL_CHANGED } from '../../common/AppEventBus';

const PROBE_TIMEOUT_MS = 2000;
const PUBLIC_PROBE_TIMEOUT_MS = 4000;
const PROBE_RETRY_DELAY_MS = 400;
const P2P_DISCONNECT_DELAY_MS = 2000;
const REQUEST_FAILURE_PROBE_COOLDOWN_MS = 5000;
const NET_CHANGE_PROBE_DELAY_MS = 800;
const NET_CHANGE_PROBE_THROTTLE_MS = 5000;

/**
 * 连接通道切换管理（对齐 Flutter ApiController 的 failover / 全局网络变化监控逻辑）：
 * - 通道模式切换（auto/direct/p2p）与直连候选探测（userInputUrl > lan > serverUrl）
 * - 全局网络类型变化（WiFi ↔ 5G）后按优先级重检通道：直连 > P2P 直连 > P2P 中继
 * - 请求连续失败后按同样优先级重检通道，并带 5s 冷却避免风暴
 */
export class ConnectChannelManager {
  /** 请求失败触发的重检任务（同一时间只允许一个，手动重检也复用该任务） */
  private static requestRecoveryInFlight: Promise<boolean> | undefined = undefined;
  /** 重检串行队列，避免并发探测互相覆盖 baseUrl */
  private static failoverQueue: Promise<boolean> = Promise.resolve(false);
  private static failoverCooldownUntilMs: number = 0;

  /** 全局网络类型变化监听 */
  private static netConnection: connection.NetConnection | undefined = undefined;
  private static netChangeTimerId: number = -1;
  private static netPollTimerId: number = -1;
  private static netChangeProbeLocked: boolean = false;
  private static netChangeProbeAtMs: number = 0;
  /** 事件携带的 netId -> bearerTypes，用于不依赖默认网络切换时机地识别网络增减 */
  private static netBearers: Map<number, number[]> = new Map<number, number[]>();
  private static activeBearers: Set<number> = new Set<number>();
  private static lastBearerKey: string = '';
  private static lastLiveBearerKey: string = '';
  private static hasBearerBaseline: boolean = false;
  /** 最近一次网络拓扑变化时间/补检次数：默认网络切换可能滞后于事件，因此补检 1~2 次 */
  private static netChangeEventAtMs: number = 0;
  private static netChangeSettleRetryCount: number = 0;
  private static lastForegroundProbeAtMs: number = 0;
  private static installed: boolean = false;
  /** 用户主动发起的连接流程（点击服务器/配对登录）计数：期间后台重检须避让，避免拆掉在途连接 */
  private static userFlowDepth: number = 0;
  /** 当前通道模式内存态：切换失败可回滚，UI 勾选与自动重连行为读写同一份状态 */
  private static currentMode: DevConnectMode | undefined = undefined;

  /** 安装到 APIClient：请求最终失败时由 APIClient 回调触发重检（避免模块循环依赖） */
  static install(): void {
    if (ConnectChannelManager.installed) {
      return;
    }
    ConnectChannelManager.installed = true;
    APIClient.getInstance().setChannelFailoverHandler(
      (endpoint: string, errorText: string): Promise<boolean> =>
        ConnectChannelManager.maybeFailoverOnRequestError(endpoint, errorText)
    );
    APIClient.getInstance().setAuthEstablishedHandler((): void => {
      ConnectChannelManager.startGlobalNetworkMonitor();
    });
    APIClient.getInstance().setAuthClearedHandler((): void => {
      ConnectChannelManager.stopGlobalNetworkMonitor();
    });
    if (APIClient.getInstance().isAuthenticated) {
      ConnectChannelManager.startGlobalNetworkMonitor();
    }
  }

  /** 标记用户连接流程开始：期间禁止后台 failover / 网络变化重检改写 baseUrl 或断开 P2P */
  static beginUserFlow(): void {
    ConnectChannelManager.userFlowDepth += 1;
  }

  static endUserFlow(): void {
    if (ConnectChannelManager.userFlowDepth > 0) {
      ConnectChannelManager.userFlowDepth -= 1;
    }
  }

  static isUserFlowActive(): boolean {
    return ConnectChannelManager.userFlowDepth > 0;
  }

  /** 读取通道模式（内存优先，默认 auto）；p2pDirect/p2pRelay 为一次性切换，不跨启动持久 */
  static getMode(): DevConnectMode {
    const inMemory = ConnectChannelManager.currentMode;
    if (inMemory !== undefined) {
      return inMemory;
    }
    const stored = DevConnectModeUtil.parse(
      PreferencesStore.getInstance().getString(CacheKeys.DEV_CONNECT_MODE, ''));
    const normalized = ConnectChannelManager.normalizeStoredMode(stored);
    ConnectChannelManager.currentMode = normalized;
    return normalized;
  }

  /** 启动恢复时不做一次性强制模式（对齐 Flutter _loadDevConnectMode） */
  private static normalizeStoredMode(mode: DevConnectMode): DevConnectMode {
    if (mode === DevConnectMode.P2P_DIRECT || mode === DevConnectMode.P2P_RELAY) {
      return DevConnectMode.AUTO;
    }
    return mode;
  }

  /** 更新内存模式并通知 UI；切换失败时回滚也用此入口，避免勾选与真实通道不一致 */
  private static setCurrentMode(mode: DevConnectMode): void {
    if (ConnectChannelManager.currentMode === mode) {
      return;
    }
    ConnectChannelManager.currentMode = mode;
    AppEventBus.emit(EVENT_CONNECT_CHANNEL_CHANGED);
  }

  private static async persistMode(mode: DevConnectMode): Promise<void> {
    try {
      await PreferencesStore.getInstance().setString(CacheKeys.DEV_CONNECT_MODE, `${mode}`);
    } catch (_e) {
      // 持久化失败不阻断切换（对齐 Flutter try/catch）
    }
  }

  /** 保存并立即生效（对齐 setDevConnectMode(applyNow: true)）；失败抛错由 UI 提示并回滚 */
  static async setMode(mode: DevConnectMode): Promise<void> {
    const previous = ConnectChannelManager.getMode();
    const oneOff = mode === DevConnectMode.P2P_DIRECT || mode === DevConnectMode.P2P_RELAY;
    // 强制直连/P2P 切换期间标记用户流程，避免网络变化/请求失败的后台重检拆掉在途切换
    const guardUserFlow = mode !== DevConnectMode.AUTO;
    ConnectChannelManager.setCurrentMode(mode);
    if (guardUserFlow) {
      ConnectChannelManager.beginUserFlow();
    }
    let applied = false;
    try {
      await ConnectChannelManager.applyNow(mode);
      applied = true;
    } finally {
      if (guardUserFlow) {
        ConnectChannelManager.endUserFlow();
      }
      if (applied) {
        // p2pDirect/p2pRelay 仅作用于本次切换，应用后回到 auto（对齐 Flutter）
        const settled = oneOff ? DevConnectMode.AUTO : mode;
        ConnectChannelManager.setCurrentMode(settled);
        await ConnectChannelManager.persistMode(settled);
      } else {
        // 切换失败：还原为切换前的模式，避免勾选停在未生效的方式上
        ConnectChannelManager.setCurrentMode(previous);
        await ConnectChannelManager.persistMode(previous);
      }
    }
  }

  /** 登录成功后调用：若当前走 P2P 中继，延迟后台探测直连并尝试无缝升级为直连
   *  （对齐 Flutter scheduleP2pDirectUpgrade → _runP2pAutoSwitchProbe） */
  static scheduleP2pDirectUpgrade(): void {
    // 连接成功后约 800ms 才会异步确认 transport kind，延迟 1500ms 确保中继状态已就绪
    setTimeout((): void => {
      void ConnectChannelManager.runDirectUpgradeProbe();
    }, 1500);
  }

  private static async runDirectUpgradeProbe(): Promise<void> {
    const api = APIClient.getInstance();
    // 仅在中继模式下才尝试升级；已是直连（含非 P2P 直连）则无需处理
    if (!api.isP2pMode || P2PService.getInstance().transportKind !== P2pTransportKind.RELAY) {
      return;
    }
    const info = ConnectChannelManager.loadServerInfo();
    if (info === undefined) {
      return;
    }
    try {
      await ConnectChannelManager.switchToDirect(info);
    } catch (_e) {
      // 升级失败保持中继，不打扰用户
    }
  }

  /** 当前模式立即生效（对齐 applyDevConnectModeNow） */
  static async applyNow(mode: DevConnectMode): Promise<void> {
    if (mode === DevConnectMode.AUTO) {
      const ok = await ConnectChannelManager.refreshConnectChannel();
      if (!ok) {
        throw new Error('dev_switch_failed');
      }
      return;
    }
    const info = ConnectChannelManager.loadServerInfo();
    if (info === undefined) {
      throw new Error('dev_switch_failed');
    }
    if (mode === DevConnectMode.DIRECT) {
      const ok = await ConnectChannelManager.switchToDirect(info);
      if (!ok) {
        throw new Error('dev_switch_direct_failed');
      }
      return;
    }
    // p2p / p2pDirect / p2pRelay
    const pref = mode === DevConnectMode.P2P_RELAY
      ? P2pIcePreference.RELAY_ONLY
      : (mode === DevConnectMode.P2P_DIRECT ? P2pIcePreference.DIRECT_ONLY : P2pIcePreference.AUTO);
    const ok2 = await ConnectChannelManager.switchToP2p(info, pref);
    if (!ok2) {
      throw new Error('dev_switch_p2p_failed');
    }
  }

  // ==================== 主动重检 / 失败重连 ====================

  /** 手动全量重检（对齐 Flutter refreshConnectChannel）：直连候选优先，其次 P2P */
  static refreshConnectChannel(): Promise<boolean> {
    const existing = ConnectChannelManager.requestRecoveryInFlight;
    if (existing !== undefined) {
      return existing;
    }
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return Promise.resolve(false);
    }
    const serverId = api.state.serverId.trim();
    if (serverId.length === 0) {
      return Promise.resolve(false);
    }
    const infos = ConnectChannelManager.loadServerInfosById(serverId);
    if (infos.length === 0) {
      return Promise.resolve(false);
    }

    const task: Promise<boolean> = ConnectChannelManager.failoverQueue.then((): Promise<boolean> => {
      ConnectChannelManager.netChangeProbeLocked = true;
      ConnectChannelManager.netChangeProbeAtMs = Date.now();
      ConnectChannelManager.failoverCooldownUntilMs = 0;
      return ConnectChannelManager.probePreferredChannel(infos, false, '')
        .finally((): void => {
          ConnectChannelManager.netChangeProbeLocked = false;
        });
    });
    let wrapped: Promise<boolean> = Promise.resolve(false);
    wrapped = task.finally((): void => {
      if (ConnectChannelManager.requestRecoveryInFlight === wrapped) {
        ConnectChannelManager.requestRecoveryInFlight = undefined;
      }
    });
    ConnectChannelManager.requestRecoveryInFlight = wrapped;
    ConnectChannelManager.failoverQueue = wrapped.catch((_e: Object): boolean => false);
    return wrapped;
  }

  /**
   * 请求因网络异常最终失败后触发通道重检（对齐 Flutter maybeFailoverOnRequestError）。
   * 返回 true 表示已切换到可用通道，调用方可重试原请求。
   */
  static maybeFailoverOnRequestError(endpoint: string, errorText: string): Promise<boolean> {
    if (ConnectChannelManager.getMode() !== DevConnectMode.AUTO) {
      return Promise.resolve(false);
    }
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return Promise.resolve(false);
    }
    if (!ConnectChannelManager.shouldFailoverForEndpoint(endpoint)) {
      return Promise.resolve(false);
    }
    if (!ConnectChannelManager.isTransportError(errorText)) {
      return Promise.resolve(false);
    }
    const serverId = api.state.serverId.trim();
    if (serverId.length === 0) {
      return Promise.resolve(false);
    }
    const now = Date.now();
    if (now < ConnectChannelManager.failoverCooldownUntilMs) {
      return Promise.resolve(false);
    }
    ConnectChannelManager.failoverCooldownUntilMs = now + REQUEST_FAILURE_PROBE_COOLDOWN_MS;

    const currentBaseUrl = api.baseUrl.trim();
    if (currentBaseUrl.length === 0) {
      return Promise.resolve(false);
    }
    const inFlight = ConnectChannelManager.requestRecoveryInFlight;
    if (inFlight !== undefined) {
      return inFlight;
    }

    const task: Promise<boolean> = ConnectChannelManager.failoverQueue.then((): Promise<boolean> => {
      return ConnectChannelManager.performFailoverLocked(serverId, currentBaseUrl);
    });
    let wrapped: Promise<boolean> = Promise.resolve(false);
    wrapped = task.finally((): void => {
      if (ConnectChannelManager.requestRecoveryInFlight === wrapped) {
        ConnectChannelManager.requestRecoveryInFlight = undefined;
      }
    });
    ConnectChannelManager.requestRecoveryInFlight = wrapped;
    ConnectChannelManager.failoverQueue = wrapped.catch((_e: Object): boolean => false);
    return wrapped;
  }

  private static shouldFailoverForEndpoint(endpoint: string): boolean {
    const ep = endpoint.trim();
    if (ep.length === 0) {
      return false;
    }
    if (ep === '/health' || ep === '/api/hw/metrics') {
      return false;
    }
    if (ep.startsWith('/api/auth/login')
      || ep.startsWith('/api/auth/refreshJwt')
      || ep.startsWith('/api/auth/2fa/')
      || ep.startsWith('/api/p2p/')) {
      return false;
    }
    return true;
  }

  /** 对齐 Flutter _isTransportError：仅网络层异常才触发 failover，避免业务/解析错误误切换 */
  private static isTransportError(errorText: string): boolean {
    const s = errorText.toLowerCase();
    if (s.trim().length === 0) {
      return false;
    }
    if (s.includes('2300006')   // couldn't resolve host
      || s.includes('2300007')  // couldn't connect to server
      || s.includes('2300028')) { // timeout
      return true;
    }
    const keywords: string[] = [
      'timeout',
      'timed out',
      'time out',
      'socket',
      'connection refused',
      'couldn\'t connect',
      'failed to connect',
      'resolve',
      'failed host lookup',
      'name or service not known',
      'network is unreachable',
      'unreachable',
      'handshake',
      'certificate',
      'ssl',
      'tls',
      'econnreset',
      'connection reset',
      'broken pipe',
      'p2p_not_connected',
      'p2p_disconnected',
      'p2p_ws_error',
      'p2p_ws_closed',
      'p2p_dc_closed',
      'p2p_dc_error',
      'p2p_dc_not_open'
    ];
    for (const keyword of keywords) {
      if (s.includes(keyword)) {
        return true;
      }
    }
    return false;
  }

  private static async performFailoverLocked(serverId: string, failedBaseUrl: string): Promise<boolean> {
    if (APIClient.getInstance().state.serverId.trim() !== serverId) {
      return false;
    }
    const infos = ConnectChannelManager.loadServerInfosById(serverId);
    if (infos.length === 0) {
      return false;
    }
    return ConnectChannelManager.probePreferredChannel(infos, true, failedBaseUrl);
  }

  /** 按优先级探测所有通道：直连 > P2P 直连 > P2P 中继 */
  private static async probePreferredChannel(infos: ServerInfo[], reconnectCurrentP2p: boolean,
    failedBaseUrl: string): Promise<boolean> {
    // 有在途 P2P 建连（点击服务器/配对码添加）时避让：后台主动 disconnect 会让
    // 在途建连代际失效并抛 p2p_connect_stale，通道选择交由建连流程自行完成
    if (P2PService.getInstance().isConnectInFlight() || ConnectChannelManager.isUserFlowActive()) {
      return false;
    }
    const api = APIClient.getInstance();
    const expectedServerId = api.state.serverId.trim();
    const failed = ConnectChannelManager.normalizeBaseUrl(failedBaseUrl);
    const seen = new Set<string>();
    const ordered = ConnectChannelManager.orderServerInfosForCurrentBaseUrl(infos);
    const candidates = ConnectChannelManager.buildDirectProbeCandidates(ordered, failed);

    for (const raw of candidates) {
      const url = ConnectChannelManager.normalizeBaseUrl(raw);
      if (url.length === 0 || !ConnectChannelManager.isValidHttpBaseUrl(url)) {
        continue;
      }
      if (seen.has(url)) {
        continue;
      }
      seen.add(url);
      const ok = await ConnectChannelManager.probeDirect(url, expectedServerId);
      if (!ok) {
        continue;
      }
      if (ConnectChannelManager.normalizeBaseUrl(api.baseUrl) !== url) {
        const wasP2p = api.isP2pMode;
        api.setBaseUrl(url);
        if (wasP2p) {
          ConnectChannelManager.disconnectP2pIfNotInUse();
        }
      }
      return true;
    }

    // 直连均不可用，回退 P2P
    const p2pInfo = ordered.find((s: ServerInfo) => (s.pairCode ?? '').trim().length > 0);
    const pairCode = (p2pInfo?.pairCode ?? '').trim();
    if (pairCode.length === 0) {
      return false;
    }

    const p2p = P2PService.getInstance();
    if (!reconnectCurrentP2p && api.isP2pMode) {
      if (p2p.isConnected) {
        // 网络变化后已处于 P2P：中继模式下先尝试升级为直连
        if (p2p.transportKind === P2pTransportKind.RELAY) {
          await ConnectChannelManager.runDirectUpgradeProbe();
          if (!api.isP2pMode) {
            return true;
          }
        }
        // isConnected 可能滞后于真实链路状态，必须探活确认
        if (await ConnectChannelManager.probeP2p(expectedServerId)) {
          return true;
        }
      }
      // 现有 P2P 连接已失效：强制断开后按原优先级重建。
      // 直连探测期间可能刚启动了新的 P2P 建连，此时不能抢断
      if (!p2p.isConnectInFlight()) {
        try {
          p2p.disconnect();
        } catch (_e) {
          // 忽略断开异常
        }
      }
    }

    return ConnectChannelManager.trySwitchToP2pAuto(p2pInfo);
  }

  private static loadServerInfosById(serverId: string): ServerInfo[] {
    const target = serverId.trim();
    if (target.length === 0) {
      return [];
    }
    const currentUsername = (CurrentUserStore.getInstance().current?.username ?? '').trim();
    const all = ServerStorageService.getInstance().loadServers();
    const matched: ServerInfo[] = [];
    if (currentUsername.length > 0) {
      for (const s of all) {
        if (s.serverId.trim() !== target) {
          continue;
        }
        if ((s.username ?? '').trim() === currentUsername) {
          matched.push(s);
        }
      }
      if (matched.length > 0) {
        return matched;
      }
    }
    const fallback: ServerInfo[] = [];
    for (const s of all) {
      if (s.serverId.trim() === target) {
        fallback.push(s);
      }
    }
    return fallback;
  }

  private static orderServerInfosForCurrentBaseUrl(infos: ServerInfo[]): ServerInfo[] {
    const current = ConnectChannelManager.normalizeBaseUrl(APIClient.getInstance().baseUrl);
    const matched: ServerInfo[] = [];
    const others: ServerInfo[] = [];
    for (const info of infos) {
      if (ConnectChannelManager.serverInfoMatchesBaseUrl(info, current)) {
        matched.push(info);
      } else {
        others.push(info);
      }
    }
    return matched.concat(others);
  }

  private static serverInfoMatchesBaseUrl(info: ServerInfo, baseUrl: string): boolean {
    if (baseUrl.length === 0 || baseUrl === NetworkConfig.P2P_BASE_URL) {
      return false;
    }
    const urls: string[] = [
      (info.userInputUrl ?? '').trim(),
      ConnectChannelManager.buildLanHttpBaseUrl(info),
      info.serverUrl.trim()
    ];
    for (const raw of urls) {
      if (ConnectChannelManager.normalizeBaseUrl(raw) === baseUrl) {
        return true;
      }
    }
    return false;
  }

  private static buildDirectProbeCandidates(infos: ServerInfo[], failedBaseUrl: string): string[] {
    const failed = ConnectChannelManager.normalizeBaseUrl(failedBaseUrl);
    const current = ConnectChannelManager.normalizeBaseUrl(APIClient.getInstance().baseUrl);
    const privateUrls: string[] = [];
    const publicUrls: string[] = [];
    const preferPublicFirst = ConnectChannelManager.shouldPreferPublicDirectUrls();

    const addUrl = (raw: string): void => {
      const url = ConnectChannelManager.normalizeBaseUrl(raw);
      if (url.length === 0) {
        return;
      }
      if (failed.length > 0 && url === failed) {
        return;
      }
      if (ConnectChannelManager.isUrlPrivateLan(url)) {
        privateUrls.push(url);
      } else {
        publicUrls.push(url);
      }
    };

    if (current.length > 0 && current !== NetworkConfig.P2P_BASE_URL && !preferPublicFirst) {
      addUrl(current);
    }
    for (const info of infos) {
      addUrl((info.userInputUrl ?? '').trim());
      addUrl(ConnectChannelManager.buildLanHttpBaseUrl(info));
      addUrl(info.serverUrl.trim());
    }
    if (current.length > 0 && current !== NetworkConfig.P2P_BASE_URL && preferPublicFirst) {
      addUrl(current);
    }
    return preferPublicFirst ? publicUrls.concat(privateUrls) : privateUrls.concat(publicUrls);
  }

  /** WiFi 下优先局域网地址；移动网络下优先公网地址（优先读取实时默认网络，避免事件期间状态滞后） */
  private static shouldPreferPublicDirectUrls(): boolean {
    const live = ConnectChannelManager.readDefaultBearers();
    if (live.size > 0) {
      if (live.has(connection.NetBearType.BEARER_WIFI)) {
        return false;
      }
      if (live.has(connection.NetBearType.BEARER_CELLULAR)) {
        return true;
      }
      return false;
    }
    if (ConnectChannelManager.activeBearers.has(connection.NetBearType.BEARER_WIFI)) {
      return false;
    }
    if (ConnectChannelManager.activeBearers.has(connection.NetBearType.BEARER_CELLULAR)) {
      return true;
    }
    return false;
  }

  private static isUrlPrivateLan(url: string): boolean {
    const m = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\/([^/:?#]+)/.exec(url.trim());
    if (m === null) {
      return false;
    }
    return ConnectChannelManager.isPrivateIpv4(m[1]);
  }

  private static isPrivateIpv4(host: string): boolean {
    const parts = host.trim().split('.');
    if (parts.length !== 4) {
      return false;
    }
    const nums: number[] = [];
    for (const part of parts) {
      const value = Number(part);
      if (Number.isNaN(value) || value < 0 || value > 255) {
        return false;
      }
      nums.push(value);
    }
    const a = nums[0];
    const b = nums[1];
    if (a === 10) {
      return true;
    }
    if (a === 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a === 192 && b === 168) {
      return true;
    }
    if (a === 127) {
      return true;
    }
    return false;
  }

  private static isValidHttpBaseUrl(baseUrl: string): boolean {
    return /^https?:\/\/[^\s]+$/i.test(baseUrl.trim());
  }

  // ==================== 全局网络类型变化监控 ====================

  /** 启动全局网络类型变化监控（对齐 Flutter startGlobalNetworkMonitor），登录后调用 */
  static startGlobalNetworkMonitor(): void {
    if (ConnectChannelManager.netConnection !== undefined) {
      return;
    }
    console.info('[NetMonitor] 启动全局网络变化监听');
    try {
      const nc = connection.createNetConnection();
      nc.on('netAvailable', (handle: connection.NetHandle): void => {
        ConnectChannelManager.onNetAvailable(handle);
      });
      nc.on('netLost', (handle: connection.NetHandle): void => {
        ConnectChannelManager.onNetLost(handle);
      });
      nc.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
        ConnectChannelManager.onNetCapabilitiesChange(info);
      });
      nc.register((err: BusinessError): void => {
        if (err) {
          console.error(`[NetMonitor] 注册网络监听失败: ${err.code} ${err.message}`);
          return;
        }
        ConnectChannelManager.refreshActiveBearers();
        console.info('[NetMonitor] 网络监听注册成功');
      });
      ConnectChannelManager.netConnection = nc;
      ConnectChannelManager.refreshActiveBearers();
      ConnectChannelManager.scheduleBearerPoll();
    } catch (e) {
      console.error(`[NetMonitor] 启动网络监听失败: ${e}`);
    }
  }

  /** 轻量轮询兜底：部分机型网络事件可能延迟/丢失，定时比对 bearer 集合确保切换能被发现 */
  private static scheduleBearerPoll(): void {
    if (ConnectChannelManager.netPollTimerId >= 0) {
      clearTimeout(ConnectChannelManager.netPollTimerId);
    }
    ConnectChannelManager.netPollTimerId = setTimeout((): void => {
      ConnectChannelManager.netPollTimerId = -1;
      if (ConnectChannelManager.netConnection === undefined) {
        return;
      }
      if (ConnectChannelManager.refreshActiveBearers()) {
        console.info(`[NetMonitor] 轮询发现网络变化 bearers=${ConnectChannelManager.bearerKey(ConnectChannelManager.activeBearers)}`);
        ConnectChannelManager.onNetworkTopologyChanged();
      }
      ConnectChannelManager.scheduleBearerPoll();
    }, 5000);
  }

  /** 网络可用事件：记录该 netId 的类型，并立即安排重检（不依赖默认网络切换时机） */
  private static onNetAvailable(handle: connection.NetHandle): void {
    const netId = handle?.netId ?? 0;
    if (netId > 0) {
      ConnectChannelManager.netBearers.set(netId, ConnectChannelManager.readBearersOfHandle(handle));
    }
    ConnectChannelManager.refreshActiveBearers();
    console.info(`[NetMonitor] netAvailable netId=${netId} bearers=${ConnectChannelManager.bearerKey(ConnectChannelManager.activeBearers)}`);
    ConnectChannelManager.onNetworkTopologyChanged();
  }

  /** 网络丢失事件：移除该 netId 并立即安排重检 */
  private static onNetLost(handle: connection.NetHandle): void {
    const netId = handle?.netId ?? 0;
    if (netId > 0) {
      ConnectChannelManager.netBearers.delete(netId);
    }
    ConnectChannelManager.refreshActiveBearers();
    console.info(`[NetMonitor] netLost netId=${netId} bearers=${ConnectChannelManager.bearerKey(ConnectChannelManager.activeBearers)}`);
    ConnectChannelManager.onNetworkTopologyChanged();
  }

  /** 能力变化事件：仅当 bearer 类型集合真的变化时才重检，避免带宽等变化造成频繁探测 */
  private static onNetCapabilitiesChange(info: connection.NetCapabilityInfo): void {
    const netId = info?.netHandle?.netId ?? 0;
    if (netId > 0) {
      const types: number[] = [];
      const caps = info.netCap;
      const bearerTypes = caps?.bearerTypes;
      if (bearerTypes !== undefined) {
        for (const t of bearerTypes) {
          types.push(t as number);
        }
      }
      ConnectChannelManager.netBearers.set(netId, types);
    }
    const changed = ConnectChannelManager.refreshActiveBearers();
    if (!changed) {
      return;
    }
    console.info(`[NetMonitor] netCapabilitiesChange netId=${netId} bearers=${ConnectChannelManager.bearerKey(ConnectChannelManager.activeBearers)}`);
    ConnectChannelManager.onNetworkTopologyChanged();
  }

  private static readBearersOfHandle(handle: connection.NetHandle): number[] {
    const types: number[] = [];
    try {
      const caps = connection.getNetCapabilitiesSync(handle);
      if (caps.bearerTypes !== undefined) {
        for (const t of caps.bearerTypes) {
          types.push(t as number);
        }
      }
    } catch (_e) {
      // 能力读取失败时留空，由后续 netCapabilitiesChange 补齐
    }
    return types;
  }

  private static onNetworkTopologyChanged(): void {
    ConnectChannelManager.netChangeEventAtMs = Date.now();
    ConnectChannelManager.netChangeSettleRetryCount = 0;
    ConnectChannelManager.scheduleNetChangeProbe(NET_CHANGE_PROBE_DELAY_MS, true);
  }

  /** 应用回到前台时补检一次，覆盖后台期间错过的网络事件 */
  static onAppForeground(): void {
    if (!APIClient.getInstance().isAuthenticated) {
      return;
    }
    const now = Date.now();
    if (now - ConnectChannelManager.lastForegroundProbeAtMs < 3000) {
      return;
    }
    ConnectChannelManager.lastForegroundProbeAtMs = now;
    ConnectChannelManager.netChangeEventAtMs = now;
    ConnectChannelManager.netChangeSettleRetryCount = 0;
    ConnectChannelManager.scheduleNetChangeProbe(500, true);
  }

  /** 停止全局网络类型变化监控（对齐 Flutter stopGlobalNetworkMonitor），登出时调用 */
  static stopGlobalNetworkMonitor(): void {
    if (ConnectChannelManager.netChangeTimerId >= 0) {
      clearTimeout(ConnectChannelManager.netChangeTimerId);
      ConnectChannelManager.netChangeTimerId = -1;
    }
    if (ConnectChannelManager.netPollTimerId >= 0) {
      clearTimeout(ConnectChannelManager.netPollTimerId);
      ConnectChannelManager.netPollTimerId = -1;
    }
    const nc = ConnectChannelManager.netConnection;
    ConnectChannelManager.netConnection = undefined;
    if (nc !== undefined) {
      try {
        nc.unregister((_err: BusinessError): void => {
        });
      } catch (_e) {
        // 忽略注销异常
      }
    }
    ConnectChannelManager.netBearers.clear();
    ConnectChannelManager.activeBearers.clear();
    ConnectChannelManager.lastBearerKey = '';
    ConnectChannelManager.lastLiveBearerKey = '';
    ConnectChannelManager.hasBearerBaseline = false;
    ConnectChannelManager.netChangeProbeLocked = false;
    ConnectChannelManager.netChangeProbeAtMs = 0;
    ConnectChannelManager.netChangeEventAtMs = 0;
    ConnectChannelManager.netChangeSettleRetryCount = 0;
  }

  /**
   * 汇总当前所有已记录网络（事件 netId）与默认网络的 bearer 类型。
   * 返回 bearer 集合是否发生变化。不依赖 getDefaultNetSync 的切换时机，
   * 避免 WiFi/5G 切换瞬间默认网络尚未更新导致“看起来没变化”。
   */
  private static refreshActiveBearers(): boolean {
    const union = new Set<number>();
    ConnectChannelManager.netBearers.forEach((types: number[]): void => {
      for (const t of types) {
        union.add(t);
      }
    });
    const live = ConnectChannelManager.readDefaultBearers();
    live.forEach((t: number): void => {
      union.add(t);
    });
    ConnectChannelManager.activeBearers = union;

    const key = ConnectChannelManager.bearerKey(union);
    const liveKey = ConnectChannelManager.bearerKey(live);
    if (!ConnectChannelManager.hasBearerBaseline) {
      ConnectChannelManager.hasBearerBaseline = true;
      ConnectChannelManager.lastBearerKey = key;
      ConnectChannelManager.lastLiveBearerKey = liveKey;
      return false;
    }
    let changed = false;
    if (key !== ConnectChannelManager.lastBearerKey) {
      ConnectChannelManager.lastBearerKey = key;
      changed = true;
    }
    // 单独比较实时默认网络，避免 netBearers 中残留的旧网络掩盖“WiFi 重新连上”等变化
    if (liveKey !== ConnectChannelManager.lastLiveBearerKey) {
      ConnectChannelManager.lastLiveBearerKey = liveKey;
      changed = true;
    }
    return changed;
  }

  private static readDefaultBearers(): Set<number> {
    const bearers = new Set<number>();
    try {
      if (connection.hasDefaultNetSync()) {
        const handle = connection.getDefaultNetSync();
        if (handle !== undefined && handle.netId !== 0) {
          const caps = connection.getNetCapabilitiesSync(handle);
          if (caps.bearerTypes !== undefined) {
            for (const t of caps.bearerTypes) {
              bearers.add(t as number);
            }
          }
        }
      }
    } catch (_e) {
      // 读取失败时忽略，等待下一步事件
    }
    return bearers;
  }

  private static bearerKey(bearers: Set<number>): string {
    const arr: number[] = [];
    bearers.forEach((v: number): void => {
      arr.push(v);
    });
    arr.sort((a: number, b: number): number => a - b);
    return arr.join(',');
  }

  /** force=true 时不受 5s 节流限制（网络上下线属于明确拓扑变化） */
  private static scheduleNetChangeProbe(delayMs: number, force: boolean = false): void {
    if (force) {
      ConnectChannelManager.netChangeProbeAtMs = 0;
    }
    if (ConnectChannelManager.netChangeTimerId >= 0) {
      clearTimeout(ConnectChannelManager.netChangeTimerId);
    }
    ConnectChannelManager.netChangeTimerId = setTimeout((): void => {
      ConnectChannelManager.netChangeTimerId = -1;
      void ConnectChannelManager.runFullChannelProbeAfterNetworkChange();
    }, delayMs);
  }

  /** 网络类型切换后按优先级全量探测通道（对齐 Flutter _runFullChannelProbeAfterNetworkChange） */
  private static async runFullChannelProbeAfterNetworkChange(): Promise<void> {
    const api = APIClient.getInstance();
    if (!api.isAuthenticated) {
      return;
    }
    if (ConnectChannelManager.netChangeProbeLocked) {
      ConnectChannelManager.scheduleNetChangeProbe(2000);
      return;
    }
    const now = Date.now();
    const elapsed = now - ConnectChannelManager.netChangeProbeAtMs;
    if (elapsed < NET_CHANGE_PROBE_THROTTLE_MS) {
      ConnectChannelManager.scheduleNetChangeProbe(NET_CHANGE_PROBE_THROTTLE_MS - elapsed + 100);
      return;
    }
    ConnectChannelManager.netChangeProbeAtMs = now;

    const serverId = api.state.serverId.trim();
    if (serverId.length === 0) {
      return;
    }
    const infos = ConnectChannelManager.loadServerInfosById(serverId);
    if (infos.length === 0) {
      return;
    }

    ConnectChannelManager.netChangeProbeLocked = true;
    ConnectChannelManager.failoverCooldownUntilMs = 0;
    console.info(`[NetMonitor] 网络变化后重检通道，当前 baseUrl=${api.baseUrl}, bearers=${ConnectChannelManager.bearerKey(ConnectChannelManager.activeBearers)}`);
    try {
      await ConnectChannelManager.probePreferredChannel(infos, false, '');
    } catch (e) {
      console.error(`[NetMonitor] 网络变化后重检通道失败: ${e}`);
    } finally {
      ConnectChannelManager.netChangeProbeLocked = false;
      // 默认网络切换可能滞后于事件：再补检 2 次，确保 WiFi 刚连上时也能切回内网直连
      if (ConnectChannelManager.netChangeSettleRetryCount < 2
        && Date.now() - ConnectChannelManager.netChangeEventAtMs < 15000) {
        ConnectChannelManager.netChangeSettleRetryCount++;
        ConnectChannelManager.scheduleNetChangeProbe(2500, true);
      }
    }
  }

  // ==================== 通道切换 ====================

  private static loadServerInfo(): ServerInfo | undefined {
    const sid = APIClient.getInstance().state.serverId.trim();
    if (sid.length === 0) {
      return undefined;
    }
    const infos = ConnectChannelManager.loadServerInfosById(sid);
    if (infos.length === 0) {
      return undefined;
    }
    return ConnectChannelManager.orderServerInfosForCurrentBaseUrl(infos)[0];
  }

  // ==================== 直连切换 ====================

  /** 逐个探测直连候选并切换（对齐 _switchDevToDirect + _trySwitchToDirect） */
  private static async switchToDirect(info: ServerInfo): Promise<boolean> {
    const api = APIClient.getInstance();
    const current = ConnectChannelManager.normalizeBaseUrl(api.baseUrl);
    const raws: string[] = [
      (info.userInputUrl ?? '').trim(),
      ConnectChannelManager.buildLanHttpBaseUrl(info),
      info.serverUrl.trim()
    ];
    const seen = new Set<string>();
    let sawDifferent = false;
    for (const raw of raws) {
      const n = ConnectChannelManager.normalizeBaseUrl(raw);
      if (n.length === 0 || n === NetworkConfig.P2P_BASE_URL) {
        continue;
      }
      if (seen.has(n)) {
        continue;
      }
      seen.add(n);
      if (n === current) {
        continue;
      }
      sawDifferent = true;
      const ok = await ConnectChannelManager.probeDirect(n, api.state.serverId);
      if (ok) {
        const wasP2p = api.isP2pMode;
        api.setBaseUrl(n);
        if (wasP2p) {
          ConnectChannelManager.disconnectP2pIfNotInUse();
        }
        return true;
      }
    }
    // 候选均为当前通道且当前不是 P2P：视为已在直连（无需切换）
    return !sawDifferent && !api.isP2pMode;
  }

  private static buildLanHttpBaseUrl(info: ServerInfo): string {
    const ip = (info.lanIpv4 ?? '').trim();
    const portRaw = (info.lanHttpPort ?? '').trim();
    if (ip.length === 0 || portRaw.length === 0) {
      return '';
    }
    const port = Number(portRaw);
    if (Number.isNaN(port) || port <= 0 || port > 65535) {
      return '';
    }
    const ref = (info.userInputUrl ?? '').trim().length > 0
      ? (info.userInputUrl ?? '').trim()
      : info.serverUrl.trim();
    const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\//.exec(ref);
    const scheme = m !== null ? m[1].toLowerCase() : 'http';
    return `${scheme}://${ip}:${portRaw}`;
  }

  /** GET {baseUrl}/health 探活（对齐 _probeHealthDirect，网络抖动时快速重试一次） */
  private static async probeDirect(baseUrl: string, expectedServerId: string): Promise<boolean> {
    const url = `${ConnectChannelManager.normalizeBaseUrl(baseUrl)}/health`;
    const timeout = ConnectChannelManager.shouldPreferPublicDirectUrls()
      && !ConnectChannelManager.isUrlPrivateLan(baseUrl)
      ? PUBLIC_PROBE_TIMEOUT_MS
      : PROBE_TIMEOUT_MS;
    for (let attempt = 0; attempt < 2; attempt++) {
      const req = http.createHttp();
      try {
        const res = await req.request(url, {
          method: http.RequestMethod.GET,
          connectTimeout: timeout,
          readTimeout: timeout,
          expectDataType: http.HttpDataType.STRING,
          remoteValidation: 'skip'
        });
        if (res.responseCode !== 200) {
          return false;
        }
        let obj: Record<string, Object> = {};
        try {
          obj = JSON.parse(`${res.result}`) as Record<string, Object>;
        } catch (_e) {
          return false;
        }
        return ConnectChannelManager.isHealthOk(obj, expectedServerId);
      } catch (_e) {
        // 网络刚切换时 ARP/路由可能未收敛，稍后重试一次
      } finally {
        req.destroy();
      }
      if (attempt === 0) {
        await ConnectChannelManager.sleep(PROBE_RETRY_DELAY_MS);
      }
    }
    return false;
  }

  // ==================== P2P 切换 ====================

  /** Failover 自动切换 P2P：不传 ICE 偏好，按服务器远程连接偏好解析（对齐 _trySwitchToP2p） */
  private static async trySwitchToP2pAuto(info: ServerInfo | undefined): Promise<boolean> {
    const code = (info?.pairCode ?? '').trim();
    if (code.length === 0) {
      return false;
    }
    const api = APIClient.getInstance();
    const previousBaseUrl = api.baseUrl;
    const previousWasP2p = api.isP2pMode;
    try {
      await P2PService.getInstance().connectByPairCode(code);
      const ok = await ConnectChannelManager.probeP2p(api.state.serverId);
      if (ok) {
        ConnectChannelManager.scheduleP2pDirectUpgrade();
        return true;
      }
    } catch (_e) {
      // 探活/连接失败走回退
    }
    try {
      // 探活失败期间可能已有新的建连在途，避免抢断
      if (!P2PService.getInstance().isConnectInFlight()) {
        P2PService.getInstance().disconnect();
      }
    } catch (_e) {
      // 忽略断开异常
    }
    if (!previousWasP2p && previousBaseUrl.trim().length > 0
      && previousBaseUrl.trim() !== NetworkConfig.P2P_BASE_URL) {
      api.setBaseUrl(previousBaseUrl);
    }
    return false;
  }

  /** 连接 P2P 并探活，失败回退原通道（对齐 _switchDevToP2p） */
  private static async switchToP2p(info: ServerInfo | undefined,
    pref: P2pIcePreference, codeIn: string = ''): Promise<boolean> {
    const api = APIClient.getInstance();
    const code = codeIn.length > 0 ? codeIn : (info?.pairCode ?? '').trim();
    if (code.length === 0) {
      return false;
    }
    const previousBaseUrl = api.baseUrl;
    const previousWasP2p = api.isP2pMode;
    try {
      await P2PService.getInstance().connectByPairCode(code, pref);
      const ok = await ConnectChannelManager.probeP2p(api.state.serverId);
      if (ok) {
        return true;
      }
    } catch (_e) {
      // 探活/连接失败走回退
    }
    try {
      // 探活失败期间可能已有新的建连在途，避免抢断
      if (!P2PService.getInstance().isConnectInFlight()) {
        P2PService.getInstance().disconnect();
      }
    } catch (_e) {
      // 忽略断开异常
    }
    if (!previousWasP2p && previousBaseUrl.trim().length > 0
      && previousBaseUrl.trim() !== NetworkConfig.P2P_BASE_URL) {
      api.setBaseUrl(previousBaseUrl);
    }
    return false;
  }

  /** P2P 通道 /health 探活（对齐 _probeHealthP2p） */
  private static async probeP2p(expectedServerId: string): Promise<boolean> {
    const p2p = P2PService.getInstance();
    if (!p2p.isConnected) {
      return false;
    }
    try {
      const res = await p2p.send('GET' as HttpMethod, '/health', new HeaderMap(),
        undefined, undefined, PROBE_TIMEOUT_MS);
      if (res.statusCode !== 200) {
        return false;
      }
      let obj: Record<string, Object> = {};
      try {
        obj = JSON.parse(res.bodyText) as Record<string, Object>;
      } catch (_e) {
        return false;
      }
      return ConnectChannelManager.isHealthOk(obj, expectedServerId);
    } catch (_e) {
      return false;
    }
  }

  private static disconnectP2pIfNotInUse(): void {
    // 延迟断开 P2P，给在途请求留时间（对齐 _disconnectP2pIfNotInUse）
    setTimeout((): void => {
      // 延迟期间可能已发起新的 P2P 建连，不能在此时断开
      if (!APIClient.getInstance().isP2pMode && !P2PService.getInstance().isConnectInFlight()) {
        P2PService.getInstance().disconnect();
      }
    }, P2P_DISCONNECT_DELAY_MS);
  }

  // ==================== 通用 ====================

  private static sleep(ms: number): Promise<void> {
    return new Promise((resolve: (value: void) => void): void => {
      setTimeout(resolve, ms);
    });
  }

  private static normalizeBaseUrl(url: string): string {
    let s = url.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /** success=true 且（可校验时）serverId 匹配（对齐 _isHealthOk） */
  private static isHealthOk(json: Record<string, Object>, expectedServerId: string): boolean {
    const s = json['success'];
    const success = s === true || s === 1 || `${s ?? ''}`.toLowerCase() === 'true';
    if (!success) {
      return false;
    }
    const expected = expectedServerId.trim();
    if (expected.length === 0) {
      return true;
    }
    const sid = `${json['serverId'] ?? ''}`.trim();
    if (sid.length === 0) {
      return true;
    }
    return sid === expected;
  }
}
