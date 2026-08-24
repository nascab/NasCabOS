const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');

async function list(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
    const { types, page, pageSize, stateList, keyword } = req.body || {};
    const logs = await fileService.getFileLogs(uid, types, page, pageSize, stateList, keyword);
    return ResponseUtil.success(req, res, logs, 'file.LOG_LIST_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.LOG_LIST_FAILED', 400, { error: err.message });
  }
}

async function clear(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    const { stateList } = req.body || {};
    await fileService.clearFileLogs(uid, stateList);
    return ResponseUtil.success(req, res, { ok: true }, 'file.LOG_CLEAR_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.LOG_CLEAR_FAILED', 400, { error: err.message });
  }
}

module.exports = {
  list,
  clear,
};
