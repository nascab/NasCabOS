const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');
const { hasPermission } = require('../../../../utils/permissionUtil');

async function list(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
    const items = await fileService.listFavoritesByUid(req.dbMain, uid);
    return ResponseUtil.success(req, res, items, 'file.FAV_LIST_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.FAV_LIST_FAILED', 400, { error: err.message });
  }
}

async function add(req, res) {
  try {
    const { path: p, paths } = req.body || {};
    const targets = [];
    if (Array.isArray(paths)) {
      targets.push(...paths);
    } else if (p && typeof p === 'string') {
      targets.push(p);
    }

    if (targets.length === 0) return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);

    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    for (const t of targets) {
      if (typeof t === 'string' && t) {
        const canView = await hasPermission(req.dbMain, req.user, 'view', t);
        if (!canView) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
        await fileService.addFavoriteByUid(req.dbMain, uid, t);
      }
    }
    return ResponseUtil.success(req, res, { ok: true }, 'file.FAV_ADD_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.FAV_ADD_FAILED', 400, { error: err.message });
  }
}

async function remove(req, res) {
  try {
    const { path: p, paths } = req.body || {};
    const targets = [];
    if (Array.isArray(paths)) {
      targets.push(...paths);
    } else if (p && typeof p === 'string') {
      targets.push(p);
    }

    if (targets.length === 0) return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);

    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    for (const t of targets) {
      if (typeof t === 'string' && t) {
        await fileService.removeFavoriteByUid(req.dbMain, uid, t);
      }
    }
    return ResponseUtil.success(req, res, { ok: true }, 'file.FAV_REMOVE_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.FAV_REMOVE_FAILED', 400, { error: err.message });
  }
}

module.exports = {
  list,
  add,
  remove,
};
