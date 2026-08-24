const path = require('path');
const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');
const { isPathInRoot } = require('./appAccessScopeUtil');

const MOUNT_ROOT_CACHE_MS = 3000;
let mountRootsCache = { at: 0, roots: [] };

/** UNC、路径中含 IPv4、常见远程协议片段等 */
function isLiteralNetworkPath(filePath) {
  const s = path.resolve(String(filePath || ''));
  if (!s) return false;

  if (process.platform === 'win32' && s.startsWith('\\\\')) return true;

  if (/(?:^|[\\/])(\d{1,3}\.){3}\d{1,3}(?:[\\/]|$)/.test(s)) return true;

  if (/(?:^|[\\/])(?:smb|ftp|sftp|webdav|nfs|afp|http|https):/i.test(s)) return true;

  return false;
}

function fileMountCandidateRoots(parentPath, mountName) {
  const parent = path.resolve(String(parentPath || ''));
  const name = String(mountName || '').trim();
  if (!parent || !name) return [];
  const roots = [];
  for (let idx = 0; idx < 50; idx++) {
    const suffix = idx === 0 ? '' : `_${idx}`;
    roots.push(path.join(parent, `${name}${suffix}`));
  }
  return roots;
}

async function loadMountRootsFromDb() {
  const roots = [];
  try {
    if (!knexUtil.hasConnection(dbUtil.DB_PATHS.MAIN_DB)) {
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    }
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);

    const fileMounts = await knex('file_mount')
      .where({ status: 'running' })
      .select('mount_path', 'name')
      .catch(() => []);
    for (const row of fileMounts || []) {
      roots.push(...fileMountCandidateRoots(row.mount_path, row.name));
    }

    const openlistMounts = await knex('openlist_mount')
      .where({ status: 'running' })
      .select('local_mount_dir', 'mount_path', 'name')
      .catch(() => []);
    for (const row of openlistMounts || []) {
      const local = String(row.local_mount_dir || '').trim();
      if (local) {
        roots.push(path.resolve(local));
      } else {
        roots.push(...fileMountCandidateRoots(row.mount_path, row.name));
      }
    }
  } catch (_) {}

  return roots;
}

async function getMountRoots() {
  const now = Date.now();
  if (now - mountRootsCache.at < MOUNT_ROOT_CACHE_MS && Array.isArray(mountRootsCache.roots)) {
    return mountRootsCache.roots;
  }
  const roots = await loadMountRootsFromDb();
  mountRootsCache = { at: now, roots };
  return roots;
}

function isUnderAnyRoot(filePath, roots) {
  const target = path.resolve(String(filePath || ''));
  if (!target || !Array.isArray(roots) || roots.length === 0) return false;
  return roots.some(root => isPathInRoot(target, root));
}

/** 网盘/rclone 挂载目录或明显网络路径，缩略图应走 worker 顺序生成 */
async function isSlowIoPathForTiny(filePath) {
  const resolved = path.resolve(String(filePath || ''));
  if (!resolved) return false;
  if (isLiteralNetworkPath(resolved)) return true;
  const roots = await getMountRoots();
  return isUnderAnyRoot(resolved, roots);
}

function clearMountRootsCache() {
  mountRootsCache = { at: 0, roots: [] };
}

module.exports = {
  isLiteralNetworkPath,
  isSlowIoPathForTiny,
  clearMountRootsCache,
  getMountRoots,
};
