'use strict';

const fs = require('fs');
const path = require('path');
const { fork } = require('child_process');
const config = require('../../config/config');
const sharpUtils = require('../../utils/sharpUtils');

function getFoliateRoot() {
  return config.getFoliateRootPath();
}

function getTinyPathByHash(fileHash) {
  const tinyCachePath = typeof config.getTinyCachePath === 'function' ? config.getTinyCachePath() : '';
  if (!tinyCachePath || !fileHash) return '';
  return path.join(tinyCachePath, `${fileHash}.webp`);
}

async function ensureBookTiny({ filePath, fileHash, coverBuffer = null, size = 500, timeoutMs = 30000 }) {
  const target = getTinyPathByHash(fileHash);
  if (!target) return false;

  try {
    const st = await fs.promises.stat(target);
    if (st && st.isFile() && st.size > 0) return true;
  } catch (_) {}

  let buf = coverBuffer;
  if (!buf) {
    const cover = await extractCoverWithTimeout(filePath, timeoutMs);
    if (!cover || !cover.ok || !cover.coverBuffer) return false;
    buf = cover.coverBuffer;
  }

  const tinyCachePath = path.dirname(target);
  try {
    await sharpUtils.genTinyFile(buf, tinyCachePath, fileHash, 'image', size);
    return true;
  } catch (_) {
    return false;
  }
}

function extractCoverWithTimeout(filePath, timeoutMs = 30000) {
  const workerPath = path.resolve(__dirname, 'bookMetaExtractWorker.js');
  const foliateRoot = getFoliateRoot();
  return new Promise(resolve => {
    let done = false;
    const child = fork(workerPath, [], {
      env: {
        ...process.env,
        WORKER_TYPE: 'bookMetaExtract',
        PATH_DATABASE: process.env.PATH_DATABASE,
        PATH_CACHE: process.env.PATH_CACHE,
        userDataFolder: process.env['userDataFolder'] || (typeof config.getUserDataPath === 'function' ? config.getUserDataPath() : ''),
      },
      windowsHide: true,
    });

    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        try {
          child.kill('SIGKILL');
        } catch (_) {}
        resolve({ ok: false, error: 'timeout' });
      },
      Math.max(1000, Number(timeoutMs || 0) || 0)
    );

    const finish = res => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(res || { ok: false, error: 'no_result' });
      try {
        child.kill();
      } catch (_) {}
    };

    child.on('message', msg => {
      if (!msg || msg.type !== 'result') return;
      finish(msg.data);
    });
    child.on('exit', () => {
      if (done) return;
      finish({ ok: false, error: 'exit_without_result' });
    });
    child.on('error', () => {
      finish({ ok: false, error: 'worker_error' });
    });

    try {
      child.send({ type: 'extract_cover', data: { filePath, foliateRoot } });
    } catch (_) {
      finish({ ok: false, error: 'send_failed' });
    }
  });
}

module.exports = {
  getTinyPathByHash,
  ensureBookTiny,
};
