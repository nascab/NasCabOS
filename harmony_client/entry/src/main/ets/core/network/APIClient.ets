import { http } from '@kit.NetworkKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { APIState } from './APIState';
import { APIResponse } from './APIResponse';
import { NetworkConfig } from './NetworkConfig';
import { L10n } from '../localization/L10n';
import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';
import { AppEventBus } from '../../common/AppEventBus';
import { ApiEnvelope, JsonCodec, LoginDataJson } from '../../common/JsonTypes';
import { HeaderMap } from '../../common/HeaderMap';
import { HttpHeaders, RefreshTokenBody } from '../../common/HttpTypes';

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'DELETE';

export class APIClient {
  private static instance: APIClient | undefined = undefined;
  state: APIState = new APIState();
  private refreshInFlight: Promise<boolean> | undefined = undefined;
  private refreshTimerId: number = -1;
  private p2pSender: P2pRequestSender | undefined = undefined;

  static getInstance(): APIClient {
    if (!APIClient.instance) {
      APIClient.instance = new APIClient();
    }
    return APIClient.instance;
  }

  setP2pSender(sender: P2pRequestSender): void {
    this.p2pSender = sender;
  }

  get baseUrl(): string {
    return this.state.baseUrl;
  }

  get accessToken(): string | undefined {
    return this.state.accessToken;
  }

  get isAuthenticated(): boolean {
    return this.state.isAuthenticated;
  }

  get isP2pMode(): boolean {
    return this.state.isP2pMode();
  }

  setBaseUrl(url: string): void {
    this.state.baseUrl = url;
    void PreferencesStore.getInstance().setString(CacheKeys.AUTH_BASE_URL, url);
  }

  setAuthInfo(
    serverId: string,
    accessToken: string,
    refreshToken: string,
    expiresInSec: number,
    shellSupported: boolean = false,
    serverVersion?: string
  ): void {
    this.state.serverId = serverId;
    this.state.accessToken = accessToken;
    this.state.refreshToken = refreshToken;
    this.state.isAuthenticated = true;
    this.state.expiresAtMs = Date.now() + expiresInSec * 1000;
    this.state.shellSupported = shellSupported;
    if (serverVersion && serverVersion.trim().length > 0) {
      this.state.serverVersion = serverVersion.trim();
    }
    this.saveTokensToStorage();
    this.startTokenRefreshTimer();
  }

  clearAuthInfo(): void {
    this.state.accessToken = undefined;
    this.state.refreshToken = undefined;
    this.state.isAuthenticated = false;
    this.state.expiresAtMs = 0;
    this.state.serverVersion = undefined;
    this.clearStoredTokens();
    this.stopTokenRefreshTimer();
  }

  loadStoredTokens(): void {
    const store = PreferencesStore.getInstance();
    const url = store.getString(CacheKeys.AUTH_BASE_URL, '');
    if (url && url.length > 0) {
      this.state.baseUrl = url;
    }
    this.state.serverId = store.getString(CacheKeys.AUTH_SERVER_ID, '') ?? '';
    const storedAccess = store.getString(CacheKeys.AUTH_ACCESS_TOKEN);
    const storedRefresh = store.getString(CacheKeys.AUTH_REFRESH_TOKEN);
    const expiryTimestamp = store.getInt(CacheKeys.AUTH_EXPIRES_IN, 0);
    this.state.shellSupported = store.getBool(CacheKeys.AUTH_SHELL_SUPPORTED, false);
    const storedVer = store.getString(CacheKeys.AUTH_SERVER_VERSION, '')?.trim();
    this.state.serverVersion = storedVer && storedVer.length > 0 ? storedVer : undefined;

    const isValid = expiryTimestamp > Date.now();
    this.state.accessToken = isValid ? storedAccess : undefined;
    this.state.refreshToken = storedRefresh;
    this.state.isAuthenticated = isValid && !!storedAccess;
    this.state.expiresAtMs = expiryTimestamp;

    this.startTokenRefreshTimer();
    if (!isValid && storedRefresh && storedRefresh.length > 0) {
      this.refreshAuthToken();
    }
  }

  async apiGet<T>(
    endpoint: string,
    queryParams?: Map<string, string>,
    timeoutMs?: number,
    maxRetries?: number,
    dataParser?: (data: Object, code: number) => T
  ): Promise<APIResponse<T>> {
    return this.apiRequest<T>('GET', endpoint, undefined, queryParams, timeoutMs, maxRetries, dataParser);
  }

  async apiPost<T>(
    endpoint: string,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number,
    maxRetries?: number,
    dataParser?: (data: Object, code: number) => T
  ): Promise<APIResponse<T>> {
    return this.apiRequest<T>('POST', endpoint, body, queryParams, timeoutMs, maxRetries, dataParser);
  }

  async getToBaseUrl(
    baseUrl: string,
    endpoint: string,
    timeoutMs: number = 3000
  ): Promise<APIResponse<Object>> {
    const fullUrl = `${baseUrl.trim()}${endpoint}`;
    try {
      const headers = this.buildHeaders();
      const req = http.createHttp();
      const response = await req.request(fullUrl, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        expectDataType: http.HttpDataType.STRING,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        remoteValidation: 'skip',
      });
      req.destroy();
      const json = JsonCodec.parseStr<ApiEnvelope>(response.result as string);
      return APIResponse.fromJSON<Object>(response.responseCode, json, (d, _) => d);
    } catch (e) {
      return APIResponse.failure<Object>(`${L10n.networkFailure}: ${e}`);
    }
  }

  private async apiRequest<T>(
    method: HttpMethod,
    endpoint: string,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number,
    maxRetries?: number,
    dataParser?: (data: Object, code: number) => T
  ): Promise<APIResponse<T>> {
    const maxAttempts = (maxRetries ?? NetworkConfig.DEFAULT_MAX_RETRIES) + 1;
    let lastError: string = L10n.networkFailure;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        const response = await this.sendRequest(method, endpoint, body, queryParams, timeoutMs);
        return this.handleResponse<T>(response, dataParser);
      } catch (e) {
        lastError = `${L10n.networkFailure}: ${e}`;
        if (attempt < maxAttempts - 1) {
          await APIClient.sleep(NetworkConfig.DEFAULT_RETRY_DELAY_MS);
        }
      }
    }
    return APIResponse.failure<T>(lastError);
  }

  private async sendRequest(
    method: HttpMethod,
    endpoint: string,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number
  ): Promise<HttpResult> {
    if (this.state.isP2pMode()) {
      return this.sendRequestViaP2P(method, endpoint, body, queryParams, timeoutMs);
    }

    let didRetryAfterRefresh = false;
    while (true) {
      const result = await this.sendDirectRequestOnce(method, endpoint, body, queryParams, timeoutMs);
      if (result.statusCode !== 401) {
        return result;
      }
      if (APIClient.isRefreshJwtEndpoint(endpoint)) {
        this.handleAuthSessionExpiredAfterRefreshJwt401();
        return result;
      }
      if (APIClient.isTwoFactorRequiredResponse(result.bodyText)) {
        return result;
      }
      if (didRetryAfterRefresh) {
        return result;
      }
      const refreshed = await this.refreshAuthToken();
      if (!refreshed) {
        return result;
      }
      didRetryAfterRefresh = true;
    }
  }

  private async sendDirectRequestOnce(
    method: HttpMethod,
    endpoint: string,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number
  ): Promise<HttpResult> {
    let fullUrl = `${this.state.baseUrl}${endpoint}`;
    if (queryParams && queryParams.size > 0) {
      const parts: string[] = [];
      queryParams.forEach((value: string, key: string) => {
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
      });
      const qs = parts.join('&');
      if (qs.length > 0) {
        fullUrl += fullUrl.includes('?') ? `&${qs}` : `?${qs}`;
      }
    }

    const headers = this.buildHeaders();
    if (method !== 'GET' && body) {
      headers.contentType = 'application/json';
    }

    const req = http.createHttp();
    const timeout = timeoutMs ?? NetworkConfig.DEFAULT_TIMEOUT_MS;
    const response = await req.request(fullUrl, {
      method: APIClient.toHttpMethod(method),
      header: headers.toMap(),
      extraData: method !== 'GET' && body ? JSON.stringify(body) : undefined,
      connectTimeout: timeout,
      readTimeout: timeout,
      expectDataType: http.HttpDataType.STRING,
      usingProtocol: http.HttpProtocol.HTTP1_1,
      remoteValidation: 'skip',
    });
    req.destroy();
    const result = new HttpResult();
    result.bodyText = response.result as string;
    result.statusCode = response.responseCode;
    return result;
  }

  private async sendRequestViaP2P(
    method: HttpMethod,
    endpoint: string,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number
  ): Promise<HttpResult> {
    if (!this.p2pSender) {
      throw new Error('P2P sender not configured');
    }
    let didRetryAfterRefresh = false;
    while (true) {
      const result = await this.p2pSender.send(
        method,
        endpoint,
        this.buildHeaderMap(),
        body,
        queryParams,
        timeoutMs
      );
      if (result.statusCode !== 401) {
        return result;
      }
      if (APIClient.isRefreshJwtEndpoint(endpoint)) {
        this.handleAuthSessionExpiredAfterRefreshJwt401();
        return result;
      }
      if (APIClient.isTwoFactorRequiredResponse(result.bodyText)) {
        return result;
      }
      if (didRetryAfterRefresh) {
        return result;
      }
      const refreshed = await this.refreshAuthToken();
      if (!refreshed) {
        return result;
      }
      didRetryAfterRefresh = true;
    }
  }

  private handleResponse<T>(
    response: HttpResult,
    dataParser?: (data: Object, code: number) => T
  ): APIResponse<T> {
    if (!response.bodyText || response.bodyText.length === 0) {
      return APIResponse.failure<T>(L10n.networkFailure);
    }
    const json = JsonCodec.parseStr<ApiEnvelope>(response.bodyText);
    return APIResponse.fromJSON<T>(response.statusCode, json, dataParser);
  }

  async refreshAuthToken(): Promise<boolean> {
    if (this.refreshInFlight) {
      return this.refreshInFlight;
    }
    this.refreshInFlight = this.performRefreshAuthToken();
    try {
      return await this.refreshInFlight;
    } finally {
      this.refreshInFlight = undefined;
    }
  }

  private async performRefreshAuthToken(): Promise<boolean> {
    const refreshToken = this.state.refreshToken;
    if (!refreshToken) {
      return false;
    }
    const body = new RefreshTokenBody(refreshToken);
    const response = await this.apiPost<LoginDataJson>(
      '/api/auth/refreshJwt',
      body,
      undefined,
      NetworkConfig.DEFAULT_TIMEOUT_MS,
      0,
      (d, _) => JsonCodec.parse<LoginDataJson>(d)
    );
    if (!response.success || !response.data) {
      return false;
    }
    const data = response.data;
    const token = data.accessToken;
    const refresh = data.refreshToken;
    const serverId = data.serverId;
    const expiresIn = data.expiresIn ?? 0;
    if (!token || !refresh || !serverId || expiresIn <= 0) {
      return false;
    }
    this.setAuthInfo(serverId, token, refresh, expiresIn, this.state.shellSupported);
    return true;
  }

  private handleAuthSessionExpiredAfterRefreshJwt401(): void {
    this.clearAuthInfo();
    AppEventBus.emitAuthSessionExpired();
  }

  private buildHeaders(): HttpHeaders {
    const headers = new HttpHeaders();
    headers.acceptLanguage = L10n.currentLanguageCode.replace(/_/g, '-');
    headers.userAgent = `NasCabOS Harmony/${deviceInfo.osFullName ?? 'HarmonyOS'}`;
    if (this.state.accessToken) {
      headers.authorization = `Bearer ${this.state.accessToken}`;
    }
    return headers;
  }

  private buildHeaderMap(): HeaderMap {
    const map = new HeaderMap();
    const h = this.buildHeaders();
    if (h.acceptLanguage.length > 0) {
      map.set('Accept-Language', h.acceptLanguage);
    }
    if (h.userAgent.length > 0) {
      map.set('User-Agent', h.userAgent);
    }
    if (h.authorization.length > 0) {
      map.set('Authorization', h.authorization);
    }
    return map;
  }

  private saveTokensToStorage(): void {
    const store = PreferencesStore.getInstance();
    void store.setString(CacheKeys.AUTH_BASE_URL, this.state.baseUrl);
    void store.setString(CacheKeys.AUTH_SERVER_ID, this.state.serverId);
    void store.setString(CacheKeys.AUTH_ACCESS_TOKEN, this.state.accessToken ?? '');
    void store.setString(CacheKeys.AUTH_REFRESH_TOKEN, this.state.refreshToken ?? '');
    void store.setInt(CacheKeys.AUTH_EXPIRES_IN, this.state.expiresAtMs);
    void store.setBool(CacheKeys.AUTH_SHELL_SUPPORTED, this.state.shellSupported);
    void store.setString(CacheKeys.AUTH_SERVER_VERSION, this.state.serverVersion ?? '');
  }

  private clearStoredTokens(): void {
    const store = PreferencesStore.getInstance();
    const keys = [
      CacheKeys.AUTH_ACCESS_TOKEN,
      CacheKeys.AUTH_REFRESH_TOKEN,
      CacheKeys.AUTH_EXPIRES_IN,
      CacheKeys.AUTH_SERVER_ID,
      CacheKeys.AUTH_BASE_URL,
      CacheKeys.AUTH_SHELL_SUPPORTED,
      CacheKeys.AUTH_SERVER_VERSION,
    ];
    for (let i = 0; i < keys.length; i++) {
      void store.remove(keys[i]);
    }
  }

  private startTokenRefreshTimer(): void {
    this.stopTokenRefreshTimer();
    if (!this.state.isAuthenticated) {
      return;
    }
    this.refreshTimerId = setInterval(() => {
      if (this.state.isTokenExpiringSoon()) {
        this.refreshAuthToken();
      }
    }, NetworkConfig.TOKEN_REFRESH_INTERVAL_MS);
  }

  private stopTokenRefreshTimer(): void {
    if (this.refreshTimerId >= 0) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
  }

  private static isRefreshJwtEndpoint(endpoint: string): boolean {
    return endpoint.includes('/api/auth/refreshJwt');
  }

  private static isTwoFactorRequiredResponse(dataStr: string): boolean {
    try {
      const json = JsonCodec.parseStr<ApiEnvelope>(dataStr);
      return `${json.code}` === 'twofa.TWO_FACTOR_REQUIRED';
    } catch (_e) {
      return false;
    }
  }

  private static toHttpMethod(method: HttpMethod): http.RequestMethod {
    switch (method) {
      case 'POST':
        return http.RequestMethod.POST;
      case 'PUT':
        return http.RequestMethod.PUT;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      default:
        return http.RequestMethod.GET;
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

export class HttpResult {
  bodyText: string = '';
  statusCode: number = 0;
}

export interface P2pRequestSender {
  send(
    method: HttpMethod,
    path: string,
    headers: HeaderMap,
    body?: Object,
    queryParams?: Map<string, string>,
    timeoutMs?: number
  ): Promise<HttpResult>;
}
