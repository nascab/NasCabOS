const fs = require('fs');
const path = require('path');
const Logger = require('../../../../../utils/logger');
const { authenticateJWT } = require('../../../../middleware/authMiddleware');

async function calculateStats(itemPath, stats, onProgress, signal, isRoot = false) {
  if (signal && signal.aborted) return;

  try {
    const itemStat = await fs.promises.stat(itemPath);
    if (itemStat.isDirectory()) {
      if (!isRoot) {
        stats.folderCount += 1;
      }
      const files = await fs.promises.readdir(itemPath);
      for (const file of files) {
        if (signal && signal.aborted) {
          return;
        }
        await calculateStats(path.join(itemPath, file), stats, onProgress, signal, false);
      }
    } else {
      stats.size += itemStat.size;
      stats.count += 1;
      if (stats.count % 100 === 0) {
        onProgress();
      }
    }
  } catch (err) {}
}

module.exports = app => {
  app.ws('/api/file/stats', (ws, req) => {
    let abortController = new AbortController();

    ws.on('message', async msg => {
      try {
        const data = JSON.parse(msg);
        const { paths, action } = data;

        if (action === 'cancel') {
          abortController.abort();
          abortController = new AbortController();
          return;
        }

        if (!paths || !Array.isArray(paths)) {
          return;
        }

        abortController.abort();
        abortController = new AbortController();
        const signal = abortController.signal;

        const stats = {
          size: 0,
          count: 0,
          folderCount: 0,
          ctime: null,
          mtime: null,
          name: '',
          path: '',
        };

        if (paths.length === 1) {
          try {
            const p = paths[0];
            const stat = await fs.promises.stat(p);
            stats.ctime = stat.birthtime;
            stats.mtime = stat.mtime;
            stats.name = path.basename(p);
            stats.path = p;
          } catch (e) {
            Logger.error('Error getting basic stat', e);
          }
        }

        const sendProgress = () => {
          if (ws.readyState === ws.OPEN) {
            ws.send(JSON.stringify({ type: 'progress', ...stats }));
          }
        };

        sendProgress();

        for (const p of paths) {
          if (signal.aborted) break;
          await calculateStats(p, stats, sendProgress, signal, true);
        }

        if (!signal.aborted && ws.readyState === ws.OPEN) {
          ws.send(JSON.stringify({ type: 'complete', ...stats }));
        }
      } catch (err) {
        Logger.error('File stats error:', err);
        if (ws.readyState === ws.OPEN) {
          ws.send(JSON.stringify({ type: 'error', message: err.message }));
        }
      }
    });

    ws.on('close', () => {
      abortController.abort();
    });
  });
};
