// 桌面 UI：数据库文件占用合计（启动后首次读取时计算并缓存，避免反复遍历磁盘）
const fs = require('fs');
const dbUtil = require('../db/dbUtil');

let cachedTotalBytes = null;

function sumSqlitePathGroupBytes(dbPath) {
  let sum = 0;
  const paths = [dbPath, `${dbPath}-wal`, `${dbPath}-shm`];
  for (const p of paths) {
    try {
      if (fs.existsSync(p)) sum += fs.statSync(p).size;
    } catch (_) {}
  }
  return sum;
}

function computeDatabaseFilesTotalBytes() {
  const paths = Object.values(dbUtil.DB_PATHS);
  let total = 0;
  for (const p of paths) {
    total += sumSqlitePathGroupBytes(p);
  }
  return total;
}

function getSnapshotDatabaseTotalBytes() {
  if (cachedTotalBytes === null) {
    cachedTotalBytes = computeDatabaseFilesTotalBytes();
  }
  return cachedTotalBytes;
}

function refreshDatabaseTotalBytesCache() {
  cachedTotalBytes = computeDatabaseFilesTotalBytes();
  return cachedTotalBytes;
}

module.exports = {
  getSnapshotDatabaseTotalBytes,
  refreshDatabaseTotalBytesCache,
  computeDatabaseFilesTotalBytes,
};
