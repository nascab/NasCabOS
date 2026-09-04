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

  static fromJson(raw: Object, httpCode: number): LoginResponse {
    const json = JsonCodec.parse<LoginDataJson>(raw);
    const r = new LoginResponse();
    r.code = httpCode;
    r.success = true;
    r.accessToken = json.accessToken;
    r.refreshToken = json.refreshToken;
    if (json.user) {
      r.user = JsonCodec.parse<UserJson>(json.user);
    }
    r.twoFactorRequired = json.twoFactorRequired === true;
    r.tempToken = json.tempToken;
    r.platform = json.platform;
    r.hostname = json.hostname;
    r.customHostname = json.customHostname;
    r.serverId = json.serverId;
    r.httpPort = `${json.httpPort ?? ''}`;
    r.httpsPort = `${json.httpsPort ?? ''}`;
    r.lanIpv4 = json.lanIpv4;
    r.pairCode = json.pairCode;
    r.expiresIn = json.expiresIn ?? 0;
    if (json.apps) {
      r.apps = JsonCodec.parse<AppsJson>(json.apps);
    }
    if (json.wallpaper) {
      r.wallpaper = JsonCodec.parse<WallpaperJson>(json.wallpaper);
    }
    r.shellSupported = json.shellSupported === true;
    r.serverVersion = json.serverVersion;
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
