const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');
const { hasPermission } = require('../../../../utils/permissionUtil');
const fs = require('fs');
const path = require('path');
const FileUtil = require('../../../../utils/fileUtil');

async function canMkdir(req, res) {
  try {
    const { base } = req.body || {};
    if (typeof base !== 'string' || !base.trim()) {
      return ResponseUtil.success(req, res, { supported: false }, 'common.SUCCESS', 200);
    }

    const resolvedBase = path.resolve(base.trim());
    // Windows: 磁盘根目录（如 E:\）在 isProtectedPath 中视为受保护，但 mkdir/check 接口允许在其下创建文件夹
    const isWinDriveRoot = process.platform === 'win32' && /^[a-zA-Z]:[\\/]*$/.test(path.normalize(resolvedBase));
    if (!isWinDriveRoot && FileUtil.isProtectedPath(resolvedBase)) {
      return ResponseUtil.success(req, res, { supported: false }, 'common.SUCCESS', 200);
    }

    try {
      const st = await fs.promises.stat(resolvedBase);
      if (!st.isDirectory()) {
        return ResponseUtil.success(req, res, { supported: false }, 'common.SUCCESS', 200);
      }
    } catch (_) {
      return ResponseUtil.success(req, res, { supported: false }, 'common.SUCCESS', 200);
    }

    const supported = await hasPermission(req.dbMain, req.user, 'upload', resolvedBase);
    return ResponseUtil.success(req, res, { supported }, 'common.SUCCESS', 200);
  } catch (_) {
    return ResponseUtil.success(req, res, { supported: false }, 'common.SUCCESS', 200);
  }
}

async function mkdir(req, res) {
  try {
    const { base, name } = req.body || {};
    if (typeof base !== 'string' || typeof name !== 'string' || !name.trim()) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }
    await fileService.mkdir(base, name.trim());
    return ResponseUtil.success(req, res, { ok: true }, 'file.MKDIR_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.MKDIR_FAILED', 400, { error: err.message });
  }
}

module.exports = {
  canMkdir,
  mkdir,
};
