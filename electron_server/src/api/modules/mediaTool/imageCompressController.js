const path = require('path');
const fs = require('fs-extra');
const multer = require('multer');
const archiver = require('archiver');
const sharpUtils = require('../../../utils/sharpUtils');
const config = require('../../../config/config');
const ResponseUtil = require('../../apiUtils/responseUtil');

function isPathWithin(parent, child) {
  const parentResolved = path.resolve(parent);
  const childResolved = path.resolve(child);
  if (parentResolved === childResolved) return true;
  return childResolved.startsWith(parentResolved + path.sep);
}

function sanitizeFilename(name) {
  const base = path.basename(String(name || ''));
  return base.replace(/[\\\/]/g, '_').trim() || 'file';
}

function createSharpFromConverted(converted) {
  if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
    const sharp = require('../../../utils/sharpConfigured');
    return sharp(converted.input, converted.options);
  }
  const sharp = require('../../../utils/sharpConfigured');
  return sharp(converted, { failOnError: false });
}

function getUserZipRoot(req) {
  const username = (req.user && req.user.username) || 'user';
  return path.join(config.getZipImgTempPath(), username);
}

async function ensureUniquePath(dir, requestedName) {
  const safeBase = sanitizeFilename(requestedName);
  const ext = path.extname(safeBase);
  const name = path.basename(safeBase, ext);
  let candidate = safeBase;
  let counter = 1;
  while (await fs.pathExists(path.join(dir, candidate))) {
    candidate = `${name}(${counter})${ext}`;
    counter++;
  }
  return path.join(dir, candidate);
}

function parseIntSafe(v) {
  const n = typeof v === 'number' ? v : parseInt(String(v || ''), 10);
  if (!Number.isFinite(n)) return null;
  return n;
}

function normalizeFormat(v) {
  const f = String(v || '').toLowerCase();
  if (f === 'png' || f === 'jpeg' || f === 'jpg' || f === 'webp') return f === 'jpg' ? 'jpeg' : f;
  return null;
}

const uploadStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    try {
      const baseRoot = getUserZipRoot(req);
      const uploadStartTime = parseIntSafe(req.query && req.query.uploadStartTime) || Date.now();
      const sessionDir = path.join(baseRoot, String(uploadStartTime));
      await fs.ensureDir(sessionDir);
      req._imgZipSessionDir = sessionDir;
      req._imgZipUploadStartTime = uploadStartTime;
      cb(null, sessionDir);
    } catch (err) {
      cb(err);
    }
  },
  filename: function (req, file, cb) {
    try {
      const dir = req._imgZipSessionDir;
      const requested = (req.query && req.query.fileName) || file.originalname || 'file';
      const safeBase = sanitizeFilename(requested);
      const ext = path.extname(safeBase);
      const name = path.basename(safeBase, ext);
      let candidate = safeBase;
      if (dir) {
        let counter = 1;
        while (fs.existsSync(path.join(dir, candidate))) {
          candidate = `${name}(${counter})${ext}`;
          counter++;
        }
      }
      cb(null, candidate);
    } catch (e) {
      cb(e);
    }
  },
});

const uploader = multer({
  storage: uploadStorage,
  limits: { fileSize: 1024 * 1024 * 80 },
}).single('file');

function uploadStage(req, res, next) {
  uploader(req, res, function (err) {
    if (err) {
      if (err.code === 'LIMIT_FILE_SIZE') return ResponseUtil.error(req, res, 'mediaTool.IMAGE_TOO_LARGE', 400);
      return ResponseUtil.error(req, res, 'mediaTool.UPLOAD_FAILED', 400);
    }
    next();
  });
}

async function compressOne(req, inputPath) {
  const inputSize = (req.file && req.file.size) || 0;
  const extLower = path.extname(path.basename(inputPath)).toLowerCase();
  const inputFormatRaw = extLower.replace('.', '').toLowerCase();
  const inputFormat = inputFormatRaw === 'jpg' ? 'jpeg' : inputFormatRaw;

  const quality = (() => {
    const q = parseIntSafe(req.query && req.query.zipQuality);
    if (!q) return 80;
    return Math.min(100, Math.max(1, q));
  })();

  const outSize = (() => {
    const s = parseIntSafe(req.query && req.query.outSize);
    if (!s) return null;
    if (s <= 0 || s >= 99999) return null;
    return s;
  })();

  const withMeta = String(req.query && req.query.withMeta) === '1';
  const requestedFormat = normalizeFormat(req.query && req.query.zipFormat);

  let outputFormat = 'jpeg';
  if (requestedFormat && ['png', 'webp', 'jpeg'].includes(requestedFormat)) {
    outputFormat = requestedFormat;
  } else if (extLower === '.png') {
    outputFormat = 'png';
  } else if (extLower === '.webp') {
    outputFormat = 'webp';
  }

  const outputDir = path.join(path.dirname(inputPath), 'output');
  await fs.ensureDir(outputDir);

  const baseName = path.basename(inputPath, extLower);
  const outputFullPath = await ensureUniquePath(outputDir, `${baseName}.${outputFormat}`);

  const converted = await sharpUtils.transSpcielFormat(inputPath);
  let sharpInstance = createSharpFromConverted(converted).rotate();

  if (outSize) {
    sharpInstance = sharpInstance.resize({
      width: outSize,
      height: outSize,
      fit: 'inside',
      withoutEnlargement: true,
    });
  }

  if (outputFormat === 'png') {
    sharpInstance = sharpInstance.png({
      quality: quality,
      palette: true,
      compressionLevel: 9,
    });
  } else if (outputFormat === 'webp') {
    sharpInstance = sharpInstance.webp({ quality: quality });
  } else {
    sharpInstance = sharpInstance.jpeg({ quality: quality, mozjpeg: true });
  }

  if (withMeta) {
    sharpInstance = sharpInstance.withMetadata();
  }

  await sharpInstance.toFile(outputFullPath);

  let outputSize = 0;
  try {
    const stat = await fs.stat(outputFullPath);
    outputSize = stat && stat.size ? stat.size : 0;
  } catch (_) {}

  if (outputSize > inputSize && inputFormat === outputFormat && inputSize > 0) {
    await fs.remove(outputFullPath).catch(() => {});
    return {
      inputSize,
      outputFullPath: inputPath,
      outputSize: inputSize,
      outputFormat: inputFormatRaw,
    };
  }

  await fs.remove(inputPath).catch(() => {});
  return {
    inputSize,
    outputFullPath,
    outputSize,
    outputFormat,
  };
}

async function uploadAndCompress(req, res) {
  const file = req.file;
  if (!file || !file.path) {
    return ResponseUtil.error(req, res, 'mediaTool.INVALID_PARAMS', 400);
  }

  try {
    const out = await compressOne(req, file.path);
    return ResponseUtil.success(
      req,
      res,
      {
        ...out,
        uploadStartTime: req._imgZipUploadStartTime || parseIntSafe(req.query && req.query.uploadStartTime) || null,
      },
      'mediaTool.IMAGE_COMPRESS_SUCCESS',
      200
    );
  } catch (err) {
    await fs.remove(file.path).catch(() => {});
    return ResponseUtil.error(req, res, 'mediaTool.IMAGE_COMPRESS_FAIL', 500);
  }
}

async function downloadFile(req, res) {
  const p = String((req.query && (req.query.path || req.query.p)) || '');
  if (!p) {
    return ResponseUtil.error(req, res, 'mediaTool.INVALID_PARAMS', 400);
  }

  const userRoot = getUserZipRoot(req);
  const resolved = path.resolve(p);
  if (!isPathWithin(userRoot, resolved)) {
    return ResponseUtil.error(req, res, 'common.FORBIDDEN', 403);
  }

  if (!(await fs.pathExists(resolved))) {
    return ResponseUtil.error(req, res, 'mediaTool.FILE_NOT_FOUND', 404);
  }

  const fileName = sanitizeFilename((req.query && req.query.fileName) || path.basename(resolved));
  return res.download(resolved, fileName);
}

async function downloadZip(req, res) {
  const userRoot = getUserZipRoot(req);
  await fs.ensureDir(userRoot);

  const minTimeStamp = parseIntSafe(req.query && req.query.minTimeStamp);
  const fileName = sanitizeFilename((req.query && req.query.fileName) || 'all-image.zip');

  try {
    const encodedFilename = encodeURIComponent(fileName).replace(/%([0-9A-F]{2})/g, (match, p1) => `%${p1.toUpperCase()}`);
    res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFilename}`);
  } catch (_) {}

  const archive = archiver('zip', { zlib: { level: 0 } });

  archive.on('error', function () {
    try {
      archive.unpipe();
    } catch (_) {}
    if (!res.headersSent) {
      res.removeHeader('Content-Disposition');
      res.status(500).end();
    } else {
      res.destroy();
    }
  });

  res.on('close', () => {
    try {
      archive.destroy();
    } catch (_) {}
  });

  archive.pipe(res);

  const added = new Set();

  async function addFile(filePath) {
    let filename = path.basename(filePath);
    const index = filename.lastIndexOf('.');
    const suffix = index >= 0 ? filename.substring(index) : '';
    const name = index >= 0 ? filename.substring(0, index) : filename;
    let candidate = filename;
    let counter = 1;
    while (added.has(candidate)) {
      candidate = `${name}(${counter})${suffix}`;
      counter++;
    }
    added.add(candidate);
    archive.append(fs.createReadStream(filePath), { name: candidate });
  }

  async function walk(dirPath) {
    let entries = [];
    try {
      entries = await fs.readdir(dirPath);
    } catch (_) {
      return;
    }
    for (const entry of entries) {
      const full = path.join(dirPath, entry);
      let stat;
      try {
        stat = await fs.stat(full);
      } catch (_) {
        continue;
      }
      if (stat.isDirectory()) {
        const base = path.basename(full);
        if (minTimeStamp && /^\d{13}$/.test(base)) {
          const folderTs = parseIntSafe(base);
          if (folderTs && folderTs < minTimeStamp) {
            if (isPathWithin(config.getZipImgTempPath(), full)) {
              fs.remove(full).catch(() => {});
            }
            continue;
          }
        }
        await walk(full);
      } else {
        await addFile(full);
      }
    }
  }

  await walk(userRoot);

  if (added.size === 0) {
    try {
      archive.destroy();
    } catch (_) {}
    return res.status(404).end();
  }

  return archive.finalize();
}

module.exports = {
  uploadStage,
  uploadAndCompress,
  downloadFile,
  downloadZip,
};
