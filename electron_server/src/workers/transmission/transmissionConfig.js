const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const config = require('../../config/config');
const tableConfig = require('../../db/table/tableConfig');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const jwtUtil = require('../../utils/jwtUtil');
const axios = require('axios');
const Logger = require('../../utils/logger');

const DEFAULT_RPC_USERNAME = 'nascab';

async function ensureMainDbReady() {
  const dbPath = dbUtil.DB_PATHS.MAIN_DB;
  if (!knexUtil.hasConnection(dbPath)) {
    await knexUtil.init(dbPath);
  }
}

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function toPortNumber(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  if (i < 1 || i > 65535) return null;
  return i;
}

function toBool(v, defaultValue = false) {
  if (v === undefined || v === null || v === '') return defaultValue;
  if (typeof v === 'boolean') return v;
  const s = String(v).trim().toLowerCase();
  if (s === '1' || s === 'true' || s === 'yes' || s === 'on') return true;
  if (s === '0' || s === 'false' || s === 'no' || s === 'off') return false;
  return defaultValue;
}

function toInt(v, defaultValue = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return defaultValue;
  return Math.trunc(n);
}

function getConfigDir() {
  return path.join(config.getUserDataPath(), 'transmission');
}

function getDaemonFallbackDownloadDir() {
  return path.join(getConfigDir(), '_daemon_fallback');
}

function normalizeDefaultTrackers(raw) {
  if (raw === undefined || raw === null) return '';
  if (Array.isArray(raw)) {
    return raw.map(v => ensureString(v).trim()).filter(Boolean).join('\n');
  }
  return ensureString(raw)
    .split(/\r?\n/)
    .map(v => v.trim())
    .filter(Boolean)
    .join('\n');
}

function parseTrackerList(raw) {
  if (raw === undefined || raw === null) return [];
  if (Array.isArray(raw)) {
    return raw.map(v => ensureString(v).trim()).filter(Boolean);
  }
  return ensureString(raw)
    .split(/\r?\n/)
    .map(v => v.trim())
    .filter(Boolean);
}

function getDefaultConfig() {
  const defaults = (config && config.transmission) || {};
  return {
    enabled: false,
    status: 'stopped',
    rpc_port: toPortNumber(defaults.defaultRpcPort) || 52019,
    actual_rpc_port: null,
    peer_port: toPortNumber(defaults.defaultPeerPort) || 37291,
    peer_limit_global: Math.max(0, toInt(defaults.defaultPeerLimitGlobal, 200)),
    peer_limit_per_torrent: Math.max(0, toInt(defaults.defaultPeerLimitPerTorrent, 50)),
    default_trackers: '',
    default_trackers_resolved: '',
    trackers_last_fetched_at: null,
    tracker_url_fetch_timeout_ms: 10000,
    speed_limit_down: 0,
    speed_limit_up: 0,
    port_forwarding: true,
    dht_enabled: false,
    pex_enabled: true,
    utp_enabled: true,
    encryption: 1,
    ratio_limit: 2,
    ratio_limit_enabled: false,
    idle_seeding_limit: 30,
    idle_seeding_limit_enabled: false,
    auto_start: false,
    rpc_username: DEFAULT_RPC_USERNAME,
    rpc_password: '',
    last_error: null,
    started_at: null,
  };
}

function decryptRpcPassword(stored) {
  const text = ensureString(stored).trim();
  if (!text) return '';
  if (jwtUtil.isEncryptedPassword(text)) {
    return jwtUtil.decryptPassword(text) || '';
  }
  return text;
}

function encryptRpcPassword(plain) {
  const raw = ensureString(plain).trim();
  if (!raw) return '';
  if (jwtUtil.isEncryptedPassword(raw)) return raw;
  return jwtUtil.encryptPassword(raw);
}

function getRpcUsername(cfg) {
  return ensureString(cfg && cfg.rpc_username).trim() || DEFAULT_RPC_USERNAME;
}

function ensureRpcCredentials(cfg) {
  const next = { ...cfg };
  if (!ensureString(next.rpc_username).trim()) {
    next.rpc_username = DEFAULT_RPC_USERNAME;
  }
  if (!ensureString(next.rpc_password).trim()) {
    next.rpc_password = crypto.randomBytes(16).toString('hex');
  }
  return next;
}

function normalizeConfig(raw) {
  const base = getDefaultConfig();
  const src = raw && typeof raw === 'object' ? raw : {};
  return {
    ...base,
    enabled: toBool(src.enabled, base.enabled),
    status: ensureString(src.status || base.status) || 'stopped',
    rpc_port: toPortNumber(src.rpc_port) || base.rpc_port,
    actual_rpc_port: toPortNumber(src.actual_rpc_port),
    peer_port: toPortNumber(src.peer_port) || base.peer_port,
    peer_limit_global: Math.max(0, toInt(src.peer_limit_global, base.peer_limit_global)),
    peer_limit_per_torrent: Math.max(0, toInt(src.peer_limit_per_torrent, base.peer_limit_per_torrent)),
    default_trackers: normalizeDefaultTrackers(
      src.default_trackers !== undefined ? src.default_trackers : base.default_trackers
    ),
    default_trackers_resolved: normalizeDefaultTrackers(
      src.default_trackers_resolved !== undefined ? src.default_trackers_resolved : base.default_trackers_resolved
    ),
    trackers_last_fetched_at:
      src.trackers_last_fetched_at === undefined || src.trackers_last_fetched_at === null
        ? null
        : ensureString(src.trackers_last_fetched_at) || null,
    tracker_url_fetch_timeout_ms: (() => {
      const {
        DEFAULT_TRACKER_FETCH_TIMEOUT_MS,
        MIN_TRACKER_FETCH_TIMEOUT_MS,
        MAX_TRACKER_FETCH_TIMEOUT_MS,
      } = require('./transmissionTrackerResolver');
      const fallback = DEFAULT_TRACKER_FETCH_TIMEOUT_MS;
      if (src.tracker_url_fetch_timeout_ms === undefined || src.tracker_url_fetch_timeout_ms === null) {
        return fallback;
      }
      const n = Number(src.tracker_url_fetch_timeout_ms);
      if (!Number.isFinite(n)) return fallback;
      return Math.min(MAX_TRACKER_FETCH_TIMEOUT_MS, Math.max(MIN_TRACKER_FETCH_TIMEOUT_MS, Math.trunc(n)));
    })(),
    speed_limit_down: Math.max(0, toInt(src.speed_limit_down, base.speed_limit_down)),
    speed_limit_up: Math.max(0, toInt(src.speed_limit_up, base.speed_limit_up)),
    port_forwarding: toBool(src.port_forwarding, base.port_forwarding),
    dht_enabled: toBool(src.dht_enabled, base.dht_enabled),
    pex_enabled: toBool(src.pex_enabled, base.pex_enabled),
    utp_enabled: toBool(src.utp_enabled, base.utp_enabled),
    encryption: [0, 1, 2].includes(toInt(src.encryption, base.encryption)) ? toInt(src.encryption, base.encryption) : base.encryption,
    ratio_limit: Math.max(0, Number(src.ratio_limit) || base.ratio_limit),
    ratio_limit_enabled: toBool(src.ratio_limit_enabled, base.ratio_limit_enabled),
    idle_seeding_limit: Math.max(0, toInt(src.idle_seeding_limit, base.idle_seeding_limit)),
    idle_seeding_limit_enabled: toBool(src.idle_seeding_limit_enabled, base.idle_seeding_limit_enabled),
    auto_start: toBool(src.auto_start, base.auto_start),
    rpc_username: ensureString(src.rpc_username).trim() || base.rpc_username,
    rpc_password: ensureString(src.rpc_password),
    last_error: src.last_error === undefined || src.last_error === null ? null : ensureString(src.last_error),
    started_at: src.started_at || null,
  };
}

async function loadConfig() {
  await ensureMainDbReady();
  const raw = await tableConfig.getJsonConfigByKey(tableConfig.KEY_TRANSMISSION_CONFIG, 0);
  return normalizeConfig(raw);
}

async function saveConfig(partial) {
  const current = await loadConfig();
  const merged = normalizeConfig({ ...current, ...(partial && typeof partial === 'object' ? partial : {}) });
  if (partial && typeof partial === 'object') {
    if (partial.rpc_port !== undefined && toPortNumber(partial.rpc_port) !== current.rpc_port) {
      merged.actual_rpc_port = null;
    }
    if (partial.peer_port !== undefined && toPortNumber(partial.peer_port) !== current.peer_port) {
      merged.actual_rpc_port = null;
    }
    if (partial.default_trackers !== undefined) {
      const nextTrackers = normalizeDefaultTrackers(partial.default_trackers);
      if (nextTrackers !== current.default_trackers) {
        merged.default_trackers_resolved = '';
        merged.trackers_last_fetched_at = null;
      }
    }
  }
  const withCreds = ensureRpcCredentials(merged);
  if (withCreds.rpc_password && !jwtUtil.isEncryptedPassword(withCreds.rpc_password)) {
    withCreds.rpc_password = encryptRpcPassword(withCreds.rpc_password);
  }
  await tableConfig.setJsonConfigByKey(tableConfig.KEY_TRANSMISSION_CONFIG, withCreds, 0);
  return withCreds;
}

function getDefaultTrackersForDaemon(cfg) {
  return require('./transmissionTrackerResolver').getDefaultTrackersForDaemon(cfg);
}

let trackersResolvePromise = null;

async function ensureTrackersResolved(cfg, { force = false } = {}) {
  if (trackersResolvePromise) return trackersResolvePromise;
  trackersResolvePromise = _ensureTrackersResolvedImpl(cfg, { force }).finally(() => {
    trackersResolvePromise = null;
  });
  return trackersResolvePromise;
}

async function _ensureTrackersResolvedImpl(cfg, { force = false } = {}) {
  const {
    getTrackerFetchTimeoutMs,
    splitTrackerInput,
    fetchTrackerListsConcurrent,
    dedupeTrackers,
    isTrackerFetchCacheValid,
  } = require('./transmissionTrackerResolver');
  const configObj = normalizeConfig(cfg || (await loadConfig()));
  const lines = parseTrackerList(configObj.default_trackers);
  const { listUrls, directTrackers } = splitTrackerInput(lines);

  if (!listUrls.length) {
    const resolved = normalizeDefaultTrackers(directTrackers.join('\n'));
    if (resolved === configObj.default_trackers_resolved) return configObj;
    const saved = await saveConfig({
      default_trackers_resolved: resolved,
      trackers_last_fetched_at: null,
    });
    Logger.info('[transmission] trackers resolved (direct only)', {
      directCount: directTrackers.length,
      totalCount: parseTrackerList(resolved).length,
    });
    return saved;
  }

  if (!force && isTrackerFetchCacheValid(configObj)) {
    Logger.info('[transmission] trackers using cache', {
      listUrlCount: listUrls.length,
      totalCount: parseTrackerList(configObj.default_trackers_resolved).length,
      lastFetchedAt: configObj.trackers_last_fetched_at,
    });
    return configObj;
  }

  const timeoutMs = getTrackerFetchTimeoutMs(configObj);
  const fetched = await fetchTrackerListsConcurrent(listUrls, timeoutMs);
  if (!fetched.length && configObj.default_trackers_resolved) {
    Logger.warn('[transmission] tracker list fetch failed, keeping cached trackers');
    return configObj;
  }

  const resolvedList = dedupeTrackers([...directTrackers, ...fetched]);
  const resolved = resolvedList.join('\n');
  const saved = await saveConfig({
    default_trackers_resolved: resolved,
    trackers_last_fetched_at: new Date().toISOString(),
  });
  Logger.info('[transmission] trackers resolved from subscription urls', {
    force,
    listUrls,
    directCount: directTrackers.length,
    fetchedCount: fetched.length,
    totalCount: resolvedList.length,
    lastFetchedAt: saved.trackers_last_fetched_at,
    sample: resolvedList.slice(0, 5),
  });
  return saved;
}

function buildSettingsJson(cfg, rpcPort) {
  const port = toPortNumber(rpcPort) || toPortNumber(cfg.rpc_port) || 52019;
  const rpcPassword = decryptRpcPassword(cfg.rpc_password);
  const fallbackDownloadDir = getDaemonFallbackDownloadDir();
  return {
    'alt-speed-down': 50,
    'alt-speed-enabled': false,
    'alt-speed-time-begin': 540,
    'alt-speed-time-day': 127,
    'alt-speed-time-enabled': false,
    'alt-speed-time-end': 1020,
    'alt-speed-up': 50,
    'bind-address-ipv4': '0.0.0.0',
    'bind-address-ipv6': '::',
    'blocklist-enabled': false,
    'dht-enabled': !!cfg.dht_enabled,
    'download-dir': fallbackDownloadDir,
    'download-queue-enabled': true,
    'download-queue-size': 5,
    'encryption': cfg.encryption,
    'idle-seeding-limit': cfg.idle_seeding_limit,
    'idle-seeding-limit-enabled': !!cfg.idle_seeding_limit_enabled,
    'incomplete-dir-enabled': false,
    'lpd-enabled': false,
    'message-level': 2,
    'default-trackers': getDefaultTrackersForDaemon(cfg),
    'peer-limit-global': Math.max(0, toInt(cfg.peer_limit_global, 200)),
    'peer-limit-per-torrent': Math.max(0, toInt(cfg.peer_limit_per_torrent, 50)),
    'peer-port': cfg.peer_port,
    'peer-port-random-on-start': false,
    'pex-enabled': !!cfg.pex_enabled,
    'port-forwarding-enabled': !!cfg.port_forwarding,
    'preallocation': 1,
    'queue-stalled-enabled': true,
    'queue-stalled-minutes': 30,
    'ratio-limit': cfg.ratio_limit,
    'ratio-limit-enabled': !!cfg.ratio_limit_enabled,
    'rename-partial-files': true,
    'rpc-authentication-required': true,
    'rpc-bind-address': '127.0.0.1',
    'rpc-enabled': true,
    'rpc-host-whitelist-enabled': true,
    'rpc-host-whitelist': '127.0.0.1,localhost',
    'rpc-password': rpcPassword,
    'rpc-port': port,
    'rpc-url': '/transmission/',
    'rpc-username': cfg.rpc_username,
    'rpc-whitelist-enabled': true,
    'rpc-whitelist': '127.0.0.1,localhost',
    'scrape-paused-torrents-enabled': true,
    'script-torrent-done-enabled': false,
    'seed-queue-enabled': false,
    'seed-queue-size': 10,
    'speed-limit-down': cfg.speed_limit_down,
    'speed-limit-down-enabled': cfg.speed_limit_down > 0,
    'speed-limit-up': cfg.speed_limit_up,
    'speed-limit-up-enabled': cfg.speed_limit_up > 0,
    'start-added-torrents': true,
    'trash-original-torrent-files': false,
    'umask': 18,
    'upload-slots-per-torrent': 14,
    'utp-enabled': !!cfg.utp_enabled,
  };
}

async function writeSettingsFile(cfg, rpcPort) {
  const configDir = getConfigDir();
  await fs.promises.mkdir(configDir, { recursive: true });
  await fs.promises.mkdir(getDaemonFallbackDownloadDir(), { recursive: true });
  const settingsPath = path.join(configDir, 'settings.json');
  let existing = {};
  try {
    const raw = await fs.promises.readFile(settingsPath, 'utf8');
    existing = JSON.parse(raw);
  } catch (_) {}
  const next = {
    ...(existing && typeof existing === 'object' ? existing : {}),
    ...buildSettingsJson(cfg, rpcPort),
  };
  await fs.promises.writeFile(settingsPath, JSON.stringify(next, null, 2), 'utf8');
  return settingsPath;
}

function sanitizeConfigForClient(cfg) {
  const next = normalizeConfig(cfg);
  return {
    ...next,
    rpc_password: next.rpc_password ? '******' : '',
  };
}

async function isRpcReachable(cfg, portOverride) {
  const configObj = cfg || (await loadConfig());
  const port = toPortNumber(portOverride) || toPortNumber(configObj.rpc_port) || 52019;
  const username = getRpcUsername(configObj);
  const password = decryptRpcPassword(configObj.rpc_password);
  try {
    const res = await axios.post(
      `http://127.0.0.1:${port}/transmission/rpc`,
      { method: 'session-get', arguments: {} },
      {
        auth: { username, password },
        timeout: 3000,
        validateStatus: () => true,
      }
    );
    return res.status === 200 || res.status === 409;
  } catch (_) {
    return false;
  }
}

async function probeTransmissionRuntime(cfg) {
  const configObj = normalizeConfig(cfg || (await loadConfig()));
  const configuredPort = toPortNumber(configObj.rpc_port);
  if (!configuredPort) {
    return {
      running: false,
      port_mismatch: false,
      configured_rpc_port: null,
      actual_rpc_port: null,
      stale_rpc_port: null,
    };
  }

  const onConfigured = await isRpcReachable(configObj, configuredPort);
  if (onConfigured) {
    return {
      running: true,
      port_mismatch: false,
      configured_rpc_port: configuredPort,
      actual_rpc_port: configuredPort,
      stale_rpc_port: null,
    };
  }

  const stalePort = toPortNumber(configObj.actual_rpc_port);
  let staleUp = false;
  if (stalePort && stalePort !== configuredPort) {
    staleUp = await isRpcReachable(configObj, stalePort);
  }

  return {
    running: false,
    port_mismatch: staleUp,
    configured_rpc_port: configuredPort,
    actual_rpc_port: staleUp ? stalePort : null,
    stale_rpc_port: staleUp ? stalePort : null,
  };
}

async function reconcileTransmissionConfigIfStale(cfg, probe) {
  const configObj = normalizeConfig(cfg || (await loadConfig()));
  const runtime =
    probe && typeof probe.running === 'boolean' ? probe : await probeTransmissionRuntime(configObj);

  if (runtime.running && !configObj.enabled) {
    const { forceStopTransmissionProcesses } = require('./transmissionWorker');
    await forceStopTransmissionProcesses(configObj, {
      actualRpcPort: runtime.actual_rpc_port,
      graceful: true,
    }).catch(() => {});
    const stillUp = await isRpcReachable(configObj, runtime.actual_rpc_port);
    if (!stillUp) {
      if (configObj.status !== 'stopped' || configObj.actual_rpc_port) {
        return saveConfig({
          status: 'stopped',
          enabled: false,
          actual_rpc_port: null,
          started_at: null,
          last_error: null,
        });
      }
    }
    return configObj;
  }

  if (runtime.running) {
    if (
      configObj.status !== 'running' ||
      configObj.actual_rpc_port !== runtime.actual_rpc_port ||
      configObj.last_error
    ) {
      return saveConfig({
        status: 'running',
        enabled: true,
        actual_rpc_port: runtime.actual_rpc_port,
        last_error: null,
      });
    }
    return configObj;
  }
  if (runtime.port_mismatch) {
    if (configObj.status !== 'stopped' || configObj.last_error !== 'port_mismatch') {
      return saveConfig({
        status: 'stopped',
        actual_rpc_port: runtime.stale_rpc_port,
        last_error: 'port_mismatch',
        started_at: null,
      });
    }
    return configObj;
  }
  if (configObj.status === 'running' || configObj.actual_rpc_port) {
    return saveConfig({
      status: 'stopped',
      actual_rpc_port: null,
      started_at: null,
      last_error: configObj.last_error === 'port_mismatch' ? null : configObj.last_error,
    });
  }
  return configObj;
}

function buildSessionSetArgs(cfg) {
  const normalized = normalizeConfig(cfg);
  return {
    'default-trackers': getDefaultTrackersForDaemon(normalized),
    'peer-limit-global': Math.max(0, toInt(normalized.peer_limit_global, 200)),
    'peer-limit-per-torrent': Math.max(0, toInt(normalized.peer_limit_per_torrent, 50)),
    'speed-limit-down': Math.max(0, toInt(normalized.speed_limit_down, 0)),
    'speed-limit-down-enabled': Math.max(0, toInt(normalized.speed_limit_down, 0)) > 0,
    'speed-limit-up': Math.max(0, toInt(normalized.speed_limit_up, 0)),
    'speed-limit-up-enabled': Math.max(0, toInt(normalized.speed_limit_up, 0)) > 0,
    'dht-enabled': !!normalized.dht_enabled,
    'pex-enabled': !!normalized.pex_enabled,
    'utp-enabled': !!normalized.utp_enabled,
    'port-forwarding-enabled': !!normalized.port_forwarding,
  };
}

const ALLOWED_SESSION_SET_KEYS = new Set([
  'alt-speed-down',
  'alt-speed-down-enabled',
  'alt-speed-enabled',
  'alt-speed-time-begin',
  'alt-speed-time-day',
  'alt-speed-time-enabled',
  'alt-speed-time-end',
  'alt-speed-up',
  'default-trackers',
  'dht-enabled',
  'encryption',
  'idle-seeding-limit',
  'idle-seeding-limit-enabled',
  'peer-limit-global',
  'peer-limit-per-torrent',
  'pex-enabled',
  'port-forwarding-enabled',
  'ratio-limit',
  'ratio-limit-enabled',
  'speed-limit-down',
  'speed-limit-down-enabled',
  'speed-limit-up',
  'speed-limit-up-enabled',
  'utp-enabled',
]);

function filterSessionSetArguments(raw) {
  const src = raw && typeof raw === 'object' ? raw : {};
  const filtered = {};
  for (const [key, value] of Object.entries(src)) {
    if (!ALLOWED_SESSION_SET_KEYS.has(key)) continue;
    filtered[key] = value;
  }
  return filtered;
}

module.exports = {
  DEFAULT_RPC_USERNAME,
  ensureString,
  toPortNumber,
  getConfigDir,
  getDefaultConfig,
  getDaemonFallbackDownloadDir,
  getRpcUsername,
  ensureRpcCredentials,
  normalizeConfig,
  normalizeDefaultTrackers,
  parseTrackerList,
  getDefaultTrackersForDaemon,
  ensureTrackersResolved,
  loadConfig,
  saveConfig,
  buildSettingsJson,
  buildSessionSetArgs,
  filterSessionSetArguments,
  writeSettingsFile,
  decryptRpcPassword,
  encryptRpcPassword,
  sanitizeConfigForClient,
  isRpcReachable,
  probeTransmissionRuntime,
  reconcileTransmissionConfigIfStale,
};
