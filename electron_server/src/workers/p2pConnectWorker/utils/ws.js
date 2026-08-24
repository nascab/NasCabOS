const apiConfig = require('../../../config/apiConfig');

function pickWebSocketImpl() {
  try {
    const mod = require('ws');
    if (mod && typeof mod === 'function') return mod;
    if (mod && typeof mod.WebSocket === 'function') return mod.WebSocket;
  } catch (_) {}
  if (typeof WebSocket === 'function') return WebSocket;
  return null;
}

function getExpectedP2pWsUrl() {
  const sample = apiConfig.apiP2pDeviceRegisterPath || apiConfig.apiP2pDeviceLoginPath || apiConfig.apiP2pDeviceHeartbeatPath || '';
  if (!sample) return '';
  try {
    const u = new URL(sample);
    u.protocol = u.protocol === 'https:' ? 'wss:' : 'ws:';
    u.pathname = '/ws/p2p';
    u.search = '';
    u.hash = '';
    return u.toString();
  } catch (_) {
    return '';
  }
}

function normalizeP2pWsUrl(wsUrl) {
  const expected = getExpectedP2pWsUrl();
  const raw = wsUrl == null ? '' : String(wsUrl).trim();
  if (!expected) return raw;
  if (!raw) return expected;
  try {
    const a = new URL(raw);
    const b = new URL(expected);
    a.protocol = b.protocol;
    a.username = '';
    a.password = '';
    a.host = b.host;
    a.pathname = b.pathname;
    a.search = '';
    a.hash = '';
    return a.toString();
  } catch (_) {
    return expected;
  }
}

module.exports = { pickWebSocketImpl, normalizeP2pWsUrl };
