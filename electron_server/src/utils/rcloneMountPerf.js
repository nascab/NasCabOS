const fs = require('fs');
const path = require('path');
const config = require('../config/config');

function ensureString(value) {
  return value == null ? '' : String(value);
}

/** 各网盘挂载独立的 rclone VFS 缓存目录 */
function getVfsCacheRoot() {
  return path.join(config.getCachePath(), 'openlist_rclone_vfs');
}

function ensureVfsCacheDir(mountId) {
  const dir = path.join(getVfsCacheRoot(), String(mountId));
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

/**
 * rclone mount 默认性能参数（经本地 OpenList WebDAV 访问云盘）。
 * 启用 VFS 写缓存、更大缓冲与并行读块，改善 Finder/资源管理器中的上传下载体验。
 */
function buildDefaultMountPerfArgs({ vfsCacheDir } = {}) {
  const cacheDir = ensureString(vfsCacheDir).trim();
  const args = [
    '--vfs-cache-mode=writes',
    '--buffer-size=32M',
    '--vfs-read-ahead=128M',
    '--vfs-read-chunk-size=32M',
    '--vfs-read-chunk-size-limit=256M',
    '--vfs-read-chunk-streams=4',
    '--vfs-cache-max-size=1G',
    '--vfs-cache-max-age=24h',
    '--vfs-write-back=10s',
    '--attr-timeout=30s',
    '--dir-cache-time=2m',
    '--low-level-retries=10',
  ];
  if (cacheDir) {
    args.unshift(`--cache-dir=${cacheDir}`);
  }
  return args;
}

module.exports = {
  getVfsCacheRoot,
  ensureVfsCacheDir,
  buildDefaultMountPerfArgs,
};
