const Logger = require('../../utils/logger');
const nascabAccountUtil = require('../../api/modules/service/utils/nascabAccountUtil');
const { pickWebSocketImpl } = require('./utils/ws');
const configStore = require('./utils/configStore');
const { createLocalExpressProxy } = require('./utils/localExpressProxy');
const { ProxyPendingStore } = require('./utils/proxyPendingStore');
const { createWebRtcSessionManager } = require('./utils/webrtcSessionManager');
const { SignalingClient } = require('./utils/signalingClient');
const { createDeviceManager } = require('./utils/deviceManager');
const { KEY_REMOTE_TOKEN, KEY_P2P_DEVICE_ID, KEY_P2P_DEVICE_SECRET, KEY_P2P_DEVICE_TOKEN } = require('./utils/constants');

if ((process.env.NODE_ENV || 'development') === 'development') {
  if (process.env.NASCAB_P2P_LOG_COMPRESSION == null) process.env.NASCAB_P2P_LOG_COMPRESSION = '1';
}

class P2pConnectWorker {
  constructor() {
    this.stopping = false;
    this.tickTimer = null;
    this.heartbeatTimer = null;

    this.wsImpl = pickWebSocketImpl();
    this.proxyPendingStore = new ProxyPendingStore();

    this.localExpressProxy = createLocalExpressProxy({ initDb: () => configStore.initDb() });
    this.webrtcManager = createWebRtcSessionManager({
      proxyPendingStore: this.proxyPendingStore,
      getSignalingClient: () => this.signalingClient,
      wsImpl: this.wsImpl,
      localExpressProxy: this.localExpressProxy,
    });

    this.signalingClient = new SignalingClient({
      wsImpl: this.wsImpl,
      configStore,
      webrtcManager: this.webrtcManager,
      ensurePairCodeSaved: async ({ serverId } = {}) => {
        if (!this.deviceManager || !this.deviceManager.ensurePairCodeSaved) return '';
        return this.deviceManager.ensurePairCodeSaved({ serverId });
      },
      onReconnectNeeded: () => {
        // WebSocket 断开后立即触发一次 tick，不等下一个 5s 轮询
        if (!this.stopping) {
          setTimeout(() => this.tick(), 0);
        }
      },
    });

    this.deviceManager = createDeviceManager({ configStore, signalingClient: this.signalingClient });
  }

  async tick() {
    if (this.stopping) return;
    try {
      await configStore.initDb();
      const serverId = await configStore.ensureServerId();
      if (!serverId) return;

      const deviceId = ((await configStore.getConfigValue(KEY_P2P_DEVICE_ID)) || '').trim();
      const deviceSecret = ((await configStore.getConfigValue(KEY_P2P_DEVICE_SECRET)) || '').trim();
      const hasDeviceCreds = Boolean(deviceId && deviceSecret);

      if (!hasDeviceCreds) {
        const userTokenEnc = await configStore.getConfigValue(KEY_REMOTE_TOKEN);
        const userToken = userTokenEnc && nascabAccountUtil.isValidJwtFormat(userTokenEnc) ? userTokenEnc : '';
        if (!userToken) {
          console.log('[P2pConnectWorker] 未找到设备凭证且无用户 token，跳过注册');
          this.signalingClient.disconnect();
          return;
        }
        try {
          await this.deviceManager.registerOrRecoverDevice({ userToken, serverId });
        } catch (err) {
          console.log('[P2pConnectWorker] registerOrRecoverDevice failed', err.code);
          const noRetryErrorCodes = ['P2P.ERR_DEVICE_NOT_BIND', 'P2P.ERR_NEED_VIP', 'P2P.ERR_DEVICE_COUNT_LIMIT'];
          if ((err && err.errorCode && noRetryErrorCodes.includes(err.errorCode)) || (err && (err.status === 403 || err.status === 401))) {
            console.log(`[P2pConnectWorker] ${err.errorCode}, exiting without retry`);
            this.stop();
            process.exit(0);
          }
        }
      }

      try {
        await this.deviceManager.ensureDeviceReady({ serverId });
      } catch (err) {
        Logger.error('[P2pConnectWorker] ensureDeviceReady failed', err ? err.message : err);
        console.log('[P2pConnectWorker] ensureDeviceReady failed', err ? err.message : err);
        const noRetryErrorCodes = ['P2P.ERR_DEVICE_NOT_BIND', 'P2P.ERR_NEED_VIP', 'P2P.ERR_DEVICE_COUNT_LIMIT'];
        if (err && err.errorCode && noRetryErrorCodes.includes(err.errorCode)) {
          console.log(`[P2pConnectWorker] ${err.errorCode}, exiting without retry`);
          this.stop();
          process.exit(0);
        }
      }
    } catch (err) {
      Logger.error('[P2pConnectWorker] tick error', err ? err.message : err);
      console.log('[P2pConnectWorker] tick error', err ? err.message : err);
    }
  }

  async runHeartbeat() {
    if (this.stopping) return;
    try {
      await configStore.initDb();
      const serverId = await configStore.ensureServerId();
      if (!serverId) return;
      const deviceToken = ((await configStore.getConfigValue(KEY_P2P_DEVICE_TOKEN)) || '').trim();
      if (!deviceToken || !nascabAccountUtil.isValidJwtFormat(deviceToken)) return;
      const res = await this.deviceManager.heartbeat(deviceToken, serverId).catch(() => ({ ok: false, auth: true }));
      if (res && res.ok) return;
      if (res && res.auth === false) {
        await configStore.clearConfigValue(KEY_P2P_DEVICE_TOKEN).catch(() => {});
        this.signalingClient.disconnect();
      }
    } catch (_) {}
  }

  start() {
    if (this.tickTimer) return;
    this.stopping = false;
    this.tickTimer = setInterval(() => this.tick(), 5000);
    this.heartbeatTimer = setInterval(() => this.runHeartbeat(), 60 * 1000);
    this.tick();
  }

  stop() {
    this.stopping = true;
    if (this.tickTimer) {
      try {
        clearInterval(this.tickTimer);
      } catch (_) {}
      this.tickTimer = null;
    }
    if (this.heartbeatTimer) {
      try {
        clearInterval(this.heartbeatTimer);
      } catch (_) {}
      this.heartbeatTimer = null;
    }
    this.signalingClient.disconnect();
    this.webrtcManager.closeAllSessions();
  }
}

let worker = null;

process.on('message', msg => {
  if (!msg || typeof msg !== 'object') return;
  if (msg.type === 'start') {
    if (!worker) worker = new P2pConnectWorker();
    worker.start();
  } else if (msg.type === 'stop') {
    if (worker) worker.stop();
    worker = null;
  }
});

if (require.main === module) {
  if (!worker) worker = new P2pConnectWorker();
  worker.start();
}
