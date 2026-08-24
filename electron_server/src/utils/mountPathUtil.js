const fs = require('fs');
const path = require('path');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function isValidMountFolderName(value) {
  const t = ensureString(value).trim();
  if (!t) return false;
  if (t === '.' || t === '..') return false;
  if (t.includes('/') || t.includes('\\')) return false;
  if (/[\x00-\x1F]/.test(t)) return false;
  if (t.endsWith(' ') || t.endsWith('.')) return false;
  if (/[<>:"|?*]/.test(t)) return false;
  return true;
}

async function checkDirReadableWritable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return 'mount_parent_not_found';
  let stat;
  try {
    stat = await fs.promises.stat(p);
  } catch (_) {
    return 'mount_parent_not_found';
  }
  if (!stat.isDirectory()) return 'mount_parent_not_dir';
  const mode = fs.constants.R_OK | fs.constants.W_OK | (fs.constants.X_OK || 0);
  try {
    await fs.promises.access(p, mode);
  } catch (_) {
    return 'mount_parent_no_access';
  }
  return '';
}

async function statNoThrow(p) {
  try {
    return await fs.promises.stat(p);
  } catch (_) {
    return null;
  }
}

async function removeDirNoThrow(dirPath) {
  try {
    await fs.promises.rmdir(dirPath);
    return true;
  } catch (_) {
    return false;
  }
}

/** rclone 使用 --allow-non-empty 时，仅含隐藏/系统文件的目录可复用 */
async function isDirReusableForMount(dirPath) {
  try {
    const entries = await fs.promises.readdir(dirPath);
    if (!Array.isArray(entries) || entries.length === 0) return true;
    return entries.every(e => e.startsWith('.'));
  } catch (_) {
    return true;
  }
}

async function resolveUniqueMountDir({ parentPath, mountName, startIndex = 0 }) {
  const parent = ensureString(parentPath).trim();
  const name = ensureString(mountName).trim();
  if (!parent || !name) return null;
  const mustNotExist = process.platform === 'win32';

  for (let idx = Math.max(0, Number(startIndex) || 0); idx < 50; idx++) {
    const suffix = idx === 0 ? '' : `_${idx}`;
    const candidate = path.join(parent, `${name}${suffix}`);
    const st = await statNoThrow(candidate);
    if (!st) {
      // WinFsp 挂目录时要求挂载点路径不存在，由 rclone/WinFsp 自行创建占用。
      if (mustNotExist) {
        return candidate;
      }
      try {
        await fs.promises.mkdir(candidate, { recursive: true });
        return candidate;
      } catch (_) {
        continue;
      }
    }
    if (!st.isDirectory()) continue;
    if (!(await isDirReusableForMount(candidate))) continue;
    if (mustNotExist) {
      const removed = await removeDirNoThrow(candidate);
      if (removed || !(await statNoThrow(candidate))) {
        return candidate;
      }
      continue;
    }
    return candidate;
  }
  return null;
}

/** 优先复用 DB 中记录的上次挂载目录，避免重启后路径递增 */
async function resolveMountDir({ parentPath, mountName, preferredPath, startIndex = 0 }) {
  const preferred = ensureString(preferredPath).trim();
  if (preferred) {
    const st = await statNoThrow(preferred);
    if (st && st.isDirectory() && (await isDirReusableForMount(preferred))) {
      if (process.platform === 'win32') {
        const removed = await removeDirNoThrow(preferred);
        if (removed || !(await statNoThrow(preferred))) {
          return preferred;
        }
      } else {
        return preferred;
      }
    }
  }
  return resolveUniqueMountDir({ parentPath, mountName, startIndex });
}

function normalizeOpenlistMountPath(name, id) {
  const slug = ensureString(name)
    .trim()
    .replace(/[^\w\u4e00-\u9fa5-]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40);
  const base = slug || 'mount';
  return `/nascab/${base}_${id}`;
}

module.exports = {
  ensureString,
  isValidMountFolderName,
  checkDirReadableWritable,
  resolveUniqueMountDir,
  resolveMountDir,
  normalizeOpenlistMountPath,
};
