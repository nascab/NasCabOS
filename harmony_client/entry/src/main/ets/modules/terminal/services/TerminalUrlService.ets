import { APIClient } from '../../../core/network/APIClient';
import { ApiUrls } from '../../../core/network/ApiUrls';
import { CurrentUserStore } from '../../../core/user/CurrentUserStore';
import { ServerStorageService } from '../../../core/storage/ServerStorageService';
import { ServerInfo } from '../../../auth/models/ServerInfo';

/**
 * 终端 WebSocket 连接地址构建（对齐 Flutter getTerminalConnectUrl 非 Web 分支）：
 * - 参数优先走 AES 加密（?aes=），失败回退明文 query
 * - 登录信息带 https 端口时用 wss + 该端口，否则按 baseUrl 协议推导（https→wss / http→ws）
 * - WS 鉴权：accessToken 放入加密参数（或明文 query），与 Flutter/服务端约定一致
 */

class ParsedBase {
  scheme: string = 'https';
  host: string = '';
  port: string = '';
}

function parseBaseUrl(raw: string): ParsedBase | undefined {
  const m = raw.match(/^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]+)/);
  if (!m) {
    return undefined;
  }
  const authority = m[2];
  const atIdx = authority.lastIndexOf('@');
  const hostPort = atIdx >= 0 ? authority.substring(atIdx + 1) : authority;
  const parsed = new ParsedBase();
  parsed.scheme = m[1].toLowerCase();
  if (hostPort.startsWith('[')) {
    // IPv6 形如 [::1]:9000
    const end = hostPort.indexOf(']');
    if (end < 0) {
      return undefined;
    }
    parsed.host = hostPort.substring(0, end + 1);
    const rest = hostPort.substring(end + 1);
    parsed.port = rest.startsWith(':') ? rest.substring(1) : '';
  } else {
    const colon = hostPort.lastIndexOf(':');
    if (colon >= 0) {
      parsed.host = hostPort.substring(0, colon);
      parsed.port = hostPort.substring(colon + 1);
    } else {
      parsed.host = hostPort;
    }
  }
  if (parsed.host.length === 0) {
    return undefined;
  }
  return parsed;
}

/**
 * 当前登录服务器信息（对齐 HomeViewModel.loadServerInfo 匹配优先级）：
 * serverId+用户名 > serverId > baseUrl+用户名 > baseUrl。
 */
export function resolveCurrentServer(): ServerInfo | undefined {
  const api = APIClient.getInstance();
  const sid = api.state.serverId.trim();
  const baseUrl = api.state.baseUrl.trim();
  const username = (CurrentUserStore.getInstance().current?.username ?? '').trim();
  const servers = ServerStorageService.getInstance().loadServers();
  let server: ServerInfo | undefined = undefined;
  if (sid.length > 0) {
    if (username.length > 0) {
      server = servers.find((s: ServerInfo): boolean =>
        s.serverId === sid && (s.username ?? '').trim() === username);
    } else {
      server = servers.find((s: ServerInfo): boolean => s.serverId === sid);
    }
  }
  if (server === undefined) {
    if (username.length > 0) {
      server = servers.find((s: ServerInfo): boolean =>
        s.serverUrl.trim() === baseUrl && (s.username ?? '').trim() === username);
    } else {
      server = servers.find((s: ServerInfo): boolean => s.serverUrl.trim() === baseUrl);
    }
  }
  return server;
}

/** 服务器是否为 Windows（对齐 Flutter serverPlatform == 'win32'，仅 win32 显示 shell 切换） */
export function isServerWin32(): boolean {
  return (resolveCurrentServer()?.serverPlatform ?? '').trim().toLowerCase() === 'win32';
}

/** 连接参数（对齐 Flutter getTerminalConnectUrl 入参） */
export class TerminalConnectOptions {
  cols: number = 100;
  rows: number = 30;
  /** 仅 win32 生效：'powershell' | 'cmd' */
  shell: string = '';
  clientDeviceId: string = '';
  terminalConnId: string = '';
  forceNew: boolean = false;
}

/** 构建终端 WS 连接地址（异步：AES 参数加密）。baseUrl 或 token 未设置时可能返回 ''。 */
export async function buildTerminalConnectUrl(opts: TerminalConnectOptions): Promise<string> {
  const api = APIClient.getInstance();
  const base = api.state.baseUrl.trim();
  if (base.length === 0) {
    return '';
  }
  const token = api.state.accessToken ?? '';
  const cols = Math.min(Math.max(opts.cols, 20), 400);
  const rows = Math.min(Math.max(opts.rows, 5), 200);

  const params = new Map<string, string>();
  params.set('cols', `${cols}`);
  params.set('rows', `${rows}`);
  if (token.length > 0) {
    params.set('accessToken', token);
  }
  if (opts.shell.trim().length > 0) {
    params.set('shell', opts.shell.trim());
  }
  if (opts.clientDeviceId.trim().length > 0) {
    params.set('clientDeviceId', opts.clientDeviceId.trim());
  }
  if (opts.terminalConnId.trim().length > 0) {
    params.set('terminalConnId', opts.terminalConnId.trim());
  }
  if (opts.forceNew) {
    params.set('forceNew', '1');
  }

  const parsed = parseBaseUrl(base);
  if (parsed === undefined) {
    return '';
  }
  let wsBase = '';
  const httpsPort = (resolveCurrentServer()?.serverPortHttps ?? '').trim();
  if (httpsPort.length > 0) {
    const p = parseInt(httpsPort);
    wsBase = `wss://${parsed.host}:${Number.isNaN(p) ? 443 : p}`;
  } else {
    const useTls = parsed.scheme === 'https';
    const scheme = useTls ? 'wss' : 'ws';
    const port = parsed.port.length > 0 ? parsed.port : (useTls ? '443' : '80');
    wsBase = `${scheme}://${parsed.host}:${port}`;
  }

  const aes = await ApiUrls.encryptParams(params);
  if (aes.length > 0) {
    return `${wsBase}/api/terminal/connect?aes=${encodeURIComponent(aes)}`;
  }
  const qp: string[] = [];
  params.forEach((v: string, k: string): void => {
    qp.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
  });
  return `${wsBase}/api/terminal/connect?${qp.join('&')}`;
}

/**
 * WS 协议降级地址（对齐 Flutter _buildWsSchemeFallbackUrl）：
 * TLS 握手异常时按 baseUrl 协议直连 /api/terminal/connect，明文 query（不带 aes/shell）。
 */
export function buildTerminalFallbackUrl(clientDeviceId: string, terminalConnId: string): string {
  const base = APIClient.getInstance().state.baseUrl.trim();
  if (base.length === 0) {
    return '';
  }
  const parsed = parseBaseUrl(base);
  if (parsed === undefined) {
    return '';
  }
  const token = APIClient.getInstance().state.accessToken ?? '';
  const scheme = parsed.scheme === 'https' ? 'wss' : 'ws';
  const port = parsed.port.length > 0 ? parsed.port : (scheme === 'wss' ? '443' : '80');
  let url = `${scheme}://${parsed.host}:${port}/api/terminal/connect?cols=100&rows=30`;
  if (token.length > 0) {
    url += `&accessToken=${encodeURIComponent(token)}`;
  }
  if (clientDeviceId.length > 0) {
    url += `&clientDeviceId=${encodeURIComponent(clientDeviceId)}`;
  }
  if (terminalConnId.length > 0) {
    url += `&terminalConnId=${encodeURIComponent(terminalConnId)}`;
  }
  return url;
}
