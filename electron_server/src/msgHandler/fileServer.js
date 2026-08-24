const path = require('path');
const dbUtil = require('../db/dbUtil');
const { FileServerService } = require('../api/modules/fileServer/fileServerService');
const remoteAssets = require('../utils/remoteAssetsManager');

function toPortValue(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  if (i < 1 || i > 65535) return null;
  return i;
}

function handleStartFileServer({ expressWorker, singletonWorkerManager, initUtil, Logger, message, serverId }) {
  const requestId = message?.data?.requestId;
  const serverType = message?.data?.serverType;
  const restart = !!message?.data?.restart;
  Logger.info('开启文件分享服务', serverType, message?.data);
  Promise.resolve()
    .then(async () => {
      const serverTypeStr = serverType === undefined || serverType === null ? '' : String(serverType).trim();
      if (!serverTypeStr) {
        if (requestId) {
          expressWorker.send({
            type: 'startFileServerResponse',
            data: { requestId, started: false, error: 'invalid_params' },
          });
        }
        return;
      }

      try {
        remoteAssets.assertFileServerPluginReady();
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: 'startFileServerResponse',
            data: { requestId, started: false, error: remoteAssets.PLUGIN_NOT_READY },
          });
        }
        return;
      }

      const knexMain = dbUtil.getConnectMainDb().knex;
      const rows = await knexMain('file_server').where({ server_type: serverTypeStr }).orderBy('id', 'desc');
      if (!rows || rows.length === 0) {
        if (requestId) {
          expressWorker.send({
            type: 'startFileServerResponse',
            data: { requestId, started: false, error: 'not_found' },
          });
        }
        return;
      }

      const workerName = `fileServer_${serverTypeStr}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      if (status && status.running) {
        if (restart) {
          const stopped = await singletonWorkerManager.stopWorker(workerName, 8000);
          if (!stopped) {
            try {
              await knexMain('file_server').where({ server_type: serverTypeStr }).update({ status: 'error', last_error: 'stop_failed', update_time: new Date() });
            } catch (_) {}
            if (requestId) {
              expressWorker.send({
                type: 'startFileServerResponse',
                data: { requestId, started: false, error: 'stop_failed' },
              });
            }
            return;
          }
        } else {
          try {
            await knexMain('file_server').where({ server_type: serverTypeStr }).update({ status: 'running', last_error: null, update_time: new Date() });
          } catch (_) {}
          if (requestId) {
            expressWorker.send({
              type: 'startFileServerResponse',
              data: { requestId, started: true, running: true, workerName, pid: status.pid },
            });
          }
          return;
        }
      }

      const worker = singletonWorkerManager.startWorker(workerName, `fileServer${path.sep}fileServerWorker.js`, {
        env: {
          WORKER_TYPE: 'fileServer',
          SERVER_ID: serverId,
          PATH_DATABASE: initUtil.pathDatabase,
          PATH_CACHE: initUtil.pathCache,
        },
        onStart: () => Logger.info(`📡 fileServer started: ${workerName}`),
        onStop: async (code, signal) => {
          const exitCode = Number(code || 0) || 0;
          // 正常退出（应用关闭 / 重启 worker）时不写入 stopped，否则下次启动无法用 status=running 恢复分享
          if (exitCode === 0) {
            Logger.info(`📡 fileServer stopped (graceful): ${workerName}`, code, signal);
            return;
          }
          try {
            await knexMain('file_server')
              .where({ server_type: serverTypeStr })
              .update({
                status: 'error',
                last_error: `exit:${code ?? ''}:${signal ?? ''}`,
                update_time: new Date(),
              });
          } catch (_) {}
          Logger.info(`📡 fileServer stopped: ${workerName}`, code, signal);
        },
        onError: async err => {
          try {
            await knexMain('file_server')
              .where({ server_type: serverTypeStr })
              .update({
                status: 'error',
                last_error: err && err.message ? String(err.message) : String(err),
                update_time: new Date(),
              });
          } catch (_) {}
          Logger.error(`❌ fileServer error: ${workerName}`, err);
        },
      });

      const waitForStart = new Promise((resolve, reject) => {
        let done = false;
        const timer = setTimeout(() => {
          if (done) return;
          done = true;
          try {
            worker.removeListener('message', onMessage);
          } catch (_) {}
          reject(new Error('start_timeout'));
        }, 15000);

        const onMessage = msg => {
          if (!msg || msg.type !== 'fileServerStartResponse') return;
          const data = msg.data || {};
          if (!requestId || data.requestId !== requestId) return;
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

      try {
        const service = new FileServerService(knexMain);
        const globalPorts = await service.getGlobalPorts({ serverType: serverTypeStr });
        worker.send({
          type: 'start',
          data: {
            requestId,
            serverType: serverTypeStr,
            items: rows.map(r => ({
              id: r.id,
              uid: r.uid,
              rootPath: r.root_path,
              config: r.config ? String(r.config) : null,
            })),
            httpPort: toPortValue(globalPorts && globalPorts.http_port),
            httpsPort: toPortValue(globalPorts && globalPorts.https_port),
          },
        });
      } catch (e) {
        if (requestId) {
          expressWorker.send({
            type: 'startFileServerResponse',
            data: { requestId, started: false, error: e && e.message ? String(e.message) : String(e) },
          });
        }
        return;
      }

      const startRes = await waitForStart;
      if (!startRes || !startRes.ok) {
        try {
          await knexMain('file_server')
            .where({ server_type: serverTypeStr })
            .update({
              status: 'error',
              last_error: startRes && startRes.error ? String(startRes.error) : 'start_failed',
              update_time: new Date(),
            });
        } catch (_) {}
        if (requestId) {
          expressWorker.send({
            type: 'startFileServerResponse',
            data: { requestId, started: false, error: startRes && startRes.error ? String(startRes.error) : 'start_failed' },
          });
        }
        return;
      }

      try {
        const actualHttpPort = toPortValue(startRes.httpPort);
        const actualHttpsPort = toPortValue(startRes.httpsPort);
        await knexMain('file_server').where({ server_type: serverTypeStr }).update({
          status: 'running',
          last_error: null,
          http_port: actualHttpPort,
          https_port: actualHttpsPort,
          update_time: new Date(),
        });
      } catch (_) {}

      if (requestId) {
        expressWorker.send({
          type: 'startFileServerResponse',
          data: {
            requestId,
            started: true,
            running: false,
            workerName,
            pid: startRes.pid,
            workDir: startRes.workDir,
            httpPort: toPortValue(startRes.httpPort),
            httpsPort: toPortValue(startRes.httpsPort),
          },
        });
      }
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'startFileServerResponse',
          data: { requestId, started: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

function handleStopFileServer({ expressWorker, singletonWorkerManager, message }) {
  const requestId = message?.data?.requestId;
  const serverType = message?.data?.serverType;
  Promise.resolve()
    .then(async () => {
      const serverTypeStr = serverType === undefined || serverType === null ? '' : String(serverType).trim();
      if (!serverTypeStr) {
        if (!requestId) return;
        try {
          expressWorker.send({
            type: 'stopFileServerResponse',
            data: { requestId, stopped: false, error: 'invalid_params' },
          });
        } catch (_) {}
        return;
      }

      const workerName = `fileServer_${serverTypeStr}`;
      const status = singletonWorkerManager.getWorkerStatus(workerName);
      const stopped = status && status.exists ? await singletonWorkerManager.stopWorker(workerName, 8000) : true;
      try {
        const knexMain = dbUtil.getConnectMainDb().knex;
        await knexMain('file_server')
          .where({ server_type: serverTypeStr })
          .update({ status: stopped ? 'stopped' : 'error', last_error: stopped ? null : 'stop_failed', update_time: new Date() });
      } catch (_) {}
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopFileServerResponse',
          data: { requestId, stopped: !!stopped },
        });
      } catch (_) {}
    })
    .catch(err => {
      if (!requestId) return;
      try {
        expressWorker.send({
          type: 'stopFileServerResponse',
          data: { requestId, stopped: false, error: err && err.message ? String(err.message) : String(err) },
        });
      } catch (_) {}
    });
}

module.exports = {
  startFileServer: handleStartFileServer,
  stopFileServer: handleStopFileServer,
};
