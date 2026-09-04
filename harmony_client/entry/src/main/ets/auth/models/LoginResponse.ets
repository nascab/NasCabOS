import { AppsJson, JsonCodec, LoginDataJson, UserJson, WallpaperJson } from '../../common/JsonTypes';

export class LoginResponse {
  success: boolean = false;
  message?: string;
  accessToken?: string;
  refreshToken?: string;
  user?: UserJson;
  twoFactorRequired?: boolean;
  tempToken?: string;
  platform?: string;
  hostname?: string;
  customHostname?: string;
  serverId?: string;
  httpPort?: string;
  httpsPort?: string;
  lanIpv4?: string;
  pairCode?: string;
  expiresIn?: number;
  code?: number;
  apps?: AppsJson;
  wallpaper?: WallpaperJson;
  shellSupported?: boolean;
  serverVersion?: string;

  /** 服务端 JSON 字段类型不稳定（数字/字符串/null 混合），对齐 Flutter fromJson 做归一化（null/undefined 归为 undefined） */
  private static toStr(v: string | number | boolean | null | undefined): string | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    return `${v}`;
  }

  static fromJson(raw: Object, httpCode: number): LoginResponse {
    const json = JsonCodec.parse<LoginDataJson>(raw);
    const r = new LoginResponse();
    r.code = httpCode;
    r.success = true;
    r.accessToken = LoginResponse.toStr(json.accessToken);
    r.refreshToken = LoginResponse.toStr(json.refreshToken);
    if (json.user) {
      r.user = JsonCodec.parse<UserJson>(json.user);
    }
    r.twoFactorRequired = json.twoFactorRequired === true;
    r.tempToken = LoginResponse.toStr(json.tempToken);
    r.platform = LoginResponse.toStr(json.platform);
    r.hostname = LoginResponse.toStr(json.hostname);
    r.customHostname = LoginResponse.toStr(json.customHostname);
    r.serverId = LoginResponse.toStr(json.serverId);
    r.httpPort = `${json.httpPort ?? ''}`;
    r.httpsPort = `${json.httpsPort ?? ''}`;
    r.lanIpv4 = LoginResponse.toStr(json.lanIpv4);
    r.pairCode = LoginResponse.toStr(json.pairCode);
    r.expiresIn = json.expiresIn ?? 0;
    if (json.apps) {
      r.apps = JsonCodec.parse<AppsJson>(json.apps);
    }
    if (json.wallpaper) {
      r.wallpaper = JsonCodec.parse<WallpaperJson>(json.wallpaper);
    }
    const shell = json.shellSupported;
    r.shellSupported = shell === true || shell === 1 || shell === '1';
    r.serverVersion = LoginResponse.toStr(json.serverVersion);
    return r;
  }
}

export class ServerStatusResponse {
  success: boolean;
  message?: string;
  isNasCabServer: boolean;
  serverData?: Object;

  constructor(success: boolean, isNasCabServer: boolean, message?: string, serverData?: Object) {
    this.success = success;
    this.isNasCabServer = isNasCabServer;
    this.message = message;
    this.serverData = serverData;
  }
}

export class RecoverInfoResponse {
  success: boolean = false;
  message?: string;
  question?: string;
  username?: string;

  static success(question?: string, username?: string): RecoverInfoResponse {
    const r = new RecoverInfoResponse();
    r.success = true;
    r.question = question;
    r.username = username;
    return r;
  }

  static failure(message?: string): RecoverInfoResponse {
    const r = new RecoverInfoResponse();
    r.success = false;
    r.message = message;
    return r;
  }
}
