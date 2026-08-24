const dns = require('dns');
const Logger = require('../../../utils/logger');
const { pickReachablePreferredDomain, replaceUrlHost, extractUrlHostname } = require('../../../utils/p2pNodeUtil');
const { normalizeIceServers } = require('./ice');
const { iceServersKey } = require('./iceKey');
const { KEY_P2P_PAIR_CODE, KEY_P2P_FIX_NODE_DOMAIN, KEY_P2P_CONNECTED_DOMAIN } = require('./constants');
const { encodeSignaling, decodeSignaling, isSignalingBinary } = require('./signalingBinary');

const WS_HEARTBEAT_INTERVAL_MS = 30000;

/**
 * 在建立 WebSocket 连接前提前解析 DNS，绕过系统/Node.js DNS 缓存。
 * 直接走 DNS 协议查询（resolve4/resolve6），不经过 OS 缓存，
 * 保证每次重连都能拿到最新 IP（对地理就近解析尤为重要）。
 *
 * 策略：优先 IPv4，IPv4 不可用时自动尝试 IPv6。
 * 注意：此函数仅影响信令 WS 连接的 DNS 解析；
 *       WebRTC ICE 打洞（IPv4/IPv6 候选收集）由 WebRTC 库独立处理，不受影响。
 *
 * 返回 { url: string, servername: string|null }
 *   - url：已将 hostname 替换为 IP 的 WS 地址（IPv6 自动加方括号）
 *   - servername：原始 hostname，用于 wss:// 的 TLS SNI / 证书校验
 * 若解析全部失败，返回原始 url 且 servername 为 null（回退到系统 DNS）。
 */
function resolveFreshWsUrl(wsUrl) {
  return new Promise(resolve => {
    let parsed;
    try {
      parsed = new URL(wsUrl);
    } catch (_) {
      return resolve({ url: wsUrl, servername: null });
    }
    const hostname = parsed.hostname;
    // 已经是 IPv4 或 IPv6（带括号）地址，无需解析
    if (!hostname || /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname) || hostname.startsWith('[')) {
      return resolve({ url: wsUrl, servername: null });
    }

    // 优先 IPv4
    dns.resolve4(hostname, (err4, v4addresses) => {
      if (!err4 && v4addresses && v4addresses.length) {
        parsed.hostname = v4addresses[0];
        console.log(`[p2p/dns] ${hostname} → ${v4addresses[0]} (IPv4)`);
        return resolve({ url: parsed.toString(), servername: hostname });
      }

      // IPv4 失败，尝试 IPv6
      dns.resolve6(hostname, (err6, v6addresses) => {
        if (!err6 && v6addresses && v6addresses.length) {
          // URL 中 IPv6 必须用方括号包裹
          parsed.hostname = v6addresses[0];
          console.log(`[p2p/dns] ${hostname} → [${v6addresses[0]}] (IPv6)`);
          return resolve({ url: parsed.toString(), servername: hostname });
        }

        // IPv4 和 IPv6 均失败，回退到系统 DNS（兼容 /etc/hosts 等本地配置）
        console.log(`[p2p/dns] resolve failed for ${hostname} (v4: ${err4 && err4.message}, v6: ${err6 && err6.message}), falling back to system DNS`);
        resolve({ url: wsUrl, servername: null });
      });
    });
  });
}

class SignalingClient {
  constructor({ wsImpl, configStore, webrtcManager, ensurePairCodeSaved, onReconnectNeeded }) {
    this.wsImpl = wsImpl;
    this.configStore = configStore;
    this.webrtcManager = webrtcManager;
    this.ensurePairCodeSaved = ensurePairCodeSaved;
    this.onReconnectNeeded = onReconnectNeeded || null;

    this.ws = null;
    this.wsConnecting = false;
    this.wsConnectAttemptId = 0;
    this.wsConnectTimeoutTimer = null;
    this.wsHeartbeatTimer = null;
    this.wsHeartbeatTimeoutTimer = null;
    this.pendingSessionClosed = new Map();
    this._loggedOfferBySession = new Set();
    this._loggedCandidateBySession = new Set();

    this._reconnectTimer = null;
    this._reconnectAttempt = 0;
  }

  _clearWsHealthTimers() {
    try {
      if (this.wsHeartbeatTimer) {
        clearInterval(this.wsHeartbeatTimer);
      }
    } catch (_) {}
    this.wsHeartbeatTimer = null;
    try {
      if (this.wsHeartbeatTimeoutTimer) {
        clearTimeout(this.wsHeartbeatTimeoutTimer);
      }
    } catch (_) {}
    this.wsHeartbeatTimeoutTimer = null;
  }

  _ackWsHeartbeat(ws) {
    if (this.ws !== ws) return;
    try {
      if (this.wsHeartbeatTimeoutTimer) {
        clearTimeout(this.wsHeartbeatTimeoutTimer);
      }
    } catch (_) {}
    this.wsHeartbeatTimeoutTimer = null;
  }

  _startWsHeartbeat(ws) {
    this._clearWsHealthTimers();
    const tick = () => {
      if (this.ws !== ws) return;
      if (!ws || ws.readyState !== ws.OPEN) return;
      try {
        if (this.wsHeartbeatTimeoutTimer) {
          clearTimeout(this.wsHeartbeatTimeoutTimer);
        }
      } catch (_) {}
      this.wsHeartbeatTimeoutTimer = setTimeout(() => {
        if (this.ws !== ws) return;
        if (!ws || ws.readyState !== ws.OPEN) return;
        console.log('[P2pConnectWorker] P2P 信令心跳超时，主动断开并准备重连');
        try {
          if (typeof ws.terminate === 'function') ws.terminate();
          else if (typeof ws.close === 'function') ws.close();
        } catch (_) {}
      }, 8000);
      this.sendBinary({ type: 'ping', ts: Date.now() });
    };
    this.wsHeartbeatTimer = setInterval(tick, WS_HEARTBEAT_INTERVAL_MS);
    tick();
  }

  _cancelReconnect() {
    if (this._reconnectTimer) {
      try {
        clearTimeout(this._reconnectTimer);
      } catch (_) {}
      this._reconnectTimer = null;
    }
  }

  _scheduleReconnect() {
    this._cancelReconnect();
    if (typeof this.onReconnectNeeded !== 'function') return;
    const attempt = this._reconnectAttempt;
    // 首次断开 500ms 后重连，之后指数退避最长 30s
    const delay = attempt === 0 ? 500 : Math.min(1000 * Math.pow(1.5, attempt - 1), 30000);
    this._reconnectAttempt += 1;
    this._reconnectTimer = setTimeout(() => {
      this._reconnectTimer = null;
      if (this.ws && this.ws.readyState === this.ws.OPEN) {
        this._reconnectAttempt = 0;
        return;
      }
      try {
        this.onReconnectNeeded();
      } catch (_) {}
    }, delay);
  }

  sendBinary(payload) {
    if (!this.ws || this.ws.readyState !== this.ws.OPEN) return false;
    try {
      const bin = encodeSignaling(payload);
      if (!bin || !bin.length) return false;
      this.ws.send(bin);
      return true;
    } catch (_) {
      return false;
    }
  }

  queueSessionClosed(sessionId, info) {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return;
    try {
      this.pendingSessionClosed.set(sid, info || { at: Date.now() });
    } catch (_) {}
  }

  flushPendingSessionClosed() {
    if (!this.ws || this.ws.readyState !== this.ws.OPEN) return;
    if (!this.pendingSessionClosed || this.pendingSessionClosed.size === 0) return;
    let entries = [];
    try {
      entries = Array.from(this.pendingSessionClosed.entries());
      this.pendingSessionClosed.clear();
    } catch (_) {
      entries = [];
    }
    for (const [sessionId, info] of entries) {
      const sid = sessionId == null ? '' : String(sessionId);
      if (!sid) continue;
      const reason = info && info.reason != null ? String(info.reason) : '';
      this.sendBinary({ type: 'session:closed', sessionId: sid, ...(reason ? { reason } : {}) });
    }
  }

  disconnect() {
    this._cancelReconnect();
    this._reconnectAttempt = 0;
    this._clearWsHealthTimers();
    this.configStore.setConfigValue(KEY_P2P_CONNECTED_DOMAIN, '', { encrypt: false }).catch(() => {});
    try {
      if (this.wsConnectTimeoutTimer) {
        clearTimeout(this.wsConnectTimeoutTimer);
      }
    } catch (_) {}
    this.wsConnectTimeoutTimer = null;
    this.wsConnectAttemptId += 1;
    this.wsConnecting = false;
    try {
      if (!this.ws) return;
      const ws = this.ws;
      this.ws = null;
      ws.__p2pManualClose = true;
      if (typeof ws.close === 'function') ws.close();
    } catch (_) {}
  }

  async ensureConnected({ wsUrl, deviceToken }) {
    if (this.ws && this.ws.readyState === this.ws.OPEN) return;
    if (!this.wsImpl) return;
    if (!wsUrl || !deviceToken) return;
    if (this.wsConnecting) return;
    this.wsConnecting = true;
    const attemptId = (this.wsConnectAttemptId += 1);

    let wsConnectUrl = String(wsUrl);
    let preferredDomain = '';
    try {
      preferredDomain = await pickReachablePreferredDomain(await this.configStore.getConfigValue(KEY_P2P_FIX_NODE_DOMAIN));
    } catch (_) {}
    if (preferredDomain) {
      wsConnectUrl = replaceUrlHost(wsConnectUrl, preferredDomain);
    }
    try {
      const u = new URL(wsConnectUrl);
      u.searchParams.set('role', 'device');
      wsConnectUrl = u.toString();
    } catch (_) {}
    const headers = { Authorization: `Bearer ${String(deviceToken)}` };
    const currentConnectDomain = extractUrlHostname(wsConnectUrl);

    // 提前解析 DNS，绕过系统缓存（地理就近解析每次重连需拿最新 IP）
    const { url: resolvedUrl, servername } = await resolveFreshWsUrl(wsConnectUrl);
    const wsOptions = { headers };
    // wss:// 时需要保留原始 hostname 作为 TLS SNI，否则证书校验失败
    if (servername) wsOptions.servername = servername;

    const WS = this.wsImpl;
    let ws;
    try {
      ws = new WS(resolvedUrl, wsOptions);
    } catch (e) {
      this.wsConnecting = false;
      throw e;
    }

    const cleanup = () => {
      try {
        if (ws && typeof ws.removeAllListeners === 'function') ws.removeAllListeners();
      } catch (_) {}
    };

    const clearConnectTimeout = () => {
      try {
        if (this.wsConnectTimeoutTimer) {
          clearTimeout(this.wsConnectTimeoutTimer);
        }
      } catch (_) {}
      this.wsConnectTimeoutTimer = null;
    };

    let socketClosed = false;
    const handleSocketLoss = ({ logMessage, error, destroySocket = false }) => {
      if (socketClosed) return;
      socketClosed = true;
      if (this.ws === ws) {
        this.ws = null;
        this._clearWsHealthTimers();
        this.configStore.setConfigValue(KEY_P2P_CONNECTED_DOMAIN, '', { encrypt: false }).catch(() => {});
      }
      this.wsConnecting = false;
      clearConnectTimeout();
      cleanup();
      if (destroySocket) {
        try {
          if (ws && typeof ws.terminate === 'function') ws.terminate();
          else if (ws && typeof ws.close === 'function') ws.close();
        } catch (_) {}
      }
      try {
        if (this.webrtcManager && typeof this.webrtcManager.closeSessionsForSignalingLoss === 'function') {
          this.webrtcManager.closeSessionsForSignalingLoss();
        } else {
          this.webrtcManager.closeAllSessions();
        }
      } catch (_) {}
      if (logMessage) {
        console.log(logMessage);
      }
      if (error) {
        const errMsg = error && (error.message || String(error)) ? String(error.message || error) : '';
        if (errMsg) {
          console.log(`[P2pConnectWorker] P2P 信令异常详情: ${errMsg}`);
        }
      }
      this._scheduleReconnect();
    };

    try {
      if (this.wsConnectTimeoutTimer) {
        clearTimeout(this.wsConnectTimeoutTimer);
      }
    } catch (_) {}
    this.wsConnectTimeoutTimer = setTimeout(() => {
      if (this.wsConnectAttemptId !== attemptId) return;
      if (!this.wsConnecting) return;
      const rs = ws && ws.readyState != null ? Number(ws.readyState) : -1;
      if (rs === ws.OPEN) return;
      handleSocketLoss({
        logMessage: '[P2pConnectWorker] P2P 信令 WebSocket 连接超时，已强制重置并立即准备重连',
        destroySocket: true
      });
    }, 12000);

    const onOpen = () => {
      if (socketClosed) return;
      this.ws = ws;
      this.wsConnecting = false;
      this._cancelReconnect();
      this._reconnectAttempt = 0;
      clearConnectTimeout();
      this._startWsHeartbeat(ws);
      if (currentConnectDomain) {
        this.configStore.setConfigValue(KEY_P2P_CONNECTED_DOMAIN, currentConnectDomain, { encrypt: false }).catch(() => {});
      }
      Logger.info(`[p2pConnectWorker] ws connected`);
      console.log(`[P2pConnectWorker] P2P 信令 WebSocket 已连接`);
      this.flushPendingSessionClosed();
      Promise.resolve()
        .then(async () => {
          const serverId = await this.configStore.ensureServerId();
          if (this.ensurePairCodeSaved) await this.ensurePairCodeSaved({ serverId });
          this.flushPendingSessionClosed();
        })
        .catch(() => {});
    };

    const onClose = () => {
      Logger.info(`[P2pConnectWorker] P2P 信令 WebSocket 已断开`);
      if (ws && ws.__p2pManualClose) {
        handleSocketLoss({
          logMessage: '[P2pConnectWorker] P2P 信令 WebSocket 已主动断开'
        });
        this._cancelReconnect();
        this._reconnectAttempt = 0;
        return;
      }
      handleSocketLoss({
        logMessage: '[P2pConnectWorker] P2P 信令 WebSocket 已断开，已清理未连接会话并准备重连'
      });
    };

    const onError = e => {
      if (ws && ws.__p2pManualClose) {
        handleSocketLoss({
          logMessage: '[P2pConnectWorker] P2P 信令 WebSocket 主动断开时收到异常',
          error: e,
          destroySocket: true
        });
        this._cancelReconnect();
        this._reconnectAttempt = 0;
        return;
      }
      handleSocketLoss({
        logMessage: '[P2pConnectWorker] P2P 信令 WebSocket 异常，已清理未连接会话并准备重连',
        error: e,
        destroySocket: true
      });
    };

    const onMessage = data => {
      if (!data) return;
      let buf = Buffer.isBuffer(data) ? data : null;
      if (!buf && data && typeof ArrayBuffer !== 'undefined' && data instanceof ArrayBuffer) {
        buf = Buffer.from(new Uint8Array(data));
      } else if (!buf && data && typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView(data)) {
        buf = Buffer.from(data.buffer, data.byteOffset, data.byteLength);
      }
      if (!buf || buf.length > 256 * 1024 || !isSignalingBinary(buf)) return;
      this._ackWsHeartbeat(ws);
      let msg;
      try {
        msg = decodeSignaling(buf);
      } catch (_) {
        msg = null;
      }
      if (!msg || typeof msg !== 'object') return;
      const type = msg.type ? String(msg.type) : '';
      const sessionId = msg.sessionId ? String(msg.sessionId) : '';

      if (type === 'pong') {
        return;
      }

      if (type === 'ping') {
        this.sendBinary({ type: 'pong', ts: Date.now() });
        return;
      }

      if (type === 'device:ready' || type === 'device:pairCode' || type === 'p2p:hello') {
        const rawMsg = msg && typeof msg === 'object' ? msg : {};
        const pairCode = rawMsg.pairCode ? String(rawMsg.pairCode) : rawMsg['pair_code'] ? String(rawMsg['pair_code']) : rawMsg['paircode'] ? String(rawMsg['paircode']) : '';
        const nodeDomain = rawMsg.nodeDomain ? String(rawMsg.nodeDomain).trim().toLowerCase() : '';
        if (pairCode || nodeDomain) {
          Promise.resolve()
            .then(async () => {
              if (pairCode) await this.configStore.setConfigValue(KEY_P2P_PAIR_CODE, pairCode, { encrypt: true });
              if (nodeDomain) await this.configStore.setConfigValue(KEY_P2P_CONNECTED_DOMAIN, nodeDomain, { encrypt: false });
            })
            .catch(() => {});
        }
      }

      if (msg.type === 'session:client_connected' && msg.sessionId) {
        if (sessionId) {
          const nextIce = normalizeIceServers(msg.iceServers);
          const prevIce = this.webrtcManager.getSessionIceServers(sessionId) || [];
          const prevIceKey = iceServersKey(prevIce);
          const nextIceKey = iceServersKey(nextIce);
          if (nextIce.length) this.webrtcManager.setSessionIceServers(sessionId, nextIce);
          const hasTurn = nextIce.some(s0 => {
            const u = s0 && s0.urls ? String(s0.urls).toLowerCase() : '';
            return u.startsWith('turn:') || u.startsWith('turns:');
          });
          console.log(`[P2pConnectWorker] 收到客户端接入 sid=${sessionId} ICE条目=${nextIce.length} TURN=${hasTurn ? '有' : '无'}`);

          const cur = this.webrtcManager.getSession(sessionId);
          if (cur && cur.pc) {
            const cs = cur.pc.connectionState ? String(cur.pc.connectionState) : '';
            const iceChanged = prevIceKey && nextIceKey && prevIceKey !== nextIceKey;
            if (cs !== 'connected') {
              const reason = iceChanged ? 'client_connected_ice_changed' : 'client_connected_reset';
              this.webrtcManager.closeSession(sessionId, { reason, expectedPc: cur.pc });
            } else if (iceChanged) {
              console.log(`[P2pConnectWorker] 已连接会话忽略 ICE 变更 sid=${sessionId}`);
            }
          }

          this.webrtcManager.ensureSession(sessionId);
          this.sendBinary({ type: 'webrtc:device_ready', sessionId });
        }
        try {
          process.send?.({ type: 'p2pSessionClientConnected', data: { sessionId: String(msg.sessionId) } });
        } catch (_) {}
        return;
      }

      if (type === 'session:closed' && sessionId) {
        this.webrtcManager.closeSession(sessionId);
        return;
      }

      if ((type === 'webrtc:ice_servers' || type === 'webrtc:iceServers') && sessionId) {
        const iceServers = normalizeIceServers(msg.iceServers);
        this.webrtcManager.setSessionIceServers(sessionId, iceServers);
        const s0 = this.webrtcManager.getSession(sessionId);
        if (s0 && s0.pc) {
          const cs = s0.pc.connectionState ? String(s0.pc.connectionState) : '';
          if (cs === 'connected') {
            console.log(`[P2pConnectWorker] 已连接会话忽略 webrtc:ice_servers 重置 sid=${sessionId}`);
          } else {
            this.webrtcManager.closeSession(sessionId);
            this.webrtcManager.ensureSession(sessionId);
          }
        }
        return;
      }

      if (type === 'webrtc:offer' && sessionId && msg.offer) {
        if (!this._loggedOfferBySession.has(sessionId)) {
          this._loggedOfferBySession.add(sessionId);
          console.log(`[P2pConnectWorker] 收到 webrtc:offer sid=${sessionId}`);
        }
        this.webrtcManager.handleOffer(sessionId, msg.offer);
        return;
      }

      if (type === 'webrtc:candidate' && sessionId && msg.candidate) {
        if (!this._loggedCandidateBySession.has(sessionId)) {
          this._loggedCandidateBySession.add(sessionId);
          console.log(`[P2pConnectWorker] 收到 webrtc:candidate sid=${sessionId}`);
        }
        this.webrtcManager.handleRemoteCandidate(sessionId, msg.candidate);
        return;
      }
    };

    if (typeof ws.on === 'function') {
      ws.on('open', onOpen);
      ws.on('close', onClose);
      ws.on('error', onError);
      ws.on('message', onMessage);
      return;
    }

    ws.onopen = onOpen;
    ws.onclose = onClose;
    ws.onerror = onError;
    ws.onmessage = ev => onMessage(ev && ev.data);
  }
}

module.exports = { SignalingClient };
