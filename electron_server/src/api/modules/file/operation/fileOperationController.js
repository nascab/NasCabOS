const ResponseUtil = require('../../../apiUtils/responseUtil');
const { hasPermission } = require('../../../../utils/permissionUtil');
const userUtil = require('../../../../utils/userUtil');
const fs = require('fs');
const path = require('path');
const tableFileLog = require('../../../../db/table/tableFileLog');
const fileService = require('../core/fileService');
const FileUtil = require('../../../../utils/fileUtil');
const archiver = require('archiver');
const Logger = require('../../../../utils/logger');

/**
 * 单文件 Range 请求解析（用于 P2P/Web 断点续传）。
 * @returns {{ start: number, end: number, chunkSize: number } | null}
 */
function parseHttpRangeSingleFile(rangeHeader, fileSize) {
  if (rangeHeader == null || !Number.isFinite(fileSize) || fileSize <= 0) return null;
  const raw = String(rangeHeader).trim();
  const m = /^bytes=(\d*)-(\d*)$/i.exec(raw);
  if (!m) return null;
  let start = m[1] === '' ? NaN : parseInt(m[1], 10);
  let end = m[2] === '' ? NaN : parseInt(m[2], 10);
  if (!Number.isFinite(start)) start = 0;
  if (start < 0 || start >= fileSize) return null;
  if (!Number.isFinite(end)) end = fileSize - 1;
  if (end < start) return null;
  if (end >= fileSize) end = fileSize - 1;
  return { start, end, chunkSize: end - start + 1 };
}

async function download(req, res) {
  try {
    let { paths, path: singlePath } = req.query;

    if (!paths && !singlePath) {
      paths = req.body.paths;
      singlePath = req.body.path;
    }

    if (singlePath && (!paths || paths.length === 0)) {
      paths = [singlePath];
    }

    if (typeof paths === 'string') paths = [paths];

    if (!paths || paths.length === 0) {
      return ResponseUtil.error(req, res, 'file.NO_FILE_SELECTED');
    }
    for (const p of paths) {
      const hasPerm = await hasPermission(req.dbMain, req.user, 'download', p);
      if (!hasPerm) {
        return ResponseUtil.error(req, res, 'file.PERMISSION_DENIED',403);
      }
    }
    if (paths.length === 1) {
      const p = paths[0];
      try {
        const stat = await fs.promises.stat(p);
        if (!stat.isDirectory()) {
          const fileSize = stat.size;
          res.setHeader('Accept-Ranges', 'bytes');
          const range = parseHttpRangeSingleFile(req.headers.range, fileSize);
          if (range) {
            if (range.start >= fileSize) {
              res.status(416);
              res.setHeader('Content-Range', `bytes */${fileSize}`);
              return res.end();
            }
            const stream = fs.createReadStream(p, { start: range.start, end: range.end });
            res.status(206);
            res.setHeader('Content-Range', `bytes ${range.start}-${range.end}/${fileSize}`);
            res.setHeader('Content-Length', String(range.chunkSize));
            res.attachment(path.basename(p));
            stream.on('error', err => {
              const code = err && err.code != null ? String(err.code) : '';
              if (code === 'EPIPE' || code === 'ECONNRESET' || code === 'ECONNABORTED') return;
              if (!res.headersSent) {
                ResponseUtil.error(req, res, 'file.DOWNLOAD_ERROR');
              } else {
                try {
                  res.destroy(err instanceof Error ? err : new Error('stream error'));
                } catch (_) {}
              }
            });
            stream.pipe(res);
            return;
          }
          return res.download(p, err => {
            if (err) {
              const code = err && err.code != null ? String(err.code) : '';
              if (code === 'EPIPE' || code === 'ECONNRESET' || code === 'ECONNABORTED') return;
              console.log('Download error:', err);
              if (res.headersSent) {
              } else {
                return ResponseUtil.error(req, res, 'file.DOWNLOAD_ERROR');
              }
            }
          });
        }
      } catch (e) {
        return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND');
      }
    }

    const archive = archiver('zip', {
      zlib: { level: 1 },
    });

    let zipName = 'download.zip';
    if (paths.length === 1) {
      zipName = `${path.basename(paths[0])}.zip`;
    }
    res.attachment(zipName);

    let stopped = false;
    const isClientAbortLikeError = err => {
      const code = err && err.code != null ? String(err.code) : '';
      return code === 'EPIPE' || code === 'ECONNRESET' || code === 'ECONNABORTED' || code === 'ERR_STREAM_PREMATURE_CLOSE';
    };
    const stop = err => {
      if (stopped) return;
      stopped = true;
      try {
        archive.abort();
      } catch (_) {}
      if (isClientAbortLikeError(err) || req.aborted || res.destroyed) {
        try {
          if (!res.destroyed) res.destroy();
        } catch (_) {}
        return;
      }
      Logger.error('Archive error', err);
      if (!res.headersSent) {
        res.status(500).send({ error: err && err.message ? err.message : 'Archive error' });
        return;
      }
      res.destroy(err instanceof Error ? err : new Error('Archive error'));
    };

    archive.on('error', stop);
    res.on('error', stop);
    res.on('close', () => {
      if (stopped) return;
      stopped = true;
      try {
        archive.abort();
      } catch (_) {}
    });

    archive.pipe(res);

    for (const p of paths) {
      try {
        const stat = await fs.promises.stat(p);
        const name = path.basename(p);
        if (stat.isDirectory()) {
          archive.directory(p, name);
        } else {
          archive.file(p, { name });
        }
      } catch (e) {
        Logger.warn(`Skipping file ${p} in zip: ${e.message}`);
      }
    }

    await archive.finalize();
  } catch (err) {
    const code = err && err.code != null ? String(err.code) : '';
    if (code === 'EPIPE' || code === 'ECONNRESET' || code === 'ECONNABORTED' || code === 'ERR_STREAM_PREMATURE_CLOSE' || req.aborted || res.destroyed) {
      try {
        if (!res.destroyed) res.destroy();
      } catch (_) {}
      return;
    }
    Logger.error('Download error', err);
    if (!res.headersSent) {
      ResponseUtil.error(req, res, 'file.DOWNLOAD_FAILED');
      return;
    }
    res.destroy(err instanceof Error ? err : new Error('Download error'));
  }
}

async function handleFileOperation(req, res, type) {
  try {
    const { paths, targetPath } = req.body || {};
    if (!Array.isArray(paths) || paths.length === 0 || !targetPath) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    const canWriteTarget = await hasPermission(req.dbMain, req.user, 'upload', targetPath);
    if (!canWriteTarget) {
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    for (const p of paths) {
      if (type === tableFileLog.TYPE_MOVE && FileUtil.isProtectedPath(p)) {
        console.log('系统保护路径 无法操作');
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
      }

      const canRead = await hasPermission(req.dbMain, req.user, 'download', p);
      if (!canRead) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }
      if (type === tableFileLog.TYPE_MOVE) {
        const canDelete = await hasPermission(req.dbMain, req.user, 'delete', p);
        if (!canDelete) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
      }
    }

    try {
      fileService.checkSourceContainTarget(paths, targetPath);
      await fileService.checkTargetConflict(paths, targetPath);
    } catch (e) {
      if (e.message === 'file.TARGET_IS_SOURCE' || e.message === 'file.TARGET_IS_SUBDIRECTORY') {
        return ResponseUtil.error(req, res, e.message, 400);
      }
      return ResponseUtil.error(req, res, 'file.TARGET_EXISTS', 400, { error: e.message });
    }
    await fileService.addFileLog(uid, type, paths, targetPath, tableFileLog.STATE_WAIT);

    if (process.send) {
      process.send({ type: 'startFileWorker' });
    }

    return ResponseUtil.success(req, res, { ok: true }, 'file.OPERATION_QUEUED', 200);
  } catch (err) {
    console.log(err);
    return ResponseUtil.error(req, res, 'file.OPERATION_FAILED', 400, { error: err.message });
  }
}

async function copy(req, res) {
  await handleFileOperation(req, res, tableFileLog.TYPE_COPY);
}

async function move(req, res) {
  await handleFileOperation(req, res, tableFileLog.TYPE_MOVE);
}

async function cancelFileOperation(req, res) {
  try {
    const uid = req.user && req.user.id;
    if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

    const { id } = req.body || {};
    if (!id) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

    const isAdmin = userUtil.isAdmin(req.user);
    await fileService.cancelFileLog(uid, id, { allowAnyUser: isAdmin });
    return ResponseUtil.success(req, res, { ok: true }, 'file.OPERATION_CANCELLED', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.OPERATION_CANCEL_FAILED', 400, {
      error: err.message,
    });
  }
}

module.exports = {
  download,
  handleFileOperation,
  copy,
  move,
  cancelFileOperation,
};
