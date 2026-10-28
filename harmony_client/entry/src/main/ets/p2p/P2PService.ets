import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { APIClient, HttpMethod, HttpResult, P2pRequestSender } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { PreferencesStore } from '../core/storage/PreferencesStore';
import { CacheKeys } from '../core/storage/CacheKeys';
import { ServerStorageService } from '../core/storage/ServerStorageService';
import { ApiEnvelope, IceServerJson, JsonCodec, P2pSessionJson } from '../common/JsonTypes';
import { HeaderMap } from '../common/HeaderMap';
import { AppEventBus, EVENT_CONNECT_CHANNEL_CHANGED } from '../common/AppEventBus';
import { WebSocketSignaling, WebSocketSignalingDelegate } from './WebSocketSignaling';
import { TransportStatsResult, WebRTCClient, P2pStreamHandler } from './WebRTCClient';
import { WebRTCNativeBridge } from './WebRTCNativeBridge';
import { P2pSignalingBinary } from './P2pSignalingBinary';
import { LocalPlaybackProxy } from './LocalPlaybackProxy';
import {
  P2pApiResponse,
  P2pChannelUtil,
  P2pIcePreference,
  P2pRtcChannel,
  P2PError,
  P2pTransportKind,
} from './P2pProtocol';
import { SignalingDecoded } from '../common/JsonTypes';
import { SignalingOfferMsg } from './P2pSignalingBinary';

export class PairCodeBody {
  pairCode: string = '';

  constructor(pairCode: string) {
    this.pairCode = pairCode;
  }
}

export enum P2PConnectionState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  FAILED = 'failed',
  RECONNECTING = 'reconnecting',
}

class SignalingReadyHandler implements WebSocketSignalingDelegate {
  private resolveFn: (ice: Object[]) => void;
  private rejectFn: (e: Error) => void;
  private resolved: boolean = false;

  constructor(resolveFn: (ice: Object[]) => void, rejectFn: (e: Error) => void) {
    this.resolveFn = resolveFn;
    this.rejectFn = rejectFn;
  }

  onSessionReady(sessionId: string, iceServers: Object[]): void {
    if (!this.resolved) {
      this.resolved = true;
      this.resolveFn(iceServers);
    }
  }

  onWebRTCMessage(_message: SignalingDecoded): void {}

  onError(code: string): void {
    if (!this.resolved) {
      this.resolved = true;
      this.rejectFn(P2PError.wsError(code) as Error);
    }
  }

  onClose(): void {
    if (!this.resolved) {
      this.resolved = true;
      this.rejectFn(P2PError.wsError('p2p_ws_closed') as Error);
    }
  }
}

class SignalingForwardHandler implements WebSocketSignalingDelegate {
  private rtcClient: WebRTCClient;
  private onCloseFn: () => void;

  constructor(rtcClient: WebRTCClient, onCloseFn: () => void) {
    this.rtcClient = rtcClient;
    this.onCloseFn = onCloseFn;
  }

  onSessionReady(_sessionId: string, _iceServers: Object[]): void {}

  onWebRTCMessage(message: SignalingDecoded): void {
    this.rtcClient.handleSignalingMessage(message);
  }

  onError(_code: string): void {}

  onClose(): void {
    this.onCloseFn();
  }
}

export class P2PService implements P2pRequestSender {
  private static instance: P2PService | undefined = undefined;

  isConnected: boolean = false;
  pairCode: string = '';
  connectionState: P2PConnectionState = P2PConnectionState.DISCONNECTED;
  lastError: string | undefined = undefined;
  relayAddress: string = '';
  transportKind: P2pTransportKind = P2pTransportKind.UNKNOWN;
  /** 本次连接的 ICE 偏好（对齐 Flutter _p2pIcePreference，relayOnly 传给 RTC 栈） */
  icePreference: P2pIcePreference = P2pIcePreference.AUTO;

  private sessionId: string = '';
  private signaling: WebSocketSignaling | undefined = undefined;
  private rtcClient: WebRTCClient | undefined = undefined;
  private allowReconnect: boolean = false;
  private reconnectAttempts: number = 0;
  private reconnectTimerId: number = -1;
  private connectSerialPromise: Promise<void> | undefined = undefined;
  /** 建连代际：disconnect() 递增，在途建连 body 检查点失效后中止且不复活状态 */
  private connectEpoch: number = 0;
  /** 当前在途建连的配对码（供 isConnectInFlightFor 判定，对齐 Flutter _isP2pConnectInFlightFor） */
  private inFlightCode: string = '';
  /** 当前在途建连的 ICE 偏好（同码同偏好并发请求直接复用同一建连） */
  private inFlightPreference: P2pIcePreference = P2pIcePreference.AUTO;
  /** 已建立连接实际使用的 ICE 偏好（短路复用时需匹配） */
  private activeIcePreference: P2pIcePreference = P2pIcePreference.AUTO;

  static getInstance(): P2PService {
    if (!P2PService.instance) {
      P2PService.instance = new P2PService();
      APIClient.getInstance().setP2pSender(P2PService.instance);
    }
    return P2PService.instance;
  }

  async connectByPairCode(code: string, icePreference?: P2pIcePreference): Promise<void> {
    // 未显式传偏好（点击服务器/配对码添加/自动重连/Failover 等 null 入口）：
    // 按已保存服务器的远程连接偏好解析（中继优先→relayOnly，否则 auto）。
    // 显式传偏好（开发者通道切换、中继→直连升级探测）不经过此分支。
    const resolved = icePreference ?? (this.isRelayPreferredForPairCode(code)
      ? P2pIcePreference.RELAY_ONLY : P2pIcePreference.AUTO);
    this.icePreference = resolved;
    const trimmed = code.trim();
    // 同码同偏好建连已在进行中：直接复用同一 Promise，避免排队方重复建连
    // 并在随后因探活失败 disconnect() 打断在途建连（p2p_connect_stale）
    if (this.connectSerialPromise !== undefined && this.inFlightCode === trimmed
      && (resolved === P2pIcePreference.AUTO || this.inFlightPreference === resolved)) {
      await this.connectSerialPromise;
      return;
    }
    while (this.connectSerialPromise) {
      // 排队等待前一次建连结束，但吞掉其错误：
      // 排队方不继承前次失败，由本次按自己的参数重新评估（可短路复用）
      const prev = this.connectSerialPromise;
      await prev.catch(() => {});
    }
    this.inFlightCode = trimmed;
    this.inFlightPreference = resolved;
    this.connectSerialPromise = this.connectByPairCodeBody(trimmed, resolved);
    try {
      await this.connectSerialPromise;
    } finally {
      this.connectSerialPromise = undefined;
      this.inFlightCode = '';
    }
  }

  /** 按配对码查询服务器级「远程连接偏好」是否中继优先（对齐 Flutter _isP2pRelayPreferredForPairCode） */
  private isRelayPreferredForPairCode(code: string): boolean {
    const target = code.trim();
    if (target.length === 0) {
      return false;
    }
    try {
      const all = ServerStorageService.getInstance().loadServers();
      for (const s of all) {
        if ((s.pairCode ?? '').trim() !== target) {
          continue;
        }
        if (s.p2pRelayPreferred) {
          return true;
        }
      }
    } catch (_e) {
      // 读取失败按默认（直连优先）处理
    }
    return false;
  }

  private async connectByPairCodeBody(code: string, requestedPref: P2pIcePreference): Promise<void> {
    const trimmed = code.trim();
    if (trimmed.length === 0) {
      throw P2PError.emptyPairCode();
    }
    // 短路复用：同配对码已连上时直接复用现有通道（对齐 Flutter _isP2pReusableFor）。
    // 自动偏好复用任意通道（点击服务器等自动流程不拆可用连接）；
    // 显式偏好（直连/中继）要求一致才复用，否则按新偏好重建。
    if (this.isConnected && this.pairCode.trim() === trimmed
      && (requestedPref === P2pIcePreference.AUTO || this.activeIcePreference === requestedPref)) {
      return;
    }

    // 代际快照：disconnect() 递增 epoch，在途建连在检查点发现失效即中止
    const epoch = this.connectEpoch;

    this.connectionState = P2PConnectionState.CONNECTING;
    this.lastError = undefined;

    try {
      this.clearReconnectTimer();
      await this.cleanupConnection(false);

      const session = await this.createP2pSession(trimmed);
      if (epoch !== this.connectEpoch) {
        throw P2PError.wsError('p2p_connect_stale');
      }
      const wsUrl = session.wsUrl ?? '';
      const sid = session.sessionId ?? '';
      console.error(`[P2P] session created: wsUrl=${wsUrl}, sid=${sid}`);
      if (wsUrl.length === 0 || sid.length === 0) {
        throw P2PError.invalidSession();
      }

      this.sessionId = sid;
      this.pairCode = trimmed;
      this.allowReconnect = true;

      const iceServers = await this.connectSignaling(wsUrl);
      if (epoch !== this.connectEpoch) {
        throw P2PError.wsError('p2p_connect_stale');
      }
      console.error(`[P2P] signaling ready: iceServers=${JSON.stringify(iceServers)}`);
      // 对齐 Flutter：初始化前先解析中继地址并按 ICE 偏好预置传输类型，
      // 中继模式连接完成后 UI 即可显示中继节点地址
      this.updateRelayAddress(this.extractTurnServerAddress(iceServers));
      if (requestedPref === P2pIcePreference.RELAY_ONLY) {
        this.updateTransportKind(P2pTransportKind.RELAY);
      } else if (requestedPref === P2pIcePreference.DIRECT_ONLY) {
        this.updateTransportKind(P2pTransportKind.DIRECT);
      } else {
        this.updateTransportKind(P2pTransportKind.UNKNOWN);
      }
      await this.startWebRTC(sid, iceServers, epoch, requestedPref);
      if (epoch !== this.connectEpoch) {
        throw P2PError.wsError('p2p_connect_stale');
      }
      console.error('[P2P] webrtc channels ready');

      this.isConnected = true;
      this.connectionState = P2PConnectionState.CONNECTED;
      this.reconnectAttempts = 0;
      this.activeIcePreference = requestedPref;

      // 对齐 Flutter：连接后 800ms 用 ICE 统计确认真实传输类型（auto 偏好下可能走中继）
      this.scheduleTransportKindConfirm(epoch);

      APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
      await LocalPlaybackProxy.getInstance().start();
      await this.savePairCode(trimmed);
    } catch (e) {
      if (epoch !== this.connectEpoch) {
        // 建连期间发生过 disconnect()：状态已被复位，这里不再写 FAILED/lastError，防止复活
        throw P2PError.wsError('p2p_connect_stale');
      }
      this.connectionState = P2PConnectionState.FAILED;
      if (e instanceof Error) {
        this.lastError = e.message;
        throw e;
      }
      const err = new Error(`${e}`);
      this.lastError = err.message;
      throw err;
    }
  }

  async send(
    method: HttpMethod,
    path: string,
    headers: HeaderMap,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number
  ): Promise<HttpResult> {
    let fullPath = path;
    if (queryParams && queryParams.size > 0) {
      const parts: string[] = [];
      queryParams.forEach((value: string, key: string) => {
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
      });
      const qs = parts.join('&');
      if (qs.length > 0) {
        fullPath += fullPath.includes('?') ? `&${qs}` : `?${qs}`;
      }
    }

    const channel = P2pChannelUtil.resolvePath(fullPath);
    let bodyBytes = new Uint8Array(0);
    if (body && method !== 'GET') {
      const encoder = new util.TextEncoder();
      bodyBytes = encoder.encodeInto(JSON.stringify(body));
      // 对齐 Flutter：JSON 序列化 body 时显式声明 Content-Type，
      // 否则服务端不按 JSON 解析请求体，导致登录等接口收到空字段
      headers.set('Content-Type', 'application/json');
    }

    const response = await this.sendOnChannel(
      channel,
      method,
      fullPath,
      headers,
      bodyBytes,
      timeoutMs ?? 300000
    );

    const decoder = new util.TextDecoder();
    const result = new HttpResult();
    result.bodyText = decoder.decodeToString(response.bodyBytes);
    result.statusCode = response.status;
    return result;
  }

  async sendOnChannel(
    channel: P2pRtcChannel,
    method: string,
    path: string,
    headers: HeaderMap,
    bodyBytes: Uint8Array,
    timeoutMs: number
  ): Promise<P2pApiResponse> {
    if (!this.rtcClient || !this.isConnected) {
      throw P2PError.notConnected();
    }
    return this.rtcClient.sendRequest(channel, method, path, headers, bodyBytes, timeoutMs);
  }

  /**
   * 流式请求：响应体边收边回调（视频/大文件用，避免整包缓存）。
   * 返回取消函数，调用后通知对端停止推送。
   */
  async sendOnChannelStream(
    channel: P2pRtcChannel,
    method: string,
    path: string,
    headers: HeaderMap,
    bodyBytes: Uint8Array,
    timeoutMs: number,
    handler: P2pStreamHandler
  ): Promise<() => void> {
    if (!this.rtcClient || !this.isConnected) {
      throw P2PError.notConnected();
    }
    return this.rtcClient.sendRequestStream(channel, method, path, headers, bodyBytes, timeoutMs, handler);
  }

  disconnect(): void {
    // 代际 +1：使在途建连 body 在后续检查点失效并中止，防止断开后被在途逻辑复活
    this.connectEpoch += 1;
    void this.cleanupConnection(true);
    this.isConnected = false;
    this.connectionState = P2PConnectionState.DISCONNECTED;
    this.sessionId = '';
    this.pairCode = '';
    LocalPlaybackProxy.getInstance().stop();
  }

  /** 现有连接是否可复用于该配对码（对齐 Flutter _isP2pReusableFor） */
  isReusableFor(code: string): boolean {
    const trimmed = code.trim();
    return trimmed.length > 0 && this.isConnected && this.pairCode.trim() === trimmed;
  }

  /** 是否有针对该配对码的建连正在进行（对齐 Flutter _isP2pConnectInFlightFor） */
  isConnectInFlightFor(code: string): boolean {
    const trimmed = code.trim();
    return trimmed.length > 0 && this.connectSerialPromise !== undefined && this.inFlightCode === trimmed;
  }

  /** 是否有任意 P2P 建连正在进行（后台通道重检需避让，否则 disconnect 会打断在途建连） */
  isConnectInFlight(): boolean {
    return this.connectSerialPromise !== undefined;
  }

  get storedPairCode(): string {
    return (PreferencesStore.getInstance().getString(CacheKeys.P2P_LAST_PAIR_CODE, '') ?? '').trim();
  }

  private async createP2pSession(pairCode: string): Promise<P2pSessionJson> {
    const url = `${NetworkConfig.SIGNAL_API_BASE_URL}/api/p2p/pair/session/create`;
    const req = http.createHttp();
    const body = new PairCodeBody(pairCode);
    const response = await req.request(url, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify(body),
      connectTimeout: NetworkConfig.DEFAULT_TIMEOUT_MS,
      readTimeout: NetworkConfig.DEFAULT_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING,
      remoteValidation: 'skip',
    });
    req.destroy();
    // 非 2xx（如服务端未在线时信令返回 404/403）优先按 HTTP 状态码抛出，
    // 对齐 Flutter pair_session_http_<status>，避免把状态码当作业务错误直接展示给用户
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw P2PError.wsError(`pair_session_http_${response.responseCode}`);
    }
    const json = JsonCodec.parseStr<ApiEnvelope>(response.result as string);
    if (json.success !== true && json.code !== 0) {
      throw P2PError.wsError(`${json.code ?? 'p2p_session_create_failed'}`);
    }
    if (json.data === undefined || json.data === null) {
      // 服务端返回成功但缺少会话数据，给出明确错误而非晦涩的运行时异常
      throw P2PError.invalidSession();
    }
    return JsonCodec.parse<P2pSessionJson>(json.data as Object);
  }

  private connectSignaling(wsUrl: string): Promise<Object[]> {
    return new Promise<Object[]>((resolve, reject) => {
      const ws = new WebSocketSignaling();
      this.signaling = ws;
      const handler = new SignalingReadyHandler(resolve, reject);
      ws.delegate = handler;
      ws.connect(wsUrl);
    });
  }

  private async startWebRTC(sessionId: string, iceServers: Object[], epoch: number,
    requestedPref: P2pIcePreference): Promise<void> {
    const ws = this.signaling;
    if (!ws) {
      throw P2PError.invalidSession();
    }

    const relayOnly = requestedPref === P2pIcePreference.RELAY_ONLY;
    const directOnly = requestedPref === P2pIcePreference.DIRECT_ONLY;
    // 纯直连探测需在本端滤除 TURN，否则仍会生成 relay 候选并抢跑（对齐 Flutter）
    const rtcIceServers = directOnly ? this.filterDirectOnlyIceServers(iceServers) : iceServers;
    const rtc = new WebRTCClient(sessionId, rtcIceServers, (msg: SignalingOfferMsg) => {
      ws.sendOffer(msg);
    }, relayOnly, directOnly);
    this.rtcClient = rtc;

    // ICE 候选上行：对齐 Flutter 端 webrtc:candidate 信令
    WebRTCNativeBridge.setOnIceCandidate((candidate: string, sdpMid: string, sdpMLineIndex: number) => {
      ws.sendCandidate(P2pSignalingBinary.encodeCandidate(sessionId, candidate, sdpMid, sdpMLineIndex));
    });

    const forwardHandler = new SignalingForwardHandler(rtc, () => {
      // 纵深防御：迟到的 onClose 若已不属于当前代际/当前客户端，直接忽略
      //（手动 disconnect 已由 WebSocketSignaling.handleDisconnect 的 connected 标志抑制）
      if (epoch !== this.connectEpoch || this.rtcClient !== rtc) {
        return;
      }
      this.isConnected = false;
      this.connectionState = P2PConnectionState.DISCONNECTED;
      if (this.rtcClient) {
        this.rtcClient.close();
        this.rtcClient = undefined;
      }
      this.scheduleReconnect();
    });
    ws.delegate = forwardHandler;

    // UPLOAD 通道供分块上传使用（对齐 Flutter P2pRtcChannel.upload）
    const channels: P2pRtcChannel[] = [P2pRtcChannel.API, P2pRtcChannel.FILE, P2pRtcChannel.UPLOAD, P2pRtcChannel.VIDEO];
    await rtc.start(channels);
  }

  /** 从 ICE servers 中提取 turn/turns 中继地址（对齐 Flutter _extractTurnServerAddress） */
  private extractTurnServerAddress(iceServers: Object[]): string {
    for (let i = 0; i < iceServers.length; i++) {
      const urls = this.iceServerUrls(iceServers[i]);
      for (let j = 0; j < urls.length; j++) {
        const url = urls[j];
        const prefixLen = P2PService.turnUrlPrefixLength(url);
        if (prefixLen === 0) {
          continue;
        }
        // 去掉 scheme 与 user:pass@ 认证段，再截掉 ?transport=... 查询参数
        let hostPart = url.substring(prefixLen);
        const atIndex = hostPart.lastIndexOf('@');
        if (atIndex >= 0) {
          hostPart = hostPart.substring(atIndex + 1);
        }
        const qIndex = hostPart.indexOf('?');
        if (qIndex >= 0) {
          hostPart = hostPart.substring(0, qIndex);
        }
        return hostPart.trim();
      }
    }
    return '';
  }

  /** 提取单个 ICE server 的 urls 列表 */
  private iceServerUrls(server: Object): string[] {
    const json = JsonCodec.parse<IceServerJson>(server);
    const urls = json.urls;
    const list: string[] = [];
    if (urls === undefined || urls === null) {
      return list;
    }
    if (typeof urls === 'string') {
      const u = urls.trim();
      if (u.length > 0) {
        list.push(u);
      }
    } else if (Array.isArray(urls)) {
      const arr = urls as string[];
      for (let i = 0; i < arr.length; i++) {
        const u = `${arr[i] ?? ''}`.trim();
        if (u.length > 0) {
          list.push(u);
        }
      }
    }
    return list;
  }

  /** turn:/turns: URL 返回 scheme 长度，非 TURN 地址返回 0 */
  private static turnUrlPrefixLength(url: string): number {
    const lower = url.trim().toLowerCase();
    if (lower.startsWith('turns:')) {
      return 6;
    }
    if (lower.startsWith('turn:')) {
      return 5;
    }
    return 0;
  }

  /** 纯直连探测时剔除 TURN 服务器，避免本端生成 relay 候选（对齐 Flutter 本地滤除 TURN） */
  private filterDirectOnlyIceServers(iceServers: Object[]): Object[] {
    const out: Object[] = [];
    for (let i = 0; i < iceServers.length; i++) {
      const urls = this.iceServerUrls(iceServers[i]);
      let hasTurn = false;
      for (let j = 0; j < urls.length; j++) {
        if (P2PService.turnUrlPrefixLength(urls[j]) > 0) {
          hasTurn = true;
          break;
        }
      }
      if (!hasTurn) {
        out.push(iceServers[i]);
      }
    }
    return out;
  }

  private updateRelayAddress(addr: string): void {
    const next = addr.trim();
    if (this.relayAddress === next) {
      return;
    }
    this.relayAddress = next;
    AppEventBus.emit(EVENT_CONNECT_CHANNEL_CHANGED);
  }

  private updateTransportKind(kind: P2pTransportKind): void {
    if (this.transportKind === kind) {
      return;
    }
    this.transportKind = kind;
    AppEventBus.emit(EVENT_CONNECT_CHANNEL_CHANGED);
  }

  /** 连接后延迟确认实际传输类型（对齐 Flutter 的 800ms getTransportStats） */
  private scheduleTransportKindConfirm(epoch: number): void {
    // 多次探测：直连打洞失败回退中继时，relay 候选延迟 1.5s 才发送，
    // 800ms 时统计可能尚无结论；后续探测确保回退中继后能正确刷新类型与地址
    const delays: number[] = [800, 2000, 5000];
    for (let i = 0; i < delays.length; i++) {
      setTimeout(() => {
        this.confirmTransportKindOnce(epoch);
      }, delays[i]);
    }
  }

  private confirmTransportKindOnce(epoch: number): void {
    const rtc = this.rtcClient;
    if (!rtc || epoch !== this.connectEpoch || !this.isConnected) {
      return;
    }
    rtc.getTransportStats().then((stats: TransportStatsResult): void => {
      if (epoch !== this.connectEpoch || this.rtcClient !== rtc) {
        return;
      }
      if (stats.type === 'relay') {
        this.updateTransportKind(P2pTransportKind.RELAY);
      } else if (stats.type === 'host' || stats.type === 'srflx' || stats.type === 'prflx') {
        this.updateTransportKind(P2pTransportKind.DIRECT);
      }
    }).catch((_e: Object): void => {
      // 统计失败时保留按 ICE 偏好预置的类型
    });
  }

  private async cleanupConnection(disableReconnect: boolean): Promise<void> {
    if (disableReconnect) {
      this.allowReconnect = false;
      this.clearReconnectTimer();
      this.reconnectAttempts = 0;
    }
    if (this.rtcClient) {
      this.rtcClient.close();
      this.rtcClient = undefined;
    }
    if (this.signaling) {
      this.signaling.disconnect();
      this.signaling = undefined;
    }
    this.updateRelayAddress('');
    this.updateTransportKind(P2pTransportKind.UNKNOWN);
  }

  private scheduleReconnect(): void {
    if (!this.allowReconnect || this.pairCode.trim().length === 0) {
      return;
    }
    if (this.reconnectTimerId >= 0) {
      return;
    }
    const exp = Math.min(this.reconnectAttempts, 5);
    const baseSeconds = Math.min(2 * (1 << exp), 30);
    this.reconnectAttempts += 1;
    this.connectionState = P2PConnectionState.RECONNECTING;
    this.reconnectTimerId = setTimeout(() => {
      this.reconnectTimerId = -1;
      this.connectByPairCode(this.pairCode).then(() => {
        this.reconnectAttempts = 0;
      }).catch(() => {
        this.scheduleReconnect();
      });
    }, baseSeconds * 1000);
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimerId >= 0) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = -1;
    }
  }

  private async savePairCode(code: string): Promise<void> {
    await PreferencesStore.getInstance().setString(CacheKeys.P2P_LAST_PAIR_CODE, code);
  }
}
