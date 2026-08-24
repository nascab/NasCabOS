import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { APIClient, HttpMethod, HttpResult, P2pRequestSender } from '../core/network/APIClient';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { PreferencesStore } from '../core/storage/PreferencesStore';
import { CacheKeys } from '../core/storage/CacheKeys';
import { ApiEnvelope, JsonCodec, P2pSessionJson } from '../common/JsonTypes';
import { HeaderMap } from '../common/HeaderMap';
import { WebSocketSignaling, WebSocketSignalingDelegate } from './WebSocketSignaling';
import { WebRTCClient } from './WebRTCClient';
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

  private sessionId: string = '';
  private signaling: WebSocketSignaling | undefined = undefined;
  private rtcClient: WebRTCClient | undefined = undefined;
  private allowReconnect: boolean = false;
  private reconnectAttempts: number = 0;
  private reconnectTimerId: number = -1;
  private connectSerialPromise: Promise<void> | undefined = undefined;

  static getInstance(): P2PService {
    if (!P2PService.instance) {
      P2PService.instance = new P2PService();
      APIClient.getInstance().setP2pSender(P2PService.instance);
    }
    return P2PService.instance;
  }

  async connectByPairCode(code: string, _icePreference: P2pIcePreference = P2pIcePreference.AUTO): Promise<void> {
    if (this.connectSerialPromise) {
      await this.connectSerialPromise;
    }
    this.connectSerialPromise = this.connectByPairCodeBody(code);
    try {
      await this.connectSerialPromise;
    } finally {
      this.connectSerialPromise = undefined;
    }
  }

  private async connectByPairCodeBody(code: string): Promise<void> {
    const trimmed = code.trim();
    if (trimmed.length === 0) {
      throw P2PError.emptyPairCode();
    }

    this.connectionState = P2PConnectionState.CONNECTING;
    this.lastError = undefined;

    try {
      this.clearReconnectTimer();
      await this.cleanupConnection(false);

      const session = await this.createP2pSession(trimmed);
      const wsUrl = session.wsUrl ?? '';
      const sid = session.sessionId ?? '';
      if (wsUrl.length === 0 || sid.length === 0) {
        throw P2PError.invalidSession();
      }

      this.sessionId = sid;
      this.pairCode = trimmed;
      this.allowReconnect = true;

      const iceServers = await this.connectSignaling(wsUrl);
      await this.startWebRTC(sid, iceServers);

      this.isConnected = true;
      this.connectionState = P2PConnectionState.CONNECTED;
      this.reconnectAttempts = 0;

      APIClient.getInstance().setBaseUrl(NetworkConfig.P2P_BASE_URL);
      await LocalPlaybackProxy.getInstance().start();
      await this.savePairCode(trimmed);
    } catch (e) {
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

  disconnect(): void {
    void this.cleanupConnection(true);
    this.isConnected = false;
    this.connectionState = P2PConnectionState.DISCONNECTED;
    this.sessionId = '';
    this.pairCode = '';
    LocalPlaybackProxy.getInstance().stop();
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
    const json = JsonCodec.parseStr<ApiEnvelope>(response.result as string);
    if (json.success !== true && json.code !== 0) {
      throw P2PError.wsError(`${json.code ?? 'p2p_session_create_failed'}`);
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

  private async startWebRTC(sessionId: string, iceServers: Object[]): Promise<void> {
    const ws = this.signaling;
    if (!ws) {
      throw P2PError.invalidSession();
    }

    const rtc = new WebRTCClient(sessionId, iceServers, (msg: SignalingOfferMsg) => {
      ws.sendOffer(msg);
    });
    this.rtcClient = rtc;

    const forwardHandler = new SignalingForwardHandler(rtc, () => {
      this.isConnected = false;
      this.connectionState = P2PConnectionState.DISCONNECTED;
      if (this.rtcClient) {
        this.rtcClient.close();
        this.rtcClient = undefined;
      }
      this.scheduleReconnect();
    });
    ws.delegate = forwardHandler;

    const channels: P2pRtcChannel[] = [P2pRtcChannel.API, P2pRtcChannel.FILE, P2pRtcChannel.VIDEO];
    await rtc.start(channels);
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
    this.relayAddress = '';
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
