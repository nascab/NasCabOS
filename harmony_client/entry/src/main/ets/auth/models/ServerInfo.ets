import { JsonCodec, ServerInfoJson } from '../../common/JsonTypes';

export class ServerInfo {
  serverId: string = '';
  serverUrl: string = '';
  userInputUrl?: string;
  lanIpv4?: string;
  lanHttpPort?: string;
  lanHttpsPort?: string;
  serverName: string = '';
  serverHost: string = '';
  serverPortHttp: string = '';
  serverPortHttps: string = '';
  serverHostName: string = '';
  customHostname?: string;
  serverPlatform: string = '';
  isAutoScanned: boolean = false;
  isLocalServer: boolean = false;
  isP2p: boolean = false;
  pairCode?: string;
  username?: string;
  password?: string;
  requirePasswordEveryLogin: boolean = false;
  accessToken?: string;
  refreshToken?: string;
  lastLoginTime?: number;

  hasPairCode(): boolean {
    return (this.pairCode ?? '').trim().length > 0;
  }

  hasDirectUrl(): boolean {
    return this.serverUrl.trim().length > 0;
  }

  get displayHostName(): string {
    const c = (this.customHostname ?? '').trim();
    if (c.length > 0) {
      return c;
    }
    return this.serverHostName;
  }

  get uniqueKey(): string {
    const user = (this.username ?? '').trim();
    const sid = this.serverId.trim();
    if (sid.length > 0) {
      return `sid:${sid}|u:${user}`;
    }
    const code = (this.pairCode ?? '').trim();
    if (code.length > 0) {
      return `pair:${code}|u:${user}`;
    }
    const url = this.serverUrl.trim();
    if (url.length > 0) {
      return `url:${url}|u:${user}`;
    }
    const input = (this.userInputUrl ?? '').trim();
    if (input.length > 0) {
      return `input:${input}|u:${user}`;
    }
    return `empty|u:${user}`;
  }

  get platformFriendlyName(): string {
    switch (this.serverPlatform.toLowerCase()) {
      case 'linux':
        return 'Linux';
      case 'win32':
        return 'Windows';
      case 'darwin':
        return 'macOS';
      default:
        return this.serverPlatform;
    }
  }

  static merged(existing: ServerInfo, incoming: ServerInfo): ServerInfo {
    const pick = (a?: string, b?: string): string | undefined => {
      const v = (a ?? '').trim();
      return v.length > 0 ? a : b;
    };
    const pickRequired = (a: string, b: string): string => {
      return a.trim().length > 0 ? a : b;
    };

    const out = new ServerInfo();
    out.serverId = pickRequired(incoming.serverId, existing.serverId);
    out.serverUrl = pickRequired(incoming.serverUrl, existing.serverUrl);
    out.userInputUrl = pick(incoming.userInputUrl, existing.userInputUrl);
    out.lanIpv4 = pick(incoming.lanIpv4, existing.lanIpv4);
    out.lanHttpPort = pick(incoming.lanHttpPort, existing.lanHttpPort);
    out.lanHttpsPort = pick(incoming.lanHttpsPort, existing.lanHttpsPort);
    out.serverName = pickRequired(incoming.serverName, existing.serverName);
    out.serverHost = pickRequired(incoming.serverHost, existing.serverHost);
    out.serverPortHttp = pickRequired(incoming.serverPortHttp, existing.serverPortHttp);
    out.serverPortHttps = pickRequired(incoming.serverPortHttps, existing.serverPortHttps);
    out.serverHostName = pickRequired(incoming.serverHostName, existing.serverHostName);
    out.customHostname = pick(incoming.customHostname, existing.customHostname);
    out.serverPlatform = pickRequired(incoming.serverPlatform, existing.serverPlatform);
    out.isAutoScanned = existing.isAutoScanned && incoming.isAutoScanned;
    out.isLocalServer = existing.isLocalServer || incoming.isLocalServer;
    out.pairCode = pick(incoming.pairCode, existing.pairCode);
    out.username = pick(incoming.username, existing.username);
    out.password = pick(incoming.password, existing.password);
    out.requirePasswordEveryLogin = incoming.requirePasswordEveryLogin;
    out.accessToken = pick(incoming.accessToken, existing.accessToken);
    out.refreshToken = pick(incoming.refreshToken, existing.refreshToken);
    out.lastLoginTime = incoming.lastLoginTime ?? existing.lastLoginTime;
    out.isP2p = out.serverUrl.trim().length === 0 && (out.pairCode ?? '').trim().length > 0;
    return out;
  }

  static fromJson(obj: Object): ServerInfo {
    const m = JsonCodec.parse<ServerInfoJson>(obj);
    const s = new ServerInfo();
    s.serverId = m.serverId ?? '';
    s.serverUrl = m.serverUrl ?? '';
    s.userInputUrl = m.userInputUrl;
    s.lanIpv4 = m.lanIpv4;
    s.lanHttpPort = m.lanHttpPort;
    s.lanHttpsPort = m.lanHttpsPort;
    s.serverName = m.serverName ?? '';
    s.serverHost = m.serverHost ?? '';
    s.serverPortHttp = m.serverPortHttp ?? '';
    s.serverPortHttps = m.serverPortHttps ?? '';
    s.serverHostName = m.serverHostName ?? '';
    s.customHostname = m.customHostname;
    s.serverPlatform = m.serverPlatform ?? '';
    s.isAutoScanned = m.isAutoScanned === true;
    s.isLocalServer = m.isLocalServer === true;
    s.isP2p = m.isP2p === true;
    s.pairCode = m.pairCode;
    s.username = m.username;
    s.password = m.password;
    s.requirePasswordEveryLogin = m.requirePasswordEveryLogin === true || m.needInputPwdEveryTime === true;
    s.accessToken = m.accessToken;
    s.refreshToken = m.refreshToken;
    if (m.lastLoginTime !== undefined) {
      s.lastLoginTime = Number(m.lastLoginTime);
    }
    return s;
  }

  toJson(): ServerInfoJson {
    const obj = new ServerInfoJson();
    obj.serverId = this.serverId;
    obj.serverUrl = this.serverUrl;
    obj.serverName = this.serverName;
    obj.serverHost = this.serverHost;
    obj.serverPortHttp = this.serverPortHttp;
    obj.serverPortHttps = this.serverPortHttps;
    obj.serverHostName = this.serverHostName;
    obj.serverPlatform = this.serverPlatform;
    obj.isAutoScanned = this.isAutoScanned;
    obj.isLocalServer = this.isLocalServer;
    obj.isP2p = this.isP2p;
    obj.requirePasswordEveryLogin = this.requirePasswordEveryLogin;
    obj.userInputUrl = this.userInputUrl;
    obj.lanIpv4 = this.lanIpv4;
    obj.lanHttpPort = this.lanHttpPort;
    obj.lanHttpsPort = this.lanHttpsPort;
    obj.customHostname = this.customHostname;
    obj.pairCode = this.pairCode;
    obj.username = this.username;
    obj.password = this.password;
    obj.accessToken = this.accessToken;
    obj.refreshToken = this.refreshToken;
    obj.lastLoginTime = this.lastLoginTime;
    return obj;
  }
}
