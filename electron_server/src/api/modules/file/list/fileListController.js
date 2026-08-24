const ResponseUtil = require('../../../apiUtils/responseUtil');
const fileService = require('../core/fileService');
const { hasPermission } = require('../../../../utils/permissionUtil');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Worker } = require('worker_threads');
const tableFileRecent = require('../../../../db/table/tableFileRecent');
const config = require('../../../../config/config');
const UserService = require('../../user/userService');
const userUtil = require('../../../../utils/userUtil');
const FileUtil = require('../../../../utils/fileUtil');
const userShareFolderUtil = require('../../../../utils/userShareFolderUtil');
const userCustomPathUtil = require('../../../../utils/userCustomPathUtil');
const {
  getAppSpecifiedRoots,
  intersectRootLists,
  isPathAllowedByRoots,
  normalizePathItem,
} = require('../../../../utils/appAccessScopeUtil');

const fileListWorkerPath = path.resolve(__dirname, '../../../../workers/fileList/listDirectoryWorker.js');
const sourceTypeConfig = {
  photo: { db: 'dbPhoto', table: 'photo_source' },
  video: { db: 'dbVideo', table: 'video_source' },
  book: { db: 'dbBook', table: 'book_source' },
  music: { db: 'dbMusic', table: 'music_source' },
};

function isAbsoluteLikePath(value) {
  if (typeof value !== 'string') return false;
  const v = value.trim();
  if (!v) return false;
  if (v.startsWith('/') || v.startsWith('\\\\') || v.startsWith('\\')) return true;
  return /^[a-zA-Z]:[\\/]/.test(v);
}

function resolveTargetRelativePath(targetDir, relativePath) {
  const base = typeof targetDir === 'string' ? targetDir.trim() : '';
  const relRaw = typeof relativePath === 'string' ? relativePath.trim() : '';
  if (!base || !relRaw) return null;
  if (isAbsoluteLikePath(relRaw)) return null;

  const normalizedRel = relRaw.replace(/^[\\/]+/, '');
  const parts = normalizedRel.split(/[\\/]+/).filter(Boolean);
  if (parts.length === 0) return null;

  const baseResolved = path.resolve(base);
  const joined = path.join(baseResolved, ...parts);
  const resolved = path.resolve(joined);

  const basePrefix = baseResolved.endsWith(path.sep) ? baseResolved : `${baseResolved}${path.sep}`;
  if (resolved !== baseResolved && !resolved.startsWith(basePrefix)) return null;
  return { baseResolved, resolved, normalizedRel: parts.join(path.sep) };
}

async function runFileListWorkerTask(action, payload, timeoutMs = 20000) {
  const worker = new Worker(fileListWorkerPath);
  let timeout = null;
  let settled = false;
  let terminatePromise = null;

  const terminateOnce = async () => {
    if (!terminatePromise) {
      terminatePromise = await worker.terminate().catch(() => {});
    }
    return terminatePromise;
  };

  try {
    if (typeof worker.unref === 'function') worker.unref();

    return await new Promise((resolve, reject) => {
      const cleanup = () => {
        worker.removeAllListeners('message');
        worker.removeAllListeners('error');
      };

      worker.once('message', async msg => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        await terminateOnce();
        if (msg && msg.ok) return resolve(msg.result);
        const errorMsg = msg && msg.error ? String(msg.error) : 'file.DIRECTORY_LIST_WORKER_ERROR';
        return reject(new Error(errorMsg));
      });

      worker.once('error', err => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        reject(err);
      });

      worker.once('exit', code => {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        reject(new Error(`file.DIRECTORY_LIST_WORKER_EXITED:${code}`));
      });

      timeout = setTimeout(() => {
        if (settled) return;
        settled = true;
        cleanup();
        terminateOnce();
        reject(new Error('file.DIRECTORY_LIST_TIMEOUT'));
      }, timeoutMs);

      try {
        worker.postMessage({ action, payload });
      } catch (err) {
        if (settled) return;
        settled = true;
        cleanup();
        if (timeout) clearTimeout(timeout);
        reject(err);
      }
    });
  } finally {
    if (timeout) clearTimeout(timeout);
    await terminateOnce();
  }
}

function resolveUniquePaths(pathList) {
  return [...new Set(
    (Array.isArray(pathList) ? pathList : [])
      .map(item => (typeof item === 'string' && item.trim() ? normalizePathItem(item.trim()) : ''))
      .filter(Boolean)
  )];
}

function isPathInRoot(targetPath, rootPath) {
  const target = normalizePathItem(String(targetPath || ''));
  const root = normalizePathItem(String(rootPath || ''));
  if (!target || !root) return false;
  if (target === root) return true;
  const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
  return target.startsWith(prefix);
}

async function filterAccessibleDirPaths(pathList) {
  const uniquePaths = resolveUniquePaths(pathList);
  const allowed = [];
  for (const item of uniquePaths) {
    try {
      await fs.promises.access(item, fs.constants.R_OK | fs.constants.X_OK);
      allowed.push(item);
    } catch (_) {}
  }
  return allowed;
}

function trimParentPaths(pathList) {
  const uniquePaths = resolveUniquePaths(pathList);
  return uniquePaths.filter(item => !uniquePaths.some(other => other !== item && isPathInRoot(other, item)));
}

async function getSourceTypePaths(req, sourceType) {
  const sourceTypeStr = sourceType ? String(sourceType).trim().toLowerCase() : '';
  const activeSourceType = sourceTypeConfig[sourceTypeStr];
  if (!activeSourceType) return null;

  const knex = req[activeSourceType.db];
  const sources = await knex(activeSourceType.table).select('path');
  let sourcePaths = await filterAccessibleDirPaths(
    (sources || []).map(item => (item && item.path ? String(item.path) : '')).filter(Boolean)
  );

  const appSpecifiedRoots = await getAppSpecifiedRoots();
  if (appSpecifiedRoots !== null) {
    sourcePaths = await filterAccessibleDirPaths(intersectRootLists(sourcePaths, appSpecifiedRoots));
  }

  if (userUtil.isAdmin(req.user)) {
    return sourcePaths;
  }

  const permittedRoots = await getUserFileAccessibleRoots(req);
  if (!Array.isArray(permittedRoots) || permittedRoots.length === 0 || sourcePaths.length === 0) {
    return [];
  }

  const intersectionPaths = [];
  for (const sourcePath of sourcePaths) {
    if (permittedRoots.some(root => isPathInRoot(sourcePath, root))) {
      intersectionPaths.push(sourcePath);
    }
  }
  for (const permittedRoot of permittedRoots) {
    if (sourcePaths.some(sourcePath => isPathInRoot(permittedRoot, sourcePath))) {
      intersectionPaths.push(permittedRoot);
    }
  }

  const accessibleIntersection = await filterAccessibleDirPaths(intersectionPaths);
  return trimParentPaths(accessibleIntersection);
}

async function list(req, res) {
  try {
    const { path: dirPath, onlyDir = 'true', mode, includeHidden = 'false', source, sourceType } = req.body || {};
    const onlyDirBool = typeof onlyDir === 'string' ? onlyDir === 'true' : !!onlyDir;
    const listDirsOnly = typeof mode === 'string' ? mode === 'dirs' : onlyDirBool;
    const includeHiddenBool = typeof includeHidden === 'string' ? includeHidden === 'true' : !!includeHidden;
    const appSpecifiedRoots = await getAppSpecifiedRoots();
    if (source === 'favorites') {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const favItems = await fileService.listFavoritesByUid(req.dbMain, uid);
      const payload = { base: '', items: favItems, segments: [], sep: require('path').sep };
      return ResponseUtil.success(req, res, payload, 'file.FAV_LIST_SUCCESS', 200);
    }

    if (source === 'recent') {
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);

      const connection = { knex: req.dbMain };
      const keepLimit = 100;
      const rows = await tableFileRecent.listRecentByUid(uid, keepLimit, connection);

      const list = Array.isArray(rows) ? rows : [];
      const itemsByIndex = new Array(list.length);
      const missingPaths = new Set();
      const needCleanup = list.length >= keepLimit;

      const concurrency = Math.min(16, list.length);
      let cursor = 0;
      async function runOne() {
        while (true) {
          const i = cursor++;
          if (i >= list.length) return;
          const r = list[i];
          const p = r && r.path ? String(r.path) : '';
          if (!p) continue;
          try {
            const st = await fs.promises.stat(p);
            const isDir = !st.isFile();
            const size = !isDir ? st.size : null;
            const mtimeMs = st.mtimeMs;
            const ext = isDir ? '' : path.extname(p).toLowerCase();
            const type = config.getFileType(ext);
            itemsByIndex[i] = {
              path: p,
              name: path.basename(p) || p,
              type: isDir ? 'dir' : type,
              size,
              mtimeMs,
              ext,
            };
          } catch (_) {
            missingPaths.add(p);
          }
        }
      }

      await Promise.all(Array.from({ length: concurrency }, () => runOne()));

      if (missingPaths.size > 0) {
        await tableFileRecent.deleteByUidAndPaths(uid, Array.from(missingPaths), connection);
      }

      const items = itemsByIndex.filter(Boolean);
      if (needCleanup) {
        setImmediate(() => {
          tableFileRecent.cleanupByUid(uid, keepLimit, connection).catch(() => {});
        });
      }

      const payload = { base: '', items, segments: [], sep: require('path').sep };
      return ResponseUtil.success(req, res, payload, 'file.RECENT_SUCCESS', 200);
    }

    const sourceTypeStr = sourceType ? String(sourceType).trim().toLowerCase() : '';
    const sourcePaths = await getSourceTypePaths(req, sourceTypeStr);
    if (sourcePaths !== null) {
      if (!req.user || !req.user.id) {
        return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      }

      const buildSourcePayload = async () => {
        return runFileListWorkerTask('listSourceDirs', { sourcePaths });
      };

      const dirPathStr = typeof dirPath === 'string' ? dirPath : '';
      if (!dirPathStr) {
        const payload = await buildSourcePayload();
        return ResponseUtil.success(req, res, payload, 'file.DIRECTORY_LIST_FETCH_SUCCESS', 200);
      }

      const resolvedDirPath = path.resolve(dirPathStr);
      const isInSources = sourcePaths.some(sourcePath => isPathInRoot(resolvedDirPath, sourcePath));
      if (!isInSources) {
        const payload = await buildSourcePayload();
        return ResponseUtil.success(req, res, payload, 'file.DIRECTORY_LIST_FETCH_SUCCESS', 200);
      }

      const result = await runFileListWorkerTask('listDirectory', {
        dirPath: dirPathStr,
        onlyDir: listDirsOnly,
        includeHidden: includeHiddenBool,
      });
      return ResponseUtil.success(req, res, result, 'file.DIRECTORY_LIST_FETCH_SUCCESS', 200);
    }

    async function returnRoot() {
      const uid = req.user && req.user.id;
      const customNameByPath = new Map();
      let customPaths = [];
      if (uid) {
        const rawCustom = await userCustomPathUtil.getUserCustomPaths(uid, { includeMissing: false });
        const isAdmin = userUtil.isAdmin(req.user);
        const out = [];
        for (const e of rawCustom) {
          const p = e && e.path ? String(e.path).trim() : '';
          if (!p) continue;
          const resolved = path.resolve(p);
          let canView = isAdmin;
          if (!canView) {
            canView = await hasPermission(req.dbMain, req.user, ['download', 'view'], resolved);
            if (!canView) {
              const isUserShare = await userShareFolderUtil.isUserSharePath(resolved);
              if (isUserShare) canView = true;
            }
          }
          if (!canView) continue;
          try {
            await fs.promises.access(resolved, fs.constants.R_OK | fs.constants.X_OK);
          } catch (_) {
            continue;
          }
          out.push(resolved);
          const n = e && e.name !== undefined && e.name !== null ? String(e.name).trim() : '';
          if (n) customNameByPath.set(resolved, n);
        }
        customPaths = out;
      }

      let payload = null;
      if (userUtil.isAdmin(req.user)) {
        if (appSpecifiedRoots !== null) {
          const limitedRoots = await filterAccessibleDirPaths(appSpecifiedRoots);
          payload = await runFileListWorkerTask('listPathList', {
            pathList: limitedRoots,
            onlyDir: listDirsOnly,
            includeHidden: includeHiddenBool,
            base: '',
          });
        } else {
          const roots = await runFileListWorkerTask('getRoots', {});
          let customItems = [];
          if (customPaths.length > 0) {
            const customPayload = await runFileListWorkerTask('listPathList', {
              pathList: customPaths,
              onlyDir: listDirsOnly,
              includeHidden: includeHiddenBool,
              base: '',
            });
            customItems = (customPayload && Array.isArray(customPayload.items) ? customPayload.items : []).map(it => {
              const p = it && it.path ? String(it.path) : '';
              const customName = p && customNameByPath.has(p) ? customNameByPath.get(p) : null;
              return {
                ...it,
                name: customName || it.name,
                isCustomPath: true,
              };
            });
          }
          const merged = [];
          const seen = new Set();
          for (const r of Array.isArray(roots) ? roots : []) {
            const p = r && r.path ? String(r.path) : '';
            if (!p) continue;
            if (seen.has(p)) continue;
            seen.add(p);
            merged.push(r);
          }
          for (const c of customItems) {
            const p = c && c.path ? String(c.path) : '';
            if (!p) continue;
            if (seen.has(p)) continue;
            seen.add(p);
            merged.push(c);
          }
          payload = { base: '', items: merged, segments: [], sep: path.sep };
        }
      } else {
        const userService = new UserService(req.dbMain);
        const roots = await userService.getUserVisiablePath(req.user.id);
        const userShareFolders = await userShareFolderUtil.getUserShareFolders({ includeMissing: false });
        const userShareByPath = new Map(userShareFolders.map(i => [i.path, i]));
        const userSharePaths = userShareFolders.map(i => i.path).filter(Boolean);
        const customSet = new Set(customPaths);
        const mergedRoots = Array.from(
          new Set(
            []
              .concat(Array.isArray(roots) ? roots : [])
              .concat(userSharePaths)
              .concat(customPaths)
              .map(p => (typeof p === 'string' && p.trim() ? normalizePathItem(p.trim()) : ''))
              .filter(Boolean)
          )
        );
        const effectiveRoots = appSpecifiedRoots !== null
          ? intersectRootLists(mergedRoots, appSpecifiedRoots)
          : mergedRoots;
        payload = await runFileListWorkerTask('listPathList', {
          pathList: effectiveRoots,
          onlyDir: listDirsOnly,
          includeHidden: includeHiddenBool,
          base: '',
        });
        if (payload && Array.isArray(payload.items) && userShareByPath.size > 0) {
          payload.items = payload.items.map(it => {
            const p = it && it.path ? String(it.path) : '';
            if (!p || !userShareByPath.has(p)) return it;
            const entry = userShareByPath.get(p);
            return {
              ...it,
              isUserShareFolder: true,
              allowDownload: !!entry?.allowDownload,
            };
          });
        }
        if (payload && Array.isArray(payload.items) && customSet.size > 0) {
          payload.items = payload.items.map(it => {
            const p = it && it.path ? String(it.path) : '';
            if (!p || !customSet.has(p)) return it;
            const customName = customNameByPath.has(p) ? customNameByPath.get(p) : null;
            return {
              ...it,
              name: customName || it.name,
              isCustomPath: true,
            };
          });
        }
      }
      return ResponseUtil.success(req, res, payload, 'file.DIRECTORY_LIST_FETCH_SUCCESS', 200);
    }
    // console.log("获取文件列表",dirPath)

    if (!dirPath || dirPath === '') {
      return await returnRoot();
    }
    if (typeof dirPath !== 'string') {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);
    }
    if (appSpecifiedRoots !== null && !isPathAllowedByRoots(dirPath, appSpecifiedRoots)) {
      return await returnRoot();
    }
    let canView = await hasPermission(req.dbMain, req.user, ['download', 'view'], dirPath);
    if (!canView) {
      const isUserShare = await userShareFolderUtil.isUserSharePath(dirPath);
      if (isUserShare) canView = true;
    }
    if (!canView) {
      return await returnRoot();
    }
    const result = await runFileListWorkerTask('listDirectory', {
      dirPath,
      onlyDir: listDirsOnly,
      includeHidden: includeHiddenBool,
    });
    return ResponseUtil.success(req, res, result, 'file.DIRECTORY_LIST_FETCH_SUCCESS', 200);
  } catch (err) {
    console.log(err);
    return ResponseUtil.error(req, res, 'file.DIRECTORY_LIST_FETCH_FAILED', 400, {
      error: err.message,
    });
  }
}
async function getRoots(req, res) {
  try {
    const roots = await fileService.getRoots();
    return ResponseUtil.success(req, res, roots, 'file.ROOTS_FETCH_SUCCESS', 200);
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.ROOTS_FETCH_FAILED', 500);
  }
}

async function getAttributes(req, res) {
  try {
    const { path: filePath } = req.query;
    if (!filePath) {
      return ResponseUtil.error(req, res, 'file.INVALID_PATH');
    }

    const stat = await fs.promises.stat(filePath);
    const result = {
      path: filePath,
      name: path.basename(filePath),
      size: stat.size,
      mtime: stat.mtimeMs,
      birthtime: stat.birthtimeMs,
      isDirectory: stat.isDirectory(),
      isFile: stat.isFile(),
    };

    return ResponseUtil.success(req, res, result);
  } catch (err) {
    if (err.code === 'ENOENT') {
      return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND', 404);
    }
    return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, {
      error: err.message,
    });
  }
}

async function getResolvedAttributes(req, res) {
  try {
    const { targetDir, relativePath } = req.query || {};
    const resolved = resolveTargetRelativePath(targetDir, relativePath);
    if (!resolved) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const canView = await hasPermission(req.dbMain, req.user, ['view'], resolved.resolved);
    if (!canView) {
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    try {
      const stat = await fs.promises.stat(resolved.resolved);
      const result = {
        exists: true,
        targetDir: resolved.baseResolved,
        relativePath: resolved.normalizedRel,
        path: resolved.resolved,
        name: path.basename(resolved.resolved),
        size: stat.size,
        mtime: stat.mtimeMs,
        birthtime: stat.birthtimeMs,
        isDirectory: stat.isDirectory(),
        isFile: stat.isFile(),
      };
      return ResponseUtil.success(req, res, result);
    } catch (err) {
      if (err && err.code === 'ENOENT') {
        const result = {
          exists: false,
          targetDir: resolved.baseResolved,
          relativePath: resolved.normalizedRel,
          path: resolved.resolved,
          name: path.basename(resolved.resolved),
          size: null,
          mtime: null,
          birthtime: null,
          isDirectory: false,
          isFile: false,
        };
        return ResponseUtil.success(req, res, result);
      }
      return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, {
        error: err && err.message ? String(err.message) : String(err),
      });
    }
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, {
      error: err && err.message ? String(err.message) : String(err),
    });
  }
}

async function getExists(req, res) {
  try {
    const { targetDir, relativePath } = req.query || {};
    const resolved = resolveTargetRelativePath(targetDir, relativePath);
    if (!resolved) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const canView = await hasPermission(req.dbMain, req.user, ['view'], resolved.resolved);
    if (!canView) {
      return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
    }

    try {
      await fs.promises.stat(resolved.resolved);
      return ResponseUtil.success(req, res, {
        exists: true,
        targetDir: resolved.baseResolved,
        relativePath: resolved.normalizedRel,
        path: resolved.resolved,
      });
    } catch (err) {
      if (err && err.code === 'ENOENT') {
        return ResponseUtil.success(req, res, {
          exists: false,
          targetDir: resolved.baseResolved,
          relativePath: resolved.normalizedRel,
          path: resolved.resolved,
        });
      }
      return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, {
        error: err && err.message ? String(err.message) : String(err),
      });
    }
  } catch (err) {
    return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, {
      error: err && err.message ? String(err.message) : String(err),
    });
  }
}

function parsePositiveInt(value) {
  const n = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

async function computeMd5Full(filePath) {
  return await new Promise((resolve, reject) => {
    const hash = crypto.createHash('md5');
    const stream = fs.createReadStream(filePath, { highWaterMark: 1024 * 1024 });
    stream.on('data', chunk => hash.update(chunk));
    stream.on('error', reject);
    stream.on('end', () => resolve(hash.digest('hex')));
  });
}

async function computeMd5HeadTail(filePath, fileSize, chunkSizeBytes) {
  const headLen = Math.min(chunkSizeBytes, fileSize);
  const tailLen = Math.min(chunkSizeBytes, fileSize);
  const headBuf = Buffer.allocUnsafe(headLen);
  const tailBuf = Buffer.allocUnsafe(tailLen);

  const fh = await fs.promises.open(filePath, 'r');
  try {
    const headRead = await fh.read(headBuf, 0, headLen, 0);
    const tailRead = await fh.read(tailBuf, 0, tailLen, Math.max(0, fileSize - tailLen));

    const hash = crypto.createHash('md5');
    if (headRead && headRead.bytesRead > 0) hash.update(headBuf.subarray(0, headRead.bytesRead));
    if (tailRead && tailRead.bytesRead > 0) hash.update(tailBuf.subarray(0, tailRead.bytesRead));
    return hash.digest('hex');
  } finally {
    await fh.close().catch(() => {});
  }
}

async function getMd5(req, res) {
  try {
    const { path: filePath, thresholdBytes, chunkSizeBytes } = req.query || {};
    const p = typeof filePath === 'string' ? filePath.trim() : '';
    if (!p) return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);

    const threshold = parsePositiveInt(thresholdBytes) ?? 50 * 1024 * 1024;
    const chunkSize = parsePositiveInt(chunkSizeBytes) ?? 1024 * 1024;
    if (threshold < 1 || chunkSize < 1 || chunkSize > 64 * 1024 * 1024) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    let stat;
    try {
      stat = await fs.promises.stat(p);
    } catch (err) {
      if (err && err.code === 'ENOENT') return ResponseUtil.error(req, res, 'file.FILE_NOT_FOUND', 404);
      return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, { error: err && err.message ? String(err.message) : String(err) });
    }

    if (!stat.isFile()) {
      return ResponseUtil.error(req, res, 'file.INVALID_PARAMS', 400);
    }

    const size = stat.size;
    const strategy = size < threshold ? 'full' : 'head_tail';
    const md5 = strategy === 'full' ? await computeMd5Full(p) : await computeMd5HeadTail(p, size, chunkSize);

    return ResponseUtil.success(req, res, {
      path: p,
      size,
      mtime: stat.mtimeMs,
      strategy,
      thresholdBytes: threshold,
      chunkSizeBytes: chunkSize,
      md5,
    });
  } catch (err) {
    return ResponseUtil.error(req, res, 'common.ERROR', 500, {
      error: err && err.message ? String(err.message) : String(err),
    });
  }
}

// Windows 下判断是否为盘符根目录（如 C:\、D:\），这些路径应做实际可访问性检查而非直接视为受保护
function isWindowsDriveRoot(filePath) {
  if (process.platform !== 'win32' || !filePath || typeof filePath !== 'string') return false;
  const normalized = path.normalize(filePath).replace(/[/\\]+$/, '') || '';
  return /^[a-zA-Z]:$/.test(normalized);
}

// 通过实际写入并删除临时文件检测目录是否可写（比 fs.access(W_OK) 更可靠，尤其 Windows）
async function canWriteDirByTestFile(dirPath) {
  const tmpName = `.nascab_access_check_${Date.now()}_${Math.random().toString(36).slice(2)}`;
  const tmpPath = path.join(dirPath, tmpName);
  try {
    await fs.promises.writeFile(tmpPath, '', 'utf8');
    await fs.promises.unlink(tmpPath);
    return true;
  } catch (_) {
    try {
      await fs.promises.unlink(tmpPath).catch(() => {});
    } catch (_) {}
    return false;
  }
}

async function getFsAccess(req, res) {
  try {
    const { path: rawPath } = req.query || {};
    console.log('getFsAccess', rawPath);
    const raw = typeof rawPath === 'string' ? rawPath.trim() : '';
    if (!raw) return ResponseUtil.error(req, res, 'file.INVALID_PATH', 400);

    const resolvedPath = path.resolve(raw);
    const isDriveRoot = isWindowsDriveRoot(resolvedPath);
    console.log('isDriveRoot', isDriveRoot);
    // Windows 盘符根目录不做“受保护”提前返回，而是继续做实际可访问性检查
    if (!isDriveRoot && FileUtil.isProtectedPath(resolvedPath)) {
      return ResponseUtil.success(req, res, {
        path: resolvedPath,
        exists: null,
        isDirectory: null,
        canRead: false,
        canWrite: false,
        isProtected: true,
      });
    }

    let exists = false;
    let isDirectory = false;
    try {
      const st = await fs.promises.stat(resolvedPath);
      exists = true;
      isDirectory = st && typeof st.isDirectory === 'function' ? st.isDirectory() : false;
    } catch (err) {
      if (err && err.code !== 'ENOENT') {
        return ResponseUtil.error(req, res, 'file.GET_ATTRIBUTES_FAILED', 500, {
          error: err && err.message ? String(err.message) : String(err),
        });
      }
    }

    if (!exists) {
      return ResponseUtil.success(req, res, {
        path: resolvedPath,
        exists: false,
        isDirectory: false,
        canRead: false,
        canWrite: false,
        isProtected: false,
      });
    }

    if (!isDirectory) {
      return ResponseUtil.success(req, res, {
        path: resolvedPath,
        exists: true,
        isDirectory: false,
        canRead: false,
        canWrite: false,
        isProtected: false,
      });
    }

    let canRead = false;
    let canWrite = false;

    try {
      await fs.promises.access(resolvedPath, fs.constants.R_OK | fs.constants.X_OK);
      canRead = true;
    } catch (_) {}

    try {
      await fs.promises.access(resolvedPath, fs.constants.W_OK | fs.constants.X_OK);
      canWrite = true;
    } catch (_) {}

    // 对目录：若 access 认为不可写，再用“实际写临时文件”兜底，避免 Windows 等平台误判
    if (!canWrite && isDirectory) {
      canWrite = await canWriteDirByTestFile(resolvedPath);
    }

    return ResponseUtil.success(req, res, {
      path: resolvedPath,
      exists: true,
      isDirectory: true,
      canRead,
      canWrite,
      isProtected: false,
    });
  } catch (err) {
    return ResponseUtil.error(req, res, 'common.ERROR', 500, {
      error: err && err.message ? String(err.message) : String(err),
    });
  }
}

function _toRows(raw) {
  if (Array.isArray(raw)) return raw;
  if (raw && Array.isArray(raw.rows)) return raw.rows;
  if (raw && Array.isArray(raw[0])) return raw[0];
  return [];
}

function _normalizeSuffixes(rawList) {
  const input = Array.isArray(rawList) ? rawList : rawList ? [rawList] : [];
  const out = [];
  const seen = new Set();
  for (const v of input) {
    const s = v === null || v === undefined ? '' : String(v).trim().toLowerCase();
    if (!s) continue;
    const ext = s.startsWith('.') ? s : `.${s}`;
    if (ext.length > 20) continue;
    if (seen.has(ext)) continue;
    seen.add(ext);
    out.push(ext);
  }
  return out;
}

function _normalizeKeyword(raw) {
  const s = raw === null || raw === undefined ? '' : String(raw).trim();
  if (!s) return '';
  const parts = s
    .toLowerCase()
    .replace(/["'`]/g, ' ')
    .split(/[\s\\/]+/)
    .map(t => t.trim())
    .filter(Boolean)
    .slice(0, 12);
  if (parts.length === 0) return '';
  return parts.map(t => `${t}*`).join(' ');
}

function _normalizeFilenameKeyword(raw) {
  const s = raw === null || raw === undefined ? '' : String(raw).trim();
  if (!s) return '';
  const parts = s
    .toLowerCase()
    .replace(/["'`]/g, ' ')
    .split(/[\s\\/]+/)
    .map(t => t.trim())
    .filter(Boolean)
    .slice(0, 12)
    .map(t => t.replace(/:/g, '').trim())
    .filter(Boolean);
  if (parts.length === 0) return '';
  return parts.map(t => `filename:${t}*`).join(' ');
}

function _clampInt(v, { min, max, def }) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return def;
  if (n < min) return min;
  if (n > max) return max;
  return n;
}

async function _fillItemStats(items) {
  const list = Array.isArray(items) ? items : [];
  if (list.length === 0) return list;

  const concurrency = Math.min(24, list.length);
  let cursor = 0;

  async function runOne() {
    while (true) {
      const i = cursor++;
      if (i >= list.length) return;
      const it = list[i];
      const p = it && it.path ? String(it.path) : '';
      if (!p) continue;
      try {
        const st = await fs.promises.stat(p);
        it.mtimeMs = st && typeof st.mtimeMs === 'number' ? st.mtimeMs : null;
        if (it.type === 'dir') {
          it.size = null;
        } else {
          it.size = st && typeof st.size === 'number' ? st.size : null;
        }
      } catch (_) {}
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => runOne()));
  return list;
}

async function _deleteFileIndexRowsByPathFilename(dbFile, pairs) {
  if (!dbFile || typeof dbFile.raw !== 'function') return;
  const list = Array.isArray(pairs) ? pairs : [];
  if (list.length === 0) return;

  const tableName = 'file_index_fts';
  const chunkSize = 200;

  for (let i = 0; i < list.length; i += chunkSize) {
    const chunk = list.slice(i, i + chunkSize).filter(p => p && p.path && p.filename);
    if (chunk.length === 0) continue;
    const where = chunk.map(() => '(path = ? AND filename = ?)').join(' OR ');
    const binds = [];
    for (const p of chunk) {
      binds.push(String(p.path), String(p.filename));
    }
    await dbFile.raw(`DELETE FROM ${tableName} WHERE ${where}`, binds).catch(() => {});
  }
}

async function _fillItemStatsAndCleanupMissingIndexRows(items, dbFile) {
  const list = Array.isArray(items) ? items : [];
  if (list.length === 0) return list;

  const missingPairs = [];
  const concurrency = Math.min(24, list.length);
  let cursor = 0;

  async function runOne() {
    while (true) {
      const i = cursor++;
      if (i >= list.length) return;
      const it = list[i];
      const p = it && it.path ? String(it.path) : '';
      if (!p) {
        if (it) it.__missing = true;
        continue;
      }
      try {
        const st = await fs.promises.stat(p);
        it.mtimeMs = st && typeof st.mtimeMs === 'number' ? st.mtimeMs : null;
        if (it.type === 'dir') {
          it.size = null;
        } else {
          it.size = st && typeof st.size === 'number' ? st.size : null;
        }
      } catch (_) {
        if (it) it.__missing = true;
        const idxPath = it && it.__idxPath ? String(it.__idxPath) : '';
        const idxName = it && it.__idxName ? String(it.__idxName) : '';
        if (idxPath && idxName) missingPairs.push({ path: idxPath, filename: idxName });
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => runOne()));

  if (missingPairs.length > 0) {
    const unique = new Map();
    for (const p of missingPairs) {
      unique.set(`${p.path}\n${p.filename}`, p);
    }
    await _deleteFileIndexRowsByPathFilename(dbFile, Array.from(unique.values()));
  }

  const out = [];
  for (const it of list) {
    if (!it || it.__missing) continue;
    delete it.__missing;
    delete it.__idxPath;
    delete it.__idxName;
    out.push(it);
  }

  return out;
}

/**
 * 与文件列表「根目录」一致：子用户可浏览的目录根（可见路径 + 用户共享 + 有权限的自定义路径）。
 * 管理员返回 null，表示不在 SQL 层按根路径限制。
 */
async function getUserFileAccessibleRoots(req) {
  if (!req.user || !req.user.id) return [];
  if (userUtil.isAdmin(req.user)) return null;

  const uid = req.user.id;
  const userService = new UserService(req.dbMain);
  const roots = await userService.getUserVisiablePath(uid);
  const userShareFolders = await userShareFolderUtil.getUserShareFolders({ includeMissing: false });
  const userSharePaths = (userShareFolders || []).map(i => i && i.path).filter(Boolean);
  const rawCustom = await userCustomPathUtil.getUserCustomPaths(uid, { includeMissing: false });
  const customPaths = [];
  for (const e of rawCustom || []) {
    const p = e && e.path ? String(e.path).trim() : '';
    if (!p) continue;
    const resolved = normalizePathItem(p);
    let canView = await hasPermission(req.dbMain, req.user, ['download', 'view'], resolved);
    if (!canView) {
      const isUserShare = await userShareFolderUtil.isUserSharePath(resolved);
      if (isUserShare) canView = true;
    }
    if (!canView) continue;
    try {
      await fs.promises.access(resolved, fs.constants.R_OK | fs.constants.X_OK);
      customPaths.push(resolved);
    } catch (_) {}
  }
  const merged = []
    .concat(Array.isArray(roots) ? roots : [])
    .concat(userSharePaths)
    .concat(customPaths)
    .map(p => (typeof p === 'string' && p.trim() ? normalizePathItem(p.trim()) : ''))
    .filter(Boolean);
  return [...new Set(merged)];
}

/** FTS 表中 path 为「父目录」列，与 globalSearch 里按子目录限定一致 */
function _pushPathUnderAnyRootsCondition(whereParts, binds, rootPaths) {
  const roots = Array.isArray(rootPaths) ? rootPaths.filter(Boolean) : [];
  if (roots.length === 0) {
    whereParts.push('(1=0)');
    return;
  }
  const orParts = [];
  for (const r of roots) {
    const resolved = normalizePathItem(String(r));
    const base =
      resolved.endsWith(path.sep) && resolved.length > 1 ? resolved.slice(0, -1) : resolved;
    const likePrefix = `${base}${path.sep}`;
    orParts.push(`(path = ? OR path LIKE ?)`);
    binds.push(base, `${likePrefix}%`);
  }
  whereParts.push(`(${orParts.join(' OR ')})`);
}

async function _filterGlobalSearchItemsByPermission(req, items) {
  const list = Array.isArray(items) ? items : [];
  const results = await Promise.all(
    list.map(async it => {
      const fp = it && it.path ? String(it.path) : '';
      if (!fp) return null;
      let ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], fp);
      if (!ok) {
        const isUserShare = await userShareFolderUtil.isUserSharePath(fp);
        if (isUserShare) ok = true;
      }
      return ok ? it : null;
    })
  );
  return results.filter(Boolean);
}

async function globalSearch(req, res) {
  try {
    const body = req.body || {};
    const rawDir = body.directory ?? body.base ?? body.dir ?? '';
    const rawKeyword = body.keyword ?? body.q ?? body.search ?? '';
    const rawMode = body.mode ?? body.type ?? '';
    const sourceTypeStr = body.sourceType ? String(body.sourceType).trim().toLowerCase() : '';
    const suffixes = _normalizeSuffixes(body.suffixes ?? body.suffixList ?? body.exts ?? body.extList);
    const limit = _clampInt(body.limit, { min: 1, max: 500, def: 200 });
    const offset = _clampInt(body.offset, { min: 0, max: 100000, def: 0 });

    const match = _normalizeFilenameKeyword(rawKeyword);
    const dirResolved = typeof rawDir === 'string' && rawDir.trim() ? path.resolve(rawDir) : '';
    const mode = typeof rawMode === 'string' ? rawMode.trim().toLowerCase() : '';
    const sourceRoots = await getSourceTypePaths(req, sourceTypeStr);

    if (!match && !dirResolved && suffixes.length === 0) {
      return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
    }

    // 指定子目录检索：必须对该目录有浏览权限（与 list 一致），防止子用户传任意路径扫索引
    if (dirResolved) {
      let canViewDir = sourceRoots !== null
        ? sourceRoots.some(root => isPathInRoot(dirResolved, root))
        : await hasPermission(req.dbMain, req.user, ['download', 'view'], dirResolved);
      if (!canViewDir && sourceRoots === null) {
        const isUserShare = await userShareFolderUtil.isUserSharePath(dirResolved);
        if (isUserShare) canViewDir = true;
      }
      if (!canViewDir) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }
    }

    const whereParts = [];
    const binds = [];
    const tableName = 'file_index_fts';

    if (match) {
      whereParts.push(`${tableName} MATCH ?`);
      binds.push(match);
    }

    if (dirResolved) {
      const base = dirResolved.endsWith(path.sep) && dirResolved.length > 1 ? dirResolved.slice(0, -1) : dirResolved;
      const likePrefix = `${base}${path.sep}`;
      whereParts.push(`(path = ? OR path LIKE ?)`);
      binds.push(base, `${likePrefix}%`);
    } else {
      const accessibleRoots = sourceRoots !== null ? sourceRoots : await getUserFileAccessibleRoots(req);
      if (accessibleRoots !== null) {
        if (accessibleRoots.length === 0) {
          return ResponseUtil.success(
            req,
            res,
            { base: '', items: [], segments: [], sep: path.sep },
            'file.GLOBAL_SEARCH_SUCCESS',
            200
          );
        }
        _pushPathUnderAnyRootsCondition(whereParts, binds, accessibleRoots);
      }
    }

    if (mode === 'dir') {
      whereParts.push(`ext = ?`);
      binds.push('__dir__');
    } else if (mode === 'file') {
      whereParts.push(`ext != ?`);
      binds.push('__dir__');
    }

    if (suffixes.length > 0) {
      whereParts.push(`ext IN (${suffixes.map(() => '?').join(',')})`);
      binds.push(...suffixes);
    }

    const whereSql = whereParts.length > 0 ? whereParts.join(' AND ') : '1=1';
    const orderSql = match ? `ORDER BY bm25(${tableName}) ASC` : `ORDER BY lower(filename) ASC`;

    const sql = `SELECT path, filename, ext FROM ${tableName} WHERE ${whereSql} ${orderSql} LIMIT ? OFFSET ?`;
    binds.push(limit, offset);

    const raw = await req.dbFile.raw(sql, binds).catch(() => []);
    const rows = _toRows(raw);

    let items = await _fillItemStatsAndCleanupMissingIndexRows(
      (rows || [])
        .filter(r => r && r.path && r.filename)
        .map(r => {
          const dir = String(r.path);
          const filename = String(r.filename);
          const extRaw = r.ext ? String(r.ext).toLowerCase() : path.extname(filename).toLowerCase();
          const isDir = extRaw === '__dir__';
          const ext = isDir ? '' : extRaw;
          const type = isDir ? 'dir' : config.getFileType(ext);
          return {
            __idxPath: dir,
            __idxName: filename,
            name: filename,
            path: path.resolve(path.join(dir, filename)),
            type,
            size: null,
            mtimeMs: null,
            ext,
          };
        })
    );

    if (!userUtil.isAdmin(req.user)) {
      items = await _filterGlobalSearchItemsByPermission(req, items);
    }

    return ResponseUtil.success(
      req,
      res,
      {
        base: dirResolved || '',
        items,
        segments: dirResolved ? fileService._buildSegments(dirResolved) : [],
        sep: path.sep,
      },
      'file.GLOBAL_SEARCH_SUCCESS',
      200
    );
  } catch (err) {
    return ResponseUtil.error(req, res, 'common.ERROR', 500, {
      error: err && err.message ? String(err.message) : String(err),
    });
  }
}

module.exports = {
  list,
  getRoots,
  getAttributes,
  getResolvedAttributes,
  getExists,
  getMd5,
  getFsAccess,
  globalSearch,
};
