const tableConfig = require('../db/table/tableConfig');
const fs = require('fs');
const path = require('path');

const CONFIG_KEY_USER_CUSTOM_PATHS = 'file_user_custom_paths';

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
    return { path: resolved, name: null };
  }
  if (!entry || typeof entry !== 'object') return null;
  const p = entry.path ? String(entry.path).trim() : '';
  if (!p || !_isAbsoluteLikePath(p)) return null;
  const resolved = path.resolve(p);
  const name = entry.name !== undefined && entry.name !== null ? String(entry.name).trim() : null;
  return { path: resolved, name: name || null };
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

async function getUserCustomPaths(uid, { includeMissing = true } = {}) {
  const uidNum = Number(uid);
  if (!Number.isFinite(uidNum) || uidNum <= 0) return [];

  let raw = null;
  try {
    raw = await tableConfig.getConfigByKey(CONFIG_KEY_USER_CUSTOM_PATHS, uidNum);
  } catch (_) {
    raw = null;
  }

  const list = _parseConfigValue(raw);
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

async function saveUserCustomPaths(uid, nextList) {
  const uidNum = Number(uid);
  if (!Number.isFinite(uidNum) || uidNum <= 0) return false;

  const input = Array.isArray(nextList) ? nextList : [];
  const unique = new Map();
  for (const e of input) {
    const normalized = _normalizeEntry(e);
    if (!normalized) continue;
    if (!unique.has(normalized.path)) unique.set(normalized.path, normalized);
  }
  const finalList = Array.from(unique.values()).map(i => ({ path: i.path, name: i.name }));
  const ok = await tableConfig.setConfigByKey(CONFIG_KEY_USER_CUSTOM_PATHS, JSON.stringify(finalList), uidNum);
  return ok;
}

module.exports = {
  CONFIG_KEY_USER_CUSTOM_PATHS,
  getUserCustomPaths,
  saveUserCustomPaths,
};
