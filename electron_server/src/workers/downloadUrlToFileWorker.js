'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const { URL } = require('url');
const Logger = require('../utils/logger');
const knexUtil = require('../db/knexUtil');
const dbUtil = require('../db/dbUtil');
const tableConfig = require('../db/table/tableConfig');
const { TmdbClient } = require('./videoIndex/nfoFetchWorker/tmdbClient');

let started = false;
let dbInitialized = false;

function _sleep(ms) {
  const n = Math.max(0, Number(ms || 0) || 0);
  if (!n) return Promise.resolve();
  return new Promise(resolve => setTimeout(resolve, n));
}

async function ensureDbInit() {
  if (dbInitialized) return;
  try {
    await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
  } catch (e) {
    Logger.error('[downloadUrlToFileWorker] init db failed', e);
  } finally {
    dbInitialized = true;
  }
}

async function getProxyAgent(allowProxy) {
  if (!allowProxy) return undefined;
  await ensureDbInit();
  try {
    const [proxyEnable, proxyUrlRaw] = await Promise.all([tableConfig.getConfigByKey('tmdbProxyEnable').catch(() => null), tableConfig.getConfigByKey('tmdbProxyUrl').catch(() => null)]);
    const enabled = proxyEnable === '1' || proxyEnable === 1;
    const proxyUrl = enabled && proxyUrlRaw ? String(proxyUrlRaw).trim() : '';
    if (!proxyUrl) return undefined;
    const client = new TmdbClient({ apiUrl: 'https://api.tmdb.org', apiToken: '', proxyUrl, language: 'en-US' });
    return client && client._proxyAgent ? client._proxyAgent : undefined;
  } catch (_) {
    return undefined;
  }
}

async function cleanupFile(p) {
  const fp = String(p || '').trim();
  if (!fp) return;
  try {
    await fs.promises.unlink(fp);
  } catch (_) {}
}

function _resolveRedirectUrl(currentUrl, location) {
  const loc = String(location || '').trim();
  if (!loc) return '';
  try {
    const u = new URL(currentUrl);
    const next = new URL(loc, u);
    return next.toString();
  } catch (_) {
    return '';
  }
}

async function downloadToFile({ url, outPath, agent, timeoutMs, maxRedirects = 3 }) {
  const urlStr = String(url || '').trim();
  const out = String(outPath || '').trim();
  if (!urlStr || !out) return false;

  let u;
  try {
    u = new URL(urlStr);
  } catch (_) {
    return false;
  }

  await fs.promises.mkdir(path.dirname(out), { recursive: true });
  await cleanupFile(out);

  return await new Promise(resolve => {
    const proto = u.protocol === 'http:' ? http : https;
    const file = fs.createWriteStream(out, { flags: 'w' });

    let finished = false;
    const finishOnce = ok => {
      if (finished) return;
      finished = true;
      try {
        file.close(() => resolve(!!ok));
      } catch (_) {
        resolve(!!ok);
      }
    };

    const req = proto.request(
      u,
      {
        method: 'GET',
        headers: { Accept: '*/*' },
        agent: u.protocol === 'https:' ? agent : undefined,
      },
      res => {
        const code = Number(res && res.statusCode ? res.statusCode : 0) || 0;
        const isRedirect = code >= 300 && code < 400 && res && res.headers && res.headers.location;
        if (isRedirect) {
          const nextUrl = _resolveRedirectUrl(u.toString(), res.headers.location);
          res.resume();
          file.close(async () => {
            await cleanupFile(out);
            if (!nextUrl || maxRedirects <= 0) return resolve(false);
            const ok = await downloadToFile({ url: nextUrl, outPath: out, agent, timeoutMs, maxRedirects: maxRedirects - 1 });
            return resolve(!!ok);
          });
          return;
        }

        if (code >= 400) {
          res.resume();
          file.close(async () => {
            await cleanupFile(out);
            resolve(false);
          });
          return;
        }

        res.pipe(file);
        file.on('finish', () => finishOnce(true));
        file.on('error', async () => {
          await cleanupFile(out);
          finishOnce(false);
        });
      }
    );

    const timeout = Math.min(300000, Math.max(1000, Number(timeoutMs || 0) || 0)) || 0;
    if (timeout) {
      req.setTimeout(timeout, () => {
        try {
          req.destroy(new Error('timeout'));
        } catch (_) {}
      });
    }

    req.on('error', async () => {
      await cleanupFile(out);
      finishOnce(false);
    });

    req.end();
  });
}

async function runJob({ url, targetPath, tmpPath, timeoutMs, allowProxy }) {
  const u = String(url || '').trim();
  const target = String(targetPath || '').trim();
  const tmp = String(tmpPath || '').trim();
  if (!u || !target || !tmp) return false;

  try {
    const st = await fs.promises.stat(target);
    if (st && st.isFile()) return true;
  } catch (_) {}

  await fs.promises.mkdir(path.dirname(target), { recursive: true });

  const agent = await getProxyAgent(allowProxy);
  const ok = await downloadToFile({ url: u, outPath: tmp, agent, timeoutMs });
  if (!ok) {
    await cleanupFile(tmp);
    return false;
  }

  try {
    const st = await fs.promises.stat(target);
    if (st && st.isFile()) {
      await cleanupFile(tmp);
      return true;
    }
  } catch (_) {}

  try {
    await fs.promises.rename(tmp, target);
    return true;
  } catch (e) {
    await cleanupFile(tmp);
    return false;
  }
}

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') {
    process.exit(0);
    return;
  }
  if (message.type !== 'start') return;
  if (started) return;
  started = true;

  const data = message.data && typeof message.data === 'object' ? message.data : {};
  const url = data.url;
  const targetPath = data.targetPath;
  const tmpPath = data.tmpPath;
  const timeoutMs = data.timeoutMs;
  const allowProxy = !!data.allowProxy;

  Promise.resolve()
    .then(async () => {
      const ok = await runJob({ url, targetPath, tmpPath, timeoutMs, allowProxy });
      await _sleep(50);
      process.exit(ok ? 0 : 1);
    })
    .catch(async e => {
      Logger.error('[downloadUrlToFileWorker] job failed', e);
      await _sleep(50);
      process.exit(1);
    });
});
