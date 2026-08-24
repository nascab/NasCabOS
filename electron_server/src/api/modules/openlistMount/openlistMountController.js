const ResponseUtil = require('../../apiUtils/responseUtil');
const Logger = require('../../../utils/logger');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const remoteAssets = require('../../../utils/remoteAssetsManager');
const { OpenlistMountService } = require('./openlistMountService');
const { getStaticDriverList } = require('../../../workers/openlist/openlistDriverCatalog');
const { assertMountSupportedOnPlatform } = require('../../../utils/mountPlatformUtil');

const OAUTH_HELP_URL = 'https://api.oplist.org/';

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
        reject(new Error('timeout'));
      },
      Number(timeoutMs || 20000) || 20000
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

function sendIpc(type, data, responseType, timeoutMs = 20000) {
  if (!process.send) {
    const err = new Error('common.ERROR');
    err.statusCode = 500;
    throw err;
  }
  const requestId = `${type}_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({ requestId, responseType, timeoutMs });
  process.send({ type, data: { ...data, requestId }, timestamp: Date.now() });
  return wait;
}

function buildHttpError(msgKey, statusCode = 500) {
  const err = new Error(String(msgKey || 'common.ERROR'));
  err.statusCode = Number(statusCode || 500) || 500;
  return err;
}

class OpenlistMountController {
  async list(req, res) {
    try {
      const service = new OpenlistMountService(req.dbMain);
      const { uid, status } = req.body || {};
      const data = await service.list({
        uid: uid === undefined ? undefined : String(uid),
        status: status === undefined ? undefined : String(status),
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('openlistMount list failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async upsert(req, res) {
    try {
      const service = new OpenlistMountService(req.dbMain);
      const uid = req.user && req.user.id;
      if (!uid) return ResponseUtil.error(req, res, 'auth.AUTHENTICATION_REQUIRED', 401);
      const { id, name, mount_path, driver, config } = req.body || {};
      const data = await service.upsert({
        uid,
        id,
        name,
        mountPath: mount_path,
        driver,
        config,
      });
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('openlistMount upsert failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async remove(req, res) {
    try {
      const service = new OpenlistMountService(req.dbMain);
      const { id } = req.body || {};
      try {
        await sendIpc('stopOpenlistMount', { id }, 'openlistMountStopResponse', 15000);
      } catch (_) {}
      try {
        await sendIpc('openlistDeleteStorage', { id }, 'openlistDeleteStorageResponse', 20000);
      } catch (e) {
        Logger.warn('openlistMount delete storage ipc failed', e);
      }
      await service.remove({ id });
      return ResponseUtil.success(req, res, { ok: true }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('openlistMount delete failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async start(req, res) {
    try {
      assertMountSupportedOnPlatform('openlistMount.PLATFORM_NOT_SUPPORTED');
      remoteAssets.assertOpenlistMountPluginReady();
      const { id } = req.body || {};
      const data = await sendIpc('startOpenlistMount', { id }, 'openlistMountStartResponse', 60000);
      if (!data.ok) {
        throw buildHttpError(data.error || 'openlistMount.START_FAILED', 500);
      }
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('openlistMount start failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async stop(req, res) {
    try {
      const { id } = req.body || {};
      const data = await sendIpc('stopOpenlistMount', { id }, 'openlistMountStopResponse', 15000);
      if (!data.ok) {
        throw buildHttpError(data.error || 'openlistMount.STOP_FAILED', 500);
      }
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? String(e.message) : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      Logger.error('openlistMount stop failed', e);
      return ResponseUtil.error(req, res, msgKey, statusCode);
    }
  }

  async drivers(req, res) {
    try {
      return ResponseUtil.success(req, res, getStaticDriverList(), 'common.SUCCESS', 200);
    } catch (e) {
      Logger.error('openlistMount drivers failed', e);
      return ResponseUtil.error(req, res, 'common.ERROR', 500);
    }
  }

  async oauthHelpUrl(req, res) {
    return ResponseUtil.success(req, res, { url: OAUTH_HELP_URL }, 'common.SUCCESS', 200);
  }
}

module.exports = new OpenlistMountController();
