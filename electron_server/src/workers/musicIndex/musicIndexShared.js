'use strict';

const path = require('path');
const FileUtil = require('../../utils/fileUtil');
const config = require('../../config/config');

function resolvePath(p) {
  const s = p ? String(p) : '';
  if (!s) return '';
  return path.resolve(s);
}

function isMusicFileExt(ext) {
  const e = String(ext || '').toLowerCase();
  if (!e) return false;
  return Array.isArray(config.musicTypeList) && config.musicTypeList.includes(e);
}

function shouldSkipFilename(filename) {
  const name = filename ? String(filename) : '';
  if (!name) return true;
  if (FileUtil.isSystemFile(name)) return true;
  if (FileUtil.isHideFile(name)) return true;
  if (FileUtil.isTemporaryOrDownloadingFile(name)) return true;
  return false;
}

function getBestMatchedItemByPath(items, targetPath) {
  const resolved = resolvePath(targetPath);
  if (!resolved) return null;
  let best = null;
  let bestRootLen = 0;

  for (const it of items || []) {
    const root = it && it.path ? resolvePath(it.path) : '';
    if (!root) continue;
    const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
    const ok = resolved === root || resolved.startsWith(prefix);
    if (!ok) continue;
    if (!best || root.length > bestRootLen) {
      best = it;
      bestRootLen = root.length;
    }
  }

  return best;
}

module.exports = {
  resolvePath,
  isMusicFileExt,
  shouldSkipFilename,
  getBestMatchedItemByPath,
};
