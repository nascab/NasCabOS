const net = require('net');

const P2P_SERVERS_CACHE_TTL_MS = 5 * 60 * 1000;
const probeCache = new Map();

function normalizeNodeDomain(domain) {
  const raw = domain == null ? '' : String(domain).trim().toLowerCase();
  if (!raw) return '';
  return raw.replace(/^https?:\/\//, '').replace(/^wss?:\/\//, '').replace(/\/.*$/, '').trim();
}

function extractUrlHostname(rawUrl) {
  try {
    const url = new URL(String(rawUrl || ''));
    return url.hostname ? String(url.hostname).trim().toLowerCase() : '';
  } catch (_) {
    return '';
  }
}

function replaceUrlHost(rawUrl, nextHost) {
  const normalized = normalizeNodeDomain(nextHost);
  if (!normalized) return String(rawUrl || '');
  try {
    const url = new URL(String(rawUrl || ''));
    url.hostname = normalized;
    return url.toString();
  } catch (_) {
    return String(rawUrl || '');
  }
}

function parseP2pServers(raw) {
  if (!raw) return [];
  let parsed = raw;
  if (typeof raw === 'string') {
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      return [];
    }
  }
  if (!Array.isArray(parsed)) return [];
  return parsed
    .map(item => {
      if (!item || typeof item !== 'object') return null;
      const domain = normalizeNodeDomain(item.domain);
      if (!domain) return null;
      return {
        chinese_name: item.chinese_name == null ? '' : String(item.chinese_name).trim(),
        english_name: item.english_name == null ? '' : String(item.english_name).trim(),
        name: item.name == null ? '' : String(item.name).trim(),
        host: item.host == null ? '' : String(item.host).trim(),
        domain,
      };
    })
    .filter(Boolean);
}

function serializeP2pServers(list) {
  return JSON.stringify(parseP2pServers(list));
}

function probeHostReachable(host, { port = 443, timeoutMs = 1500, cacheMs = 30 * 1000 } = {}) {
  const normalized = normalizeNodeDomain(host);
  if (!normalized) return Promise.resolve(false);
  const now = Date.now();
  const cached = probeCache.get(`${normalized}:${port}`);
  if (cached && now - cached.at < cacheMs) {
    return Promise.resolve(!!cached.ok);
  }
  return new Promise(resolve => {
    let settled = false;
    const socket = net.connect({ host: normalized, port });
    const done = ok => {
      if (settled) return;
      settled = true;
      probeCache.set(`${normalized}:${port}`, { ok: !!ok, at: Date.now() });
      try {
        socket.destroy();
      } catch (_) {}
      resolve(!!ok);
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
  });
}

async function pickReachablePreferredDomain(domain) {
  const normalized = normalizeNodeDomain(domain);
  if (!normalized) return '';
  const ok = await probeHostReachable(normalized);
  return ok ? normalized : '';
}

module.exports = {
  P2P_SERVERS_CACHE_TTL_MS,
  normalizeNodeDomain,
  extractUrlHostname,
  replaceUrlHost,
  parseP2pServers,
  serializeP2pServers,
  probeHostReachable,
  pickReachablePreferredDomain,
};
