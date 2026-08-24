const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');
const { EncryptedSpaceService } = require('./encryptedSpaceService');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Transform } = require('stream');
const multer = require('multer');
const sharpUtils = require('../../../utils/sharpUtils');
const mediaUtils = require('../../../utils/mediaUtils');
const config = require('../../../config/config');
const tableConfig = require('../../../db/table/tableConfig');
const userUtil = require('../../../utils/userUtil');
const jwtUtil = require('../../../utils/jwtUtil');
const videoFfprobeUtil = require('../../../utils/videoFfprobeUtil');
const {
  encryptString,
  decryptString,
  getInitialIv,
  encryptFile,
  encryptFileChunkAppend,
  decryptFileToStream,
  createDecipherByPwd,
  getDecryptedFileSize,
  formatJoin,
  resolveSpacePwdForSign,
  ensureSpaceConfigFolders,
  getIndexDb,
  ensureIndexDbSchema,
  configFolderName,
  folderSignString,
  folderSignFileName,
  indexDbFileName,
} = require('./encryptedSpaceFileUtil');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function toInt(v, fallback = 0) {
  const n = Number.parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) ? n : fallback;
}

function parseHttpRange(rangeHeader, size) {
  const raw = ensureString(rangeHeader).trim();
  if (!raw) return null;
  const m = /^bytes=(\d*)-(\d*)$/i.exec(raw);
  if (!m) return null;

  const total = Number(size);
  if (!Number.isFinite(total) || total <= 0) return null;

  const leftRaw = m[1];
  const rightRaw = m[2];

  let start = leftRaw ? Number(leftRaw) : null;
  let end = rightRaw ? Number(rightRaw) : null;

  if (start !== null && (!Number.isFinite(start) || start < 0)) return null;
  if (end !== null && (!Number.isFinite(end) || end < 0)) return null;

  if (start === null) {
    if (end === null) return null;
    const suffix = end;
    if (suffix <= 0) return null;
    start = Math.max(0, total - suffix);
    end = total - 1;
  } else if (end === null) {
    end = total - 1;
  }

  if (start >= total) return { unsatisfiable: true, size: total };
  if (end >= total) end = total - 1;
  if (end < start) return { unsatisfiable: true, size: total };
  return { start, end, size: total, unsatisfiable: false };
}

async function readFileBytes(filePath, position, length) {
  const fd = await fs.promises.open(filePath, 'r');
  try {
    const buf = Buffer.alloc(length);
    const r = await fd.read(buf, 0, length, position);
    if (!r || r.bytesRead !== length) return null;
    return buf;
  } finally {
    await fd.close().catch(() => {});
  }
}

function getTokenFromReq(req) {
  const fromHeader = req.headers && (req.headers.token || req.headers.space_token || req.headers.spaceToken);
  const fromQuery = req.query && (req.query.token || req.query.spaceToken || req.query.space_token);
  const fromBody = req.body && (req.body.token || req.body.spaceToken || req.body.space_token);
  const raw = fromBody ?? fromQuery ?? fromHeader;
  return ensureString(raw).trim();
}

function getSpaceIdFromReq(req) {
  const fromHeader = req.headers && (req.headers.space_id || req.headers.spaceId);
  const fromQuery = req.query && (req.query.spaceId || req.query.space_id);
  const fromBody = req.body && (req.body.spaceId || req.body.space_id);
  const raw = fromBody ?? fromQuery ?? fromHeader;
  const n = Number(raw);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function getExtAndType(uploadFileName) {
  const ext = uploadFileName && path.extname(uploadFileName) ? path.extname(uploadFileName).toLowerCase() : '';
  const imgList = Array.isArray(config.imgTypeList) ? config.imgTypeList : [];
  const rawList = Array.isArray(config.rawImgTypeList) ? config.rawImgTypeList : [];
  const videoList = Array.isArray(config.videoTypeList) ? config.videoTypeList : [];
  let fileType = 'other';
  if (ext) {
    const e = ext.toLowerCase();
    if (imgList.map(s => String(s || '').toLowerCase()).includes(e) || rawList.map(s => String(s || '').toLowerCase()).includes(e)) fileType = 'image';
    else if (videoList.map(s => String(s || '').toLowerCase()).includes(e)) fileType = 'video';
  }
  return { ext, fileType };
}

function isSpecialImageExt(ext) {
  const e = ensureString(ext).toLowerCase();
  if (!e) return false;
  if (e === '.heic' || e === '.heif' || e === '.hif') return true;
  if (e === '.bmp') return true;
  const rawList = Array.isArray(config.rawImgTypeList) ? config.rawImgTypeList : [];
  return rawList.map(s => String(s || '').toLowerCase()).includes(e);
}

async function resolvePhotoPreviewSharpParams(uid, querySize, queryQuality) {
  let finalSize = querySize;
  try {
    const nUid = uid ? Number(uid) : 0;
    if (nUid) {
      const configured = await tableConfig.getConfigByKey('photo_preview_size', nUid).catch(() => null);
      const s = configured == null ? '' : String(configured).trim();
      if (s && s !== 'origin') {
        const n = Math.floor(Number(s));
        if (Number.isFinite(n) && n > 0) finalSize = String(n);
      }
    }
  } catch (err) {
    console.log(err);
  }
  return { finalSize, quality: queryQuality };
}

function safeListOrder(orderField, orderType) {
  const allowedFields = new Set(['id', 'create_time', 'check_time', 'original_time', 'size', 'duration', 'show_name']);
  const f = ensureString(orderField).trim() || 'id';
  const t = ensureString(orderType).trim().toLowerCase() || 'desc';
  return {
    field: allowedFields.has(f) ? f : 'id',
    type: t === 'asc' ? 'asc' : 'desc',
  };
}

function getIndexById(db, id) {
  const row = db.prepare('SELECT * FROM private_space_index WHERE id=? LIMIT 1').get(Number(id));
  return row || null;
}

function getIndexByFileName(db, filenameBase64) {
  const row = db.prepare('SELECT id FROM private_space_index WHERE filename=? LIMIT 1').get(String(filenameBase64));
  return row || null;
}

function insertIndex(db, { filenameBase64, filenameEnc, fileType, ext, showName }) {
  const stmt = db.prepare('INSERT INTO private_space_index(filename, filename_enc, file_type, ext, show_name) VALUES(?,?,?,?,?)');
  const r = stmt.run(String(filenameBase64), String(filenameEnc), String(fileType), String(ext || ''), ensureString(showName));
  return r && r.lastInsertRowid ? Number(r.lastInsertRowid) : 0;
}

function deleteIndexById(db, id) {
  db.prepare('DELETE FROM private_space_index WHERE id=?').run(Number(id));
  return true;
}

function updateIndexFields(db, id, fields) {
  const keys = Object.keys(fields || {}).filter(k => fields[k] !== undefined);
  if (keys.length === 0) return false;
  const cols = keys.map(k => `${k}=?`).join(',');
  const values = keys.map(k => fields[k]);
  values.push(Number(id));
  db.prepare(`UPDATE private_space_index SET ${cols} WHERE id=?`).run(...values);
  return true;
}

function listIndex(db, opts) {
  const count = Math.max(1, Math.min(500, toInt(opts.count, 100)));
  const offsetCount = Math.max(0, toInt(opts.offsetCount, 0));
  const { field, type } = safeListOrder(opts.orderField, opts.orderType);
  const fileType = ensureString(opts.fileType).trim();
  const keyword = ensureString(opts.keyword).trim();
  const conditions = [];
  const args = [];
  if (fileType && fileType !== 'all') {
    conditions.push(' file_type=? ');
    args.push(fileType);
  }
  if (keyword.length > 0) {
    conditions.push(" (COALESCE(show_name, '') LIKE ? ESCAPE '\\') ");
    args.push('%' + keyword.replace(/[\\%_]/g, m => '\\' + m) + '%');
  }
  const where = conditions.length > 0 ? ' WHERE ' + conditions.join(' AND ') : '';
  const sql = `SELECT * FROM private_space_index${where} ORDER BY ${field} ${type} LIMIT ? OFFSET ?`;
  args.push(count, offsetCount);
  return db.prepare(sql).all(...args);
}

async function runMulter(uploader, req, res) {
  await new Promise((resolve, reject) => {
    uploader(req, res, err => {
      if (err) reject(err);
      else resolve(true);
    });
  });
}

async function safeEnsureDir(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return;
  await fs.promises.mkdir(p, { recursive: true }).catch(() => {});
}

async function safeRemovePath(p) {
  const fp = ensureString(p).trim();
  if (!fp) return;
  await fs.promises.rm(fp, { recursive: true, force: true }).catch(() => {});
}

async function readLastBytes(filePath, length) {
  const fp = ensureString(filePath).trim();
  const len = toInt(length, 0);
  if (!fp || len <= 0) return Buffer.alloc(0);

  const fh = await fs.promises.open(fp, 'r');
  try {
    const st = await fh.stat();
    const size = Number(st && st.size ? st.size : 0) || 0;
    if (size < len) return Buffer.alloc(0);
    const buf = Buffer.alloc(len);
    await fh.read(buf, 0, len, size - len);
    return buf;
  } finally {
    await fh.close().catch(() => {});
  }
}

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (typeof process.send !== 'function') {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      reject(err);
      return;
    }

    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        process.removeListener('message', onMessage);
        const err = new Error('common.ERROR');
        err.statusCode = 504;
        reject(err);
      },
      Math.max(500, Number(timeoutMs || 0) || 0)
    );

    const onMessage = message => {
      if (!message || message.type !== responseType) return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(message.data || {});
    };

    process.on('message', onMessage);
  });
}

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

function mapStartStopErrorToResponse(errorCode) {
  const code = errorCode === undefined || errorCode === null ? '' : String(errorCode);
  if (code === 'invalid_params') return { msgKey: 'common.INVALID_PARAMS', statusCode: 400 };
  if (code === 'not_found') return { msgKey: 'common.NOT_FOUND', statusCode: 404 };
  if (code === 'start_timeout' || code === 'stop_timeout') return { msgKey: 'common.ERROR', statusCode: 504 };
  return { msgKey: 'common.ERROR', statusCode: 500 };
}

async function startExportTaskByIpc({ id }) {
  const idNum = Number(id);
  if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('common.INVALID_PARAMS', 400);
  if (typeof process.send !== 'function') throw buildHttpError('common.ERROR', 500);
  const requestId = `startEncryptedSpaceExportTask_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({ requestId, responseType: 'startEncryptedSpaceExportTaskResponse', timeoutMs: 20000 });
  process.send({ type: 'startEncryptedSpaceExportTask', data: { requestId, id: idNum }, timestamp: Date.now() });
  const data = await wait;
  if (!data.started) {
    const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
    throw buildHttpError(mapped.msgKey, mapped.statusCode);
  }
  return data;
}

async function stopExportTaskByIpc({ id }) {
  const idNum = Number(id);
  if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('common.INVALID_PARAMS', 400);
  if (typeof process.send !== 'function') throw buildHttpError('common.ERROR', 500);
  const requestId = `stopEncryptedSpaceExportTask_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({ requestId, responseType: 'stopEncryptedSpaceExportTaskResponse', timeoutMs: 20000 });
  process.send({ type: 'stopEncryptedSpaceExportTask', data: { requestId, id: idNum }, timestamp: Date.now() });
  const data = await wait;
  if (!data.stopped) {
    const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
    throw buildHttpError(mapped.msgKey, mapped.statusCode);
  }
  return data;
}

class EncryptedSpaceController {
  async list(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.list({ uid, isAdmin: userUtil.isAdmin(req.user), user: req.user });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace list failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async addSpace(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const { folderPath, spaceName, spacePwd } = req.body || {};
      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.addSpace({ uid, folderPath, spaceName, spacePwd });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace addSpace failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async checkPwd(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const { spaceId, spacePwd } = req.body || {};
      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.checkPwd({ uid, spaceId, spacePwd, isAdmin: userUtil.isAdmin(req.user) });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace checkPwd failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async checkToken(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const { token } = req.body || {};
      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.checkToken({ uid, token });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace checkToken failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async deleteToken(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const { spaceId } = req.body || {};
      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.deleteToken({ uid, spaceId });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace deleteToken failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getFileList(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const spaceId = getSpaceIdFromReq(req);
      const token = getTokenFromReq(req);
      if (!spaceId || !token) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const service = new EncryptedSpaceService(req.dbMain);
      const { spaceRow } = await service.getPwdFromToken({ uid, spaceId, token });

      const rawFolderPath = ensureString(spaceRow && spaceRow.folder_path).trim();
      if (!rawFolderPath) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      // 跨平台路径规范化：Windows 导入后 DB 可能存的是反斜杠，在 Mac 上需转为当前系统分隔符
      const spaceFolderPath = path.normalize(rawFolderPath.replace(/[\\/]+/g, path.sep));
      const folderStat = await fs.promises.stat(spaceFolderPath).catch(() => null);
      if (!folderStat || !folderStat.isDirectory()) {
        return ResponseUtil.error(req, res, 'encryptedSpace.SPACE_FOLDER_MISSING', 404);
      }
      console.log(spaceFolderPath,folderStat)
      // getIndexDb 内部会 realpath，保证同一目录始终用同一缓存、不会有时打开空库有时打开真实库
      const indexDbPath = path.join(spaceFolderPath, configFolderName, indexDbFileName);
      const dbFileExists = await fs.promises
        .stat(indexDbPath)
        .then(s => s.isFile())
        .catch(() => false);
      const dbFileSize = dbFileExists
        ? await fs.promises
            .stat(indexDbPath)
            .then(s => s.size)
            .catch(() => 0)
        : 0;
      Logger.info('[encryptedSpace getFileList] spaceId=%s folder_path=%s indexDbPath=%s exists=%s size=%s', spaceId, spaceFolderPath, indexDbPath, dbFileExists, dbFileSize);

      const privateIndexDb = getIndexDb(spaceFolderPath);
      ensureIndexDbSchema(privateIndexDb);

      const totalCountRow = privateIndexDb.prepare('SELECT COUNT(*) as total FROM private_space_index').get();
      const totalInDb = Number(totalCountRow && totalCountRow.total) || 0;

      const payload = listIndex(privateIndexDb, {
        count: req.body && req.body.count,
        offsetCount: req.body && (req.body.offsetCount ?? req.body.offset_count),
        orderField: req.body && (req.body.orderField ?? req.body.order_field),
        orderType: req.body && (req.body.orderType ?? req.body.order_type),
        fileType: req.body && (req.body.fileType ?? req.body.file_type),
        keyword: ensureString(req.body && req.body.keyword),
      });

      Logger.info('[encryptedSpace getFileList] private_space_index total rows=%s listIndex returned length=%s', totalInDb, Array.isArray(payload) ? payload.length : 0);

      return ResponseUtil.success(req, res, payload, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace getFileList failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async getDecodeFile(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const spaceId = getSpaceIdFromReq(req);
      const indexId = toInt(req.query && req.query.indexId, 0);
      const token = getTokenFromReq(req);
      const download = toInt(req.query && req.query.download, 0);
      const wantsOriginalImage = download === 1 || String(ensureString(req.query && req.query.raw).trim()) === '1';
      const type = ensureString(req.query && req.query.type).trim();

      if (!spaceId || !indexId || !token) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const service = new EncryptedSpaceService(req.dbMain);
      const { spaceRow, pwd } = await service.getPwdFromToken({ uid, spaceId, token });
      const spaceFolderPath = ensureString(spaceRow && spaceRow.folder_path).trim();
      if (!spaceFolderPath) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const privateIndexDb = getIndexDb(spaceFolderPath);
      ensureIndexDbSchema(privateIndexDb);
      const indexObj = getIndexById(privateIndexDb, indexId);
      if (!indexObj) return res.status(404).end();

      const rel = type === 'tiny' ? ensureString(indexObj.tiny_path).trim() : ensureString(indexObj.filename_enc).trim();
      if (!rel) return res.status(404).end();

      const fullPath = formatJoin(spaceFolderPath, rel);
      const baseResolved = path.resolve(spaceFolderPath);
      if (fullPath !== baseResolved && !fullPath.startsWith(`${baseResolved}${path.sep}`)) return res.status(403).end();

      if (download === 1) {
        try {
          const decodeFileName = Buffer.from(String(indexObj.filename || ''), 'base64').toString();
          const encodedFilename = encodeURIComponent(decodeFileName).replace(/%([0-9A-F]{2})/g, (match, p1) => `%${p1.toUpperCase()}`);
          res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFilename}`);
        } catch (_) {}
      }

      const st = await fs.promises.stat(fullPath).catch(() => null);
      if (!st || !st.isFile() || st.size <= 0) return res.status(404).end();

      if (type !== 'tiny') {
        try {
          updateIndexFields(privateIndexDb, indexId, { check_time: Date.now() });
        } catch (_) {}
      }

      if (type === 'tiny') {
        res.type('image/webp');
        await decryptFileToStream(pwd, fullPath, res);
        return;
      }

      const ext = ensureString(indexObj.ext).toLowerCase();
      if (isSpecialImageExt(ext)) {
        if (wantsOriginalImage) {
          if (!download && ext) {
            try {
              res.type(ext);
            } catch (_) {}
          }
          await decryptFileToStream(pwd, fullPath, res);
          return;
        }
        const { tempFolder } = await ensureSpaceConfigFolders(spaceFolderPath);
        const tempDecryptedPath = path.join(tempFolder, `${crypto.randomBytes(12).toString('hex')}${ext || ''}`);
        const cleanup = async () => {
          await fs.promises.unlink(tempDecryptedPath).catch(() => {});
        };
        res.once('close', cleanup);
        res.once('finish', cleanup);
        await decryptFileToStream(pwd, fullPath, fs.createWriteStream(tempDecryptedPath));
        const { finalSize, quality: previewQuality } = await resolvePhotoPreviewSharpParams(
          uid,
          req.query && req.query.size,
          req.query && req.query.quality
        );
        await sharpUtils.processToResponse(res, tempDecryptedPath, finalSize, previewQuality);
        return;
      }

      const encryptedSize = Number(st.size);
      const rangeHeader = req.headers && req.headers.range ? String(req.headers.range) : '';
      let plainSize = toInt(indexObj.size, 0);
      if (!plainSize) {
        plainSize = await getDecryptedFileSize(pwd, fullPath);
      }

      const range = rangeHeader && plainSize > 0 ? parseHttpRange(rangeHeader, plainSize) : null;
      if (range && range.unsatisfiable) {
        res.setHeader('Content-Range', `bytes */${range.size}`);
        return res.status(416).end();
      }

      if (config.isImg(ext) && !wantsOriginalImage && !range) {
        const { tempFolder } = await ensureSpaceConfigFolders(spaceFolderPath);
        const tempDecryptedPath = path.join(tempFolder, `${crypto.randomBytes(12).toString('hex')}${ext || ''}`);
        const cleanup = async () => {
          await fs.promises.unlink(tempDecryptedPath).catch(() => {});
        };
        res.once('close', cleanup);
        res.once('finish', cleanup);
        await decryptFileToStream(pwd, fullPath, fs.createWriteStream(tempDecryptedPath));
        const { finalSize, quality: previewQuality } = await resolvePhotoPreviewSharpParams(
          uid,
          req.query && req.query.size,
          req.query && req.query.quality
        );
        await sharpUtils.processToResponse(res, tempDecryptedPath, finalSize, previewQuality);
        return;
      }

      if (range && plainSize > 0) {
        const start = range.start;
        const end = range.end;
        const total = range.size;

        const blockSize = 16;
        const startBlock = Math.floor(start / blockSize);
        const endBlock = Math.floor(end / blockSize);
        const cipherStart = startBlock * blockSize;
        const cipherEnd = Math.min(encryptedSize - 1, (endBlock + 1) * blockSize - 1);

        const ivOverride = cipherStart <= 0 ? getInitialIv() : await readFileBytes(fullPath, cipherStart - blockSize, blockSize);
        if (!ivOverride || ivOverride.length !== blockSize) return res.status(404).end();

        const input = fs.createReadStream(fullPath, { start: cipherStart, end: cipherEnd });
        const decipher = createDecipherByPwd(pwd, ivOverride);
        if (end !== total - 1) decipher.setAutoPadding(false);

        let skipLeft = start - cipherStart;
        let left = end - start + 1;
        const slicer = new Transform({
          transform(chunk, _encoding, cb) {
            if (left <= 0) return cb();
            let startIdx = 0;
            if (skipLeft > 0) {
              const skipped = Math.min(skipLeft, chunk.length);
              skipLeft -= skipped;
              startIdx = skipped;
            }
            if (startIdx >= chunk.length) return cb();
            const take = Math.min(left, chunk.length - startIdx);
            if (take > 0) {
              this.push(chunk.subarray(startIdx, startIdx + take));
              left -= take;
            }
            return cb();
          },
        });

        res.status(206);
        res.setHeader('Accept-Ranges', 'bytes');
        res.setHeader('Content-Range', `bytes ${start}-${end}/${total}`);
        res.setHeader('Content-Length', String(end - start + 1));

        if (!download && ext) {
          try {
            res.type(ext);
          } catch (_) {}
        }

        await new Promise((resolve, reject) => {
          let done = false;
          const finish = () => {
            if (done) return;
            done = true;
            resolve();
          };
          const onErr = err => {
            if (done) return;
            done = true;
            reject(err);
          };

          input.on('error', onErr);
          decipher.on('error', onErr);
          slicer.on('error', onErr);
          res.on('error', onErr);

          res.on('finish', finish);
          res.on('close', finish);

          input.pipe(decipher).pipe(slicer).pipe(res);
        });
        return;
      }

      if (!download && ext) {
        try {
          res.type(ext);
        } catch (_) {}
      }
      res.setHeader('Accept-Ranges', 'bytes');
      await decryptFileToStream(pwd, fullPath, res);
      return;
    } catch (e) {
      Logger.error('encryptedSpace getDecodeFile failed', e);
      if (!res.headersSent) return res.status(404).end();
      return;
    }
  }

  async checkChunk(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const spaceId = getSpaceIdFromReq(req);
      const token = getTokenFromReq(req);
      if (!spaceId || !token) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const { hash, chunkSize } = req.body || {};
      const hashStr = ensureString(hash).trim();
      const parsedChunkSize = toInt(chunkSize, 0);
      if (!hashStr || parsedChunkSize <= 0) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const service = new EncryptedSpaceService(req.dbMain);
      const { spaceRow } = await service.getPwdFromToken({ uid, spaceId, token });
      const spaceFolderPath = ensureString(spaceRow && spaceRow.folder_path).trim();
      if (!spaceFolderPath) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      const folderStat = await fs.promises.stat(spaceFolderPath).catch(() => null);
      if (!folderStat || !folderStat.isDirectory()) {
        return ResponseUtil.error(req, res, 'encryptedSpace.SPACE_FOLDER_MISSING', 404);
      }

      const { tempFolder } = await ensureSpaceConfigFolders(spaceFolderPath);
      const partialPath = path.join(tempFolder, `${config.uploadTempPartPrefix}enc_${hashStr}`);
      const st = await fs.promises.stat(partialPath).catch(() => null);
      if (!st || !st.isFile() || st.size <= 0) {
        return ResponseUtil.success(req, res, { uploadedChunks: [] }, 'file.CHECK_CHUNK_SUCCESS', 200);
      }

      const size = Number(st.size) || 0;
      const completedChunksCount = Math.floor(size / parsedChunkSize);
      const uploadedChunks = Array.from({ length: completedChunksCount }, (_, i) => i);
      return ResponseUtil.success(req, res, { uploadedChunks }, 'file.CHECK_CHUNK_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace checkChunk failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async uploadChunk(req, res) {
    let stagePath = '';
    let partialEncPath = '';
    let afterEnFullPath = '';
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const spaceId = getSpaceIdFromReq(req);
      const token = getTokenFromReq(req);
      if (!spaceId || !token) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const stageDir = path.join(config.getUploadTempDir(), 'encrypted_space_uploads_stage');
      await safeEnsureDir(stageDir);

      const uploader = multer({
        storage: multer.diskStorage({
          destination: function (req2, file, cb) {
            cb(null, stageDir);
          },
          filename: function (req2, file, cb) {
            cb(null, `${crypto.randomBytes(12).toString('hex')}.chunk`);
          },
        }),
        limits: { fileSize: 50 * 1024 * 1024 },
      }).single('file');

      await runMulter(uploader, req, res);

      stagePath = req.file && req.file.path ? ensureString(req.file.path).trim() : '';
      if (!stagePath) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const { hash, index, chunkSize, fileName, totalChunks } = req.body || {};
      const hashStr = ensureString(hash).trim();
      const fileNameStr = ensureString(fileName).trim();
      const parsedIndex = toInt(index, -1);
      const parsedChunkSize = toInt(chunkSize, 0);
      const parsedTotalChunks = toInt(totalChunks, 0);

      if (!hashStr || !fileNameStr || parsedIndex < 0 || parsedChunkSize <= 0 || parsedTotalChunks <= 0 || parsedIndex >= parsedTotalChunks) {
        await safeRemovePath(stagePath);
        stagePath = '';
        return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
      }

      const service = new EncryptedSpaceService(req.dbMain);
      const { spaceRow, pwd } = await service.getPwdFromToken({ uid, spaceId, token });
      const spaceFolderPath = ensureString(spaceRow && spaceRow.folder_path).trim();
      if (!spaceFolderPath) {
        await safeRemovePath(stagePath);
        stagePath = '';
        return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      }
      const folderStat = await fs.promises.stat(spaceFolderPath).catch(() => null);
      if (!folderStat || !folderStat.isDirectory()) {
        await safeRemovePath(stagePath);
        stagePath = '';
        return ResponseUtil.error(req, res, 'encryptedSpace.SPACE_FOLDER_MISSING', 404);
      }

      const { tinyFolder, tempFolder } = await ensureSpaceConfigFolders(spaceFolderPath);
      const privateIndexDb = getIndexDb(spaceFolderPath);
      ensureIndexDbSchema(privateIndexDb);

      const blockSize = 16;
      const isLast = parsedIndex + 1 === parsedTotalChunks;
      const stageSt = await fs.promises.stat(stagePath).catch(() => null);
      const stageSize = Number(stageSt && stageSt.size ? stageSt.size : 0) || 0;
      if (stageSize <= 0) {
        await safeRemovePath(stagePath);
        stagePath = '';
        return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
      }

      if (isLast && stageSize > parsedChunkSize) {
        await safeRemovePath(stagePath);
        stagePath = '';
        return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
      }

      if (!isLast && (parsedChunkSize % blockSize !== 0 || stageSize !== parsedChunkSize)) {
        await safeRemovePath(stagePath);
        stagePath = '';
        return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
      }

      partialEncPath = path.join(tempFolder, `${config.uploadTempPartPrefix}enc_${hashStr}`);
      if (parsedIndex === 0) {
        await safeRemovePath(partialEncPath);
        try {
          const knex = req.dbMain;
          await knex('temp_file').insert({
            path: partialEncPath,
            type: 'upload',
            create_time: Date.now(),
          });
        } catch (_) {}

        await encryptFileChunkAppend(pwd, stagePath, partialEncPath, {
          iv: getInitialIv(),
          append: false,
          isLast,
        });
        await safeRemovePath(stagePath);
        stagePath = '';
      } else {
        const st = await fs.promises.stat(partialEncPath).catch(() => null);
        if (!st || !st.isFile()) {
          await safeRemovePath(stagePath);
          stagePath = '';
          return ResponseUtil.error(req, res, 'file.MISSING_PREVIOUS_CHUNKS', 400);
        }

        const expectedSize = parsedIndex * parsedChunkSize;
        if (Number(st.size) !== expectedSize) {
          await safeRemovePath(stagePath);
          stagePath = '';
          if (Number(st.size) > expectedSize) {
            return ResponseUtil.success(req, res, { index: parsedIndex, completed: false }, 'file.UPLOAD_CHUNK_SUCCESS', 200);
          }
          return ResponseUtil.error(req, res, 'file.CHUNK_MISMATCH', 409, {
            currentSize: st.size,
            expected: expectedSize,
          });
        }

        const prevIv = await readLastBytes(partialEncPath, blockSize);
        if (!prevIv || prevIv.length !== blockSize) {
          await safeRemovePath(stagePath);
          stagePath = '';
          return ResponseUtil.error(req, res, 'common.FAILED', 400);
        }

        await encryptFileChunkAppend(pwd, stagePath, partialEncPath, {
          iv: prevIv,
          append: true,
          isLast,
        });
        await safeRemovePath(stagePath);
        stagePath = '';
      }

      if (!isLast) {
        return ResponseUtil.success(req, res, { index: parsedIndex, completed: false }, 'file.UPLOAD_CHUNK_SUCCESS', 200);
      }

      const uploadFileNamePreview = fileNameStr;
      const uploadFileNameBase64 = Buffer.from(uploadFileNamePreview).toString('base64');
      const sameNameFile = getIndexByFileName(privateIndexDb, uploadFileNameBase64);
      if (sameNameFile) {
        await safeRemovePath(partialEncPath);
        partialEncPath = '';
        return ResponseUtil.error(req, res, 'file.FILE_EXISTS', 409);
      }

      const { ext, fileType } = getExtAndType(uploadFileNamePreview);
      const cryptName = await encryptString(pwd, uploadFileNamePreview);
      if (cryptName.length > 240) {
        await safeRemovePath(partialEncPath);
        partialEncPath = '';
        return ResponseUtil.error(req, res, 'common.FAILED', 400);
      }

      afterEnFullPath = path.join(spaceFolderPath, cryptName);
      const stEnc = await fs.promises.stat(partialEncPath).catch(() => null);
      if (!stEnc || !stEnc.isFile() || stEnc.size <= 0) {
        await safeRemovePath(partialEncPath);
        partialEncPath = '';
        return ResponseUtil.error(req, res, 'common.FAILED', 400);
      }

      const stFinalExists = await fs.promises.stat(afterEnFullPath).catch(() => null);
      if (stFinalExists && stFinalExists.isFile()) {
        await safeRemovePath(partialEncPath);
        partialEncPath = '';
        return ResponseUtil.error(req, res, 'file.PATH_ALREADY_EXISTS', 409);
      }

      await fs.promises.rename(partialEncPath, afterEnFullPath);
      partialEncPath = '';

      const newIndexId = insertIndex(privateIndexDb, {
        filenameBase64: uploadFileNameBase64,
        filenameEnc: cryptName,
        fileType,
        ext,
        showName: uploadFileNamePreview,
      });
      if (!newIndexId) {
        await fs.promises.unlink(afterEnFullPath).catch(() => {});
        afterEnFullPath = '';
        return ResponseUtil.error(req, res, 'common.FAILED', 500);
      }

      try {
        const encryptedSt = await fs.promises.stat(afterEnFullPath).catch(() => null);
        const encSize = Number(encryptedSt && encryptedSt.size ? encryptedSt.size : 0) || 0;
        const plainSize = (parsedTotalChunks - 1) * parsedChunkSize + stageSize;
        updateIndexFields(privateIndexDb, newIndexId, {
          size: fileType === 'video' ? plainSize : encSize,
        });
      } catch (_) {}

      try {
        const knex = req.dbMain;
        await knex('temp_file')
          .where('path', path.join(tempFolder, `${config.uploadTempPartPrefix}enc_${hashStr}`))
          .del();
      } catch (_) {}

      if (fileType === 'video') {
        let tempDecryptedPath = '';
        let tinyWebpPath = '';
        try {
          tempDecryptedPath = path.join(tempFolder, `${crypto.randomBytes(12).toString('hex')}${ext || ''}`);
          await decryptFileToStream(pwd, afterEnFullPath, fs.createWriteStream(tempDecryptedPath));

          const meta = await videoFfprobeUtil.probeVideo(tempDecryptedPath).catch(() => null);
          const duration = meta && Number.isFinite(meta.duration) ? Math.trunc(meta.duration) : 0;
          const originalTime = await mediaUtils.getFileTime(tempDecryptedPath, { filename: uploadFileNamePreview });
          const streamInfo = meta && meta.streamInfo ? String(meta.streamInfo) : '';
          updateIndexFields(privateIndexDb, newIndexId, {
            original_time: originalTime,
            duration,
            stream_info: streamInfo,
          });

          tinyWebpPath = await sharpUtils.genTinyFile(tempDecryptedPath, tempFolder, `tiny-${cryptName}`, 'video', 640);
          const encryptedTinyPath = path.join(tinyFolder, cryptName);
          await encryptFile(pwd, tinyWebpPath, encryptedTinyPath);
          updateIndexFields(privateIndexDb, newIndexId, {
            tiny_path: path.join(configFolderName, 'tiny', cryptName),
          });
        } catch (err) {
          Logger.error('encryptedSpace video postprocess failed', err);
          try {
            deleteIndexById(privateIndexDb, newIndexId);
          } catch (_) {}
          await fs.promises.unlink(afterEnFullPath).catch(() => {});
          afterEnFullPath = '';
          await fs.promises.unlink(path.join(tinyFolder, cryptName)).catch(() => {});
          const e = new Error('common.FAILED');
          e.statusCode = 500;
          throw e;
        } finally {
          if (tinyWebpPath) await fs.promises.unlink(tinyWebpPath).catch(() => {});
          if (tempDecryptedPath) await fs.promises.unlink(tempDecryptedPath).catch(() => {});
        }
      } else {
        res.once('finish', () => {
          (async () => {
            if (!afterEnFullPath) return;

            if (fileType === 'image' || fileType === 'raw') {
              let tempDecryptedPath = '';
              let tinyWebpPath = '';
              try {
                tempDecryptedPath = path.join(tempFolder, `${cryptName}${ext || ''}`);
                tinyWebpPath = path.join(tempFolder, `tiny-${cryptName}.webp`);
                await decryptFileToStream(pwd, afterEnFullPath, fs.createWriteStream(tempDecryptedPath));
                await sharpUtils.genTinyFile(tempDecryptedPath, tempFolder, `tiny-${cryptName}`, 'image', 640);
                const encryptedTinyPath = path.join(tinyFolder, cryptName);
                await encryptFile(pwd, tinyWebpPath, encryptedTinyPath);
                try {
                  updateIndexFields(privateIndexDb, newIndexId, {
                    tiny_path: path.join(configFolderName, 'tiny', cryptName),
                  });
                } catch (_) {}

                try {
                  const t = await mediaUtils.getFileTime(tempDecryptedPath, { filename: uploadFileNamePreview });
                  if (Number.isFinite(t) && t > 0) {
                    updateIndexFields(privateIndexDb, newIndexId, { original_time: t });
                  }
                } catch (_) {}
              } catch (err) {
                Logger.error('encryptedSpace image postprocess failed', err);
              } finally {
                if (tinyWebpPath) await fs.promises.unlink(tinyWebpPath).catch(() => {});
                if (tempDecryptedPath) await fs.promises.unlink(tempDecryptedPath).catch(() => {});
              }
            }
          })();
        });
      }

      return ResponseUtil.success(req, res, { id: newIndexId, completed: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace uploadChunk failed', e);
      await safeRemovePath(stagePath);
      await safeRemovePath(partialEncPath);
      await safeRemovePath(afterEnFullPath);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async deleteSpaceFiles(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const spaceId = toInt(req.body && req.body.spaceId, 0);
      const idsRaw = req.body && req.body.ids;
      if (!spaceId || idsRaw === undefined || idsRaw === null) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const isAdmin = userUtil.isAdmin(req.user);
      const service = new EncryptedSpaceService(req.dbMain);
      const spaceRow = await service.knexMain(service.tableName).where({ id: spaceId }).first();
      if (!spaceRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      if (!isAdmin && String(spaceRow.uid || '').trim() !== String(uid).trim()) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      const spaceFolderPath = ensureString(spaceRow.folder_path).trim();
      if (!spaceFolderPath) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const privateIndexDb = getIndexDb(spaceFolderPath);
      ensureIndexDbSchema(privateIndexDb);

      let idArr = [];
      if (Array.isArray(idsRaw)) idArr = idsRaw;
      else {
        try {
          idArr = JSON.parse(String(idsRaw));
        } catch (_) {
          idArr = [];
        }
      }
      const ids = (idArr || []).map(n => Number(n)).filter(n => Number.isFinite(n) && n > 0);
      if (ids.length < 1) return ResponseUtil.success(req, res, { deleteList: [], deleteCount: 0, errCount: 0 }, 'common.SUCCESS', 200);

      let deleteCount = 0;
      let errCount = 0;
      const deleteList = [];
      for (const id of ids) {
        const indexObj = getIndexById(privateIndexDb, id);
        if (!indexObj) continue;

        const fileEnc = ensureString(indexObj.filename_enc).trim();
        const tinyRel = ensureString(indexObj.tiny_path).trim();
        const tasks = [];
        if (fileEnc) tasks.push(fs.promises.unlink(path.join(spaceFolderPath, fileEnc)));
        if (tinyRel && tinyRel !== 'undefined') tasks.push(fs.promises.unlink(formatJoin(spaceFolderPath, tinyRel)));
        const results = await Promise.allSettled(tasks);
        const hasErr = results.some(r => r.status === 'rejected');
        if (hasErr) errCount += 1;
        else {
          deleteCount += 1;
          deleteList.push(id);
        }
        try {
          deleteIndexById(privateIndexDb, id);
        } catch (_) {}
      }

      return ResponseUtil.success(req, res, { deleteList, deleteCount, errCount }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace deleteSpaceFiles failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async deleteSpace(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const spaceId = toInt(req.body && req.body.spaceId, 0);
      if (!spaceId) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const isAdmin = userUtil.isAdmin(req.user);
      const service = new EncryptedSpaceService(req.dbMain);
      const spaceRow = await service.knexMain(service.tableName).where({ id: spaceId }).first();
      if (!spaceRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      if (!isAdmin && String(spaceRow.uid || '').trim() !== String(uid).trim()) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      await service.knexMain(service.tokenTableName).where({ space_id: spaceId }).delete();
      await service.knexMain(service.tableName).where({ id: spaceId }).delete();
      return ResponseUtil.success(req, res, { ok: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace deleteSpace failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async updateSpaceName(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const spaceId = toInt(req.body && req.body.spaceId, 0);
      const spaceName = ensureString(req.body && req.body.spaceName).trim();
      if (!spaceId || !spaceName) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const isAdmin = userUtil.isAdmin(req.user);
      const service = new EncryptedSpaceService(req.dbMain);
      const spaceRow = await service.knexMain(service.tableName).where({ id: spaceId }).first();
      if (!spaceRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      if (!isAdmin && String(spaceRow.uid || '').trim() !== String(uid).trim()) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      const ownerUid = String(spaceRow.uid || '').trim();
      const dupName = await service
        .knexMain(service.tableName)
        .where({ uid: ownerUid, space_name: spaceName })
        .whereNot({ id: spaceId })
        .first();
      if (dupName) return ResponseUtil.error(req, res, 'file_custom_path_name_exists', 409);

      await service.knexMain(service.tableName).where({ id: spaceId }).update({ space_name: spaceName, update_time: new Date() });
      return ResponseUtil.success(req, res, { ok: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace updateSpaceName failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async importSpace(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const folderPath = ensureString(req.body && req.body.folderPath).trim();
      const spaceName = ensureString(req.body && req.body.spaceName).trim();
      const spacePwd = ensureString(req.body && req.body.spacePwd).trim();
      if (!folderPath || !spaceName || !spacePwd) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      const service = new EncryptedSpaceService(req.dbMain);
      const uidStr = String(uid).trim();
      const existByName = await service
        .knexMain(service.tableName)
        .where({ uid: uidStr, space_name: spaceName })
        .first();
      if (existByName) return ResponseUtil.error(req, res, 'file_custom_path_name_exists', 409);
      const existByPath = await service
        .knexMain(service.tableName)
        .where({ uid: uidStr, folder_path: folderPath })
        .first();
      if (existByPath) return ResponseUtil.error(req, res, 'file_custom_path_path_exists', 409);

      await fs.promises.access(folderPath, fs.constants.R_OK | fs.constants.W_OK);

      const decodedPwd = jwtUtil.decodeClientPassword(spacePwd);
      const signFilePath = path.join(folderPath, configFolderName, folderSignFileName);
      const signText = await fs.promises.readFile(signFilePath, 'utf8').catch(() => '');
      if (!signText.trim()) return ResponseUtil.error(req, res, 'encryptedSpace.SIGN_FILE_MISSING', 400);

      const resolvedPwd = await resolveSpacePwdForSign(decodedPwd, signText);
      if (!resolvedPwd) return ResponseUtil.error(req, res, 'encryptedSpace.PASSWORD_INCORRECT', 403);

      const dbPath = path.join(folderPath, configFolderName, indexDbFileName);
      const stDb = await fs.promises.stat(dbPath).catch(() => null);
      if (!stDb || !stDb.isFile() || stDb.size <= 0) return ResponseUtil.error(req, res, 'encryptedSpace.SPACE_DB_INVALID', 400);
      const privateIndexDb = getIndexDb(folderPath);
      ensureIndexDbSchema(privateIndexDb);

      const now = new Date();
      const encryptedPwd = jwtUtil.encryptPassword(resolvedPwd);
      const [newId] = await service.knexMain(service.tableName).insert({
        uid: String(uid),
        space_name: spaceName,
        folder_path: folderPath,
        space_pwd: encryptedPwd,
        create_time: now,
        update_time: now,
      });

      return ResponseUtil.success(req, res, { id: newId }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace importSpace failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async exportTaskList(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.listExportTasks({ uid, isAdmin: userUtil.isAdmin(req.user) });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace exportTaskList failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async addExportTask(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const { spaceId, spacePwd, targetPath } = req.body || {};
      const service = new EncryptedSpaceService(req.dbMain);
      const created = await service.addExportTask({ uid, spaceId, spacePwd, targetPath, isAdmin: userUtil.isAdmin(req.user) });
      const taskId = created && created.id ? Number(created.id) : 0;
      if (!taskId) return ResponseUtil.error(req, res, 'common.ERROR', 500);

      try {
        await startExportTaskByIpc({ id: taskId });
      } catch (e) {
        try {
          await service.deleteExportTask({ uid, id: taskId, isAdmin: userUtil.isAdmin(req.user) });
        } catch (_) {}
        const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
        const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
        return ResponseUtil.error(req, res, msgKey, statusCode);
      }

      return ResponseUtil.success(req, res, { id: taskId }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace addExportTask failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async deleteExportTask(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const id = toInt(req.body && req.body.id, 0);
      if (!id) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

      try {
        await stopExportTaskByIpc({ id });
      } catch (_) {}

      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.deleteExportTask({ uid, id, isAdmin: userUtil.isAdmin(req.user) });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace deleteExportTask failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async clearFinishedExportTasks(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const service = new EncryptedSpaceService(req.dbMain);
      const data = await service.clearFinishedExportTasks({ uid, isAdmin: userUtil.isAdmin(req.user) });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace clearFinishedExportTasks failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async exitSpaceId(req, res) {
    try {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const spaceId = toInt(req.body && req.body.spaceId, 0);
      if (!spaceId) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
      const service = new EncryptedSpaceService(req.dbMain);
      await service.deleteToken({ uid, spaceId });
      return ResponseUtil.success(req, res, { ok: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('encryptedSpace exitSpaceId failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new EncryptedSpaceController();
