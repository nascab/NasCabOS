const fs = require('fs');
const path = require('path');
const config = require('../../../../../config/config');
const FileUtil = require('../../../../../utils/fileUtil');
const { hasPermission, parseAnyOrArray, matchApi } = require('../../../../../utils/permissionUtil');
const { decodeJWT } = require('../../../../middleware/authMiddleware');

module.exports = app => {
  app.ws('/api/file/watch', async (ws, req) => {
    try {
      const accessToken = req.query.accessToken;
      let targetPath = req.query.path;
      if (!targetPath || !accessToken) {
        ws.close(4000, 'targetPath or accessToken is empty');
        return;
      }

      req.user = decodeJWT(req, accessToken);
      if (!req.user) {
        ws.close(4000, 'invalid accessToken');
        return;
      }
      req.user.id = req.user.userId || req.user.id || req.user.uid || req.user.user_id;

      if (req.user && req.user.tokenType === 'scoped') {
        const now = new Date();
        const tokenRecord = await req.dbMain('user_token').where({ token: accessToken, is_valid: true, type: 'scoped' }).andWhere('expire_time', '>', now).first();
        if (!tokenRecord) {
          ws.close(4000, 'invalid accessToken');
          return;
        }
        const allowApi = parseAnyOrArray(tokenRecord.allow_api);
        if (!matchApi(allowApi, '/api/file/watch')) {
          ws.close(4000, 'no permission');
          return;
        }
        req.user.allow_api = allowApi;
        req.user.allow_path = parseAnyOrArray(tokenRecord.allow_path);
      }

      targetPath = decodeURIComponent(targetPath);
      const ok = await hasPermission(req.dbMain, req.user, 'view', targetPath);
      if (!ok) {
        ws.close(4000, 'no permission');
        return;
      }
    } catch (_) {
      ws.close(4000, 'auth check failed');
      return;
    }

    let watcher = null;
    let currentPath = null;
    let debounceTimer = null;
    let changedFiles = new Set();
    let watcherErrorHandler = null;
    let cleaned = false;
    const cleanup = () => {
      if (cleaned) return;
      cleaned = true;

      if (watcher) {
        try {
          if (watcherErrorHandler && typeof watcher.removeListener === 'function') {
            watcher.removeListener('error', watcherErrorHandler);
          }
        } catch (_) {}
        try {
          watcher.close();
        } catch (_) {}
        watcher = null;
      }

      watcherErrorHandler = null;

      if (debounceTimer) {
        try {
          clearTimeout(debounceTimer);
        } catch (_) {}
        debounceTimer = null;
      }

      try {
        changedFiles.clear();
      } catch (_) {}
      changedFiles = new Set();
      currentPath = null;
    };
    const processChanges = async () => {
      if (changedFiles.size === 0) return;
      if (!currentPath) return;
      const addedItems = [];
      const removedItems = [];

      const filesToCheck = Array.from(changedFiles);
      changedFiles.clear();

      for (const filename of filesToCheck) {
        if (!filename) continue;
        const filePath = path.join(currentPath, filename);

        try {
          const st = await fs.promises.stat(filePath);
          const isDir = st.isDirectory();

          const ext = isDir ? '' : path.extname(filename).toLowerCase();
          const type = isDir ? 'dir' : config.getFileType(ext);
          const returnFileName = path.basename(filePath);
          addedItems.push({
            name: returnFileName,
            path: filePath,
            type,
            size: isDir ? null : st.size,
            mtimeMs: st.mtimeMs,
            ext,
          });
        } catch (e) {
          if (e.code === 'ENOENT') {
            removedItems.push(filePath);
          }
        }
      }

      if (addedItems.length > 0 || removedItems.length > 0) {
        if (ws.readyState === 1) {
          ws.send(
            JSON.stringify({
              type: 'change',
              added: addedItems,
              removed: removedItems,
              changeDir: currentPath,
            })
          );
        }
      }
    };

    ws.on('message', async msg => {
      try {
        const data = JSON.parse(msg);
        if (data.type === 'watch') {
          const targetPath = data.path;
          if (!targetPath) return;

          if (watcher) {
            try {
              if (watcherErrorHandler && typeof watcher.removeListener === 'function') {
                watcher.removeListener('error', watcherErrorHandler);
              }
            } catch (_) {}
            watcher.close();
            watcher = null;
          }

          if (debounceTimer) clearTimeout(debounceTimer);
          changedFiles.clear();

          currentPath = targetPath;

          try {
            if (fs.existsSync(targetPath)) {
              watcher = fs.watch(targetPath, { recursive: false }, (eventType, filename) => {
                if (filename) {
                  if (FileUtil.isSystemFile(filename) || FileUtil.isHideFile(filename)) return;
                  changedFiles.add(filename);
                  if (debounceTimer) clearTimeout(debounceTimer);
                  debounceTimer = setTimeout(processChanges, 100);
                }
              });

              watcherErrorHandler = e => {
                console.error('FS Watcher Error:', e);
              };
              watcher.on('error', watcherErrorHandler);
            }
          } catch (e) {
            console.error('FS Watch Init Error:', e);
          }
        }
      } catch (e) {
        console.error('WS Message Error:', e);
      }
    });

    ws.on('close', cleanup);
    ws.on('error', cleanup);
  });
};
