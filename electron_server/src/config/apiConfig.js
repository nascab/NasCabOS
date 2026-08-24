const os = require('os');
const dns = require('dns');
const axios = require('axios');
const nodeEnv = String(process.env.NODE_ENV || '').trim().toLowerCase();
const isDev = nodeEnv === 'development';

/**
 * 强制所有请求走 IPv4。
 *
 * Node.js 17+ 中 dns.lookup 默认 `verbatim` 为 `true`，DNS 返回的 A / AAAA
 * 记录会按 getaddrinfo 返回的顺序尝试，部分用户家宽"有 IPv6 但实际不通"会
 * 导致连接卡死到超时。设置 family=4 强制所有 TCP 连接只解析 IPv4 地址。
 */
axios.defaults.family = 4;

// 用自定义 lookup 加日志确认实际走的 IP 版本
const origLookup = dns.lookup;
axios.defaults.lookup = function (hostname, options, callback) {
  const start = Date.now();
  return origLookup(hostname, { ...options, family: 4 }, (err, address, family) => {
    const ms = Date.now() - start;
    if (err) {
      console.log(`[ipv4] DNS FAILED: ${hostname} (${ms}ms)`, err.message);
    } else {
      console.log(`[ipv4] DNS resolved: ${hostname} → ${address} (family=${family}, ${ms}ms)`);
    }
    callback(err, address, family);
  });
};
// const testServer = "https://test.nas.cab"
// const ddnsTestIpv4Server = "https://testipv4.nas.cab"
// const ddnsTestIpv6Server = "https://testipv6.nas.cab"
const testServer = "https://nas.cab"
const productServer = "https://nas.cab"
const p2pServer = "https://p2p.nas.cab"
const ddnsIpv4Server = "https://ipv4.nas.cab"
const ddnsIpv6Server = "https://ipv6.nas.cab"
const ddnsTestIpv4Server = "https://ipv4.nas.cab"
const ddnsTestIpv6Server = "https://ipv6.nas.cab"
const apiBaseUrl = String(process.env.NASCAB_REMOTE_API_BASE_URL || (isDev ? testServer : productServer)).trim();
console.log("apiBaseUrl",apiBaseUrl)
// P2P 专用域名，仅解析到提供 COTURN 服务的节点
// 所有会写入 p2p:pair:node 的接口必须走此域名，防止非 COTURN 节点覆盖正确的 wsUrl
const P2P = String(process.env.NASCAB_REMOTE_P2P_BASE_URL || (isDev ? apiBaseUrl : p2pServer)).trim();
console.log("P2P url",P2P)
const DDNS_IPV4 = String(process.env.NASCAB_REMOTE_DDNS_IPV4_BASE_URL || (isDev ? ddnsTestIpv4Server : ddnsIpv4Server)).trim();
const DDNS_IPV6 = String(process.env.NASCAB_REMOTE_DDNS_IPV6_BASE_URL || (isDev ? ddnsTestIpv6Server : ddnsIpv6Server)).trim();
const config = {
  apiBaseUrl,
  apiP2pBaseUrl: P2P,
  apiDdnsIpv4BaseUrl: DDNS_IPV4,
  apiDdnsIpv6BaseUrl: DDNS_IPV6,
  //使用jwt登录并获取用户信息
  apiAuthJwtRefreshPath: `${apiBaseUrl}/api/auth/jwt/refresh`,
  apiAuthTokenRefreshPath: `${apiBaseUrl}/api/auth/token/refresh`,
  apiP2pServersListPath: `${apiBaseUrl}/api/p2p_servers`,
  apiP2pDeviceRegisterPath: `${P2P}/api/p2p/device/register`,
  apiP2pDeviceBindPath: `${P2P}/api/p2p/device/bind`,
  apiP2pDeviceSecretRotatePath: `${P2P}/api/p2p/device/secret/rotate`,
  apiP2pDevicePairCodeResetPath: `${P2P}/api/p2p/device/pairCode/reset`,
  apiP2pDevicePairCodeCustomPath: `${P2P}/api/p2p/device/pairCode/custom`,
  apiP2pDeviceLoginPath: `${P2P}/api/p2p/device/login`,
  apiP2pDeviceTokenRefreshPath: `${P2P}/api/p2p/device/token/refresh`,
  apiP2pDeviceHeartbeatPath: `${P2P}/api/p2p/device/heartbeat`,
  apiP2pDevicesListPath: `${P2P}/api/p2p/devices`,
  apiP2pSessionCreatePath: `${P2P}/api/p2p/session/create`,
  apiDdnsIpPath: `${P2P}/api/ddns/ip`,
  apiDdnsStatusPath: `${P2P}/api/ddns/status`,
  apiDdnsDomainPath: `${P2P}/api/ddns/domain`,
  apiDdnsTypePath: `${P2P}/api/ddns/type`,
  apiDdnsUpdatePath: `${P2P}/api/ddns/update`,
  apiDdnsClearPath: `${P2P}/api/ddns/clear`,
  /** 远端歌词搜索 */
  apiMusicLyricSearchPath: `${apiBaseUrl}/api/music/lyric/search`,
  /** 获取远端应用默认配置（tmdbConfig + tileServer） */
  apiRemoteDefaultConfigPath: `${apiBaseUrl}/api/config/default`,
  /** 获取临时授权 code（10 分钟过期，一次性） */
  apiAuthCodeGeneratePath: `${apiBaseUrl}/api/auth/code/generate`,
  /** 用临时 code 换取 accessToken */
  apiAuthCodeExchangePath: `${apiBaseUrl}/api/auth/code/exchange`,
};
module.exports = config;
