const ResponseUtil = require('../../../apiUtils/responseUtil');
const { hasPermission } = require('../../../../utils/permissionUtil');
const fileService = require('../core/fileService');
const tableFileLog = require('../../../../db/table/tableFileLog');
const FileUtil = require('../../../../utils/fileUtil');

async function rename(req, res) {
  try {
    const { path: oldPath, newName } = req.body || {};
    if (typeof oldPath !== 'string' || typeof newName !== 'string' || !newName.trim()) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    if (FileUtil.isProtectedPath(oldPath)) {
      return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
    }

    const canWrite = await hasPermission(req.dbMain, req.user, 'update', oldPath);
    if (!canWrite) {
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    const result = await fileService.rename(oldPath, newName.trim());
    const uid = req.user && req.user.id;
    await fileService.addFileLog(uid, tableFileLog.TYPE_RENAME, [oldPath], newName, tableFileLog.STATE_SUCCESS);

    return ResponseUtil.success(req, res, result, 'file.RENAME_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.RENAME_FAILED', 400, { error: err.message });
  }
}

module.exports = {
  rename,
};
