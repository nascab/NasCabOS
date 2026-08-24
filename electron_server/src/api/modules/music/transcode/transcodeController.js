const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const FileUtil = require('../../../../utils/fileUtil');
const transCodeUtil = require('../../../../utils/transCodeUtil');
const ffmpegPath = require('../../../../libsPath/ffmpegPath');

const _inflight = new Map();

function _safeString(v) {
  if (v === undefined || v === null) return '';
  return String(v).trim();
}

function _parseRange(rangeHeader, totalSize) {
  const raw = _safeString(rangeHeader);
  if (!raw) return null;
  const m = /^bytes=(\d*)-(\d*)$/i.exec(raw);
  if (!m) return null;
  const startStr = m[1] ?? '';
  const endStr = m[2] ?? '';
  const start = startStr === '' ? null : Number(startStr);
  const end = endStr === '' ? null : Number(endStr);
  if (start !== null && (!Number.isFinite(start) || start < 0)) return null;
  if (end !== null && (!Number.isFinite(end) || end < 0)) return null;
  if (start === null && end === null) return null;

  if (start === null && end !== null) {
    const suffix = end;
    if (suffix <= 0) return null;
    const s = Math.max(0, totalSize - suffix);
    return { start: s, end: totalSize - 1 };
  }

  const s = start ?? 0;
  const e = end ?? totalSize - 1;
  if (s > e) return null;
  if (s >= totalSize) return { invalid: true };
  return { start: s, end: Math.min(e, totalSize - 1) };
}

async function _ensureDir(dirPath) {
  try {
    await fs.promises.mkdir(dirPath, { recursive: true });
  } catch (_) {}
}

async function _statFile(filePath) {
  try {
    return await fs.promises.stat(filePath);
  } catch (_) {
    return null;
  }
}

async function _ensureTranscodedMp3(fullPath) {
  const st = await _statFile(fullPath);
  if (!st || !st.isFile()) {
    const err = new Error('common.NOT_FOUND');
    err.statusCode = 404;
    throw err;
  }

  const keySeed = `${path.resolve(fullPath)}|${st.size}|${st.mtimeMs}|mp3_v1`;
  const key = crypto.createHash('md5').update(keySeed).digest('hex');

  const dir = path.join(os.tmpdir(), 'nascab_music_transcode');
  await _ensureDir(dir);

  const finalPath = path.join(dir, `${key}.mp3`);
  const tempPath = path.join(dir, `${key}.mp3.part`);

  const existed = await _statFile(finalPath);
  if (existed && existed.isFile() && existed.size > 0) {
    return { mp3Path: finalPath };
  }

  const inflight = _inflight.get(key);
  if (inflight) {
    await inflight;
    return { mp3Path: finalPath };
  }

  const promise = (async () => {
    await fs.promises.unlink(tempPath).catch(() => {});

    const input = transCodeUtil.dealFfmpegPath(fullPath);
    const args = ['-hide_banner', '-loglevel', 'error', '-y', '-i', input, '-vn', '-codec:a', 'libmp3lame', '-b:a', '192k', '-f', 'mp3', tempPath];

    await new Promise((resolve, reject) => {
      let stderr = '';
      const p = spawn(ffmpegPath.path, args, { windowsHide: true });
      p.on('error', err => reject(err));
      if (p.stderr) {
        p.stderr.on('data', d => {
          try {
            stderr += String(d);
            if (stderr.length > 8192) stderr = stderr.slice(-8192);
          } catch (_) {}
        });
      }
      p.on('close', code => {
        if (code === 0) return resolve();
        const err = new Error(stderr.trim() ? stderr.trim() : `ffmpeg_exit_${code}`);
        err.statusCode = 500;
        reject(err);
      });
    });

    await fs.promises.rename(tempPath, finalPath).catch(async err => {
      await fs.promises.unlink(tempPath).catch(() => {});
      throw err;
    });
  })();

  _inflight.set(key, promise);
  try {
    await promise;
    return { mp3Path: finalPath };
  } finally {
    _inflight.delete(key);
  }
}

function _sendMp3File(req, res, mp3Path, downloadName) {
  const name = _safeString(downloadName) || path.basename(mp3Path);
  res.setHeader('Content-Type', 'audio/mpeg');
  res.setHeader('Accept-Ranges', 'bytes');
  res.setHeader('Content-Disposition', `inline; filename="${encodeURIComponent(name).replace(/%22/g, '')}"`);

  fs.stat(mp3Path, (err, st) => {
    if (err || !st || !st.isFile()) {
      if (!res.headersSent) res.status(404).end();
      return;
    }

    const total = st.size;
    const range = _parseRange(req.headers.range, total);
    if (range && range.invalid) {
      res.status(416);
      res.setHeader('Content-Range', `bytes */${total}`);
      res.end();
      return;
    }

    const start = range && range.start !== undefined ? range.start : 0;
    const end = range && range.end !== undefined ? range.end : total - 1;

    if (range) {
      res.status(206);
      res.setHeader('Content-Range', `bytes ${start}-${end}/${total}`);
      res.setHeader('Content-Length', String(end - start + 1));
    } else {
      res.status(200);
      res.setHeader('Content-Length', String(total));
    }

    const stream = fs.createReadStream(mp3Path, { start, end });
    const cleanup = () => {
      try {
        stream.destroy();
      } catch (_) {}
    };
    res.on('close', cleanup);
    res.on('error', cleanup);
    stream.on('error', cleanup);
    stream.pipe(res);
  });
}

async function streamMp3(req, res) {
  try {
    const raw = _safeString(req.query && req.query.path);
    if (!raw) return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);

    const fullPath = path.resolve(raw);
    if (FileUtil.isProtectedPath(fullPath)) {
      return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH', 403);
    }

    try {
      await fs.promises.access(fullPath, fs.constants.R_OK);
    } catch (_) {
      return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
    }

    const { mp3Path } = await _ensureTranscodedMp3(fullPath);
    const base = path.parse(fullPath).name || 'audio';
    _sendMp3File(req, res, mp3Path, `${base}.mp3`);
  } catch (err) {
    const status = Number(err && err.statusCode) || 500;
    const key = err && err.message ? String(err.message) : 'common.ERROR';
    if (!res.headersSent) {
      return ResponseUtil.error(req, res, key, status, {
        error: err && err.stack ? String(err.stack) : String(err),
      });
    }
  }
}

module.exports = {
  streamMp3,
};
