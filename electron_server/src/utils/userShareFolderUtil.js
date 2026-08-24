const tableConfig = require('../db/table/tableConfig');
const fs = require('fs');
const path = require('path');

const CONFIG_KEY_USER_SHARE_FOLDERS = 'file_user_share_folders';

let _cacheAtMs = 0;
let _cacheValue = null;
let _cacheRaw = null;

function _isAbsoluteLikePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\') || v.startsWith('\\')) return true;
  return /^[a-zA-Z]:[\\/]/.test(v);
}

function _normalizeEntry(entry) {
  if (typeof entry === 'string') {
    const p = entry.trim();
    if (!p || !_isAbsoluteLikePath(p)) return null;
    const resolved = path.resolve(p);
    return { path: resolved, name: null, allowDownload: false };
  }
  if (!entry || typeof entry !== 'object') return null;
  const p = entry.path ? String(entry.path).trim() : '';
  if (!p || !_isAbsoluteLikePath(p)) return null;
  const resolved = path.resolve(p);
  const name = entry.name !== undefined && entry.name !== null ? String(entry.name).trim() : null;
  const allowDownload =
    entry.allowDownload === true ||
    entry.allowDownload === 1 ||
    String(entry.allowDownload || '')
      .trim()
      .toLowerCase() === 'true';
  return { path: resolved, name: name || null, allowDownload };
}

function _parseConfigValue(raw) {
  if (!raw) return [];
  const text = String(raw).trim();
  if (!text) return [];
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch (_) {
    parsed = null;
  }
  if (!Array.isArray(parsed)) return [];

  const unique = new Map();
  for (const item of parsed) {
    const normalized = _normalizeEntry(item);
    if (!normalized) continue;
    if (!unique.has(normalized.path)) {
      unique.set(normalized.path, normalized);
    }
  }
  return Array.from(unique.values());
}

async function _loadCachedFolders(ttlMs = 5000) {
  const now = Date.now();
  if (_cacheValue && now - _cacheAtMs < ttlMs) return _cacheValue;

  let raw = null;
  try {
    raw = await tableConfig.getConfigByKey(CONFIG_KEY_USER_SHARE_FOLDERS);
  } catch (_) {
    raw = null;
  }

  if (_cacheRaw !== raw || !_cacheValue) {
    _cacheRaw = raw;
    _cacheValue = _parseConfigValue(raw);
  }
  _cacheAtMs = now;
  return _cacheValue;
}

function invalidateCache() {
  _cacheAtMs = 0;
  _cacheValue = null;
  _cacheRaw = null;
}

async function getUserShareFolders({ includeMissing = true } = {}) {
  const list = await _loadCachedFolders();
  if (includeMissing) return list;

  const existing = [];
  for (const item of list) {
    try {
      const st = await fs.promises.stat(item.path);
      if (st && st.isDirectory()) existing.push(item);
    } catch (_) {}
  }
  return existing;
}

async function getUserShareFoldersWithStats() {
  const list = await _loadCachedFolders();
  const out = [];
  for (const item of list) {
    let exists = false;
    let isDirectory = false;
    let mtimeMs = null;
    try {
      const st = await fs.promises.stat(item.path);
      exists = true;
      isDirectory = !!st.isDirectory();
      mtimeMs = st.mtimeMs;
    } catch (_) {}
    out.push({
      path: item.path,
      name: item.name || path.basename(item.path) || item.path,
      exists,
      isDirectory,
      mtimeMs,
      allowDownload: !!item.allowDownload,
      isUserShareFolder: true,
    });
  }
  return out;
}

async function saveUserShareFolders(nextList) {
  const input = Array.isArray(nextList) ? nextList : [];
  const unique = new Map();
  for (const e of input) {
    const normalized = _normalizeEntry(e);
    if (!normalized) continue;
    if (!unique.has(normalized.path)) unique.set(normalized.path, normalized);
  }
  const finalList = Array.from(unique.values()).map(i => ({
    path: i.path,
    name: i.name,
    allowDownload: !!i.allowDownload,
  }));
  const ok = await tableConfig.setConfigByKey(CONFIG_KEY_USER_SHARE_FOLDERS, JSON.stringify(finalList));
  invalidateCache();
  return ok;
}

function _isPathUnderRoot(resolvedTarget, root) {
  const rootResolved = path.resolve(root);
  if (resolvedTarget === rootResolved) return true;
  const prefix = rootResolved.endsWith(path.sep) ? rootResolved : `${rootResolved}${path.sep}`;
  return resolvedTarget.startsWith(prefix);
}

async function matchUserShareEntry(targetPath) {
  const p = typeof targetPath === 'string' ? targetPath.trim() : '';
  if (!p) return null;
  const resolved = path.resolve(p);
  const roots = await _loadCachedFolders();
  let best = null;
  let bestLen = -1;
  for (const r of roots) {
    if (!r || !r.path) continue;
    if (!_isPathUnderRoot(resolved, r.path)) continue;
    const len = String(r.path).length;
    if (len > bestLen) {
      best = r;
      bestLen = len;
    }
  }
  return best;
}

async function isUserSharePath(targetPath) {
  const matched = await matchUserShareEntry(targetPath);
  return !!matched;
}

async function isUserShareDownloadAllowed(targetPath) {
  const matched = await matchUserShareEntry(targetPath);
  return !!matched && !!matched.allowDownload;
}

module.exports = {
  CONFIG_KEY_USER_SHARE_FOLDERS,
  getUserShareFolders,
  getUserShareFoldersWithStats,
  saveUserShareFolders,
  invalidateCache,
  isUserSharePath,
  isUserShareDownloadAllowed,
  matchUserShareEntry,
};
