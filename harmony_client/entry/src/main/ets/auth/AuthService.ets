import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { APIClient } from '../core/network/APIClient';
import { APIResponse } from '../core/network/APIResponse';
import { L10n } from '../core/localization/L10n';
import { NetworkConfig } from '../core/network/NetworkConfig';
import { DeviceFingerprint } from '../core/device/DeviceFingerprint';
import { CurrentUserStore } from '../core/user/CurrentUserStore';
import { ServerInfo } from './models/ServerInfo';
import { LoginResponse, RecoverInfoResponse, ServerStatusResponse } from './models/LoginResponse';
import { ApiEnvelope, JsonCodec, RecoverInfoJson, ServerStatusJson } from '../common/JsonTypes';
import { P2PService } from '../p2p/P2PService';
import { LogoutBody, RefreshTokenBody } from '../common/HttpTypes';

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

export class TwofaSetupBody {
  issuer?: string;
  accountName?: string;

  constructor(issuer?: string, accountName?: string) {
    this.issuer = issuer;
    this.accountName = accountName;
  }
}

export class TwofaEnableBody {
  code: string = '';
  secret?: string;

  constructor(code: string, secret?: string) {
    this.code = code;
    this.secret = secret;
  }
}

export class TwofaCodeBody {
  code: string = '';

  constructor(code: string) {
    this.code = code;
  }
}

export class CreateSuperAdminBody {
  username: string = '';
  password: string = '';
  question: string = '';
  answer: string = '';

  constructor(username: string, password: string, question: string, answer: string) {
    this.username = username;
    this.password = password;
    this.question = question;
    this.answer = answer;
  }
}

export class RecoverPasswordBody {
  username: string = '';
  answer: string = '';
  newPassword: string = '';

  constructor(username: string, answer: string, newPassword: string) {
    this.username = username;
    this.answer = answer;
    this.newPassword = newPassword;
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

  /// 对密保答案进行SHA256加密
  static async encryptPassword(password: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    const bytes = new util.TextEncoder().encodeInto(password);
    await md.update({ data: bytes });
    const digest = await md.digest();
    let hex = '';
    const data = digest.data;
    for (let i = 0; i < data.length; i++) {
      const b = data[i];
      hex += (b < 16 ? '0' : '') + b.toString(16);
    }
    return hex;
  }

  /** 读取响应外层 code（如密码错误 999） */
  private static envelopeCode(response: APIResponse<Object>): string {
    const raw = response.rawResponse?.code;
    if (raw === undefined || raw === null) {
      return '';
    }
    return `${raw}`;
  }

  async getLoginConfig(): Promise<APIResponse<Object>> {
    return this.api.apiGet<Object>('/api/apiSetting/loginConfig');
  }

  async getTwofaStatus(): Promise<APIResponse<Object>> {
    return this.api.apiGet<Object>('/api/auth/2fa/status');
  }

  async setupTwofa(issuer?: string, accountName?: string): Promise<APIResponse<Object>> {
    const body = new TwofaSetupBody(issuer, accountName);
    return this.api.apiPost<Object>('/api/auth/2fa/setup', body);
  }

  async enableTwofa(code: string, secret?: string): Promise<APIResponse<Object>> {
    const body = new TwofaEnableBody(code, secret);
    return this.api.apiPost<Object>('/api/auth/2fa/enable', body);
  }

  async disableTwofa(code: string): Promise<APIResponse<Object>> {
    const body = new TwofaCodeBody(code);
    return this.api.apiPost<Object>('/api/auth/2fa/disable', body);
  }

  async rotateTwofaBackupCodes(code: string): Promise<APIResponse<Object>> {
    const body = new TwofaCodeBody(code);
    return this.api.apiPost<Object>('/api/auth/2fa/backup/rotate', body);
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
      if (AuthService.envelopeCode(apiResponse) === '999') {
        // 密码错误
        fail.code = 999;
      }
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

  async refreshTokenApi(refreshToken: string): Promise<LoginResponse> {
    const body = new RefreshTokenBody(refreshToken);
    const apiResponse = await this.api.apiPost<LoginResponse>(
      '/api/auth/refreshJwt',
      body,
      undefined,
      NetworkConfig.DEFAULT_TIMEOUT_MS,
      0,
      (d, code) => LoginResponse.fromJson(d, code)
    );
    if (!apiResponse.success || !apiResponse.data) {
      const fail = new LoginResponse();
      fail.success = false;
      fail.message = apiResponse.message ?? L10n.authTokenRefreshFailure;
      return fail;
    }
    return apiResponse.data;
  }

  /// 创建超级管理员
  async createSuperAdmin(
    username: string,
    password: string,
    securityQuestion: string,
    securityAnswer: string
  ): Promise<LoginResponse> {
    const answer = await AuthService.encryptPassword(securityAnswer);
    const body = new CreateSuperAdminBody(
      username,
      AuthService.obfuscatePassword(password),
      securityQuestion,
      answer
    );
    const apiResponse = await this.api.apiPost<LoginResponse>(
      '/api/auth/createSuperAdmin',
      body,
      undefined,
      undefined,
      undefined,
      (d, code) => LoginResponse.fromJson(d, code)
    );
    if (!apiResponse.success || !apiResponse.data) {
      const fail = new LoginResponse();
      fail.success = false;
      fail.message = apiResponse.message ?? L10n.adminCreateFailure;
      return fail;
    }
    return apiResponse.data;
  }

  /// 找回管理员密码
  async recoverAdminPassword(username: string, answer: string, newPassword: string): Promise<LoginResponse> {
    const body = new RecoverPasswordBody(
      username,
      await AuthService.encryptPassword(answer),
      AuthService.obfuscatePassword(newPassword)
    );
    const apiResponse = await this.api.apiPost<LoginResponse>(
      '/api/auth/recoverPassword',
      body,
      undefined,
      undefined,
      undefined,
      (d, code) => LoginResponse.fromJson(d, code)
    );
    if (!apiResponse.success || !apiResponse.data) {
      const fail = new LoginResponse();
      fail.success = false;
      fail.message = apiResponse.message ?? L10n.recoverFailure;
      return fail;
    }
    return apiResponse.data;
  }

  /// 获取找回密码信息（按用户名）
  async getRecoverInfo(username: string): Promise<RecoverInfoResponse> {
    const params = new Map<string, string>();
    params.set('username', username);
    const apiResponse = await this.api.apiGet<Object>(
      '/api/auth/recoverInfo',
      params,
      10000,
      2,
      (d, _) => d
    );
    if (!apiResponse.success || !apiResponse.data) {
      return RecoverInfoResponse.failure(apiResponse.message ?? L10n.authRecoverInfoFailure);
    }
    const data = JsonCodec.parse<RecoverInfoJson>(apiResponse.data);
    return RecoverInfoResponse.success(data.question, data.username);
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
