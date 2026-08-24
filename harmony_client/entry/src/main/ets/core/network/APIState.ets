import { NetworkConfig } from './NetworkConfig';

export class APIState {
  serverId: string = '';
  accessToken: string | undefined = undefined;
  refreshToken: string | undefined = undefined;
  baseUrl: string = NetworkConfig.LOCALHOST_BASE_URL;
  isAuthenticated: boolean = false;
  expiresAtMs: number = 0;
  shellSupported: boolean = false;
  serverVersion: string | undefined = undefined;

  isTokenExpiringSoon(): boolean {
    if (this.expiresAtMs <= 0) {
      return false;
    }
    return (this.expiresAtMs - Date.now()) <= NetworkConfig.TOKEN_EXPIRY_THRESHOLD_MS;
  }

  isP2pMode(): boolean {
    return this.baseUrl.trim() === NetworkConfig.P2P_BASE_URL;
  }
}
