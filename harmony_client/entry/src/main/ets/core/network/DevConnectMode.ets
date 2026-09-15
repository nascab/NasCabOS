/**
 * 开发者连接通道模式（对齐 Flutter enum DevConnectMode）：
 * auto=自动探测，direct=强制直连，p2p=自动 P2P，p2pDirect=强制 P2P 打洞直连，p2pRelay=强制 P2P 中继。
 */
export enum DevConnectMode {
  AUTO = 'auto',
  DIRECT = 'direct',
  P2P = 'p2p',
  P2P_DIRECT = 'p2pDirect',
  P2P_RELAY = 'p2pRelay'
}

/** 序列化/解析（对齐 Flutter _parseDevConnectMode/_serializeDevConnectMode） */
export class DevConnectModeUtil {
  static parse(v: string | undefined | null): DevConnectMode {
    const s = (v ?? '').trim().toLowerCase();
    switch (s) {
      case 'direct':
        return DevConnectMode.DIRECT;
      case 'p2p':
        return DevConnectMode.P2P;
      case 'p2pdirect':
        return DevConnectMode.P2P_DIRECT;
      case 'p2prelay':
        return DevConnectMode.P2P_RELAY;
      default:
        return DevConnectMode.AUTO;
    }
  }
}
