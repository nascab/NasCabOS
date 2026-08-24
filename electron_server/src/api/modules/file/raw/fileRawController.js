const fs = require('fs');
const path = require('path');
const sharpUtils = require('../../../../utils/sharpUtils');
const config = require('../../../../config/config');
const tableFileRecent = require('../../../../db/table/tableFileRecent');
const tableConfig = require('../../../../db/table/tableConfig');
const { hasPermission } = require('../../../../utils/permissionUtil');
const { getLocalizedMessage } = require('../../../../utils/i18nUtil');
const { getAppSpecifiedRoots, isPathAllowedByRoots } = require('../../../../utils/appAccessScopeUtil');

/** rawFile 直链发送累计（进程内，开发观测用；按当前文件路径分别累计） */
const rawFileSendStats = {
  currentFilePath: null,
  requestCount: 0,
  totalBytesSent: 0,
};

function resetRawFileSendStatsForPath(fullPath) {
  rawFileSendStats.currentFilePath = path.resolve(fullPath);
  rawFileSendStats.requestCount = 0;
  rawFileSendStats.totalBytesSent = 0;
}

function ensureRawFileSendStatsForPath(fullPath) {
  const resolved = path.resolve(fullPath);
  if (rawFileSendStats.currentFilePath !== resolved) {
    resetRawFileSendStatsForPath(resolved);
  }
}

function formatMb(n) {
  return Number.isFinite(n) && n >= 0 ? (n / 1024 / 1024).toFixed(4) : null;
}

/** 观测 Range / 响应长度（sendFile 由 express send 处理 206/304） */
function sendRawFileWithObservability(req, res, fullPath) {
  ensureRawFileSendStatsForPath(fullPath);
  const rangeHeader =
    (typeof req.get === 'function' ? req.get('Range') : null) || req.headers.range || null;
  let bytesActuallySent = 0;
  let closedLogged = false;
  const origWrite = res.write.bind(res);
  const origEnd = res.end.bind(res);
  res.write = (chunk, ...args) => {
    if (chunk) bytesActuallySent += Buffer.isBuffer(chunk) ? chunk.length : Buffer.byteLength(chunk);
    return origWrite(chunk, ...args);
  };
  res.end = (chunk, ...args) => {
    if (chunk) bytesActuallySent += Buffer.isBuffer(chunk) ? chunk.length : Buffer.byteLength(chunk);
    return origEnd(chunk, ...args);
  };
  const logOnClose = () => {
    if (closedLogged) return;
    closedLogged = true;

    rawFileSendStats.requestCount += 1;
    rawFileSendStats.totalBytesSent += bytesActuallySent;

    const contentLength = res.getHeader('Content-Length');
    const contentRange = res.getHeader('Content-Range');
    const declaredLen = contentLength != null && contentLength !== '' ? Number(contentLength) : NaN;
    const event = res.writableFinished ? 'finish' : 'close';
    if (process.env.NODE_ENV === 'development') {
      console.log('rawFile sendFile', {
        event,
        range: rangeHeader || '(none)',
        status: res.statusCode,
        writableFinished: res.writableFinished,
        contentLength: contentLength != null ? String(contentLength) : null,
        contentRange: contentRange != null ? String(contentRange) : null,
        declaredMb: formatMb(declaredLen),
        sentMb: formatMb(bytesActuallySent),
        sentBytes: bytesActuallySent,
        totalSentMb: formatMb(rawFileSendStats.totalBytesSent),
        totalSentBytes: rawFileSendStats.totalBytesSent,
        totalRequests: rawFileSendStats.requestCount,
        file: path.basename(fullPath),
      });
    }
  };
  res.once('close', logOnClose);
  return res.sendFile(fullPath, err => {
    if (err && !res.headersSent) {
      if (err.code === 'ENOENT') return res.status(404).send('File not found');
      return res.status(500).send(err.message || 'sendFile error');
    }
  });
}

async function getRawFile(req, res) {
  try {
    const { path: pathUrl, download, size, quality, raw, code } = req.query;
    console.log("raw file request", req.query);
    if (!pathUrl) return res.status(400).send('Missing path');

    const fullPath = path.resolve(pathUrl);
    // const appSpecifiedRoots = await getAppSpecifiedRoots();
    // if (appSpecifiedRoots !== null && !isPathAllowedByRoots(fullPath, appSpecifiedRoots)) {
    //   return res.status(403).send(getLocalizedMessage(req, 'auth.PERMISSION_DENIED'));
    // }
    const filename = path.basename(fullPath);
    const ext = path.extname(fullPath).toLowerCase();

    try {
      const uid = req.user && req.user.id;
      if (uid && typeof pathUrl === 'string' && pathUrl) {
        await tableFileRecent.upsertRecent(uid, fullPath, { knex: req.dbMain });
      }
    } catch (_) {}
    try {
      await fs.promises.access(fullPath, fs.constants.R_OK);
    } catch (e) {
      return res.status(404).send('File not found');
    }
    const isDownloadReq = download == '1';
    if (config.isImg(ext) && raw != '1') {
      let finalSize = size;
      try {
        const uid = req.user && req.user.id ? Number(req.user.id) : 0;
        if (uid) {
          const configured = await tableConfig.getConfigByKey('photo_preview_size', uid);
          const s = configured == null ? '' : String(configured).trim();
          console.log("configured",s)
          if (s && s !== 'origin') {
            const n = Math.floor(Number(s));
            if (Number.isFinite(n) && n > 0) finalSize = String(n);
          }
        }
        console.log("finalSize",finalSize)
      } catch (err) {
        console.log(err);
      }
      await sharpUtils.processToResponse(res, fullPath, finalSize, quality);
    } else if (code == 'utf8' && path.extname(fullPath).toLowerCase() == '.txt') {
      const content = await fs.promises.readFile(fullPath, 'utf8');
      res.type('text/plain; charset=utf-8');
      return res.send(content);
    } else {
      if (isDownloadReq) {
        const canDownload = await hasPermission(req.dbMain, req.user, 'download', fullPath);
        if (!canDownload) {
          return res.status(403).send(getLocalizedMessage(req, 'auth.PERMISSION_DENIED'));
        }
        res.download(fullPath, filename);
        return;
      }
      // 与旧版一致：由 express send 处理 Range(206)、ETag/Last-Modified(304)，避免 moov 在尾部时反复整文件 200
      return sendRawFileWithObservability(req, res, fullPath);
    }
  } catch (err) {
    console.error('getRawFile error:', err);
    if (!res.headersSent) res.status(500).send(err.message);
  }
}

module.exports = {
  getRawFile,
  getRawFileSendStats: () => ({ ...rawFileSendStats }),
  resetRawFileSendStats: () => {
    rawFileSendStats.currentFilePath = null;
    rawFileSendStats.requestCount = 0;
    rawFileSendStats.totalBytesSent = 0;
  },
};
