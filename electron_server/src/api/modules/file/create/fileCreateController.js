const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');
const { hasPermission } = require('../../../../utils/permissionUtil');
const fs = require('fs');
const path = require('path');
const FileUtil = require('../../../../utils/fileUtil');

function normalizeCreateFilename(inputName, type) {
  const raw = typeof inputName === 'string' ? inputName.trim() : '';
  if (!raw) return null;
  if (/[\\/]/.test(raw)) return null;
  if (path.isAbsolute(raw)) return null;

  const rawType = typeof type === 'string' ? type.trim().toLowerCase() : '';
  const allowedByType = rawType === 'txt' ? '.txt' : rawType === 'md' ? '.md' : '';

  const ext = path.extname(raw).toLowerCase();
  if (ext) {
    if (!allowedByType) return null;
    if (ext !== allowedByType) return null;
    return raw;
  }
  if (!allowedByType) return null;
  return `${raw}${allowedByType}`;
}

async function create(req, res) {
  try {
    const { base, name, type } = req.body || {};
    if (typeof base !== 'string') {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const resolvedBase = path.resolve(base.trim());
    if (!resolvedBase) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }
    if (FileUtil.isProtectedPath(resolvedBase)) {
      return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
    }

    const filename = normalizeCreateFilename(name, type);
    if (!filename) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const canWriteByPermission = await hasPermission(req.dbMain, req.user, 'upload', resolvedBase);
    if (!canWriteByPermission) {
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    const st = await fs.promises.stat(resolvedBase).catch(() => null);
    if (!st || !st.isDirectory()) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }

    try {
      await fs.promises.access(resolvedBase, fs.constants.W_OK | fs.constants.X_OK);
    } catch (_) {
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    const created = await fileService.createFile(resolvedBase, filename, '');
    return ResponseUtil.success(req, res, created, 'common.SUCCESS', 200);
  } catch (err) {
    const msgKey = err && err.message ? String(err.message) : 'common.ERROR';
    const status = msgKey === 'file.PATH_ALREADY_EXISTS' ? 409 : 400;
    return ResponseUtil.error(req, res, msgKey, status, { error: err && err.message ? String(err.message) : String(err) });
  }
}

module.exports = {
  create,
};
