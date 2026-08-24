'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const { URL } = require('url');
const config = require('../config/config');
const Logger = require('./logger');
const { getPlatformArch } = require('../libsPath/platformArch');

const ONNX_BUNDLE_IDS = ['onnx_models.faces', 'onnx_models.ppocrv5', 'onnx_models.places365'];
const MOUNT_LIB_NAMES = ['rclone', 'openlist', 'sftpgo'];
const PLUGIN_NOT_READY = 'mountShare.PLUGIN_NOT_READY';

let _manifestCache = null;
let _manifestPromise = null;
let _startupSyncPromise = null;
let _mountLibsSyncPromise = null;
let _mountLibSyncing = false;
const _mountLibReady = { rclone: false, openlist: false, sftpgo: false };
const _mountLibDownloading = { rclone: false, openlist: false, sftpgo: false };
const _bundlePromises = new Map();

const LOG_PREFIX = '[remoteAssets]';

function formatBytes(size) {
  const n = Number(size) || 0;
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KiB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(2)} MiB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GiB`;
}

function logCacheState(context = 'status') {
  if (!shouldUseRemoteAssets()) {
    Logger.info(`${LOG_PREFIX} cache disabled`, {
      context,
      mode: 'bundled',
      rootPath: config.getRootPath(),
    });
    return;
  }

  const state = readInstalledState();
  const bundles = state.bundles || {};
  const bundleSummaries = Object.entries(bundles).map(([id, info]) => ({
    bundleId: id,
    version: info && info.version,
    installedAt: info && info.installedAt,
    fileCount: info && info.files ? Object.keys(info.files).length : 0,
    totalSize: info && info.files ? Object.values(info.files).reduce((sum, f) => sum + (Number(f.size) || 0), 0) : 0,
  }));

  let filesRootBytes = 0;
  let filesRootCount = 0;
  try {
    const root = getAssetsFilesRoot();
    if (fs.existsSync(root)) {
      const stack = [root];
      while (stack.length) {
        const dir = stack.pop();
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const abs = path.join(dir, entry.name);
          if (entry.isDirectory()) stack.push(abs);
          else if (entry.isFile()) {
            filesRootCount += 1;
            filesRootBytes += fs.statSync(abs).size;
          }
        }
      }
    }
  } catch (e) {
    Logger.warn(`${LOG_PREFIX} cache scan failed`, { context, error: e && e.message });
  }

  Logger.info(`${LOG_PREFIX} cache state`, {
    context,
    enabled: true,
    manifestUrl: getManifestUrl(),
    manifestCached: !!_manifestCache,
    manifestVersion: _manifestCache && _manifestCache.version,
    manifestPublishedAt: _manifestCache && _manifestCache.publishedAt,
    remoteAssetsRoot: getRemoteAssetsRoot(),
    filesRoot: getAssetsFilesRoot(),
    installedStatePath: getInstalledStatePath(),
    installedBundleCount: bundleSummaries.length,
    cachedFileCount: filesRootCount,
    cachedTotalSize: filesRootBytes,
    cachedTotalSizeHuman: formatBytes(filesRootBytes),
    bundles: bundleSummaries,
  });
}

function describeBundleUpdateReason(installedBundle, remoteBundle) {
  if (!installedBundle) return 'not_installed';
  if (compareVersions(remoteBundle.version, installedBundle.version) > 0) {
    return 'version_upgrade';
  }
  for (const fileEntry of remoteBundle.files) {
    const rel = normalizeRelPath(fileEntry.path);
    const installedFile = installedBundle.files && installedBundle.files[rel];
    const dest = resolvePath(rel);
    if (!installedFile) return 'missing_installed_record';
    if (installedFile.sha256 !== fileEntry.sha256) return 'hash_changed';
    if (!localFileMatches(dest, fileEntry.size, fileEntry.sha256)) return 'local_file_invalid';
  }
  return 'up_to_date';
}

function shouldUseRemoteAssets() {
  return typeof config.shouldUseRemoteAssets === 'function' ? config.shouldUseRemoteAssets() : false;
}

function getManifestUrl() {
  return config.getRemoteAssetsManifestUrl();
}

function getRemoteAssetsRoot() {
  return path.join(config.getUserDataPath(), 'remote_assets');
}

function getAssetsFilesRoot() {
  return path.join(getRemoteAssetsRoot(), 'files');
}

function getInstalledStatePath() {
  return path.join(getRemoteAssetsRoot(), 'installed.json');
}

function normalizeRelPath(relativePath) {
  return String(relativePath || '')
    .replace(/\\/g, '/')
    .replace(/^\/+/, '');
}

function compareVersions(a, b) {
  const pa = String(a || '0')
    .split('.')
    .map(n => parseInt(n, 10) || 0);
  const pb = String(b || '0')
    .split('.')
    .map(n => parseInt(n, 10) || 0);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const da = pa[i] || 0;
    const db = pb[i] || 0;
    if (da > db) return 1;
    if (da < db) return -1;
  }
  return 0;
}

function readInstalledState() {
  try {
    const raw = fs.readFileSync(getInstalledStatePath(), 'utf8');
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : { bundles: {} };
  } catch (_) {
    return { bundles: {} };
  }
}

async function writeInstalledState(state) {
  const root = getRemoteAssetsRoot();
  await fs.promises.mkdir(root, { recursive: true });
  const tmp = `${getInstalledStatePath()}.${process.pid}.${Date.now()}.tmp`;
  await fs.promises.writeFile(tmp, JSON.stringify(state, null, 2), 'utf8');
  await fs.promises.rename(tmp, getInstalledStatePath());
}

function sha256FileSync(filePath) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
}

function resolveBundledPath(relativePath) {
  const rel = normalizeRelPath(relativePath);
  return path.join(config.getRootPath(), ...rel.split('/'));
}

function resolvePath(relativePath) {
  const rel = normalizeRelPath(relativePath);
  if (!shouldUseRemoteAssets()) {
    return resolveBundledPath(rel);
  }
  return path.join(getAssetsFilesRoot(), ...rel.split('/'));
}

function resolveOnnxModelsRoot() {
  return resolvePath('onnx_models');
}

function bundleIdForLib(libName) {
  const { platform, arch } = getPlatformArch();
  return `libs.${libName}.${platform}.${arch}`;
}

function resolveLibBinaryRelativePath(libName) {
  const { platform, arch } = getPlatformArch();
  const binaryName = platform === 'win' ? `${libName}.exe` : libName;
  return normalizeRelPath(path.posix.join('libs', libName, platform, arch, binaryName));
}

function resolveFileUrl(manifest, fileEntry) {
  if (fileEntry.url) return fileEntry.url;
  const base = String(manifest.baseUrl || '').replace(/\/+$/, '');
  const rel = normalizeRelPath(fileEntry.path);
  return `${base}/${rel}`;
}

function fetchText(url, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    let parsed;
    try {
      parsed = new URL(url);
    } catch (e) {
      reject(e);
      return;
    }
    const proto = parsed.protocol === 'http:' ? http : https;
    const req = proto.get(
      parsed,
      { timeout: timeoutMs },
      res => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          fetchText(new URL(res.headers.location, parsed).toString(), timeoutMs).then(resolve, reject);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} for ${url}`));
          res.resume();
          return;
        }
        const chunks = [];
        res.on('data', d => chunks.push(d));
        res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      }
    );
    req.on('timeout', () => {
      req.destroy(new Error(`Timeout fetching ${url}`));
    });
    req.on('error', reject);
  });
}

async function fetchManifest(force = false) {
  if (!shouldUseRemoteAssets()) return null;
  if (_manifestCache && !force) {
    Logger.debug(`${LOG_PREFIX} manifest cache hit`, {
      version: _manifestCache.version,
      publishedAt: _manifestCache.publishedAt,
      bundleCount: _manifestCache.bundles ? Object.keys(_manifestCache.bundles).length : 0,
    });
    return _manifestCache;
  }
  if (_manifestPromise && !force) return _manifestPromise;

  _manifestPromise = (async () => {
    const url = getManifestUrl();
    const startedAt = Date.now();
    Logger.info(`${LOG_PREFIX} manifest fetch start`, { url, force });
    const text = await fetchText(url);
    const manifest = JSON.parse(text);
    if (!manifest || typeof manifest !== 'object' || !manifest.bundles) {
      throw new Error('Invalid remote assets manifest');
    }
    _manifestCache = manifest;
    Logger.info(`${LOG_PREFIX} manifest fetch ok`, {
      url,
      version: manifest.version,
      publishedAt: manifest.publishedAt,
      baseUrl: manifest.baseUrl,
      bundleCount: Object.keys(manifest.bundles).length,
      elapsedMs: Date.now() - startedAt,
    });
    return manifest;
  })();

  try {
    return await _manifestPromise;
  } catch (e) {
    Logger.error(`${LOG_PREFIX} manifest fetch failed`, e, { url: getManifestUrl(), force });
    throw e;
  } finally {
    _manifestPromise = null;
  }
}

function localFileMatches(filePath, expectedSize, expectedSha256) {
  try {
    const st = fs.statSync(filePath);
    if (!st.isFile()) return false;
    if (Number(expectedSize) > 0 && st.size !== Number(expectedSize)) return false;
    if (expectedSha256) {
      return sha256FileSync(filePath) === String(expectedSha256).toLowerCase();
    }
    return true;
  } catch (_) {
    return false;
  }
}


async function downloadFileVerified({ url, destPath, expectedSize, expectedSha256, onProgress, logContext = {} }) {
  await fs.promises.mkdir(path.dirname(destPath), { recursive: true });
  const partialPath = `${destPath}.partial`;
  const relPath = logContext.relPath || destPath;
  const startedAt = Date.now();

  Logger.info(`${LOG_PREFIX} download start`, {
    ...logContext,
    relPath,
    url,
    destPath,
    expectedSize,
    expectedSizeHuman: formatBytes(expectedSize),
  });

  try {
    await new Promise((resolve, reject) => {
      let parsed;
      try {
        parsed = new URL(url);
      } catch (e) {
        reject(e);
        return;
      }

      const proto = parsed.protocol === 'http:' ? http : https;
      let downloaded = 0;
      let lastLoggedPct = -1;

      const req = proto.get(parsed, { timeout: 10 * 60 * 1000 }, res => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          Logger.debug(`${LOG_PREFIX} download redirect`, {
            ...logContext,
            relPath,
            from: url,
            to: new URL(res.headers.location, parsed).toString(),
            statusCode: res.statusCode,
          });
          downloadFileVerified({
            url: new URL(res.headers.location, parsed).toString(),
            destPath,
            expectedSize,
            expectedSha256,
            onProgress,
            logContext,
          })
            .then(resolve, reject);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} downloading ${url}`));
          res.resume();
          return;
        }

        const file = fs.createWriteStream(partialPath, { flags: 'w' });
        res.on('data', chunk => {
          downloaded += chunk.length;
          if (onProgress) onProgress(downloaded, Number(expectedSize) || downloaded);
          const total = Number(expectedSize) || 0;
          if (total > 0) {
            const pct = Math.floor((100 * downloaded) / total);
            if (pct >= lastLoggedPct + 10) {
              lastLoggedPct = pct;
              Logger.info(`${LOG_PREFIX} download progress`, {
                ...logContext,
                relPath,
                downloaded,
                total,
                downloadedHuman: formatBytes(downloaded),
                totalHuman: formatBytes(total),
                percent: pct,
              });
            }
          }
        });
        file.on('error', reject);
        res.on('error', reject);
        res.pipe(file);
        file.on('finish', () => {
          file.close(err => {
            if (err) return reject(err);
            resolve();
          });
        });
      });
      req.on('timeout', () => req.destroy(new Error(`Timeout downloading ${url}`)));
      req.on('error', reject);
    });

    const st = await fs.promises.stat(partialPath);
    if (Number(expectedSize) > 0 && st.size !== Number(expectedSize)) {
      await fs.promises.unlink(partialPath).catch(() => {});
      throw new Error(`Size mismatch for ${destPath}: expected ${expectedSize}, got ${st.size}`);
    }

    Logger.debug(`${LOG_PREFIX} download verify sha256`, { ...logContext, relPath, size: st.size });
    const digest = sha256FileSync(partialPath);
    if (expectedSha256 && digest !== String(expectedSha256).toLowerCase()) {
      await fs.promises.unlink(partialPath).catch(() => {});
      throw new Error(`SHA256 mismatch for ${destPath}`);
    }

    await fs.promises.rename(partialPath, destPath);

    if (process.platform !== 'win32') {
      try {
        await fs.promises.chmod(destPath, 0o755);
      } catch (_) {}
    }

    Logger.info(`${LOG_PREFIX} download ok`, {
      ...logContext,
      relPath,
      destPath,
      size: st.size,
      sizeHuman: formatBytes(st.size),
      sha256: digest,
      elapsedMs: Date.now() - startedAt,
    });
  } catch (e) {
    Logger.error(`${LOG_PREFIX} download failed`, e, {
      ...logContext,
      relPath,
      url,
      destPath,
      elapsedMs: Date.now() - startedAt,
    });
    await fs.promises.unlink(partialPath).catch(() => {});
    throw e;
  }
}

async function installBundle(bundleId, remoteBundle, manifest) {
  const stagingRoot = path.join(getRemoteAssetsRoot(), 'staging', bundleId.replace(/[^\w.-]+/g, '_'));
  await fs.promises.rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
  await fs.promises.mkdir(stagingRoot, { recursive: true });

  const totalSize = remoteBundle.files.reduce((sum, f) => sum + (Number(f.size) || 0), 0);
  const startedAt = Date.now();
  Logger.info(`${LOG_PREFIX} bundle install start`, {
    bundleId,
    version: remoteBundle.version,
    fileCount: remoteBundle.files.length,
    totalSize,
    totalSizeHuman: formatBytes(totalSize),
    stagingRoot,
  });

  for (let i = 0; i < remoteBundle.files.length; i++) {
    const fileEntry = remoteBundle.files[i];
    const rel = normalizeRelPath(fileEntry.path);
    const stagingPath = path.join(stagingRoot, ...rel.split('/'));
    const url = resolveFileUrl(manifest, fileEntry);
    await downloadFileVerified({
      url,
      destPath: stagingPath,
      expectedSize: fileEntry.size,
      expectedSha256: fileEntry.sha256,
      logContext: {
        bundleId,
        bundleVersion: remoteBundle.version,
        fileIndex: i + 1,
        fileTotal: remoteBundle.files.length,
        relPath: rel,
      },
    });
  }

  Logger.info(`${LOG_PREFIX} bundle staging commit start`, {
    bundleId,
    version: remoteBundle.version,
    fileCount: remoteBundle.files.length,
  });

  for (const fileEntry of remoteBundle.files) {
    const rel = normalizeRelPath(fileEntry.path);
    const stagingPath = path.join(stagingRoot, ...rel.split('/'));
    const finalPath = resolvePath(rel);
    await fs.promises.mkdir(path.dirname(finalPath), { recursive: true });
    await fs.promises.rename(stagingPath, finalPath);
    Logger.debug(`${LOG_PREFIX} bundle file committed`, { bundleId, relPath: rel, finalPath });
  }

  await fs.promises.rm(stagingRoot, { recursive: true, force: true }).catch(() => {});

  const state = readInstalledState();
  state.bundles = state.bundles || {};
  state.bundles[bundleId] = {
    version: remoteBundle.version,
    installedAt: new Date().toISOString(),
    files: {},
  };
  for (const fileEntry of remoteBundle.files) {
    const rel = normalizeRelPath(fileEntry.path);
    state.bundles[bundleId].files[rel] = {
      sha256: fileEntry.sha256,
      size: fileEntry.size,
    };
  }
  await writeInstalledState(state);

  Logger.info(`${LOG_PREFIX} bundle install ok`, {
    bundleId,
    version: remoteBundle.version,
    fileCount: remoteBundle.files.length,
    totalSize,
    totalSizeHuman: formatBytes(totalSize),
    elapsedMs: Date.now() - startedAt,
    installedStatePath: getInstalledStatePath(),
  });
  logCacheState(`after_install:${bundleId}`);
}

async function ensureBundle(bundleId) {
  if (!shouldUseRemoteAssets()) return true;

  if (_bundlePromises.has(bundleId)) {
    Logger.debug(`${LOG_PREFIX} bundle ensure waiting`, { bundleId, reason: 'in_flight' });
    return _bundlePromises.get(bundleId);
  }

  const task = (async () => {
    const startedAt = Date.now();
    Logger.info(`${LOG_PREFIX} bundle ensure start`, { bundleId });

    const manifest = await fetchManifest();
    const remoteBundle = manifest.bundles[bundleId];
    if (!remoteBundle) {
      throw new Error(`Bundle not found in manifest: ${bundleId}`);
    }

    const state = readInstalledState();
    const installedBundle = state.bundles && state.bundles[bundleId];
    const reason = describeBundleUpdateReason(installedBundle, remoteBundle);
    const needsUpdate = reason !== 'up_to_date';

    Logger.info(`${LOG_PREFIX} bundle ensure check`, {
      bundleId,
      remoteVersion: remoteBundle.version,
      installedVersion: installedBundle && installedBundle.version,
      installedAt: installedBundle && installedBundle.installedAt,
      fileCount: remoteBundle.files.length,
      needsUpdate,
      reason,
    });

    if (!needsUpdate) {
      Logger.info(`${LOG_PREFIX} bundle cache hit`, {
        bundleId,
        version: remoteBundle.version,
        elapsedMs: Date.now() - startedAt,
      });
      return true;
    }

    await installBundle(bundleId, remoteBundle, manifest);
    Logger.info(`${LOG_PREFIX} bundle ensure ok`, {
      bundleId,
      version: remoteBundle.version,
      reason,
      elapsedMs: Date.now() - startedAt,
    });
    return true;
  })();

  _bundlePromises.set(bundleId, task);
  try {
    return await task;
  } catch (e) {
    Logger.error(`${LOG_PREFIX} bundle ensure failed`, e, { bundleId });
    throw e;
  } finally {
    _bundlePromises.delete(bundleId);
  }
}

async function ensureLib(libName) {
  const bundleId = bundleIdForLib(libName);
  Logger.info(`${LOG_PREFIX} lib ensure start`, { libName, bundleId });
  return ensureBundle(bundleId);
}

function isMountLibCachedOnDisk(libName) {
  if (!shouldUseRemoteAssets()) return true;
  try {
    const bundleId = bundleIdForLib(libName);
    const state = readInstalledState();
    const installed = state.bundles && state.bundles[bundleId];
    if (!installed) return false;
    const rel = resolveLibBinaryRelativePath(libName);
    const dest = resolvePath(rel);
    const manifest = _manifestCache;
    if (manifest && manifest.bundles && manifest.bundles[bundleId]) {
      const upToDate = describeBundleUpdateReason(installed, manifest.bundles[bundleId]) === 'up_to_date';
      // 即使远程版本更新，本地已有的二进制仍然可用
      return upToDate || localFileMatches(dest, 0, null);
    }
    return localFileMatches(dest, 0, null);
  } catch (_) {
    return false;
  }
}

function refreshMountLibReadyFromCache() {
  if (!shouldUseRemoteAssets()) {
    for (const lib of MOUNT_LIB_NAMES) {
      _mountLibReady[lib] = true;
      _mountLibDownloading[lib] = false;
    }
    return;
  }
  for (const lib of MOUNT_LIB_NAMES) {
    if (_mountLibDownloading[lib]) continue;
    const cached = isMountLibCachedOnDisk(lib);
    _mountLibReady[lib] = _mountLibReady[lib] || cached;
  }
}

function isMountLibSyncing() {
  if (!shouldUseRemoteAssets()) return false;
  if (_mountLibSyncing) return true;
  return MOUNT_LIB_NAMES.some(lib => _mountLibDownloading[lib] || !isMountLibReady(lib));
}

function isMountLibReady(libName) {
  if (!shouldUseRemoteAssets()) return true;
  return !!_mountLibReady[libName];
}

function isMountLibDownloading(libName) {
  if (!shouldUseRemoteAssets()) return false;
  return !!_mountLibDownloading[libName];
}

function getMountLibsStatus() {
  refreshMountLibReadyFromCache();
  const enabled = shouldUseRemoteAssets();
  const libs = {};
  for (const lib of MOUNT_LIB_NAMES) {
    libs[lib] = {
      ready: isMountLibReady(lib),
      downloading: isMountLibDownloading(lib),
    };
  }
  return {
    enabled,
    syncing: isMountLibSyncing(),
    libs,
    fileMountReady: isMountLibReady('rclone'),
    openlistMountReady: isMountLibReady('openlist') && isMountLibReady('rclone'),
    fileServerReady: isMountLibReady('sftpgo'),
  };
}

function assertMountLibReady(libName) {
  if (isMountLibReady(libName)) return;
  const err = new Error(PLUGIN_NOT_READY);
  err.statusCode = 503;
  throw err;
}

function assertFileMountPluginReady() {
  assertMountLibReady('rclone');
}

function assertOpenlistMountPluginReady() {
  assertMountLibReady('openlist');
  assertMountLibReady('rclone');
}

function assertFileServerPluginReady() {
  assertMountLibReady('sftpgo');
}

async function syncMountLibsAtStartup() {
  if (!shouldUseRemoteAssets()) {
    refreshMountLibReadyFromCache();
    Logger.info(`${LOG_PREFIX} mount libs startup sync skipped`, { reason: 'remote_assets_disabled' });
    return;
  }
  if (_mountLibsSyncPromise) {
    Logger.debug(`${LOG_PREFIX} mount libs startup sync waiting`, { reason: 'in_flight' });
    return _mountLibsSyncPromise;
  }

  refreshMountLibReadyFromCache();
  const needSync = MOUNT_LIB_NAMES.filter(lib => !isMountLibReady(lib));
  if (needSync.length === 0) {
    Logger.info(`${LOG_PREFIX} mount libs startup sync skipped`, { reason: 'cache_hit', libs: MOUNT_LIB_NAMES });
    return;
  }

  _mountLibSyncing = true;
  for (const lib of needSync) {
    _mountLibDownloading[lib] = true;
  }

  _mountLibsSyncPromise = (async () => {
    const startedAt = Date.now();
    Logger.info(`${LOG_PREFIX} mount libs startup sync start`, {
      libs: needSync,
      manifestUrl: getManifestUrl(),
    });
    logCacheState('mount_libs_startup_before');

    try {
      await fetchManifest();
      refreshMountLibReadyFromCache();
      const pending = MOUNT_LIB_NAMES.filter(lib => !isMountLibReady(lib));
      await Promise.all(
        pending.map(async lib => {
          _mountLibDownloading[lib] = true;
          try {
            await ensureLib(lib);
            _mountLibReady[lib] = true;
            Logger.info(`${LOG_PREFIX} mount lib ready`, { libName: lib });
          } catch (e) {
            _mountLibReady[lib] = isMountLibCachedOnDisk(lib);
            Logger.warn(`${LOG_PREFIX} mount lib sync failed`, {
              libName: lib,
              error: e && e.message ? e.message : String(e),
              cachedFallback: _mountLibReady[lib],
            });
          } finally {
            _mountLibDownloading[lib] = false;
          }
        })
      );
      Logger.info(`${LOG_PREFIX} mount libs startup sync ok`, {
        libs: MOUNT_LIB_NAMES,
        ready: { ..._mountLibReady },
        elapsedMs: Date.now() - startedAt,
      });
      logCacheState('mount_libs_startup_after');
    } catch (e) {
      Logger.warn(`${LOG_PREFIX} mount libs startup sync failed`, {
        error: e && e.message ? e.message : String(e),
        elapsedMs: Date.now() - startedAt,
      });
      logCacheState('mount_libs_startup_failed');
    } finally {
      _mountLibSyncing = false;
    }
  })();

  return _mountLibsSyncPromise;
}

async function syncOnnxModelsAtStartup() {
  if (!shouldUseRemoteAssets()) {
    Logger.info(`${LOG_PREFIX} startup sync skipped`, { reason: 'remote_assets_disabled' });
    return;
  }
  if (_startupSyncPromise) {
    Logger.debug(`${LOG_PREFIX} startup sync waiting`, { reason: 'in_flight' });
    return _startupSyncPromise;
  }

  _startupSyncPromise = (async () => {
    const startedAt = Date.now();
    Logger.info(`${LOG_PREFIX} startup sync start`, {
      bundleIds: ONNX_BUNDLE_IDS,
      manifestUrl: getManifestUrl(),
    });
    logCacheState('startup_before');

    try {
      await fetchManifest();
      for (const bundleId of ONNX_BUNDLE_IDS) {
        await ensureBundle(bundleId);
      }
      Logger.info(`${LOG_PREFIX} startup sync ok`, {
        bundleIds: ONNX_BUNDLE_IDS,
        elapsedMs: Date.now() - startedAt,
      });
      logCacheState('startup_after');
    } catch (e) {
      Logger.warn(`${LOG_PREFIX} startup sync failed`, {
        error: e && e.message ? e.message : String(e),
        elapsedMs: Date.now() - startedAt,
      });
      logCacheState('startup_failed');
    }
  })();

  return _startupSyncPromise;
}

module.exports = {
  ONNX_BUNDLE_IDS,
  MOUNT_LIB_NAMES,
  PLUGIN_NOT_READY,
  shouldUseRemoteAssets,
  getManifestUrl,
  resolvePath,
  resolveOnnxModelsRoot,
  resolveBundledPath,
  bundleIdForLib,
  resolveLibBinaryRelativePath,
  fetchManifest,
  ensureBundle,
  ensureLib,
  syncOnnxModelsAtStartup,
  syncMountLibsAtStartup,
  isMountLibReady,
  isMountLibDownloading,
  getMountLibsStatus,
  assertMountLibReady,
  assertFileMountPluginReady,
  assertOpenlistMountPluginReady,
  assertFileServerPluginReady,
  logCacheState,
};
