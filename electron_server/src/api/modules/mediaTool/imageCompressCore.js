const path = require('path');
const fs = require('fs-extra');
const sharpUtils = require('../../../utils/sharpUtils');

function createSharpFromConverted(converted) {
  if (converted && typeof converted === 'object' && !Buffer.isBuffer(converted) && converted.input && converted.options) {
    const sharp = require('../../../utils/sharpConfigured');
    return sharp(converted.input, converted.options);
  }
  const sharp = require('../../../utils/sharpConfigured');
  return sharp(converted, { failOnError: false });
}

function sanitizeFilename(name) {
  const base = path.basename(String(name || ''));
  return base.replace(/[\\\/]/g, '_').trim() || 'file';
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

function getInputFormatFromPath(filePath) {
  const extLower = path.extname(path.basename(filePath)).toLowerCase();
  const inputFormatRaw = extLower.replace('.', '').toLowerCase();
  const inputFormat = inputFormatRaw === 'jpg' ? 'jpeg' : inputFormatRaw;
  return { extLower, inputFormatRaw, inputFormat };
}

function buildTempPath(finalPath) {
  const dir = path.dirname(finalPath);
  const base = path.basename(finalPath);
  const stamp = `${Date.now()}_${process.pid}_${Math.random().toString(16).slice(2)}`;
  return path.join(dir, `.${base}.${stamp}.nas.tmp`);
}

async function moveTempToFinal({ tempPath, finalPath }) {
  try {
    await fs.move(tempPath, finalPath, { overwrite: false });
  } catch (e) {
    await fs.remove(tempPath).catch(() => {});
    throw e;
  }
}

async function copyFileAtomic({ sourcePath, destPath }) {
  const destDir = path.dirname(destPath);
  await fs.ensureDir(destDir);
  const exists = await fs.pathExists(destPath);
  if (exists) return { ok: false, skipped: true };

  const tempPath = buildTempPath(destPath);
  try {
    await fs.copy(sourcePath, tempPath, { overwrite: true, errorOnExist: false });
    await moveTempToFinal({ tempPath, finalPath: destPath });
    return { ok: true };
  } catch (e) {
    await fs.remove(tempPath).catch(() => {});
    throw e;
  }
}

async function compressImageAtomic({ inputPath, outputPath, outputFormat, quality, outSize, withMeta = false, fallbackCopyIfLargerSameFormat = true }) {
  const { inputFormat } = getInputFormatFromPath(inputPath);
  let inputSize = 0;
  try {
    const stat = await fs.stat(inputPath);
    inputSize = stat && stat.size ? stat.size : 0;
  } catch (_) {}

  const outFmt = String(outputFormat || 'jpeg').toLowerCase();
  const q = Math.min(100, Math.max(1, Number(quality || 80) || 80));
  const s = outSize === undefined || outSize === null ? null : Number(outSize);
  const sizeNum = Number.isFinite(s) && s > 0 ? s : null;

  const destDir = path.dirname(outputPath);
  await fs.ensureDir(destDir);
  const exists = await fs.pathExists(outputPath);
  if (exists) return { ok: false, skipped: true, inputSize: 0, outputSize: 0 };

  const tempPath = buildTempPath(outputPath);
  try {
    const converted = await sharpUtils.transSpcielFormat(inputPath);
    let sharpInstance = createSharpFromConverted(converted).rotate();

    if (sizeNum) {
      sharpInstance = sharpInstance.resize({
        width: sizeNum,
        height: sizeNum,
        fit: 'inside',
        withoutEnlargement: true,
      });
    }

    if (outFmt === 'png') {
      sharpInstance = sharpInstance.png({
        quality: q,
        palette: true,
        compressionLevel: 9,
      });
    } else if (outFmt === 'webp') {
      sharpInstance = sharpInstance.webp({ quality: q });
    } else {
      sharpInstance = sharpInstance.jpeg({ quality: q, mozjpeg: true });
    }

    if (withMeta) {
      sharpInstance = sharpInstance.withMetadata();
    }

    await sharpInstance.toFile(tempPath);
  } catch (e) {
    await fs.remove(tempPath).catch(() => {});
    throw e;
  }

  let outputSize = 0;
  try {
    const stat = await fs.stat(tempPath);
    outputSize = stat && stat.size ? stat.size : 0;
  } catch (_) {}

  if (fallbackCopyIfLargerSameFormat && outputSize > inputSize && inputSize > 0 && inputFormat === outFmt) {
    await fs.remove(tempPath).catch(() => {});
    const copyRes = await copyFileAtomic({ sourcePath: inputPath, destPath: outputPath });
    if (copyRes && copyRes.ok) {
      return { ok: true, inputSize, outputSize: inputSize, outputFormat: inputFormat, copiedOriginal: true };
    }
    return { ok: false, skipped: true, inputSize: 0, outputSize: 0 };
  }

  await moveTempToFinal({ tempPath, finalPath: outputPath });
  return { ok: true, inputSize, outputSize, outputFormat: outFmt, copiedOriginal: false };
}

module.exports = {
  createSharpFromConverted,
  sanitizeFilename,
  ensureUniquePath,
  parseIntSafe,
  normalizeFormat,
  getInputFormatFromPath,
  copyFileAtomic,
  compressImageAtomic,
};
