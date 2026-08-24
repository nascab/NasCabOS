const fs = require('fs');
const path = require('path');
const os = require('os');
const tableConfig = require('../../db/table/tableConfig');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const { getDaemonFallbackDownloadDir } = require('./transmissionConfig');

const MAX_RECENT_DIRS = 32;

async function ensureMainDbReady() {
  const dbPath = dbUtil.DB_PATHS.MAIN_DB;
  if (!knexUtil.hasConnection(dbPath)) {
    await knexUtil.init(dbPath);
  }
}

function normalizeDir(dir) {
  const text = dir === undefined || dir === null ? '' : String(dir).trim();
  if (!text) return '';
  return path.resolve(text);
}

function isFallbackDownloadDir(dir) {
  const normalized = normalizeDir(dir);
  if (!normalized) return false;
  return normalized === normalizeDir(getDaemonFallbackDownloadDir());
}

async function loadStore() {
  await ensureMainDbReady();
  const raw = await tableConfig.getJsonConfigByKey(tableConfig.KEY_TRANSMISSION_TORRENT_PATHS, 0);
  if (!raw || typeof raw !== 'object') {
    return { byHash: {}, recentDirs: [] };
  }
  const byHash = raw.byHash && typeof raw.byHash === 'object' ? raw.byHash : {};
  const recentDirs = Array.isArray(raw.recentDirs)
    ? raw.recentDirs.map(normalizeDir).filter(Boolean)
    : [];
  return { byHash, recentDirs };
}

async function saveStore(store) {
  await ensureMainDbReady();
  const payload = {
    byHash: store && store.byHash && typeof store.byHash === 'object' ? store.byHash : {},
    recentDirs: Array.isArray(store && store.recentDirs)
      ? store.recentDirs.map(normalizeDir).filter(Boolean).slice(0, MAX_RECENT_DIRS)
      : [],
  };
  await tableConfig.setJsonConfigByKey(tableConfig.KEY_TRANSMISSION_TORRENT_PATHS, payload, 0);
  return payload;
}

async function rememberDownloadDir(downloadDir) {
  const dir = normalizeDir(downloadDir);
  if (!dir || isFallbackDownloadDir(dir)) return;
  const store = await loadStore();
  const recentDirs = [dir, ...store.recentDirs.filter(v => v !== dir)].slice(0, MAX_RECENT_DIRS);
  await saveStore({ ...store, recentDirs });
}

async function setTorrentDownloadDir(hashString, downloadDir) {
  const hash = hashString === undefined || hashString === null ? '' : String(hashString).trim();
  const dir = normalizeDir(downloadDir);
  if (!hash || !dir || isFallbackDownloadDir(dir)) return null;
  const store = await loadStore();
  store.byHash[hash] = {
    downloadDir: dir,
    updatedAt: new Date().toISOString(),
  };
  const recentDirs = [dir, ...store.recentDirs.filter(v => v !== dir)].slice(0, MAX_RECENT_DIRS);
  await saveStore({ ...store, recentDirs });
  return dir;
}

async function getTorrentDownloadDir(hashString) {
  const hash = hashString === undefined || hashString === null ? '' : String(hashString).trim();
  if (!hash) return '';
  const store = await loadStore();
  const entry = store.byHash[hash];
  return entry && entry.downloadDir ? normalizeDir(entry.downloadDir) : '';
}

async function removeTorrentDownloadDir(hashString) {
  const hash = hashString === undefined || hashString === null ? '' : String(hashString).trim();
  if (!hash) return;
  const store = await loadStore();
  if (!store.byHash[hash]) return;
  delete store.byHash[hash];
  await saveStore(store);
}

async function pathHasTorrentData(baseDir, torrentName) {
  const root = normalizeDir(baseDir);
  if (!root) return null;
  const candidates = [root];
  const name = torrentName === undefined || torrentName === null ? '' : String(torrentName).trim();
  if (name) candidates.push(path.join(root, name));

  for (const dir of candidates) {
    try {
      const st = await fs.promises.stat(dir);
      if (!st.isDirectory()) continue;
      const entries = await fs.promises.readdir(dir);
      if (entries.some(entry => entry.endsWith('.part') || entry.endsWith('.!qB'))) {
        return root;
      }
      for (const entry of entries) {
        const sub = path.join(dir, entry);
        try {
          const subSt = await fs.promises.stat(sub);
          if (!subSt.isFile()) continue;
          if (subSt.size > 1024 * 1024) return root;
        } catch (_) {}
      }
    } catch (_) {}
  }
  return null;
}

function getDefaultSearchRoots() {
  const home = os.homedir();
  return [
    path.join(home, 'Desktop'),
    path.join(home, 'Downloads'),
    path.join(home, 'Movies'),
    path.join(home, 'Videos'),
  ].map(normalizeDir);
}

async function findDownloadDirByTorrentName(torrentName, extraRoots = []) {
  const name = torrentName === undefined || torrentName === null ? '' : String(torrentName).trim();
  if (!name) return '';
  const roots = [...extraRoots.map(normalizeDir).filter(Boolean), ...getDefaultSearchRoots()];
  const seen = new Set();
  for (const root of roots) {
    if (!root || seen.has(root)) continue;
    seen.add(root);
    const direct = await pathHasTorrentData(root, name);
    if (direct) return direct;
    try {
      const entries = await fs.promises.readdir(root, { withFileTypes: true });
      for (const entry of entries) {
        if (!entry.isDirectory()) continue;
        const candidate = path.join(root, entry.name);
        const hit = await pathHasTorrentData(candidate, name);
        if (hit) return hit;
      }
    } catch (_) {}
  }
  return '';
}

async function resolveStoredDownloadDir(hashString, torrentName) {
  const stored = await getTorrentDownloadDir(hashString);
  if (stored) return stored;
  const store = await loadStore();
  for (const dir of store.recentDirs) {
    const hit = await pathHasTorrentData(dir, torrentName);
    if (hit) return hit;
  }
  return findDownloadDirByTorrentName(torrentName, store.recentDirs);
}

module.exports = {
  normalizeDir,
  isFallbackDownloadDir,
  loadStore,
  rememberDownloadDir,
  setTorrentDownloadDir,
  getTorrentDownloadDir,
  removeTorrentDownloadDir,
  pathHasTorrentData,
  resolveStoredDownloadDir,
  findDownloadDirByTorrentName,
};
