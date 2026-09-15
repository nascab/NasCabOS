import { http } from '@kit.NetworkKit';
import { APIClient, HttpMethod } from './APIClient';
import { NetworkConfig } from './NetworkConfig';
import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';
import { ServerStorageService } from '../storage/ServerStorageService';
import { ServerInfo } from '../../auth/models/ServerInfo';
import { P2PService } from '../../p2p/P2PService';
import { P2pIcePreference } from '../../p2p/P2pProtocol';
import { DevConnectMode, DevConnectModeUtil } from './DevConnectMode';
import { HeaderMap } from '../../common/HeaderMap';

const PROBE_TIMEOUT_MS = 2000;
const P2P_DISCONNECT_DELAY_MS = 2000;

/**
 * 连接通道切换管理（对齐 Flutter ApiController 的 DevConnectMode 相关逻辑）：
 * 直连候选探测（userInputUrl > lan > serverUrl）与 P2P 连接（ICE 偏好），/health 探活校验 serverId。
 */
export class ConnectChannelManager {
  /** 读取持久化的通道模式（默认 auto） */
  static getMode(): DevConnectMode {
    return DevConnectModeUtil.parse(
      PreferencesStore.getInstance().getString(CacheKeys.DEV_CONNECT_MODE, ''));
  }

  /** 保存并立即生效（对齐 setDevConnectMode(applyNow: true)）；失败抛错由 UI 提示 */
  static async setMode(mode: DevConnectMode): Promise<void> {
    try {
      await PreferencesStore.getInstance().setString(CacheKeys.DEV_CONNECT_MODE, `${mode}`);
    } catch (_e) {
      // 持久化失败不阻断切换（对齐 Flutter try/catch）
    }
    await ConnectChannelManager.applyNow(mode);
  }

  /** 当前模式立即生效（对齐 applyDevConnectModeNow） */
  static async applyNow(mode: DevConnectMode): Promise<void> {
    if (mode === DevConnectMode.AUTO) {
      const ok = await ConnectChannelManager.applyAuto();
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

  /** 自动：直连候选优先，其次 P2P（对齐 refreshConnectChannel 优先级：直连 > P2P直连 > P2P中继） */
  private static async applyAuto(): Promise<boolean> {
    const info = ConnectChannelManager.loadServerInfo();
    if (info !== undefined) {
      const directOk = await ConnectChannelManager.switchToDirect(info);
      if (directOk) {
        return true;
      }
    }
    const code = ConnectChannelManager.resolvePairCode(info);
    if (code.length > 0) {
      return ConnectChannelManager.switchToP2p(info, P2pIcePreference.AUTO, code);
    }
    // 无候选时保持现状（对齐 refreshConnectChannel 无候选返回当前通道可用）
    return true;
  }

  private static loadServerInfo(): ServerInfo | undefined {
    const sid = APIClient.getInstance().state.serverId.trim();
    if (sid.length === 0) {
      return undefined;
    }
    return ServerStorageService.getInstance().loadServers()
      .find((s: ServerInfo) => s.serverId === sid);
  }

  private static resolvePairCode(info: ServerInfo | undefined): string {
    const fromInfo = (info?.pairCode ?? '').trim();
    if (fromInfo.length > 0) {
      return fromInfo;
    }
    return P2PService.getInstance().storedPairCode;
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
      const ok = await ConnectChannelManager.probeDirect(n);
      if (ok) {
        const wasP2p = api.isP2pMode;
        api.setBaseUrl(n);
        if (wasP2p) {
          // 延迟断开 P2P，给在途请求留时间（对齐 _disconnectP2pIfNotInUse）
          setTimeout((): void => {
            if (!APIClient.getInstance().isP2pMode) {
              P2PService.getInstance().disconnect();
            }
          }, P2P_DISCONNECT_DELAY_MS);
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

  /** GET {baseUrl}/health 探活（对齐 _probeHealthDirect） */
  private static async probeDirect(baseUrl: string): Promise<boolean> {
    const url = `${ConnectChannelManager.normalizeBaseUrl(baseUrl)}/health`;
    const req = http.createHttp();
    try {
      const res = await req.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: PROBE_TIMEOUT_MS,
        readTimeout: PROBE_TIMEOUT_MS,
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
      return ConnectChannelManager.isHealthOk(obj);
    } catch (_e) {
      return false;
    } finally {
      req.destroy();
    }
  }

  // ==================== P2P 切换 ====================

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
      const ok = await ConnectChannelManager.probeP2p();
      if (ok) {
        return true;
      }
    } catch (_e) {
      // 探活/连接失败走回退
    }
    try {
      P2PService.getInstance().disconnect();
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
  private static async probeP2p(): Promise<boolean> {
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
      return ConnectChannelManager.isHealthOk(obj);
    } catch (_e) {
      return false;
    }
  }

  // ==================== 通用 ====================

  private static normalizeBaseUrl(url: string): string {
    let s = url.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /** success=true 且（可校验时）serverId 匹配（对齐 _isHealthOk） */
  private static isHealthOk(json: Record<string, Object>): boolean {
    const s = json['success'];
    const success = s === true || s === 1 || `${s ?? ''}`.toLowerCase() === 'true';
    if (!success) {
      return false;
    }
    const expected = APIClient.getInstance().state.serverId.trim();
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
