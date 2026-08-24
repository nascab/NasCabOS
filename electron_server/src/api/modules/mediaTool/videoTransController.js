const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');
const { VideoTransService } = require('./videoTransService');

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

function buildHttpError(msgKey, statusCode) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

function mapStartStopErrorToResponse(errorCode) {
  const code = errorCode === undefined || errorCode === null ? '' : String(errorCode);
  if (code === 'invalid_params') return { msgKey: 'common.INVALID_PARAMS', statusCode: 400 };
  if (code === 'not_found') return { msgKey: 'common.NOT_FOUND', statusCode: 404 };
  if (code === 'start_timeout' || code === 'stop_timeout') return { msgKey: 'common.ERROR', statusCode: 504 };
  return { msgKey: 'common.ERROR', statusCode: 500 };
}

class VideoTransController {
  async _startByIpc({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('common.INVALID_PARAMS', 400);
    if (typeof process.send !== 'function') throw buildHttpError('common.ERROR', 500);
    const requestId = `startVideoTransTask_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'startVideoTransTaskResponse', timeoutMs: 20000 });
    process.send({ type: 'startVideoTransTask', data: { requestId, id: idNum }, timestamp: Date.now() });
    const data = await wait;
    if (!data.started) {
      const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
      throw buildHttpError(mapped.msgKey, mapped.statusCode);
    }
    return data;
  }

  async _stopByIpc({ id }) {
    const idNum = Number(id);
    if (!Number.isFinite(idNum) || idNum <= 0) throw buildHttpError('common.INVALID_PARAMS', 400);
    if (typeof process.send !== 'function') throw buildHttpError('common.ERROR', 500);
    const requestId = `stopVideoTransTask_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType: 'stopVideoTransTaskResponse', timeoutMs: 30000 });
    process.send({ type: 'stopVideoTransTask', data: { requestId, id: idNum }, timestamp: Date.now() });
    const data = await wait;
    if (!data.stopped) {
      const mapped = mapStartStopErrorToResponse(data && data.error ? data.error : '');
      throw buildHttpError(mapped.msgKey, mapped.statusCode);
    }
    return data;
  }

  async list(req, res) {
    try {
      const service = new VideoTransService(req.dbMain);
      const { page, pageSize, keyword, sort_by, sort_order } = req.body || {};
      const data = await service.list({
        page,
        pageSize,
        keyword,
        sortBy: sort_by,
        sortOrder: sort_order,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('videoTrans list failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async upsert(req, res) {
    try {
      const service = new VideoTransService(req.dbMain);
      const { id, source_path, target_path, trans_config, non_video_policy } = req.body || {};
      const data = await service.upsert({
        id,
        sourcePath: source_path,
        targetPath: target_path,
        transConfig: trans_config,
        nonVideoPolicy: non_video_policy,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('videoTrans upsert failed', e);
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async remove(req, res) {
    try {
      const service = new VideoTransService(req.dbMain);
      const { id } = req.body || {};
      try {
        await this._stopByIpc({ id });
      } catch (_) {}
      const data = await service.remove({ id });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('videoTrans delete failed', e);
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async start(req, res) {
    try {
      const { id } = req.body || {};
      const data = await this._startByIpc({ id });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('videoTrans start failed', e);
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async stop(req, res) {
    try {
      const { id } = req.body || {};
      const data = await this._stopByIpc({ id });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('videoTrans stop failed', e);
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new VideoTransController();
