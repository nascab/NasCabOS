const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');
const jwtUtil = require('../../../utils/jwtUtil');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const remoteAssets = require('../../../utils/remoteAssetsManager');
const { FileServerService } = require('./fileServerService');

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function normalizeRootPathForResponse(rootPath) {
  if (Array.isArray(rootPath)) return rootPath;
  const text = rootPath === undefined || rootPath === null ? '' : String(rootPath);
  const parsed = safeJsonParse(text);
  if (Array.isArray(parsed)) return parsed;
  if (!text.trim()) return [];
  return [text];
}

function sanitizeConfigForResponse(config) {
  if (!config || typeof config !== 'object') return config;
  const cloned = JSON.parse(JSON.stringify(config));

  if (Array.isArray(cloned.users)) {
    for (const u of cloned.users) {
      if (u && typeof u === 'object') {
        if (u.password !== undefined) delete u.password;
        if (u.password_enc !== undefined) delete u.password_enc;
      }
    }
  }

  if (cloned.tls_key_pem !== undefined) delete cloned.tls_key_pem;
  if (cloned.tls_cert_pem !== undefined) delete cloned.tls_cert_pem;

  return cloned;
}

function encryptSensitiveConfig(config) {
  if (!config || typeof config !== 'object') return config;
  const cloned = JSON.parse(JSON.stringify(config));

  if (typeof cloned.tls_key_pem === 'string' && cloned.tls_key_pem.trim()) {
    const raw = cloned.tls_key_pem.trim();
    if (!jwtUtil.isEncryptedPassword(raw)) {
      cloned.tls_key_pem = jwtUtil.encryptPassword(raw);
    }
  }

  if (typeof cloned.tls_cert_pem === 'string' && cloned.tls_cert_pem.trim()) {
    const raw = cloned.tls_cert_pem.trim();
    if (!jwtUtil.isEncryptedPassword(raw)) {
      cloned.tls_cert_pem = jwtUtil.encryptPassword(raw);
    }
  }

  if (Array.isArray(cloned.users)) {
    for (const u of cloned.users) {
      if (!u || typeof u !== 'object') continue;
      if (typeof u.password !== 'string' || !u.password.trim()) continue;
      const rawPassword = jwtUtil.decodeClientPassword(u.password);
      if (!jwtUtil.isEncryptedPassword(rawPassword)) {
        u.password = jwtUtil.encryptPassword(rawPassword);
      } else {
        u.password = rawPassword;
      }
    }
  }

  return cloned;
}

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (typeof process.send !== 'function') {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      reject(err);
      return;
    }

    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        process.removeListener('message', onMessage);
        const err = new Error('common.ERROR');
        err.statusCode = 504;
        reject(err);
      },
      Math.max(500, Number(timeoutMs || 0) || 0)
    );

    const onMessage = message => {
      if (!message || message.type !== responseType) return;
      if (!message.data || message.data.requestId !== requestId) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(message.data || {});
    };

    process.on('message', onMessage);
  });
}

function mapStartStopErrorToResponse(errorCode) {
  const code = errorCode === undefined || errorCode === null ? '' : String(errorCode);
  if (code === 'invalid_params') return { msgKey: 'common.INVALID_PARAMS', statusCode: 400 };
  if (code === 'not_found') return { msgKey: 'common.NOT_FOUND', statusCode: 404 };
  if (code === 'no_users') return { msgKey: 'validation.VALIDATION_ERROR', statusCode: 400 };
  if (code === 'duplicate_username') return { msgKey: 'validation.VALIDATION_ERROR', statusCode: 400 };
  if (code === 'root_path_not_exists' || code === 'root_path_invalid') return { msgKey: 'validation.VALIDATION_ERROR', statusCode: 400 };
  if (code === 'start_timeout') return { msgKey: 'common.ERROR', statusCode: 504 };
  if (code === remoteAssets.PLUGIN_NOT_READY || code === 'mountShare.PLUGIN_NOT_READY') {
    return { msgKey: remoteAssets.PLUGIN_NOT_READY, statusCode: 503 };
  }
  return { msgKey: 'common.ERROR', statusCode: 500 };
}

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

class FileServerController {
  async _startFileServerByIpc({ serverType, restart }) {
    const serverTypeStr = serverType === undefined || serverType === null ? '' : String(serverType).trim();
    if (!serverTypeStr) throw buildHttpError('common.INVALID_PARAMS', 400);

    const requestId = `startFileServer_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'startFileServerResponse', timeoutMs: 15000 });

    process.send({
      type: 'startFileServer',
      data: { requestId, serverType: serverTypeStr, restart: !!restart },
      timestamp: Date.now(),
    });

    const data = await wait;
    if (!data.started) {
      const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
      throw buildHttpError(mapped.msgKey, mapped.statusCode);
    }
    return data;
  }

  async _stopFileServerByIpc({ serverType }) {
    const serverTypeStr = serverType === undefined || serverType === null ? '' : String(serverType).trim();
    if (!serverTypeStr) throw buildHttpError('common.INVALID_PARAMS', 400);

    const requestId = `stopFileServer_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'stopFileServerResponse', timeoutMs: 15000 });

    process.send({
      type: 'stopFileServer',
      data: { requestId, serverType: serverTypeStr },
      timestamp: Date.now(),
    });

    const data = await wait;
    if (!data.stopped) {
      const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
      throw buildHttpError(mapped.msgKey, mapped.statusCode);
    }
    return data;
  }

  async getPorts(req, res) {
    try {
      const service = new FileServerService(req.dbMain);
      const { server_type } = req.body || {};
      const data = await service.getGlobalPorts({ serverType: String(server_type) });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('fileServer getPorts failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async setPorts(req, res) {
    try {
      const service = new FileServerService(req.dbMain);
      const { server_type, http_port, https_port } = req.body || {};
      const serverTypeStr = String(server_type);
      const runningRow = await req
        .dbMain('file_server')
        .where({ server_type: serverTypeStr, status: 'running' })
        .first()
        .catch(() => null);
      const wasRunning = !!runningRow;
      const data = await service.setGlobalPorts({
        serverType: serverTypeStr,
        httpPort: http_port,
        httpsPort: https_port,
      });
      if (wasRunning) {
        await this._startFileServerByIpc({ serverType: serverTypeStr, restart: true });
      }
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileServer setPorts failed', e);
      if (e && e.code) {
        return res.status(statusCode).json({
          success: false,
          message: getLocalizedMessage(req, msgKey, Array.isArray(e.args) ? e.args : []),
          code: String(e.code),
          details: e.details || null,
        });
      }
      if (e && Array.isArray(e.args)) {
        return ResponseUtil.errorWithArgs(req, res, msgKey, e.args, statusCode);
      }
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async list(req, res) {
    try {
      const service = new FileServerService(req.dbMain);
      const { uid, server_type, status } = req.body || {};
      const rows = await service.list({
        uid: uid === undefined ? undefined : String(uid),
        serverType: server_type === undefined ? undefined : String(server_type),
        status: status === undefined ? undefined : String(status),
      });

      const data = rows.map(r => {
        const config = safeJsonParse(r.config);
        return {
          ...r,
          root_path: normalizeRootPathForResponse(r.root_path),
          config: sanitizeConfigForResponse(config),
        };
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('fileServer list failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async get(req, res) {
    try {
      const service = new FileServerService(req.dbMain);
      const { uid, server_type } = req.body || {};
      const row = await service.getOne({ uid: String(uid), serverType: String(server_type) });
      if (!row) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      const config = safeJsonParse(row.config);
      return ResponseUtil.success(
        req,
        res,
        {
          ...row,
          root_path: normalizeRootPathForResponse(row.root_path),
          config: sanitizeConfigForResponse(config),
        },
        'common.SUCCESS',
        200
      );
    } catch (e) {
      Logger.error('fileServer get failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async upsert(req, res) {
    try {
      const service = new FileServerService(req.dbMain);
      const { uid, server_type, root_path, http_port, https_port, config } = req.body || {};
      const serverTypeStr = String(server_type);

      const runningRow = await req
        .dbMain('file_server')
        .where({ server_type: serverTypeStr, status: 'running' })
        .first()
        .catch(() => null);
      const wasRunning = !!runningRow;

      const normalizedConfig = encryptSensitiveConfig(config);
      const row = await service.upsert({
        uid: String(uid),
        serverType: serverTypeStr,
        rootPath: root_path,
        httpPort: http_port === undefined ? undefined : Number(http_port),
        httpsPort: https_port === undefined ? undefined : Number(https_port),
        config: normalizedConfig,
      });

      if (wasRunning) {
        await this._startFileServerByIpc({ serverType: serverTypeStr, restart: true });
      }

      const parsedConfig = safeJsonParse(row.config);
      return ResponseUtil.success(
        req,
        res,
        {
          ...row,
          root_path: normalizeRootPathForResponse(row.root_path),
          config: sanitizeConfigForResponse(parsedConfig),
        },
        'common.SUCCESS',
        200
      );
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileServer upsert failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async remove(req, res) {
    try {
      const service = new FileServerService(req.dbMain);
      const { uid, server_type } = req.body || {};

      const serverTypeStr = String(server_type);
      const runningRow = await req
        .dbMain('file_server')
        .where({ server_type: serverTypeStr, status: 'running' })
        .first()
        .catch(() => null);
      const wasRunning = !!runningRow;

      const ok = await service.delete({ uid: String(uid), serverType: serverTypeStr });
      if (wasRunning) {
        const remaining = await req
          .dbMain('file_server')
          .where({ server_type: serverTypeStr })
          .first()
          .catch(() => null);
        if (remaining) {
          await this._startFileServerByIpc({ serverType: serverTypeStr, restart: true });
        } else {
          await this._stopFileServerByIpc({ serverType: serverTypeStr });
        }
      }

      return ResponseUtil.success(req, res, { deleted: !!ok }, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('fileServer delete failed', e);
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async start(req, res) {
    try {
      const { server_type, restart } = req.body || {};
      if (!server_type) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      remoteAssets.assertFileServerPluginReady();
      console.log('开启文件服务 start', server_type);
      const data = await this._startFileServerByIpc({ serverType: String(server_type), restart: !!restart });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      console.log('开启文件服务 start failed', e);
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileServer start failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async restart(req, res) {
    try {
      const { server_type } = req.body || {};
      if (!server_type) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      remoteAssets.assertFileServerPluginReady();
      const data = await this._startFileServerByIpc({ serverType: String(server_type), restart: true });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileServer restart failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async stop(req, res) {
    try {
      const { server_type } = req.body || {};
      if (!server_type) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);

      const data = await this._stopFileServerByIpc({ serverType: String(server_type) });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileServer stop failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new FileServerController();
