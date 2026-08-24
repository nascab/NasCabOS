const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const remoteAssets = require('../../../utils/remoteAssetsManager');
const { FileMountService } = require('./fileMountService');
const { localizeFileMountLastError } = require('./fileMountI18n');
const { detectWinFsp } = require('../../../utils/winfspUtil');
const { assertMountSupportedOnPlatform } = require('../../../utils/mountPlatformUtil');

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        try {
          process.removeListener('message', onMessage);
        } catch (_) {}
        try {
          Logger.error('[fileMount API IPC] 主进程未在时限内回复 express', {
            requestId,
            responseType,
            timeoutMs: Number(timeoutMs || 15000) || 15000,
            apiPid: process.pid,
            hint:
              responseType === 'startFileMountResponse'
                ? '无 [fileMount bridge] 则 startFileMount 未分发；有 bridge 无 [fileMountWorker] 则子进程未响应'
                : '检查 stopFileMount 链路与 fileMountWorker',
          });
        } catch (_) {}
        reject(new Error('timeout'));
      },
      Number(timeoutMs || 15000) || 15000
    );

    const onMessage = msg => {
      if (done) return;
      if (!msg || msg.type !== responseType) return;
      if (!msg.data || msg.data.requestId !== requestId) return;
      done = true;
      clearTimeout(timer);
      try {
        process.removeListener('message', onMessage);
      } catch (_) {}
      resolve(msg.data);
    };

    process.on('message', onMessage);
  });
}

function mapStartStopErrorToResponse(errorCode) {
  const code = errorCode === undefined || errorCode === null ? '' : String(errorCode);
  if (code === 'invalid_params' || code === 'common.INVALID_PARAMS') {
    return { msgKey: 'common.INVALID_PARAMS', statusCode: 400 };
  }
  if (code === 'not_found' || code === 'common.NOT_FOUND') {
    return { msgKey: 'common.NOT_FOUND', statusCode: 404 };
  }
  if (code === 'invalid_mount_name' || code === 'fileMount.INVALID_MOUNT_NAME') {
    return { msgKey: 'fileMount.INVALID_MOUNT_NAME', statusCode: 400 };
  }
  if (code === 'mount_parent_not_found' || code === 'fileMount.MOUNT_PARENT_NOT_FOUND') {
    return { msgKey: 'fileMount.MOUNT_PARENT_NOT_FOUND', statusCode: 400 };
  }
  if (code === 'mount_parent_not_dir' || code === 'fileMount.MOUNT_PARENT_NOT_DIR') {
    return { msgKey: 'fileMount.MOUNT_PARENT_NOT_DIR', statusCode: 400 };
  }
  if (code === 'mount_parent_no_access' || code === 'fileMount.MOUNT_PARENT_NO_ACCESS') {
    return { msgKey: 'fileMount.MOUNT_PARENT_NO_ACCESS', statusCode: 400 };
  }
  if (code === 'fileMount.PLATFORM_NOT_SUPPORTED') {
    return { msgKey: 'fileMount.PLATFORM_NOT_SUPPORTED', statusCode: 400 };
  }
  if (code === remoteAssets.PLUGIN_NOT_READY || code === 'mountShare.PLUGIN_NOT_READY') {
    return { msgKey: remoteAssets.PLUGIN_NOT_READY, statusCode: 503 };
  }
  if (code === 'fileMount.MOUNT_POINT_NOT_EMPTY') {
    return { msgKey: 'fileMount.MOUNT_POINT_NOT_EMPTY', statusCode: 400 };
  }
  if (code === 'fileMount.OBSCURE_FAILED') {
    return { msgKey: 'fileMount.OBSCURE_FAILED', statusCode: 500 };
  }
  if (code === 'start_timeout' || code === 'fileMount.START_TIMEOUT') {
    return { msgKey: 'fileMount.START_TIMEOUT', statusCode: 504 };
  }
  if (code === 'stop_timeout' || code === 'fileMount.STOP_TIMEOUT') {
    return { msgKey: 'fileMount.STOP_TIMEOUT', statusCode: 504 };
  }
  if (code === 'send_failed' || code === 'fileMount.WORKER_SEND_FAILED') {
    return { msgKey: 'fileMount.WORKER_SEND_FAILED', statusCode: 500 };
  }
  if (code === 'db_not_ready' || code === 'fileMount.DB_NOT_READY') {
    return { msgKey: 'fileMount.DB_NOT_READY', statusCode: 500 };
  }
  if (code.startsWith('fileMount.AUTO_MOUNT_')) {
    return { msgKey: code, statusCode: 400 };
  }
  if (code.startsWith('fileMount.RCLONE_')) {
    return { msgKey: code, statusCode: 502 };
  }
  if (code.startsWith('fileMount.')) {
    return { msgKey: code, statusCode: 500 };
  }
  return { msgKey: 'common.ERROR', statusCode: 500 };
}

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

function buildHttpErrorWithArgs(msgKey, args = [], statusCode = 500) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  err.args = Array.isArray(args) ? args : [];
  return err;
}

class FileMountController {
  async _startByIpc({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('common.INVALID_PARAMS', 400);
    if (!process.send) throw buildHttpError('common.ERROR', 500);
    const requestId = `startFileMount_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'startFileMountResponse', timeoutMs: 15000 });
    try {
      Logger.info('[fileMount API IPC] express→main startFileMount', { requestId, idNum, apiPid: process.pid });
    } catch (_) {}
    process.send({ type: 'startFileMount', data: { requestId, id: idNum }, timestamp: Date.now() });
    const data = await wait;
    if (!data.started) {
      const errCode = data && data.error ? String(data.error) : '';
      const detail = data && data.detail !== undefined && data.detail !== null ? String(data.detail) : '';
      const mapped = mapStartStopErrorToResponse(errCode);
      if (mapped.msgKey !== 'common.ERROR') {
        if (mapped.msgKey === 'fileMount.RCLONE_UNKNOWN') {
          throw buildHttpErrorWithArgs(mapped.msgKey, [detail || '—'], mapped.statusCode);
        }
        throw buildHttpError(mapped.msgKey, mapped.statusCode);
      }
      throw buildHttpErrorWithArgs('fileMount.START_FAILED', [detail || errCode || 'common.ERROR'], mapped.statusCode);
    }
    return data;
  }

  async _stopByIpc({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('common.INVALID_PARAMS', 400);
    if (!process.send) throw buildHttpError('common.ERROR', 500);
    const requestId = `stopFileMount_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'stopFileMountResponse', timeoutMs: 15000 });
    process.send({ type: 'stopFileMount', data: { requestId, id: idNum }, timestamp: Date.now() });
    const data = await wait;
    if (!data.stopped) {
      const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
      throw buildHttpError(mapped.msgKey, mapped.statusCode);
    }
    return data;
  }

  async list(req, res) {
    try {
      const service = new FileMountService(req.dbMain);
      const { uid, status } = req.body || {};
      const data = await service.list({
        uid: uid === undefined ? undefined : String(uid),
        status: status === undefined ? undefined : String(status),
      });
      const enriched = Array.isArray(data)
        ? data.map(row => ({
            ...row,
            last_error_display: localizeFileMountLastError(req, row.last_error),
          }))
        : data;
      return ResponseUtil.success(req, res, enriched, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('fileMount list failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async upsert(req, res) {
    try {
      const service = new FileMountService(req.dbMain);
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const { id, name, mount_path, remote, config } = req.body || {};
      const data = await service.upsert({
        uid,
        id,
        name,
        mountPath: mount_path,
        remote,
        config,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileMount upsert failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async start(req, res) {
    try {
      assertMountSupportedOnPlatform('fileMount.PLATFORM_NOT_SUPPORTED');
      remoteAssets.assertFileMountPluginReady();
      const { id } = req.body || {};
      const data = await this._startByIpc({ id });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      const args = e && Array.isArray(e.args) ? e.args : [];
      const localized = getLocalizedMessage(req, msgKey, args);
      Logger.error('fileMount start failed', { code: msgKey, message: localized, statusCode });
      return ResponseUtil.error(req, res, msgKey, statusCode, null, args);
    }
  }

  async stop(req, res) {
    try {
      const { id } = req.body || {};
      const data = await this._stopByIpc({ id });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileMount stop failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async checkWinfsp(req, res) {
    try {
      const data = detectWinFsp();
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('fileMount checkWinfsp failed', e);
      return ResponseUtil.error(req, res, 'fileMount.WINFSP_CHECK_FAILED', 500);
    }
  }

  async remove(req, res) {
    try {
      const service = new FileMountService(req.dbMain);
      const { id } = req.body || {};
      await this._stopByIpc({ id });
      const data = await service.remove({ id });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('fileMount delete failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new FileMountController();
