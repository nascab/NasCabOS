const fs = require('fs');
const path = require('path');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookListService = require('./bookListService');
const fileService = require('../../file/core/fileService');
const tableFileLog = require('../../../../db/table/tableFileLog');
const { hasPermission } = require('../../../../utils/permissionUtil');
const FileUtil = require('../../../../utils/fileUtil');
const { getLocalizedMessage } = require('../../../../utils/i18nUtil');

class BookListController {
  async list(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new BookListService(req.dbBook);
      const data = await service.listPaged(body, user);
      return ResponseUtil.success(req, res, data, 'book.BOOK_LIST_FETCH_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'book.BOOK_LIST_FETCH_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'book.BOOK_LIST_FETCH_FAILED' : msgKey, statusCode);
    }
  }

  async deleteEntries(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const inputPaths = body.paths;
      const recycleRaw = body.recycle ?? false;
      const recycle = recycleRaw === true || recycleRaw === 1 || recycleRaw === '1';

      if (!Array.isArray(inputPaths) || inputPaths.length === 0) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const rawTargets = inputPaths.map(v => String(v || '').trim()).filter(Boolean);
      const targets = Array.from(new Set(rawTargets))
        .map(p => path.resolve(p))
        .filter(Boolean);

      if (targets.length === 0) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const service = new BookListService(req.dbBook);
      const roots = await service.getValidPaths(user);
      if (!roots || roots.length === 0) {
        return ResponseUtil.error(req, res, 'book.BOOK_SOURCE_LIST_EMPTY', 400);
      }

      const isUnderAnyRoot = (filePath, rootList) => {
        const resolved = filePath ? path.resolve(String(filePath)) : '';
        if (!resolved) return false;
        const list = Array.isArray(rootList) ? rootList.map(p => path.resolve(String(p || ''))).filter(Boolean) : [];
        for (const root of list) {
          if (resolved === root) return true;
          const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
          if (resolved.startsWith(prefix)) return true;
        }
        return false;
      };

      for (const p of targets) {
        if (FileUtil.isProtectedPath(p)) {
          return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
        }
        if (!isUnderAnyRoot(p, roots)) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
        const canDelete = await hasPermission(req.dbMain, user, 'delete', p);
        if (!canDelete) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
      }

      const existedTargets = [];
      const missingTargets = [];
      for (const p of targets) {
        try {
          await fs.promises.access(p, fs.constants.F_OK);
          existedTargets.push(p);
        } catch (_) {
          missingTargets.push(p);
        }
      }

      const deletedTargets = [];
      const failedTargets = [];
      if (existedTargets.length > 0) {
        await fileService.deleteEntries(existedTargets, recycle);

        const waitUntilNotExists = async (p, timeoutMs = 3000, intervalMs = 120) => {
          const full = path.resolve(p);
          const deadline = Date.now() + timeoutMs;
          while (Date.now() < deadline) {
            try {
              await fs.promises.access(full, fs.constants.F_OK);
            } catch (_) {
              return true;
            }
            await new Promise(resolve => setTimeout(resolve, intervalMs));
          }
          try {
            await fs.promises.access(full, fs.constants.F_OK);
            return false;
          } catch (_) {
            return true;
          }
        };

        if (recycle) {
          const checks = await Promise.all(
            existedTargets.map(async p => {
              const ok = await waitUntilNotExists(p);
              return ok ? p : null;
            })
          );
          deletedTargets.push(...checks.filter(Boolean));
        } else {
          for (const p of existedTargets) {
            try {
              await fs.promises.access(path.resolve(p), fs.constants.F_OK);
              failedTargets.push(p);
            } catch (_) {
              deletedTargets.push(p);
            }
          }
        }

        if (recycle) {
          const deletedSet = new Set(deletedTargets);
          for (const p of existedTargets) {
            if (!deletedSet.has(p)) failedTargets.push(p);
          }
        }
      }

      const cleanedTargets = Array.from(new Set([...missingTargets, ...deletedTargets]));
      const affected = cleanedTargets.length > 0 ? await service.deleteIndexesByFullPaths(cleanedTargets) : 0;

      const data = {
        cleaned_paths: cleanedTargets,
        failed_paths: failedTargets,
        affected,
      };

      if (failedTargets.length > 0) {
        const key = recycle ? 'book.BOOK_TRASH_FAILED' : 'file.DELETE_FAILED';
        return res.status(400).json({
          success: false,
          message: getLocalizedMessage(req, key),
          code: key,
          data,
        });
      }

      if (deletedTargets.length > 0) {
        await fileService.addFileLog(uid, tableFileLog.TYPE_DELETE, deletedTargets, null, tableFileLog.STATE_SUCCESS, recycle ? 'RECYCLE' : 'DELETE');
      }

      return ResponseUtil.success(req, res, data, 'file.DELETE_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'file.DELETE_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'file.DELETE_FAILED' : msgKey, statusCode);
    }
  }

  async count(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new BookListService(req.dbBook);
      const data = await service.getVisibleIndexCounts(body, user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new BookListController();
