'use strict';

const fs = require('fs');
const path = require('path');

let si = null;
try {
  si = require('systeminformation');
} catch (_) {
  si = null;
}

async function _rootsFromSystemInformation() {
  if (!si || typeof si.fsSize !== 'function') return [];
  const sizes = await si.fsSize().catch(() => []);
  const mounts = new Set();
  for (const s of sizes || []) {
    const mount = s && (s.mount || s.fs) ? String(s.mount || s.fs) : '';
    if (mount) mounts.add(mount);
  }
  return Array.from(mounts);
}

async function _rootsFallback() {
  const isWin = process.platform === 'win32';
  if (isWin) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
    const roots = [];
    for (const l of letters) {
      const p = `${l}:\\`;
      try {
        if (fs.existsSync(p)) roots.push(p);
      } catch (_) {}
    }
    return roots;
  }

  const candidates = ['/', '/Users', '/Volumes', '/home', '/mnt', '/media', '/volume1', '/volume2', '/data'];
  return candidates.filter(p => {
    try {
      return fs.existsSync(p);
    } catch (_) {
      return false;
    }
  });
}

function _isExistingDirectory(p) {
  try {
    const st = fs.statSync(p);
    return st && st.isDirectory();
  } catch (_) {
    return false;
  }
}

function _dedupeAndSort(roots) {
  const set = new Set();
  for (const r of roots || []) {
    if (!r) continue;
    const resolved = path.resolve(String(r));
    set.add(resolved);
  }
  return Array.from(set).sort();
}

async function getAllDiskRoots() {
  const isWin = process.platform === 'win32';
  const isMac = process.platform === 'darwin';
  const all = (await _rootsFromSystemInformation()) || [];
  const roots = all.length > 0 ? all : await _rootsFallback();

  const normalized = [];
  for (const r of roots || []) {
    if (!r) continue;
    const s = String(r);
    if (isWin) {
      const m = s.match(/^([A-Za-z]:)/);
      if (m) normalized.push(`${m[1]}\\`);
      continue;
    }
    if (s.startsWith('/')) normalized.push(s);
  }

  const unique = _dedupeAndSort(normalized).filter(_isExistingDirectory);

  if (isWin) return unique;

  if (isMac) {
    const res = [];
    if (_isExistingDirectory('/Users')) res.push('/Users');
    if (_isExistingDirectory('/Volumes')) {
      let vols = [];
      try {
        vols = fs.readdirSync('/Volumes', { withFileTypes: true });
      } catch (_) {
        vols = [];
      }
      for (const ent of vols) {
        if (!ent || !ent.isDirectory()) continue;
        const p = path.join('/Volumes', ent.name);
        if (_isExistingDirectory(p)) res.push(p);
      }
    }
    return _dedupeAndSort(res);
  }

  const preferred = ['/home', '/mnt', '/media', '/volume1', '/volume2', '/data'];
  const res = [];
  for (const p of preferred) {
    if (_isExistingDirectory(p)) res.push(p);
  }
  return _dedupeAndSort(res.length > 0 ? res : unique);
}

module.exports = {
  getAllDiskRoots,
};
