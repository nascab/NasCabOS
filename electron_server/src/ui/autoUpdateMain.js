// 应用自动更新（主进程侧）
// 自定义请求 yml 文件解析最新版本，仅做检测；有更新时由 UI 在「关于」卡片展示「去下载」按钮

const path = require('path');
const fs = require('fs-extra');
const https = require('https');
const http = require('http');
const { app } = require('electron');

const config = require('../config/config');
const versionConfig = require('../config/versionConfig');

/** 持久化文件：上次检测时间 + 最后一次获取到的最新版本 */
const LAST_UPDATE_INFO_FILE = 'last-update-info.json';
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;


function getUpdatePlatform() {
  const p = process.platform || '';
  return p === 'darwin' || p === 'win32' || p === 'linux' ? p : 'darwin';
}

function getUpdateArch() {
  const a = process.arch || 'x64';
  return a === 'x64' || a === 'arm64' || a === 'ia32' ? a : 'x64';
}

function buildUpdateFeedBaseUrl() {
  try {
    const base = (versionConfig.UPDATE_FEED_URL || '').replace(/\/+$/, '');
    if (!base) return '';
    return `${base}/${getUpdatePlatform()}/${getUpdateArch()}`;
  } catch (e) {
    return '';
  }
}

/** electron-builder generic：darwin 用 latest-mac.yml，其余用 latest.yml */
function getYmlFileName() {
  return process.platform === 'darwin' ? 'latest-mac.yml' : 'latest.yml';
}

function getLastUpdateInfoPath() {
  try {
    return path.join(app.getPath('userData'), LAST_UPDATE_INFO_FILE);
  } catch (e) {
    return path.join(process.cwd(), LAST_UPDATE_INFO_FILE);
  }
}

/** 读取持久化的更新信息 { lastCheck, latestVersion? } */
async function getLastUpdateInfo() {
  try {
    const p = getLastUpdateInfoPath();
    const exists = await fs.pathExists(p);
    if (!exists) return { lastCheck: 0, latestVersion: null };
    const data = await fs.readJson(p).catch(() => ({}));
    return {
      lastCheck: data && typeof data.lastCheck === 'number' ? data.lastCheck : 0,
      latestVersion: data && typeof data.latestVersion === 'string' ? data.latestVersion : null,
    };
  } catch (e) {
    return { lastCheck: 0, latestVersion: null };
  }
}

/** 是否已超过 24 小时未检测，可以再次请求网络 */
async function shouldCheckForUpdate() {
  try {
    const { lastCheck } = await getLastUpdateInfo();
    return Date.now() - lastCheck >= CHECK_INTERVAL_MS;
  } catch (e) {
    return true;
  }
}

/** 持久化：检测时间与最新版本（仅成功解析到版本时写入 latestVersion，否则保留上次） */
async function saveLastUpdateInfo(latestVersion) {
  try {
    const p = getLastUpdateInfoPath();
    const existing = await fs.readJson(p).catch(() => ({}));
    const payload = {
      lastCheck: Date.now(),
      latestVersion: latestVersion != null ? latestVersion : (existing.latestVersion ?? null),
    };
    await fs.writeJson(p, payload, { spaces: 0 });
  } catch (e) {}
}

function safeSend(win, channel, data, Logger) {
  try {
    if (win && !win.isDestroyed()) {
      win.webContents.send(channel, data);
    }
  } catch (e) {
    try {
      if (Logger && Logger.warn) Logger.warn('[autoUpdate] send failed: ' + channel, e && e.message);
    } catch (e2) {}
  }
}

/** 从 yml 内容中解析 version 字段（首行或 version: x.y.z） */
function parseVersionFromYml(ymlContent) {
  try {
    if (!ymlContent || typeof ymlContent !== 'string') return null;
    const m = ymlContent.match(/version:\s*["']?([\d.]+)["']?/m);
    return m ? m[1].trim() : null;
  } catch (e) {
    return null;
  }
}

/** 比较版本 v1 > v2 返回 true */
function isVersionNewer(v1, v2) {
  try {
    if (!v1 || !v2 || typeof v1 !== 'string' || typeof v2 !== 'string') return false;
    const parts1 = v1.split('.').map(Number);
    const parts2 = v2.split('.').map(Number);
    for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
      const a = parts1[i] || 0;
      const b = parts2[i] || 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  } catch (e) {
    return false;
  }
}

/** 请求 yml 内容 */
function fetchYml(url) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;
    const req = protocol.get(url, { timeout: 15000 }, res => {
      const { statusCode } = res;
      if (statusCode !== 200) {
        res.resume();
        reject(new Error(`HTTP ${statusCode}`));
        return;
      }
      let data = '';
      res.setEncoding('utf8');
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => resolve(data));
    });
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('timeout'));
    });
  });
}

/**
 * 执行一次更新检测：请求 yml，解析版本，与当前版本比较。内部异常不向外抛出。
 */
async function checkForUpdateOnce(mainWindow, Logger) {
  try {
    const baseUrl = process.env.NASCAB_UPDATE_URL || buildUpdateFeedBaseUrl();
    if (!baseUrl) {
      if (Logger) Logger.info('[autoUpdate] no update feed url, skip');
      return;
    }

    const ymlName = getYmlFileName();
    const ymlUrl = `${baseUrl.replace(/\/+$/, '')}/${ymlName}`;
    const currentVersion = (app && app.getVersion && app.getVersion()) || '0.0.0';

    if (Logger) Logger.info('[autoUpdate] checking: ' + ymlUrl);
    safeSend(mainWindow, 'update:status', { status: 'checking' }, Logger);

    let ymlContent;
    try {
      ymlContent = await fetchYml(ymlUrl);
    } catch (e) {
      const msg = e && e.message ? String(e.message) : String(e);
      if (Logger) Logger.warn('[autoUpdate] fetch failed', msg);
      safeSend(mainWindow, 'update:status', { status: 'error', message: msg }, Logger);
      await saveLastUpdateInfo(null).catch(() => {});
      return;
    }

    const latestVersion = parseVersionFromYml(ymlContent);
    if (!latestVersion) {
      if (Logger) Logger.warn('[autoUpdate] no version in yml');
      safeSend(mainWindow, 'update:status', { status: 'error', message: 'Invalid yml' }, Logger);
      await saveLastUpdateInfo(null).catch(() => {});
      return;
    }

    await saveLastUpdateInfo(latestVersion).catch(() => {});

    if (isVersionNewer(latestVersion, currentVersion)) {
      if (Logger) Logger.info('[autoUpdate] update available: ' + latestVersion);
      safeSend(mainWindow, 'update:available', { version: latestVersion }, Logger);
    } else {
      if (Logger) Logger.info('[autoUpdate] no update, current=' + currentVersion + ' latest=' + latestVersion);
      safeSend(mainWindow, 'update:status', { status: 'no-update' }, Logger);
    }
  } catch (e) {
    if (Logger) Logger.warn('[autoUpdate] checkForUpdateOnce error', e && e.message);
    try {
      safeSend(mainWindow, 'update:status', { status: 'error', message: (e && e.message) || String(e) }, Logger);
      await saveLastUpdateInfo(null);
    } catch (e2) {}
  }
}

/**
 * 初始化自动更新逻辑：每 24 小时最多检测一次，请求 yml 解析版本并比较
 * @param {Electron.BrowserWindow} mainWindow
 * @param {import('../utils/logger')} Logger
 */
function setupAutoUpdate(mainWindow, Logger) {
  try {
    if (!mainWindow || mainWindow.isDestroyed()) {
      return;
    }

    if (process.env.NASCAB_DISABLE_AUTO_UPDATE === '1') {
      Logger.info('[autoUpdate] auto check disabled by env');
      return;
    }

    (async () => {
      try {
        const currentVersion = (app && app.getVersion && app.getVersion()) || '0.0.0';
        const { latestVersion } = await getLastUpdateInfo();
        if (latestVersion && isVersionNewer(latestVersion, currentVersion)) {
          if (Logger) Logger.info('[autoUpdate] using cached latest version: ' + latestVersion);
          safeSend(mainWindow, 'update:available', { version: latestVersion }, Logger);
        }

        const ok = await shouldCheckForUpdate();
        if (!ok) {
          if (Logger) Logger.info('[autoUpdate] skip network check (within 24h)');
          return;
        }
        await checkForUpdateOnce(mainWindow, Logger);
      } catch (e) {
        if (Logger) Logger.warn('[autoUpdate] setup async error', e && e.message);
      }
    })().catch(() => {});
  } catch (e) {
    if (Logger) Logger.warn('[autoUpdate] setup failed', e && e.message);
  }
}

function getIsQuittingForUpdate() {
  return false;
}

module.exports = {
  setupAutoUpdate,
  getIsQuittingForUpdate,
};
