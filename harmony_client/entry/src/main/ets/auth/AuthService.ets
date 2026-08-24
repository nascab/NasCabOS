import { util } from '@kit.ArkTS';
import { APIClient } from '../core/network/APIClient';
import { APIResponse } from '../core/network/APIResponse';
import { L10n } from '../core/localization/L10n';
import { DeviceFingerprint } from '../core/device/DeviceFingerprint';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { ServerInfo } from './models/ServerInfo';
import { LoginResponse, ServerStatusResponse } from './models/LoginResponse';
import { ApiEnvelope, JsonCodec, ServerStatusJson } from '../common/JsonTypes';
import { P2PService } from '../p2p/P2PService';
import { LogoutBody } from '../common/HttpTypes';

export class LoginRequestBody {
  username: string = '';
  password: string = '';
  device_fingerprint: Object = new Object();

  constructor(username: string, password: string, fingerprint: Object) {
    this.username = username;
    this.password = password;
    this.device_fingerprint = fingerprint;
  }
}

export class TwofaVerifyBody {
  tempToken: string = '';
  code: string = '';
  device_fingerprint: Object = new Object();

  constructor(tempToken: string, code: string, fingerprint: Object) {
    this.tempToken = tempToken;
    this.code = code;
    this.device_fingerprint = fingerprint;
  }
}

export class AuthService {
  private static instance: AuthService | undefined = undefined;
  private api: APIClient = APIClient.getInstance();

  static getInstance(): AuthService {
    if (!AuthService.instance) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  static obfuscatePassword(password: string): string {
    const helper = new util.Base64Helper();
    const b64 = helper.encodeToStringSync(new util.TextEncoder().encodeInto(password));
    return `b64:${b64}`;
  }

  async checkServerStatus(timeoutMs: number = 5000): Promise<ServerStatusResponse> {
    const response = await this.api.apiGet<Object>(
      '/api/auth/isNasCabServer',
      undefined,
      timeoutMs,
      0,
      (d, _) => d
    );
    return AuthService.parseServerStatus(response);
  }

  async checkServerStatusAt(baseUrl: string, timeoutMs: number = 3000): Promise<ServerStatusResponse> {
    const response = await this.api.getToBaseUrl(baseUrl, '/api/auth/isNasCabServer', timeoutMs);
    return AuthService.parseServerStatus(response);
  }

  private static parseServerStatus(response: APIResponse<Object>): ServerStatusResponse {
    const envelope = response.rawResponse;
    let isNasCab = envelope?.isNasCabOSServer === true;
    if (!isNasCab && response.data) {
      const statusData = JsonCodec.parse<ServerStatusJson>(response.data);
      isNasCab = statusData.isNasCabOSServer === true;
    }
    if (!response.success) {
      return new ServerStatusResponse(false, false, response.message);
    }
    return new ServerStatusResponse(true, isNasCab, response.message, response.data);
  }

  async loginToServer(serverInfo: ServerInfo): Promise<LoginResponse> {
    DeviceFingerprint.getOrCreateVideoPlayerDeviceId();
    const fingerprint = DeviceFingerprint.getDeviceFingerprintPayload();
    const body = new LoginRequestBody(
      serverInfo.username ?? '',
      AuthService.obfuscatePassword(serverInfo.password ?? ''),
      fingerprint
    );

    const apiResponse = await this.api.apiPost<LoginResponse>(
      '/api/auth/login',
      body,
      undefined,
      undefined,
      undefined,
      (d, code) => LoginResponse.fromJson(d, code)
    );

    if (!apiResponse.success || !apiResponse.data) {
      const fail = new LoginResponse();
      fail.success = false;
      fail.message = apiResponse.message ?? L10n.authLoginFailure;
      fail.code = apiResponse.code;
      return fail;
    }

    const data = apiResponse.data;
    if (data.twoFactorRequired === true) {
      data.success = true;
      return data;
    }

    if (data.user) {
      CurrentUserStore.getInstance().setUserFromJson(data.user);
    }
    if (data.apps) {
      CurrentUserStore.getInstance().setAppsFromJson(data.apps);
    }
    if (data.wallpaper) {
      CurrentUserStore.getInstance().setWallpaperFromJson(data.wallpaper);
    }

    data.success = true;
    return data;
  }

  async verifyTwoFactorLogin(tempToken: string, code: string): Promise<LoginResponse> {
    const fingerprint = DeviceFingerprint.getDeviceFingerprintPayload();
    const body = new TwofaVerifyBody(tempToken, code, fingerprint);
    const apiResponse = await this.api.apiPost<LoginResponse>(
      '/api/auth/2fa/login/verify',
      body,
      undefined,
      undefined,
      undefined,
      (d, c) => LoginResponse.fromJson(d, c)
    );
    if (!apiResponse.success || !apiResponse.data) {
      const fail = new LoginResponse();
      fail.success = false;
      fail.message = apiResponse.message ?? L10n.authLoginFailure;
      return fail;
    }
    const data = apiResponse.data;
    if (data.user) CurrentUserStore.getInstance().setUserFromJson(data.user);
    if (data.apps) CurrentUserStore.getInstance().setAppsFromJson(data.apps);
    if (data.wallpaper) CurrentUserStore.getInstance().setWallpaperFromJson(data.wallpaper);
    data.success = true;
    return data;
  }

  applyLoginSuccess(serverInfo: ServerInfo, login: LoginResponse): void {
    if (login.accessToken && login.refreshToken && login.serverId && login.expiresIn) {
      this.api.setAuthInfo(
        login.serverId,
        login.accessToken,
        login.refreshToken,
        login.expiresIn,
        login.shellSupported ?? false,
        login.serverVersion
      );
    }
    if (login.pairCode) {
      serverInfo.pairCode = login.pairCode;
    }
    if (login.hostname) {
      serverInfo.serverHostName = login.hostname;
    }
    if (login.customHostname) {
      serverInfo.customHostname = login.customHostname;
    }
    if (login.platform) {
      serverInfo.serverPlatform = login.platform;
    }
    serverInfo.serverId = login.serverId ?? serverInfo.serverId;
    serverInfo.accessToken = login.accessToken;
    serverInfo.refreshToken = login.refreshToken;
    serverInfo.lastLoginTime = Date.now();
  }

  async logout(): Promise<void> {
    const refreshToken = this.api.state.refreshToken;
    if (refreshToken) {
      const body = new LogoutBody(refreshToken);
      await this.api.apiPost<Object>('/api/auth/logout', body);
    }
    this.api.clearAuthInfo();
    CurrentUserStore.getInstance().clear();
    P2PService.getInstance().disconnect();
  }
}
