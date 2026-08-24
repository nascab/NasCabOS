export class NetworkConfig {
  static readonly SIGNAL_API_BASE_URL: string = 'https://nas.cab';
  static readonly P2P_BASE_URL: string = 'http://p2p.local';
  static readonly LOCALHOST_BASE_URL: string = 'http://127.0.0.1:9000';
  static readonly DEFAULT_TIMEOUT_MS: number = 10000;
  static readonly DEFAULT_MAX_RETRIES: number = 1;
  static readonly DEFAULT_RETRY_DELAY_MS: number = 500;
  static readonly TOKEN_REFRESH_INTERVAL_MS: number = 60000;
  static readonly TOKEN_EXPIRY_THRESHOLD_MS: number = 300000;
}
