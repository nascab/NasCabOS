const { attachDataChannel } = require('./dataChannelProxy');

/** 中继(relay)候选延迟发送时间(ms)，优先让 IPv4/IPv6 host、srflx 直连被测试，避免直连可用时仍走中继 */
const RELAY_CANDIDATE_DELAY_MS = 4000;

/** ICE 配置是否仅有 TURN（客户端中继模式下发），此时无直连候选意义，不应延迟 relay */
function iceServersAreRelayOnly(iceServers) {
  const list = Array.isArray(iceServers) ? iceServers : [];
  if (!list.length) return false;
  for (const s of list) {
    if (!s || typeof s !== 'object') return false;
    const urls = s.urls;
    const urlList = [];
    if (typeof urls === 'string' && urls.trim()) urlList.push(urls.trim());
    else if (Array.isArray(urls)) {
      for (const u of urls) {
        const t = u == null ? '' : String(u).trim();
        if (t) urlList.push(t);
      }
    }
    if (urlList.length === 0) return false;
    for (const u of urlList) {
      const lower = u.toLowerCase();
      if (!lower.startsWith('turn:') && !lower.startsWith('turns:')) return false;
    }
  }
  return true;
}

function createWebRtcSessionManager({ proxyPendingStore, getSignalingClient, wsImpl, localExpressProxy }) {
  const webrtcSessions = new Map();
  const sessionIceServers = new Map();
  let webrtc = null;
  let nodeDataChannel = null;
  let nodeDataChannelCleanupTimer = null;

  const ensureWebRtcPolyfill = () => {
    if (webrtc) return webrtc;
    try {
      const mod = require('node-datachannel/polyfill');
      webrtc = mod;
      ensureNodeDataChannelLib();
      return mod;
    } catch (_) {
      webrtc = null;
      return null;
    }
  };

  const ensureNodeDataChannelLib = () => {
    if (nodeDataChannel) return nodeDataChannel;
    try {
      const mod = require('node-datachannel');
      nodeDataChannel = mod;
      return mod;
    } catch (_) {
      nodeDataChannel = null;
      return null;
    }
  };

  const scheduleNodeDataChannelCleanup = reason => {
    if (nodeDataChannelCleanupTimer) {
      try {
        clearTimeout(nodeDataChannelCleanupTimer);
      } catch (_) {}
      nodeDataChannelCleanupTimer = null;
    }
    nodeDataChannelCleanupTimer = setTimeout(() => {
      nodeDataChannelCleanupTimer = null;
      if (webrtcSessions.size !== 0) return;
      console.log(`[P2pConnectWorker] node-datachannel cleanup skipped (persisting for future connections)${reason ? ` reason=${String(reason)}` : ''}`);
    }, 250);
  };

  const sendSignal = payload => {
    const sc = getSignalingClient ? getSignalingClient() : null;
    if (!sc || typeof sc.sendBinary !== 'function') return false;
    return sc.sendBinary(payload);
  };

  const queueSessionClosed = (sessionId, info) => {
    const sc = getSignalingClient ? getSignalingClient() : null;
    if (!sc || typeof sc.queueSessionClosed !== 'function') return;
    sc.queueSessionClosed(sessionId, info);
  };

  const clearSessionState = sessionId => {
    const key = sessionId == null ? '' : String(sessionId);
    if (!key) return;
    proxyPendingStore.cleanupProxyPendingForSession(key);
    proxyPendingStore.pendingRemoteCandidatesBySession.delete(key);
    sessionIceServers.delete(key);
  };

  const closeSession = (sessionId, opts = {}) => {
    const key = sessionId == null ? '' : String(sessionId);
    if (!key) return;
    const expectedPc = opts && opts.expectedPc ? opts.expectedPc : null;
    const cur = webrtcSessions.get(key);
    if (expectedPc && cur && cur.pc && cur.pc !== expectedPc) return;
    clearSessionState(key);
    if (!cur) return;
    const s = cur;
    webrtcSessions.delete(key);
    const reason = opts && opts.reason != null ? String(opts.reason) : '';
    const tk = s && s.transportKind ? String(s.transportKind) : '未知';
    console.log(`[P2pConnectWorker] 清理 P2P 会话 sid=${key} 传输=${tk}${reason ? ` reason=${reason}` : ''}`);
    if (s && s.connectTimer) {
      try {
        clearTimeout(s.connectTimer);
      } catch (_) {}
      s.connectTimer = null;
    }
    if (s && s.disconnectTimer) {
      try {
        clearTimeout(s.disconnectTimer);
      } catch (_) {}
      s.disconnectTimer = null;
    }
    if (opts && opts.notifyPeer) {
      const payload = { type: 'session:closed', sessionId: key, ...(reason ? { reason } : {}) };
      const ok = sendSignal(payload);
      if (!ok) {
        try {
          queueSessionClosed(key, { reason, at: Date.now() });
        } catch (_) {}
      }
    }
    try {
      const dcs = s.dcs;
      if (dcs && typeof dcs.values === 'function') {
        for (const ch of dcs.values()) {
          try {
            if (ch && typeof ch.close === 'function') ch.close();
          } catch (_) {}
        }
      }
    } catch (_) {}
    try {
      if (s.pc && typeof s.pc.close === 'function') s.pc.close();
    } catch (_) {}
    if (webrtcSessions.size === 0) {
      scheduleNodeDataChannelCleanup(reason || 'session_closed');
    }
  };

  const ensureSession = sessionId => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return null;
    const existing = webrtcSessions.get(sid);
    if (existing && existing.pc) {
      const cs = existing.pc.connectionState ? String(existing.pc.connectionState) : '';
      if (cs === 'closed' || cs === 'failed') {
        closeSession(sid, { notifyPeer: true, reason: cs });
      } else {
        return existing;
      }
    }

    const polyfill = ensureWebRtcPolyfill();
    if (!polyfill) return null;

    const iceServers = sessionIceServers.get(sid) || [];
    const relayOnlyIce = iceServersAreRelayOnly(iceServers);
    let pc;
    try {
      const cfg = { iceServers };
      if (relayOnlyIce) cfg.iceTransportPolicy = 'relay';
      pc = new polyfill.RTCPeerConnection(cfg);
    } catch (_) {
      pc = new polyfill.RTCPeerConnection({ iceServers });
    }
    const state = {
      sessionId: sid,
      pc,
      dcs: new Map(),
      createdAt: Date.now(),
      connectTimer: null,
      disconnectTimer: null,
      lastConnectionState: '',
      transportKind: '',
      remoteDescriptionSet: false,
      relayOnlyIce,
    };
    webrtcSessions.set(sid, state);

    state.connectTimer = setTimeout(() => {
      const cur = webrtcSessions.get(sid);
      if (!cur || !cur.pc || cur.pc !== pc) return;
      const cs = cur.pc.connectionState ? String(cur.pc.connectionState) : '';
      if (cs === 'connected') return;
      console.log(`[P2pConnectWorker] P2P 连接超时 sid=${sid} cs=${cs || 'unknown'}，清理会话`);
      closeSession(sid, { notifyPeer: true, reason: cs || 'connect_timeout', expectedPc: pc });
    }, 30000);

    pc.onicecandidate = ev => {
      const cur = webrtcSessions.get(sid);
      if (!cur || cur.pc !== pc) return;
      const c = ev && ev.candidate ? ev.candidate : null;
      if (!c) {
        console.log(`[P2pConnectWorker] ICE 候选收集完成 sid=${sid}`);
        return;
      }
      const candidateStr = c.candidate ? String(c.candidate) : '';
      const isIPv6 = candidateStr.includes(' typ ') && /[0-9a-f]{4,}:[0-9a-f:]+/.test(candidateStr);
      const parts = candidateStr.split(' ');
      const addr = parts[4] || '?';
      const port = parts[5] || '?';
      const typIdx = parts.indexOf('typ');
      const typ = typIdx >= 0 ? parts[typIdx + 1] || '?' : '?';
      const proto = parts[2] || '?';
      const curForRelay = webrtcSessions.get(sid);
      const skipRelayDelay = !!(curForRelay && curForRelay.relayOnlyIce);
      if (!skipRelayDelay) {
        console.log(`[P2pConnectWorker] ICE候选 sid=${sid} ${isIPv6 ? '[IPv6]' : '[IPv4]'} ${proto} ${typ} ${addr}:${port}`);
      }

      const doSend = () => sendSignal({ type: 'webrtc:candidate', sessionId: sid, candidate: c });

      if (typ === 'relay' && !skipRelayDelay) {
        // 延迟 4s 发送中继候选，让直连（IPv4/IPv6 host、srflx）优先被测试和 nominated
        // 若 4s 内已直连成功，则丢弃该中继候选，避免被随机选中
        setTimeout(() => {
          const cur2 = webrtcSessions.get(sid);
          if (!cur2 || cur2.pc !== pc) return;
          const cs = cur2.pc.connectionState ? String(cur2.pc.connectionState) : '';
          if (cs === 'connected') {
            console.log(`[P2pConnectWorker] 跳过中继候选（已直连）sid=${sid} ${addr}:${port}`);
            return;
          }
          console.log(`[P2pConnectWorker] 发送延迟中继候选 sid=${sid} ${addr}:${port}`);
          doSend();
        }, RELAY_CANDIDATE_DELAY_MS);
      } else {
        doSend();
      }
    };

    pc.onconnectionstatechange = () => {
      const cs = pc.connectionState ? String(pc.connectionState) : '';
      const cur = webrtcSessions.get(sid);
      if (!cur || cur.pc !== pc) return;
      const prev = cur && cur.lastConnectionState ? String(cur.lastConnectionState) : '';
      if (cur) cur.lastConnectionState = cs;
      if (cs && cs !== prev) {
        const tk = cur && cur.transportKind ? String(cur.transportKind) : '未知';
        console.log(`[P2pConnectWorker] P2P 连接状态变化 sid=${sid} ${prev || 'unknown'} -> ${cs} 传输=${tk}`);
      }
      if (cs === 'connected') {
        try {
          if (cur && !cur.transportKind && pc && typeof pc.selectedCandidatePair === 'function') {
            const cp = pc.selectedCandidatePair();
            const localType = cp && cp.local && cp.local.type ? String(cp.local.type) : '';
            const remoteType = cp && cp.remote && cp.remote.type ? String(cp.remote.type) : '';
            const isRelay = localType === 'relay' || remoteType === 'relay';
            cur.transportKind = isRelay ? '中继' : '直连';
            const la = cp && cp.local && cp.local.address ? String(cp.local.address) : '';
            const lp = cp && cp.local && Number.isFinite(cp.local.port) ? String(cp.local.port) : '';
            const ra = cp && cp.remote && cp.remote.address ? String(cp.remote.address) : '';
            const rp = cp && cp.remote && Number.isFinite(cp.remote.port) ? String(cp.remote.port) : '';
            if (ra) cur.remoteAddress = ra;
            console.log(
              `[P2pConnectWorker] P2P 已连接 sid=${sid} 传输=${cur.transportKind} local=${la}${lp ? `:${lp}` : ''}(${localType || 'unknown'}) remote=${ra}${rp ? `:${rp}` : ''}(${remoteType || 'unknown'})`
            );
          } else if (cur && cur.transportKind && pc && typeof pc.selectedCandidatePair === 'function') {
            const cp = pc.selectedCandidatePair();
            const ra = cp && cp.remote && cp.remote.address ? String(cp.remote.address) : '';
            if (ra && !cur.remoteAddress) cur.remoteAddress = ra;
          } else if (cur) {
            console.log(`[P2pConnectWorker] P2P 已连接 sid=${sid} 传输=${cur.transportKind || '未知'}`);
          }
        } catch (_) {}
        if (cur && cur.connectTimer) {
          try {
            clearTimeout(cur.connectTimer);
          } catch (_) {}
          cur.connectTimer = null;
        }
        if (cur && cur.disconnectTimer) {
          try {
            clearTimeout(cur.disconnectTimer);
          } catch (_) {}
          cur.disconnectTimer = null;
        }
        return;
      }
      if (cs === 'disconnected') {
        if (!cur) return;
        if (cur.disconnectTimer) return;
        console.log(`[P2pConnectWorker] P2P 进入 disconnected sid=${sid}，20s 内若未恢复将清理会话`);
        cur.disconnectTimer = setTimeout(() => {
          const cur2 = webrtcSessions.get(sid);
          if (!cur2 || !cur2.pc || cur2.pc !== pc) return;
          const cs2 = cur2.pc.connectionState ? String(cur2.pc.connectionState) : '';
          if (cs2 === 'disconnected' || cs2 === 'failed' || cs2 === 'closed') {
            closeSession(sid, { notifyPeer: true, reason: cs2 || 'disconnected', expectedPc: pc });
          } else {
            try {
              clearTimeout(cur2.disconnectTimer);
            } catch (_) {}
            cur2.disconnectTimer = null;
          }
        }, 20000);
        return;
      }
      if (cs === 'failed' || cs === 'closed') {
        console.log(`[P2pConnectWorker] P2P 连接失败/关闭 sid=${sid} state=${cs}，清理会话`);
        closeSession(sid, { notifyPeer: true, reason: cs, expectedPc: pc });
      }
    };

    pc.ondatachannel = ev => {
      const cur = webrtcSessions.get(sid);
      if (!cur || cur.pc !== pc) return;
      const ch = ev && ev.channel ? ev.channel : null;
      if (!ch) return;
      attachDataChannel({ sessionId: sid, dc: ch, pc, webrtcManager: api, proxyPendingStore, localExpressProxy, wsImpl });
    };

    return state;
  };

  const handleOffer = (sessionId, offer) => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid || !offer) return;
    let state = webrtcSessions.get(sid);
    if (state && state.pc) {
      let ss = '';
      try {
        ss = state.pc.signalingState ? String(state.pc.signalingState) : '';
      } catch (_) {
        ss = '';
      }
      if (state.remoteDescriptionSet || (ss && ss !== 'stable')) {
        closeSession(sid, { reason: 'new_offer_reset' });
        state = null;
      }
    }
    if (!state || !state.pc) state = ensureSession(sid);
    if (!state || !state.pc) return;
    const polyfill = ensureWebRtcPolyfill();
    if (!polyfill) return;
    Promise.resolve()
      .then(async () => {
        await state.pc.setRemoteDescription(offer);
        state.remoteDescriptionSet = true;
        const pendingCandidates = proxyPendingStore.drainPendingRemoteCandidates(sid);
        for (const c of pendingCandidates) {
          try {
            await state.pc.addIceCandidate(c);
          } catch (e) {
            const em = e && e.message ? String(e.message) : e != null ? String(e) : '';
            console.log(`[P2pConnectWorker] webrtc:pending_candidate failed sid=${sid}${em ? ` error=${em}` : ''}`);
            throw e;
          }
        }
        const ans = await state.pc.createAnswer();
        await state.pc.setLocalDescription(ans);
        sendSignal({ type: 'webrtc:answer', sessionId: sid, answer: state.pc.localDescription });
      })
      .catch(e => {
        const em = e && e.message ? String(e.message) : e != null ? String(e) : '';
        console.log(`[P2pConnectWorker] webrtc:offer failed sid=${sid}${em ? ` error=${em}` : ''}`);
        closeSession(sid, { notifyPeer: true, reason: 'offer_failed' });
      });
  };

  const handleRemoteCandidate = (sessionId, candidate) => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid || !candidate) return;
    const state = webrtcSessions.get(sid);
    if (!state || !state.pc || !state.remoteDescriptionSet) {
      proxyPendingStore.pushPendingRemoteCandidate(sid, candidate);
      return;
    }
    const pc = state.pc;
    const polyfill = ensureWebRtcPolyfill();
    if (!polyfill) return;
    Promise.resolve()
      .then(async () => {
        await pc.addIceCandidate(candidate);
      })
      .catch(e => {
        const em = e && e.message ? String(e.message) : e != null ? String(e) : '';
        console.log(`[P2pConnectWorker] webrtc:candidate failed sid=${sid}${em ? ` error=${em}` : ''}`);
        closeSession(sid, { notifyPeer: true, reason: 'candidate_failed', expectedPc: pc });
      });
  };

  const closeAllSessions = () => {
    for (const [sid] of webrtcSessions.entries()) {
      closeSession(sid);
    }
    try {
      proxyPendingStore.pendingRemoteCandidatesBySession.clear();
    } catch (_) {}
    try {
      sessionIceServers.clear();
    } catch (_) {}
  };

  const closeSessionsForSignalingLoss = () => {
    for (const [sid, state] of webrtcSessions.entries()) {
      const cs = state && state.pc && state.pc.connectionState ? String(state.pc.connectionState) : '';
      if (cs === 'connected') {
        console.log(`[P2pConnectWorker] 信令断开但保留已连接会话 sid=${sid}`);
        continue;
      }
      closeSession(sid, { reason: 'signaling_lost', expectedPc: state && state.pc ? state.pc : null });
    }
    try {
      for (const sid of Array.from(proxyPendingStore.pendingRemoteCandidatesBySession.keys())) {
        if (!webrtcSessions.has(sid)) {
          proxyPendingStore.pendingRemoteCandidatesBySession.delete(sid);
        }
      }
    } catch (_) {}
    try {
      for (const sid of Array.from(sessionIceServers.keys())) {
        if (!webrtcSessions.has(sid)) {
          sessionIceServers.delete(sid);
        }
      }
    } catch (_) {}
  };

  const setSessionIceServers = (sessionId, iceServers) => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return;
    const list = Array.isArray(iceServers) ? iceServers : [];
    if (list.length) sessionIceServers.set(sid, list);
  };

  const getSessionIceServers = sessionId => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return [];
    return sessionIceServers.get(sid) || [];
  };

  const getSession = sessionId => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return null;
    return webrtcSessions.get(sid) || null;
  };

  const hasSession = sessionId => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return false;
    return webrtcSessions.has(sid);
  };

  const getTransportKind = sessionId => {
    const s = getSession(sessionId);
    return s && s.transportKind ? String(s.transportKind) : '';
  };

  /** 获取会话对端（P2P 请求端）的真实 IP，用于转发到 express 时设置 X-Real-IP / X-Forwarded-For */
  const getSessionRemoteAddress = sessionId => {
    const s = getSession(sessionId);
    if (!s) return '';
    if (s.remoteAddress) return String(s.remoteAddress).trim();
    try {
      if (s.pc && s.pc.connectionState === 'connected' && typeof s.pc.selectedCandidatePair === 'function') {
        const cp = s.pc.selectedCandidatePair();
        const ra = cp && cp.remote && cp.remote.address ? String(cp.remote.address) : '';
        if (ra) {
          s.remoteAddress = ra;
          return ra.trim();
        }
      }
    } catch (_) {}
    return '';
  };

  const registerDataChannel = (sessionId, label, dc) => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return;
    const s = webrtcSessions.get(sid);
    if (!s || !s.dcs || typeof s.dcs.set !== 'function') return;
    const key = label == null ? '' : String(label);
    if (!key) return;
    s.dcs.set(key, dc);
  };

  const unregisterDataChannel = (sessionId, label, expectedDc) => {
    const sid = sessionId == null ? '' : String(sessionId);
    if (!sid) return;
    const s = webrtcSessions.get(sid);
    if (!s || !s.dcs || typeof s.dcs.get !== 'function') return;
    const key = label == null ? '' : String(label);
    if (!key) return;
    try {
      if (expectedDc && s.dcs.get(key) !== expectedDc) return;
      s.dcs.delete(key);
    } catch (_) {}
  };

  const hasAnyDataChannel = sessionId => {
    const s = getSession(sessionId);
    if (!s || !s.dcs || typeof s.dcs.size !== 'number') return false;
    return s.dcs.size > 0;
  };

  const api = {
    ensureWebRtcPolyfill,
    ensureNodeDataChannelLib,
    scheduleNodeDataChannelCleanup,
    ensureSession,
    closeSession,
    closeAllSessions,
    closeSessionsForSignalingLoss,
    handleOffer,
    handleRemoteCandidate,
    setSessionIceServers,
    getSessionIceServers,
    getSession,
    hasSession,
    getTransportKind,
    getSessionRemoteAddress,
    registerDataChannel,
    unregisterDataChannel,
    hasAnyDataChannel,
  };

  return api;
}

module.exports = { createWebRtcSessionManager };
