const ResponseUtil = require('../../../apiUtils/responseUtil');
const userShareFolderUtil = require('../../../../utils/userShareFolderUtil');
const fs = require('fs');
const path = require('path');

function _isAbsoluteLikePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\') || v.startsWith('\\')) return true;
  return /^[a-zA-Z]:[\\/]/.test(v);
}

async function list(req, res) {
  try {
    const items = await userShareFolderUtil.getUserShareFoldersWithStats();
    return ResponseUtil.success(req, res, { items }, 'file.USER_SHARE_LIST_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.USER_SHARE_LIST_FAILED', 500, { error: err && err.message ? String(err.message) : String(err) });
  }
}

async function add(req, res) {
  try {
    const rawPath = req.body && req.body.path ? String(req.body.path).trim() : '';
    const rawName = req.body && req.body.name !== undefined && req.body.name !== null ? String(req.body.name).trim() : '';
    const allowDownload =
      req.body &&
      (req.body.allowDownload === true ||
        req.body.allowDownload === 1 ||
        String(req.body.allowDownload || '')
          .trim()
          .toLowerCase() === 'true');

    if (!rawPath || !_isAbsoluteLikePath(rawPath)) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }

    const resolved = path.resolve(rawPath);
    try {
      const st = await fs.promises.stat(resolved);
      if (!st.isDirectory()) {
        return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
      }
    } catch (_) {
      return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST', 404);
    }

    const current = await userShareFolderUtil.getUserShareFolders({ includeMissing: true });
    const merged = current.filter(i => i && i.path);
    const existed = merged.some(i => path.resolve(i.path) === resolved);
    if (!existed) {
      merged.push({ path: resolved, name: rawName || null, allowDownload });
      const ok = await userShareFolderUtil.saveUserShareFolders(merged);
      if (!ok) return ResponseUtil.error(req, res, 'file.USER_SHARE_SAVE_FAILED', 500);
    }
    return ResponseUtil.success(req, res, { path: resolved }, 'file.USER_SHARE_ADD_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.USER_SHARE_SAVE_FAILED', 500, { error: err && err.message ? String(err.message) : String(err) });
  }
}

async function remove(req, res) {
  try {
    const rawPath = req.body && req.body.path ? String(req.body.path).trim() : '';
    if (!rawPath || !_isAbsoluteLikePath(rawPath)) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }
    const resolved = path.resolve(rawPath);

    const current = await userShareFolderUtil.getUserShareFolders({ includeMissing: true });
    const filtered = (current || []).filter(i => i && i.path && path.resolve(i.path) !== resolved);
    const ok = await userShareFolderUtil.saveUserShareFolders(filtered);
    if (!ok) return ResponseUtil.error(req, res, 'file.USER_SHARE_SAVE_FAILED', 500);
    return ResponseUtil.success(req, res, { path: resolved }, 'file.USER_SHARE_REMOVE_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.USER_SHARE_SAVE_FAILED', 500, { error: err && err.message ? String(err.message) : String(err) });
  }
}

async function setAllowDownload(req, res) {
  try {
    const rawPath = req.body && req.body.path ? String(req.body.path).trim() : '';
    if (!rawPath || !_isAbsoluteLikePath(rawPath)) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }
    const resolved = path.resolve(rawPath);

    const allowDownload = req.body && (req.body.allowDownload === true || req.body.allowDownload === 1 || String(req.body.allowDownload).trim().toLowerCase() === 'true');

    const current = await userShareFolderUtil.getUserShareFolders({ includeMissing: true });
    const list = Array.isArray(current) ? current : [];
    const next = [];
    let found = false;
    for (const item of list) {
      if (!item || !item.path) continue;
      const p = path.resolve(item.path);
      if (p === resolved) {
        found = true;
        next.push({
          path: p,
          name: item.name || null,
          allowDownload,
        });
      } else {
        next.push({
          path: p,
          name: item.name || null,
          allowDownload: !!item.allowDownload,
        });
      }
    }
    if (!found) {
      return ResponseUtil.error(req, res, 'file.USER_SHARE_NOT_FOUND', 404);
    }
    const ok = await userShareFolderUtil.saveUserShareFolders(next);
    if (!ok) return ResponseUtil.error(req, res, 'file.USER_SHARE_SAVE_FAILED', 500);
    return ResponseUtil.success(req, res, { path: resolved, allowDownload }, 'file.USER_SHARE_UPDATE_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.USER_SHARE_SAVE_FAILED', 500, { error: err && err.message ? String(err.message) : String(err) });
  }
}

module.exports = {
  list,
  add,
  remove,
  setAllowDownload,
};
