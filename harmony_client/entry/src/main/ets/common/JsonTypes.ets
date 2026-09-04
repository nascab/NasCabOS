import { HeaderMap } from './HeaderMap';

/** API 响应外层结构 */
export class ApiEnvelope {
  success?: boolean;
  code?: number | string;
  message?: string;
  data?: Object;
  isNasCabOSServer?: boolean;
}

export class LoginDataJson {
  accessToken?: string;
  refreshToken?: string;
  user?: Object;
  twoFactorRequired?: boolean;
  tempToken?: string;
  platform?: string;
  hostname?: string;
  customHostname?: string;
  serverId?: string;
  httpPort?: string | number;
  httpsPort?: string | number;
  lanIpv4?: string;
  pairCode?: string;
  expiresIn?: number;
  apps?: Object;
  wallpaper?: Object;
  shellSupported?: boolean;
  serverVersion?: string;
}

export class UserJson {
  id?: number;
  username?: string;
  role?: string;
  isAdmin?: boolean;
}

export class AppsJson {
  all_app?: string[];
  hide_app?: string[];
}

export class WallpaperJson {
  url?: string;
}

export class HomeConfigJson {
  message?: string;
}

export class P2pSessionJson {
  wsUrl?: string;
  sessionId?: string;
}

export class UdpDiscoveryJson {
  service?: string;
  host?: string;
  port?: string | number;
  httpPort?: string | number;
  httpsPort?: string | number;
  name?: string;
  hostname?: string;
  platform?: string;
  serverId?: string;
}

export class SignalingDecoded {
  type?: string;
  ts?: number;
  sessionId?: string;
  reason?: string;
  code?: string;
  iceServers?: Object[];
  offer?: SdpJson;
  answer?: SdpJson;
  candidate?: IceCandidateJson;
}

export class SdpJson {
  type?: string;
  sdp?: string;
}

export class IceCandidateJson {
  candidate: string = '';
  sdpMid: string = '';
  sdpMLineIndex: number = 0;
}

export class DeviceFingerprintJson {
  user_agent: string = '';
  platform: string = '';
  os_version: string = '';
  device_model: string = '';
  device_name: string = '';
  language: string = '';
  timezone_offset: number = 0;
  timezone_name: string = '';
  storage_id: string = '';
  storage_type: string = '';
}

export class ServerStatusJson {
  isNasCabOSServer?: boolean;
  hasSuperAdmin?: boolean;
  serverId?: string;
  hostname?: string;
  platform?: string;
  httpPort?: string | number;
  httpsPort?: string | number;
}

export class RecoverInfoJson {
  question?: string;
  username?: string;
}

export class ServerInfoJson {
  serverId?: string;
  serverUrl?: string;
  userInputUrl?: string;
  lanIpv4?: string;
  lanHttpPort?: string;
  lanHttpsPort?: string;
  serverName?: string;
  serverHost?: string;
  serverPortHttp?: string;
  serverPortHttps?: string;
  serverHostName?: string;
  customHostname?: string;
  serverPlatform?: string;
  isAutoScanned?: boolean;
  isLocalServer?: boolean;
  isP2p?: boolean;
  pairCode?: string;
  username?: string;
  password?: string;
  requirePasswordEveryLogin?: boolean;
  needInputPwdEveryTime?: boolean;
  accessToken?: string;
  refreshToken?: string;
  lastLoginTime?: number;
}

export class P2pControlPayload {
  ts: number = 0;
  id: string = '';
  method: string = '';
  path: string = '';
  length: number = 0;
  headers: HeaderMap = new HeaderMap();
}

export class TransportStats {
  type: string = 'relay';
}

export class JsonCodec {
  static parse<T>(obj: Object): T {
    return JSON.parse(JSON.stringify(obj)) as T;
  }

  static parseStr<T>(text: string): T {
    return JSON.parse(text) as T;
  }
}
