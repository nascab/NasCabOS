const ResponseUtil = require('../../../apiUtils/responseUtil');
const tableFileRecent = require('../../../../db/table/tableFileRecent');

async function clear(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
    const connection = { knex: req.dbMain };
    await tableFileRecent.deleteAllByUid(uid, connection);
    return ResponseUtil.success(req, res, { ok: true }, 'file.RECENT_CLEAR_SUCCESS', 200);
  } catch (err) {
    console.log(err);
    return ResponseUtil.error(req, res, 'file.RECENT_CLEAR_FAILED', 400, {
      error: err.message,
    });
  }
}

module.exports = {
  clear,
};
