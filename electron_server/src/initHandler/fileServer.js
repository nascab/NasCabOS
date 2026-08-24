const path = require('path');
const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const { FileServerService } = require('../api/modules/fileServer/fileServerService');
const { getSingletonWorkerManager } = require('../workers/singletonWorkerManager');

const singletonWorkerManager = getSingletonWorkerManager();

function toPortValue(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  if (i < 1 || i > 65535) return null;
  return i;
}

function waitForWorkerMessage({ worker, type, requestId, timeoutMs }) {
  return new Promise((resolve, reject) => {
    let done = false;
    const ms = Math.max(200, Number(timeoutMs || 0) || 0);
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      reject(new Error('start_timeout'));
    }, ms);

    const onMessage = msg => {
      if (!msg || msg.type !== type) return;
      const data = msg.data || {};
      if (requestId && data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      try {
        worker.removeListener('message', onMessage);
      } catch (_) {}
      resolve(data);
    };

    worker.on('message', onMessage);
  });
}

module.exports = {
  async restoreFileServersOnStartup({ serverId }) {
    const serverIdStr = serverId === undefined || serverId === null ? '' : String(serverId).trim();
    if (!serverIdStr) return;

    const knexMain = dbUtil.getConnectMainDb().knex;
    let runningRows = [];
    try {
      runningRows = await knexMain('file_server').where({ status: 'running' }).orderBy('id', 'desc');
    } catch (err) {
      Logger.error('❌ read file_server table failed:', err);
      return;
    }
    if (!runningRows || runningRows.length === 0) return;

    const byType = new Map();
    for (const r of runningRows) {
      const serverTypeStr = r && r.server_type !== undefined && r.server_type !== null ? String(r.server_type).trim() : '';
      if (!serverTypeStr) continue;
      if (!byType.has(serverTypeStr)) byType.set(serverTypeStr, []);
      byType.get(serverTypeStr).push(r);
    }
    if (byType.size === 0) return;

    const service = new FileServerService(knexMain);
    const tasks = [];
    for (const [serverTypeStr, rows] of byType.entries()) {
      const rowIds = (Array.isArray(rows) ? rows : [])
        .map(r => r && r.id)
        .filter(v => v !== undefined && v !== null)
        .map(v => Number(v))
        .filter(v => Number.isFinite(v) && v > 0);
      tasks.push(
        Promise.resolve()
          .then(async () => {
            const workerName = `fileServer_${serverTypeStr}`;
            const status = singletonWorkerManager.getWorkerStatus(workerName);
            if (status && status.running) {
              try {
                if (rowIds.length > 0) {
                  await knexMain('file_server').whereIn('id', rowIds).update({ status: 'running', last_error: null, update_time: new Date() });
                }
              } catch (_) {}
              return;
            }

            const worker = singletonWorkerManager.startWorker(workerName, `fileServer${path.sep}fileServerWorker.js`, {
              env: {
                WORKER_TYPE: 'fileServer',
                SERVER_ID: serverIdStr,
                PATH_DATABASE: this.pathDatabase,
                PATH_CACHE: this.pathCache,
              },
              onStart: () => Logger.info(`📡 fileServer started: ${workerName}`),
              onStop: async (code, signal) => {
                const exitCode = Number(code || 0) || 0;
                if (exitCode === 0) {
                  Logger.info(`📡 fileServer stopped (graceful): ${workerName}`, code, signal);
                  return;
                }
                try {
                  if (rowIds.length > 0) {
                    await knexMain('file_server')
                      .whereIn('id', rowIds)
                      .update({
                        status: 'error',
                        last_error: `exit:${code ?? ''}:${signal ?? ''}`,
                        update_time: new Date(),
                      });
                  }
                } catch (_) {}
                Logger.info(`📡 fileServer stopped: ${workerName}`, code, signal);
              },
              onError: async err => {
                try {
                  if (rowIds.length > 0) {
                    await knexMain('file_server')
                      .whereIn('id', rowIds)
                      .update({
                        status: 'error',
                        last_error: err && err.message ? String(err.message) : String(err),
                        update_time: new Date(),
                      });
                  }
                } catch (_) {}
                Logger.error(`❌ fileServer error: ${workerName}`, err);
              },
            });

            const requestId = `startup_${Date.now()}_${serverTypeStr}`;
            const globalPorts = await service.getGlobalPorts({ serverType: serverTypeStr }).catch(() => null);
            const items = (Array.isArray(rows) ? rows : []).map(r => ({
              id: r.id,
              uid: r.uid,
              rootPath: r.root_path,
              config: r.config ? String(r.config) : null,
            }));

            try {
              worker.send({
                type: 'start',
                data: {
                  requestId,
                  serverType: serverTypeStr,
                  items,
                  httpPort: toPortValue(globalPorts && globalPorts.http_port),
                  httpsPort: toPortValue(globalPorts && globalPorts.https_port),
                },
              });
            } catch (e) {
              try {
                if (rowIds.length > 0) {
                  await knexMain('file_server')
                    .whereIn('id', rowIds)
                    .update({ status: 'error', last_error: e && e.message ? String(e.message) : String(e), update_time: new Date() });
                }
              } catch (_) {}
              return;
            }

            let startRes = null;
            try {
              startRes = await waitForWorkerMessage({ worker, type: 'fileServerStartResponse', requestId, timeoutMs: 15000 });
            } catch (err) {
              try {
                if (rowIds.length > 0) {
                  await knexMain('file_server')
                    .whereIn('id', rowIds)
                    .update({ status: 'error', last_error: err && err.message ? String(err.message) : String(err), update_time: new Date() });
                }
              } catch (_) {}
              await singletonWorkerManager.stopWorker(workerName, 8000).catch(() => false);
              return;
            }

            if (!startRes || !startRes.ok) {
              try {
                if (rowIds.length > 0) {
                  await knexMain('file_server')
                    .whereIn('id', rowIds)
                    .update({
                      status: 'error',
                      last_error: startRes && startRes.error ? String(startRes.error) : 'start_failed',
                      update_time: new Date(),
                    });
                }
              } catch (_) {}
              await singletonWorkerManager.stopWorker(workerName, 8000).catch(() => false);
              return;
            }

            try {
              if (rowIds.length > 0) {
                await knexMain('file_server')
                  .whereIn('id', rowIds)
                  .update({
                    status: 'running',
                    last_error: null,
                    http_port: toPortValue(startRes.httpPort),
                    https_port: toPortValue(startRes.httpsPort),
                    update_time: new Date(),
                  });
              }
            } catch (_) {}
          })
          .catch(err => {
            Logger.error(`❌ start file share service failed: ${serverTypeStr}`, err);
          })
      );
    }

    await Promise.all(tasks);
  },
};
