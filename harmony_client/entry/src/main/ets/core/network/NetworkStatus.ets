import { wifiManager } from '@kit.ConnectivityKit';

/**
 * 网络状态工具：移动端自动备份仅在 WiFi 下执行（对齐 Flutter Connectivity().checkConnectivity）。
 * 无 Wi-Fi 模块（模拟器/PC）时返回 false，与 Flutter 的"检测失败不自动备份"语义一致。
 */
export class NetworkStatus {
  /** 当前是否连接 Wi-Fi */
  static isOnWifi(): boolean {
    try {
      return wifiManager.isWifiActive();
    } catch (_e) {
      return false;
    }
  }
}
