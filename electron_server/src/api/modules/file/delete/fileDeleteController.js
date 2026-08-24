const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');
const { hasPermission } = require('../../../../utils/permissionUtil');
const fs = require('fs');
const path = require('path');
const tableFileLog = require('../../../../db/table/tableFileLog');
const FileUtil = require('../../../../utils/fileUtil');

async function remove(req, res) {
  try {
    const { paths = [], recycle = false, deleteScrapeFiles = false } = req.body || {};
    if (!Array.isArray(paths) || paths.length === 0) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const deleteScrapeFilesBool = deleteScrapeFiles === true || deleteScrapeFiles === 1 || deleteScrapeFiles === '1';
    let targets = fileService.mergeUniquePaths(paths);
    if (deleteScrapeFilesBool) {
      const extra = [];
      for (const p of targets) {
        extra.push(...fileService.getScrapeSidecarPathsForFilePath(p));
      }
      targets = fileService.mergeUniquePaths([...targets, ...extra]);
    }

    for (const p of targets) {
      if (typeof p === 'string' && p) {
        if (FileUtil.isProtectedPath(p)) {
          return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
        }

        const canDelete = await hasPermission(req.dbMain, req.user, 'delete', p);
        if (!canDelete) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
      }
    }

    const existedTargets = [];
    for (const p of targets) {
      const full = typeof p === 'string' ? path.resolve(p) : '';
      if (!full) continue;
      try {
        await fs.promises.access(full, fs.constants.F_OK);
        existedTargets.push(p);
      } catch (_) {}
    }

    if (existedTargets.length > 0) {
      await fileService.deleteEntries(existedTargets, recycle);

      const deletedTargets = [];
      if (recycle) {
        const waitUntilNotExists = async (p, timeoutMs = 800, intervalMs = 80) => {
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

        const checks = await Promise.all(
          existedTargets.map(async p => {
            const ok = await waitUntilNotExists(p);
            return ok ? p : null;
          })
        );
        deletedTargets.push(...checks.filter(Boolean));
      } else {
        for (const p of existedTargets) {
          const full = path.resolve(p);
          try {
            await fs.promises.access(full, fs.constants.F_OK);
          } catch (_) {
            deletedTargets.push(p);
          }
        }
      }

      const uid = req.user && req.user.id;
      if (deletedTargets.length > 0) {
        await fileService.addFileLog(uid, tableFileLog.TYPE_DELETE, deletedTargets, null, tableFileLog.STATE_SUCCESS, recycle ? 'RECYCLE' : 'DELETE');
      }
    }
    return ResponseUtil.success(req, res, { ok: true }, 'file.DELETE_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.DELETE_FAILED', 400, { error: err.message });
  }
}

module.exports = {
  remove,
};
