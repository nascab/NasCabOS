const axios = require('axios');
const Logger = require('../../utils/logger');
const { ensureString, parseTrackerList, normalizeDefaultTrackers } = require('./transmissionConfig');

const TRACKER_FETCH_INTERVAL_MS = 6 * 60 * 60 * 1000;
const DEFAULT_TRACKER_FETCH_TIMEOUT_MS = 10000;
const MIN_TRACKER_FETCH_TIMEOUT_MS = 1000;
const MAX_TRACKER_FETCH_TIMEOUT_MS = 120000;

function getTrackerFetchTimeoutMs(cfg) {
  const n = Number(cfg && cfg.tracker_url_fetch_timeout_ms);
  if (!Number.isFinite(n)) return DEFAULT_TRACKER_FETCH_TIMEOUT_MS;
  return Math.min(MAX_TRACKER_FETCH_TIMEOUT_MS, Math.max(MIN_TRACKER_FETCH_TIMEOUT_MS, Math.trunc(n)));
}

function isTrackerListUrl(line) {
  const s = ensureString(line).trim();
  if (!/^https?:\/\//i.test(s)) return false;
  try {
    const pathname = new URL(s).pathname.toLowerCase();
    return pathname.endsWith('.txt') || pathname.includes('.txt');
  } catch (_) {
    return /\.txt(?:\?|#|$)/i.test(s);
  }
}

function parseTrackerListText(text) {
  return ensureString(text)
    .split(/\r?\n/)
    .map(v => v.trim())
    .filter(v => v && !v.startsWith('#'))
    .filter(v => /^(udp|https?|wss?):\/\//i.test(v));
}

function dedupeTrackers(trackers) {
  const seen = new Set();
  const out = [];
  for (const t of trackers) {
    const key = ensureString(t).trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(key);
  }
  return out;
}

function splitTrackerInput(lines) {
  const listUrls = [];
  const directTrackers = [];
  for (const line of lines) {
    if (isTrackerListUrl(line)) listUrls.push(line.trim());
    else directTrackers.push(line);
  }
  return { listUrls, directTrackers };
}

async function fetchTrackerListUrl(url, timeoutMs) {
  try {
    const res = await axios.get(url, {
      timeout: timeoutMs,
      responseType: 'text',
      maxContentLength: 2 * 1024 * 1024,
      validateStatus: status => status >= 200 && status < 300,
      headers: { 'User-Agent': 'NascabTransmission/1.0' },
    });
    const trackers = parseTrackerListText(res.data);
    Logger.info('[transmission] tracker list url fetched', {
      url,
      count: trackers.length,
      sample: trackers.slice(0, 3),
    });
    return trackers;
  } catch (err) {
    Logger.warn('[transmission] fetch tracker list failed', {
      url,
      error: err && err.message ? err.message : String(err),
    });
    return [];
  }
}

async function fetchTrackerListsConcurrent(urls, timeoutMs) {
  if (!urls.length) return [];
  const results = await Promise.all(urls.map(url => fetchTrackerListUrl(url, timeoutMs)));
  return dedupeTrackers(results.flat());
}

function getDefaultTrackersForDaemon(cfg) {
  const resolved = ensureString(cfg && cfg.default_trackers_resolved).trim();
  if (resolved) return resolved;
  return normalizeDefaultTrackers(cfg && cfg.default_trackers);
}

function isTrackerFetchCacheValid(cfg) {
  const lastFetched = ensureString(cfg && cfg.trackers_last_fetched_at).trim();
  const cached = ensureString(cfg && cfg.default_trackers_resolved).trim();
  if (!lastFetched || !cached) return false;
  const ts = Date.parse(lastFetched);
  if (!Number.isFinite(ts)) return false;
  return Date.now() - ts < TRACKER_FETCH_INTERVAL_MS;
}

async function resolveTrackerLines(lines, timeoutMs) {
  const normalized = parseTrackerList(lines);
  const { listUrls, directTrackers } = splitTrackerInput(normalized);
  if (!listUrls.length) return dedupeTrackers(directTrackers);
  const fetched = await fetchTrackerListsConcurrent(listUrls, timeoutMs);
  return dedupeTrackers([...directTrackers, ...fetched]);
}

async function resolveTrackerInput(raw, timeoutMs) {
  return resolveTrackerLines(parseTrackerList(raw), timeoutMs);
}

module.exports = {
  TRACKER_FETCH_INTERVAL_MS,
  DEFAULT_TRACKER_FETCH_TIMEOUT_MS,
  MIN_TRACKER_FETCH_TIMEOUT_MS,
  MAX_TRACKER_FETCH_TIMEOUT_MS,
  getTrackerFetchTimeoutMs,
  isTrackerListUrl,
  parseTrackerListText,
  dedupeTrackers,
  splitTrackerInput,
  fetchTrackerListsConcurrent,
  getDefaultTrackersForDaemon,
  isTrackerFetchCacheValid,
  resolveTrackerLines,
  resolveTrackerInput,
};
