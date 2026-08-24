const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');

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
        try {
          process.removeListener('message', onMessage);
        } catch (_) {}
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
      try {
        process.removeListener('message', onMessage);
      } catch (_) {}
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

class SecurityController {
  async _sendToMain({ type, responseType, payload, timeoutMs }) {
    const requestId = `${type}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    const wait = waitForIpcResponse({ requestId, responseType, timeoutMs: timeoutMs ?? 8000 });
    process.send({
      type,
      data: { requestId, ...(payload || {}) },
      timestamp: Date.now(),
    });
    const data = await wait;
    if (!data || data.ok !== true) throw buildHttpError('common.ERROR', 500);
    return data;
  }

  async getConfig(req, res) {
    try {
      const data = await this._sendToMain({
        type: 'securityGetConfig',
        responseType: 'securityGetConfigResponse',
        timeoutMs: 6000,
      });
      return ResponseUtil.success(req, res, data.config || {}, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('security getConfig failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async setConfig(req, res) {
    try {
      const { banEnabled, maxFailedAttempts, banMinutes, bypassLanAuth } = req.body || {};
      const data = await this._sendToMain({
        type: 'securitySetConfig',
        responseType: 'securitySetConfigResponse',
        payload: { banEnabled, maxFailedAttempts, banMinutes, bypassLanAuth },
        timeoutMs: 6000,
      });
      return ResponseUtil.success(req, res, data.config || {}, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('security setConfig failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async listIpBlacklist(req, res) {
    try {
      const data = await this._sendToMain({
        type: 'securityListIpBlacklist',
        responseType: 'securityListIpBlacklistResponse',
        timeoutMs: 6000,
      });
      return ResponseUtil.success(req, res, { items: data.items || [] }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('security listIpBlacklist failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async deleteIpBlacklist(req, res) {
    try {
      const ip = req.body && req.body.ip ? String(req.body.ip).trim() : '';
      if (!ip) return ResponseUtil.error(req, res, 'common.INVALID_PARAMS', 400);
      const data = await this._sendToMain({
        type: 'securityDeleteIpBlacklist',
        responseType: 'securityDeleteIpBlacklistResponse',
        payload: { ip },
        timeoutMs: 6000,
      });
      return ResponseUtil.success(req, res, { deleted: !!data.deleted }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('security deleteIpBlacklist failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async clearIpBlacklist(req, res) {
    try {
      const data = await this._sendToMain({
        type: 'securityClearIpBlacklist',
        responseType: 'securityClearIpBlacklistResponse',
        timeoutMs: 6000,
      });
      return ResponseUtil.success(req, res, { cleared: data.cleared || 0 }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('security clearIpBlacklist failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }
}

module.exports = new SecurityController();
