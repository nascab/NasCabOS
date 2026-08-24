'use strict';

const fs = require('fs');
const path = require('path');

const { shouldIgnoreDirectoryEntry, shouldIgnoreFileEntry, shouldIgnorePath } = require('./fileAllIndexFilter');

function _toFsPath(p) {
  const s = String(p || '');
  if (process.platform !== 'win32') return s;
  if (s.startsWith('\\\\?\\')) return s;
  if (s.startsWith('\\\\')) return s;
  if (s.length < 250) return s;
  return `\\\\?\\${s}`;
}

async function walkAndCollectFiles(rootDir, onFile) {
  const root = rootDir ? path.resolve(String(rootDir)) : '';
  if (!root) return;
  if (shouldIgnorePath(root)) return;

  const stack = [root];
  const seenDirs = new Set();

  while (stack.length > 0) {
    const current = stack.pop();
    const resolvedDir = current ? path.resolve(String(current)) : '';
    if (!resolvedDir) continue;
    if (seenDirs.has(resolvedDir)) continue;
    seenDirs.add(resolvedDir);

    if (shouldIgnorePath(resolvedDir)) continue;

    let entries;
    try {
      entries = await fs.promises.readdir(_toFsPath(resolvedDir), { withFileTypes: true });
    } catch (_) {
      continue;
    }

    for (const ent of entries || []) {
      if (!ent) continue;
      const name = ent.name;
      if (!name) continue;

      if (ent.isSymbolicLink && ent.isSymbolicLink()) continue;

      if (ent.isDirectory && ent.isDirectory()) {
        if (shouldIgnoreDirectoryEntry({ parentDir: resolvedDir, name })) continue;
        const full = path.join(resolvedDir, name);
        const res = await onFile({ fullPath: full, dirPath: resolvedDir, filename: name, ext: '__dir__', isDir: true });
        if (res === false) return;
        stack.push(full);
        continue;
      }

      if (ent.isFile && ent.isFile()) {
        if (shouldIgnoreFileEntry({ parentDir: resolvedDir, name })) continue;
        const fullPath = path.join(resolvedDir, name);
        const ext = path.extname(name).toLowerCase();
        const res = await onFile({ fullPath, dirPath: resolvedDir, filename: name, ext, isDir: false });
        if (res === false) return;
      }
    }
  }
}

module.exports = {
  walkAndCollectFiles,
};
