const ResponseUtil = require('../../../apiUtils/responseUtil');
const userUtil = require('../../../../utils/userUtil');
const { hasPermission } = require('../../../../utils/permissionUtil');
const userShareFolderUtil = require('../../../../utils/userShareFolderUtil');
const userCustomPathUtil = require('../../../../utils/userCustomPathUtil');
const UserService = require('../../user/userService');
const fs = require('fs');
const path = require('path');
const { Worker } = require('worker_threads');

function _isAbsoluteLikePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\') || v.startsWith('\\')) return true;
  return /^[a-zA-Z]:[\\/]/.test(v);
}

const fileListWorkerPath = path.resolve(__dirname, '../../../../workers/fileList/listDirectoryWorker.js');

async function runFileListWorkerTask(action, payload, timeoutMs = 30000) {
  const worker = new Worker(fileListWorkerPath);
  let timeout = null;
  let settled = false;
  let terminatePromise = null;

  const terminateOnce = async () => {
    if (!terminatePromise) {
      terminatePromise = await worker.terminate().catch(() => {});
    }
    return terminatePromise;
  };

  try {
    if (typeof worker.unref === 'function') worker.unref();

    return await new Promise((resolve, reject) => {
      const cleanup = () => {
        worker.removeAllListeners('message');
        worker.removeAllListeners('error');
      };

      worker.once('message', async msg => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        await terminateOnce();
        if (msg && msg.ok) return resolve(msg.result);
        const errorMsg = msg && msg.error ? String(msg.error) : 'file.DIRECTORY_LIST_WORKER_ERROR';
        return reject(new Error(errorMsg));
      });

      worker.once('error', err => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        reject(err);
      });

      worker.once('exit', code => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        reject(new Error(`file.DIRECTORY_LIST_WORKER_EXITED:${code}`));
      });

      timeout = setTimeout(() => {
        if (settled) return;
        settled = true;
        cleanup();
        terminateOnce();
        reject(new Error('file.DIRECTORY_LIST_TIMEOUT'));
      }, timeoutMs);

      try {
        worker.postMessage({ action, payload });
      } catch (err) {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        reject(err);
      }
    });
  } finally {
    if (timeout) clearTimeout(timeout);
    await terminateOnce();
  }
}

async function add(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    const rawPath = req.body && req.body.path ? String(req.body.path).trim() : '';
    const rawName = req.body && req.body.name !== undefined && req.body.name !== null ? String(req.body.name).trim() : '';

    if (!rawName) {
      return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_NAME_REQUIRED', 400);
    }

    if (!rawPath || !_isAbsoluteLikePath(rawPath)) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }

    const resolved = path.resolve(rawPath);
    try {
      const st = await fs.promises.stat(resolved);
      if (!st.isDirectory()) {
        return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
      }
      await fs.promises.access(resolved, fs.constants.R_OK | fs.constants.X_OK);
    } catch (err) {
      if (err && err.code === 'ENOENT') {
        return ResponseUtil.error(req, res, 'file.FOLDER_NOT_EXIST', 404);
      }
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    if (!userUtil.isAdmin(req.user)) {
      let canView = await hasPermission(req.dbMain, req.user, ['download', 'view'], resolved);
      if (!canView) {
        const isUserShare = await userShareFolderUtil.isUserSharePath(resolved);
        if (isUserShare) canView = true;
      }
      if (!canView) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }
    }

    const current = await userCustomPathUtil.getUserCustomPaths(uid, { includeMissing: true });
    const merged = current.filter(i => i && i.path);
    const existedIndex = merged.findIndex(i => path.resolve(i.path) === resolved);

    if (rawName) {
      const wanted = rawName.trim().toLowerCase();
      const nameExists = merged.some((i, idx) => {
        if (idx == existedIndex) return false;
        const n = i && i.name ? String(i.name).trim().toLowerCase() : '';
        return n && n === wanted;
      });
      if (nameExists) {
        return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_NAME_EXISTS', 409);
      }
    }

    if (existedIndex >= 0) {
      return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_PATH_EXISTS', 409);
    }

    if (userUtil.isAdmin(req.user)) {
      try {
        const roots = await runFileListWorkerTask('getRoots', {});
        const rootPaths = (Array.isArray(roots) ? roots : [])
          .map(r => (r && r.path ? String(r.path).trim() : ''))
          .filter(Boolean)
          .map(p => path.resolve(p));
        if (rootPaths.includes(resolved)) {
          return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_PATH_EXISTS', 409);
        }
      } catch (_) {}
    } else {
      const userService = new UserService(req.dbMain);
      const visibleRoots = await userService.getUserVisiablePath(uid);
      const userShareFolders = await userShareFolderUtil.getUserShareFolders({ includeMissing: false });
      const sharePaths = userShareFolders.map(i => i.path).filter(Boolean);
      const existing = new Set(
        []
          .concat(Array.isArray(visibleRoots) ? visibleRoots : [])
          .concat(sharePaths)
          .map(p => (typeof p === 'string' && p.trim() ? path.resolve(p.trim()) : ''))
          .filter(Boolean)
      );
      if (existing.has(resolved)) {
        return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_PATH_EXISTS', 409);
      }
    }

    merged.push({ path: resolved, name: rawName });

    const ok = await userCustomPathUtil.saveUserCustomPaths(uid, merged);
    if (!ok) return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_SAVE_FAILED', 500);

    return ResponseUtil.success(
      req,
      res,
      {
        path: resolved,
        name: rawName,
      },
      'file.CUSTOM_PATH_ADD_SUCCESS',
      200
    );
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_SAVE_FAILED', 500, { error: err && err.message ? String(err.message) : String(err) });
  }
}

async function remove(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    const rawPath = req.body && req.body.path ? String(req.body.path).trim() : '';
    if (!rawPath || !_isAbsoluteLikePath(rawPath)) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }

    const resolved = path.resolve(rawPath);
    const current = await userCustomPathUtil.getUserCustomPaths(uid, { includeMissing: true });
    const filtered = (current || []).filter(i => i && i.path && path.resolve(i.path) !== resolved);
    const ok = await userCustomPathUtil.saveUserCustomPaths(uid, filtered);
    if (!ok) return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_SAVE_FAILED', 500);

    return ResponseUtil.success(req, res, { path: resolved }, 'file.CUSTOM_PATH_REMOVE_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.CUSTOM_PATH_SAVE_FAILED', 500, {
      error: err && err.message ? String(err.message) : String(err),
    });
  }
}

module.exports = {
  add,
  remove,
};
