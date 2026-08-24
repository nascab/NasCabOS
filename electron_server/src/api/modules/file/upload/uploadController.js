const fs = require('fs-extra');
const path = require('path');
const childProcess = require('child_process');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const { hasPermission } = require('../../../../utils/permissionUtil');
const config = require('../../../../config/config');
const FileUtil = require('../../../../utils/fileUtil');
const dbUtil = require('../../../../db/dbUtil');
const knexUtil = require('../../../../db/knexUtil');
const ignoreCheckSameName = ['.DS_Store'];

let _photoMetaHelpers = null;
function _getPhotoMetaHelpers() {
  if (_photoMetaHelpers) return _photoMetaHelpers;
  let indexUtil = null;
  let util = null;
  try {
    indexUtil = require('../../../../workers/photoIndex/photoIndexIndexUtil');
  } catch (_) {}
  try {
    util = require('../../../../workers/photoIndex/photoIndexUtil');
  } catch (_) {}
  _photoMetaHelpers = { indexUtil, util };
  return _photoMetaHelpers;
}

function _normalizeSaveType(value) {
  const v = String(value || '')
    .trim()
    .toLowerCase();
  if (v === 'year' || v === 'month' || v === 'day') return v;
  return '';
}

function _getSaveTypeSubPath(ms, saveType) {
  const st = _normalizeSaveType(saveType);
  if (!st) return '';
  const t = Number(ms);
  if (!Number.isFinite(t) || t <= 0) return '';
  const d = new Date(t);
  const y = d.getFullYear();
  if (!Number.isFinite(y) || y <= 0) return '';
  const m = String(d.getMonth() + 1);
  const day = String(d.getDate());
  if (st === 'year') return path.join(String(y));
  if (st === 'month') return path.join(String(y), m);
  if (st === 'day') return path.join(String(y), m, day);
  return '';
}

async function _getMediaShotTimeMs(fullPath, fileName) {
  const helpers = _getPhotoMetaHelpers();
  const indexUtil = helpers.indexUtil;
  const util = helpers.util;
  if (!indexUtil || !util) return null;

  const name = String(fileName || '').trim() || path.basename(fullPath || '');
  const ext = path.extname(name).toLowerCase();
  const fileType = typeof config.getFileType === 'function' ? config.getFileType(ext) : '';
  if (fileType !== 'image' && fileType !== 'video' && fileType !== 'raw') return null;

  if (fileType === 'video') {
    const v = await indexUtil.extractVideoMeta(fullPath).catch(() => null);
    const originalTimeMs = v && v.originalTimeMs ? v.originalTimeMs : null;
    return util.getTimeFromFileName(originalTimeMs, name) || null;
  }

  const imageMeta = await indexUtil.extractImageMeta(fullPath).catch(() => null);
  let originalTimeMs = null;
  if (imageMeta) {
    originalTimeMs =
      util.parseExifDate(imageMeta.DateTimeOriginal) ||
      util.parseExifDate(imageMeta.CreateDate) ||
      util.parseExifDate(imageMeta.ModifyDate) ||
      util.parseExifDate(imageMeta.DateCreated) ||
      util.parseExifDate(imageMeta.CreationDate) ||
      null;
  }
  return util.getTimeFromFileName(originalTimeMs, name) || null;
}

/**
 * 获取用于按年月日生成保存路径的时间戳（毫秒）。
 * 优先级：媒体拍摄时间(EXIF等) -> 文件创建时间 -> 文件修改时间 -> 前端传入的 birthtimeMs/mtimeMs -> 当日
 * @param {string} fullPath - 文件路径
 * @param {string} fileName - 文件名
 * @param {number|null} [frontendTimeMs] - 前端传入的创建/修改时间（用于路径回退，与最终写入文件的时间一致）
 */
async function _getTimeForSavePath(fullPath, fileName, frontendTimeMs) {
  let ms = await _getMediaShotTimeMs(fullPath, fileName).catch(() => null);
  if (ms != null && Number.isFinite(ms) && ms > 0) return ms;
  try {
    const stat = await fs.stat(fullPath);
    const birth = stat.birthtimeMs != null && Number.isFinite(stat.birthtimeMs) && stat.birthtimeMs > 0 ? stat.birthtimeMs : null;
    const mtime = stat.mtimeMs != null && Number.isFinite(stat.mtimeMs) && stat.mtimeMs > 0 ? stat.mtimeMs : null;
    const list = [birth, mtime, frontendTimeMs].filter(v => v != null && Number.isFinite(v) && v > 0);
    if (list.length > 0) return Math.ceil(Math.min(...list));
  } catch (_) {}
  if (frontendTimeMs != null && Number.isFinite(frontendTimeMs) && frontendTimeMs > 0) return Math.ceil(frontendTimeMs);
  return Date.now();
}

function parseEpochMs(value) {
  if (value === undefined || value === null) return null;
  const n = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

function pickEarliestEpochMs(...values) {
  const list = values.map(v => parseEpochMs(v)).filter(v => v != null);
  if (list.length === 0) return null;
  return Math.min(...list);
}

function formatSetFileDate(ms) {
  const d = new Date(ms);
  const pad = v => String(v).padStart(2, '0');
  return `${pad(d.getMonth() + 1)}/${pad(d.getDate())}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function escapePowerShellSingleQuotedLiteral(str) {
  return `'${String(str).replace(/'/g, "''")}'`;
}

async function execFileSafe(file, args) {
  await new Promise((resolve, reject) => {
    childProcess.execFile(file, args, { windowsHide: true }, err => {
      if (err) reject(err);
      else resolve();
    });
  });
}

async function tryApplyFileTimes(filePath, { mtimeMs, birthtimeMs }) {
  const mtime = parseEpochMs(mtimeMs);
  const birthtime = parseEpochMs(birthtimeMs);

  if (mtime) {
    try {
      const d = new Date(mtime);
      await fs.utimes(filePath, d, d);
    } catch (_) {}
  }

  if (!birthtime) return;

  if (process.platform === 'win32') {
    try {
      const p = escapePowerShellSingleQuotedLiteral(filePath);
      const script = [`$p=${p};`, `$d=[DateTimeOffset]::FromUnixTimeMilliseconds(${birthtime}).LocalDateTime;`, `(Get-Item -LiteralPath $p).CreationTime=$d;`].join(' ');
      await execFileSafe('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script]);
    } catch (_) {}
    return;
  }

  if (process.platform === 'darwin') {
    try {
      await execFileSafe('SetFile', ['-d', formatSetFileDate(birthtime), filePath]);
    } catch (_) {}
  }
}

function isWindowsRootPath(filePath) {
  if (!filePath || typeof filePath !== 'string') return false;
  let normalized = path.normalize(filePath);

  if (normalized.length > 1 && normalized.endsWith(path.sep)) {
    normalized = normalized.slice(0, -1);
  }

  return process.platform === 'win32' && /^[a-zA-Z]:[\\/]*$/.test(normalized);
}

async function safeEnsureDir(dirPath) {
  if (isWindowsRootPath(dirPath)) {
    return;
  }
  await fs.ensureDir(dirPath);
}

class UploadController {
  constructor() {
    this.checkChunk = this.checkChunk.bind(this);
    this.uploadChunk = this.uploadChunk.bind(this);
  }

  _getChunkDir(targetDir, hash) {
    return path.join(targetDir, `${config.uploadTempFilePrefix}${hash}`);
  }

  async checkChunk(req, res) {
    try {
      const { hash, targetDir, chunkSize, fileName, nameStrategy, relativePath, saveType } = req.body;
      const headerStrategy = req.headers['x-name-strategy'];
      if (!hash || !chunkSize) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS');

      if (!targetDir) {
        return ResponseUtil.error(req, res, 'file.NO_WRITE_PERMISSION');
      }

      const strategy = ((headerStrategy || nameStrategy || 'skip') + '').toLowerCase();
      if (strategy === 'skip' && (fileName || relativePath) && !ignoreCheckSameName.includes(fileName)) {
        let baseDir = targetDir;
        const st = _normalizeSaveType(saveType);
        if (st) {
          const helpers = _getPhotoMetaHelpers();
          if (helpers.util && typeof helpers.util.getTimeFromFileName === 'function') {
            let guessed = helpers.util.getTimeFromFileName(null, fileName);
            if (!guessed) guessed = pickEarliestEpochMs(req.body.birthtimeMs, req.body.mtimeMs);
            const sub = guessed ? _getSaveTypeSubPath(guessed, st) : '';
            if (sub) baseDir = path.join(targetDir, sub);
          }
        }
        const pathForCheck = st ? path.basename(relativePath || fileName) : relativePath || fileName;
        const finalPath = path.join(baseDir, pathForCheck);
        if (await fs.pathExists(finalPath)) {
          return ResponseUtil.error(req, res, 'file.FILE_EXISTS', 409);
        }
      }

      const partialPath = path.join(targetDir, `${config.uploadTempPartPrefix}${hash}`);
      if (!(await fs.pathExists(partialPath))) {
        return ResponseUtil.success(req, res, { uploadedChunks: [] }, 'file.CHECK_CHUNK_SUCCESS', 200);
      }

      const stats = await fs.stat(partialPath);
      const size = stats.size;
      const parsedChunkSize = parseInt(chunkSize);

      const completedChunksCount = Math.floor(size / parsedChunkSize);

      const cleanSize = completedChunksCount * parsedChunkSize;
      if (size > cleanSize) {
        await fs.truncate(partialPath, cleanSize);
      }

      const uploadedChunks = Array.from({ length: completedChunksCount }, (_, i) => i);

      return ResponseUtil.success(req, res, { uploadedChunks }, 'file.CHECK_CHUNK_SUCCESS', 200);
    } catch (err) {
      console.error('Error checking chunks:', err);
      const message = FileUtil.getErrorMessageKey(err);
      return ResponseUtil.error(req, res, message);
    }
  }

  async uploadChunk(req, res) {
    try {
      const { hash, index, targetDir, chunkSize, fileName, totalChunks, nameStrategy, relativePath, saveType } = req.body;
      const headerStrategy = req.headers['x-name-strategy'];
      const file = req.file;

      if (!hash || index === undefined || !file || !targetDir || !chunkSize || !fileName || !totalChunks) {
        if (file) await fs.remove(file.path);
        return ResponseUtil.error(req, res, 'file.INVALID_PARAMS');
      }

      const strategyEarly = ((headerStrategy || nameStrategy || 'skip') + '').toLowerCase();
      if (strategyEarly === 'skip' && !ignoreCheckSameName.includes(fileName)) {
        const relEarly = relativePath || fileName;
        let baseDir = targetDir;
        const st = _normalizeSaveType(saveType);
        if (st) {
          const helpers = _getPhotoMetaHelpers();
          if (helpers.util && typeof helpers.util.getTimeFromFileName === 'function') {
            let guessed = helpers.util.getTimeFromFileName(null, fileName);
            if (!guessed) guessed = pickEarliestEpochMs(req.body.birthtimeMs, req.body.mtimeMs);
            const sub = guessed ? _getSaveTypeSubPath(guessed, st) : '';
            if (sub) baseDir = path.join(targetDir, sub);
          }
        }
        const pathForCheckEarly = st ? path.basename(relEarly) : relEarly;
        const finalPathEarly = path.join(baseDir, pathForCheckEarly);
        if (await fs.pathExists(finalPathEarly)) {
          await fs.remove(file.path).catch(() => {});
          return ResponseUtil.error(req, res, 'file.FILE_EXISTS', 409);
        }
      }

      const partialPath = path.join(targetDir, `${config.uploadTempPartPrefix}${hash}`);
      const parsedIndex = parseInt(index);
      const parsedChunkSize = parseInt(chunkSize);
      const parsedTotalChunks = parseInt(totalChunks);

      if (parsedIndex === 0) {
        const knex = req.dbMain;
        await knex('temp_file').insert({
          path: partialPath,
          type: 'upload',
          create_time: Date.now(),
        });

        await fs.move(file.path, partialPath, { overwrite: true });
      } else {
        if (!(await fs.pathExists(partialPath))) {
          await fs.remove(file.path);
          return ResponseUtil.error(req, res, 'file.MISSING_PREVIOUS_CHUNKS');
        }

        const stats = await fs.stat(partialPath);
        const expectedSize = parsedIndex * parsedChunkSize;
        if (stats.size !== expectedSize) {
          await fs.remove(file.path);
          if (stats.size > expectedSize) {
            return ResponseUtil.success(req, res, { index: parsedIndex }, 'file.UPLOAD_CHUNK_SUCCESS', 200);
          } else {
            return ResponseUtil.error(req, res, 'file.CHUNK_MISMATCH', 409, {
              currentSize: stats.size,
              expected: expectedSize,
            });
          }
        }

        const appendStream = fs.createWriteStream(partialPath, { flags: 'a' });
        const readStream = fs.createReadStream(file.path);

        await new Promise((resolve, reject) => {
          readStream.pipe(appendStream);
          readStream.on('error', reject);
          appendStream.on('error', reject);
          appendStream.on('finish', resolve);
        });

        await fs.remove(file.path);
      }

      if (parsedIndex + 1 === parsedTotalChunks) {
        let rel = relativePath || fileName;
        const strategy = ((headerStrategy || nameStrategy || 'skip') + '').toLowerCase();

        if (!(await fs.pathExists(targetDir))) {
          return ResponseUtil.error(req, res, 'file.TARGET_DIR_NOT_FOUND', 404);
        }

        let baseDir = targetDir;
        const st = _normalizeSaveType(saveType);
        if (st) {
          const frontendMs = pickEarliestEpochMs(req.body.birthtimeMs, req.body.mtimeMs);
          const timeMs = await _getTimeForSavePath(partialPath, fileName, frontendMs);
          const sub = _getSaveTypeSubPath(timeMs, st);
          if (sub) {
            baseDir = path.join(targetDir, sub);
            await safeEnsureDir(baseDir);
          }
        }
        // 按年月日保存时，文件直接存到日期路径下，不再带原文件夹名（如 Camera）
        if (st) rel = path.basename(rel);

        let safePath;
        const parts = rel.split(/[\\\/]/).filter(Boolean);

        if (parts.length > 1) {
          const rootName = parts[0];
          const subPath = parts.slice(1).join(path.sep);
          const finalDir = path.join(baseDir, rootName);
          safePath = path.join(finalDir, subPath);
          await safeEnsureDir(path.dirname(safePath));

          if (await fs.pathExists(safePath)) {
            if (strategy === 'skip' && !ignoreCheckSameName.includes(fileName)) {
              return ResponseUtil.error(req, res, 'file.FILE_EXISTS', 409);
            } else if (strategy === 'rename') {
              const dirOfFile = path.dirname(safePath);
              const base = path.basename(safePath);
              const ext = path.extname(base);
              const name = path.basename(base, ext);
              let candidate = safePath;
              let counter = 1;
              while (await fs.pathExists(candidate)) {
                const safeFileName = `${name}(${counter})${ext}`;
                candidate = path.join(dirOfFile, safeFileName);
                counter++;
              }
              safePath = candidate;
            } else if (strategy === 'overwrite') {
            } else {
              return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400, {
                error: '非法同名策略',
              });
            }
          }
        } else {
          const finalPath = path.join(baseDir, rel);
          if (await fs.pathExists(finalPath)) {
            if (strategy === 'skip' && !ignoreCheckSameName.includes(fileName)) {
              console.log('同名文件已存在错误');
              return ResponseUtil.error(req, res, 'file.FILE_EXISTS', 409);
            } else if (strategy === 'rename') {
              let counter = 1;
              const ext = path.extname(rel);
              const name = path.basename(rel, ext);
              let candidate = finalPath;
              while (await fs.pathExists(candidate)) {
                const safeFileName = `${name}(${counter})${ext}`;
                candidate = path.join(baseDir, safeFileName);
                counter++;
              }
              safePath = candidate;
            } else if (strategy === 'overwrite') {
              safePath = finalPath;
            } else {
              return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400, {
                error: '非法同名策略',
              });
            }
          } else {
            safePath = finalPath;
          }
          await safeEnsureDir(path.dirname(safePath));
        }

        await fs.move(partialPath, safePath, { overwrite: true });
        // 支持前端传入 mtimeMs / birthtimeMs，写入文件的修改时间与创建时间
        await tryApplyFileTimes(safePath, {
          mtimeMs: req.body.mtimeMs,
          birthtimeMs: req.body.birthtimeMs,
        });

        const chunkDir = this._getChunkDir(targetDir, hash);
        await fs.remove(chunkDir).catch(() => {});
        const knex = req.dbMain;
        await knex('temp_file').where('path', partialPath).del();
        return ResponseUtil.success(req, res, { index: parsedIndex, completed: true, path: safePath }, 'file.UPLOAD_COMPLETED', 200);
      }

      return ResponseUtil.success(req, res, { index: parsedIndex, completed: false }, 'file.UPLOAD_CHUNK_SUCCESS', 200);
    } catch (err) {
      console.log(err);
      if (req.file) await fs.remove(req.file.path).catch(() => {});
      const message = FileUtil.getErrorMessageKey(err);
      return ResponseUtil.error(req, res, message);
    }
  }
}

module.exports = new UploadController();
