import { SIGNAL_API_BASE } from './constants.js';
import { decryptPairCode } from './crypto-util.js';
import { createDeferred } from './p2p-deferred.js';
import { makeDcClient } from './p2p-datachannel.js';
import { encodeSignalMessage, decodeSignalMessage } from './p2p-signaling-codec.js';

export async function connectP2pByEncPairCode(enc, opts = {}) {
  const pairCode = await decryptPairCode(enc);
  if (!pairCode) throw new Error('pair_code_invalid');

  const createUrl = `${SIGNAL_API_BASE}/api/p2p/pair/session/create`;
  console.log('[QuickShare][P2P] creating session');
  const createResp = await fetch(createUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pairCode }),
  });
  const createJson = await createResp.json().catch(() => null);
  const data = createJson && createJson.data && typeof createJson.data === 'object' ? createJson.data : createJson;
  const wsUrl = data && data.wsUrl ? String(data.wsUrl) : '';
  const sessionIdRaw = data && data.sessionId ? String(data.sessionId) : '';
  if (!wsUrl || !sessionIdRaw) throw new Error('p2p_session_invalid');

  console.log('[QuickShare][P2P] ws connecting', { sessionId: sessionIdRaw });
  const ws = new WebSocket(wsUrl);
  ws.binaryType = 'arraybuffer';
  const wsReady = createDeferred();
  let sessionId = sessionIdRaw;
  let iceServers = [];
  let wsHeartbeatTimer = null;
  const onDisconnected = typeof opts.onDisconnected === 'function' ? opts.onDisconnected : null;
  let disconnectedOnce = false;
  const notifyDisconnected = reason => {
    if (disconnectedOnce) return;
    disconnectedOnce = true;
    try {
      if (onDisconnected) onDisconnected(reason);
    } catch (_) {}
  };

  const sendSignal = payload => {
    try {
      const bin = encodeSignalMessage(payload);
      if (bin && ws.readyState === ws.OPEN) ws.send(bin);
    } catch (_) {}
  };

  ws.onopen = () => {
    console.log('[QuickShare][P2P] ws open');
    sendSignal({ type: 'ping', ts: Date.now() });
  };
  ws.onmessage = ev => {
    const raw = ev && ev.data != null ? ev.data : null;
    const msg = raw && (raw instanceof ArrayBuffer || ArrayBuffer.isView(raw)) ? decodeSignalMessage(raw) : null;
    if (!msg || typeof msg !== 'object') return;
    const type = msg.type ? String(msg.type) : '';
    if (type === 'session:ready') {
      if (msg.sessionId) sessionId = String(msg.sessionId);
      iceServers = Array.isArray(msg.iceServers) ? msg.iceServers : [];
      console.log('[QuickShare][P2P] session ready', { sessionId, iceServers: iceServers.length });
      wsReady.resolve(true);
      return;
    }
    if (type === 'error') {
      wsReady.reject(new Error(String(msg.code || 'p2p_ws_error')));
    }
  };
  ws.onerror = () => {
    wsReady.reject(new Error('p2p_ws_error'));
  };
  ws.onclose = () => {
    wsReady.reject(new Error('p2p_ws_closed'));
  };

  await Promise.race([wsReady.promise, new Promise((_, reject) => setTimeout(() => reject(new Error('p2p_session_ready_timeout')), 15000))]);

  // directOnly 模式：过滤掉 TURN relay 条目，只保留 STUN + 直连候选
  const directOnly = !!(opts && opts.directOnly);
  const effectiveIceServers = directOnly
    ? iceServers
        .map(s => {
          if (!s || !s.urls) return s;
          const urls = Array.isArray(s.urls) ? s.urls : [s.urls];
          const nonTurn = urls.filter(u => {
            const lower = String(u || '').toLowerCase();
            return !lower.startsWith('turn:') && !lower.startsWith('turns:');
          });
          if (!nonTurn.length) return null;
          return { ...s, urls: nonTurn.length === 1 ? nonTurn[0] : nonTurn };
        })
        .filter(Boolean)
    : iceServers;

  const pc = new RTCPeerConnection({
    iceServers: effectiveIceServers,
    // 预热候选池：减少 relay 和 IPv6 直连之间的竞速随机性
    iceCandidatePoolSize: 2,
  });
  const apiDc = pc.createDataChannel('api');
  apiDc.binaryType = 'arraybuffer';
  const fileDc = pc.createDataChannel('file');
  fileDc.binaryType = 'arraybuffer';
  const closeAll = () => {
    if (wsHeartbeatTimer) {
      try {
        clearInterval(wsHeartbeatTimer);
      } catch (_) {}
    }
    wsHeartbeatTimer = null;
    try {
      apiDc.close();
    } catch (_) {}
    try {
      fileDc.close();
    } catch (_) {}
    try {
      pc.close();
    } catch (_) {}
    try {
      ws.close();
    } catch (_) {}
  };

  try {
    ws.addEventListener('close', () => notifyDisconnected('ws_closed'));
    ws.addEventListener('error', () => notifyDisconnected('ws_error'));
  } catch (_) {}
  try {
    pc.addEventListener('connectionstatechange', () => {
      const cs = pc.connectionState ? String(pc.connectionState) : '';
      if (cs) console.log('[QuickShare][P2P] pc state', cs);
      if (cs === 'failed' || cs === 'disconnected' || cs === 'closed') notifyDisconnected(`pc_${cs || 'closed'}`);
    });
  } catch (_) {}
  try {
    apiDc.addEventListener('close', () => notifyDisconnected('dc_api_closed'));
    fileDc.addEventListener('close', () => notifyDisconnected('dc_file_closed'));
  } catch (_) {}
  apiDc.onclose = () => notifyDisconnected('dc_api_closed');
  fileDc.onclose = () => notifyDisconnected('dc_file_closed');
  apiDc.onopen = () => console.log('[QuickShare][P2P] dc open api');
  fileDc.onopen = () => console.log('[QuickShare][P2P] dc open file');

  // 中继(relay)候选延迟 4s 发送，优先让 IPv4/IPv6 直连被测试，避免直连可用时仍走中继
  const RELAY_CANDIDATE_DELAY_MS = 4000;
  pc.onicecandidate = ev => {
    const c = ev && ev.candidate ? ev.candidate : null;
    if (!c) return;
    const candidateStr = c.candidate ? String(c.candidate) : '';
    const parts = candidateStr.split(' ');
    const typIdx = parts.indexOf('typ');
    const typ = typIdx >= 0 && typIdx + 1 < parts.length ? parts[typIdx + 1] : '';
    const doSend = () => {
      sendSignal({
        type: 'webrtc:candidate',
        sessionId,
        candidate: { candidate: c.candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex },
      });
    };
    if (typ === 'relay') {
      setTimeout(() => {
        if (pc.connectionState === 'connected') return;
        doSend();
      }, RELAY_CANDIDATE_DELAY_MS);
    } else {
      doSend();
    }
  };

  ws.onmessage = ev => {
    const raw = ev && ev.data != null ? ev.data : null;
    const msg = raw && (raw instanceof ArrayBuffer || ArrayBuffer.isView(raw)) ? decodeSignalMessage(raw) : null;
    if (!msg || typeof msg !== 'object') return;
    const type = msg.type ? String(msg.type) : '';
    if (type === 'pong' || type === 'ping') return;
    if (type === 'session:ready') return;
    if (type === 'webrtc:answer' && msg.answer) {
      console.log('[QuickShare][P2P] got answer');
      pc.setRemoteDescription(msg.answer).catch(() => {});
      return;
    }
    if (type === 'webrtc:candidate' && msg.candidate) {
      pc.addIceCandidate(msg.candidate).catch(() => {});
      return;
    }
    if (type === 'session:closed') {
      console.log('[QuickShare][P2P] session closed');
      try {
        pc.close();
      } catch (_) {}
    }
  };

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  sendSignal({ type: 'webrtc:offer', sessionId, offer: { type: offer.type, sdp: offer.sdp } });
  console.log('[QuickShare][P2P] offer sent');

  const api = makeDcClient('api', apiDc);
  const file = makeDcClient('file', fileDc);
  wsHeartbeatTimer = setInterval(() => {
    sendSignal({ type: 'ping', ts: Date.now() });
  }, 15000);

  await Promise.race([Promise.all([api.ready, file.ready]), new Promise((_, reject) => setTimeout(() => reject(new Error('p2p_dc_ready_timeout')), 20000))]);
  console.log('[QuickShare][P2P] dc ready');

  // 检测当前连接的传输类型（relay / direct），用于 auto-upgrade 决策
  let transportKind = 'unknown';
  try {
    await new Promise(r => setTimeout(r, 600));
    const statsReport = await pc.getStats();
    const statsArr = [];
    statsReport.forEach(v => statsArr.push(v));
    const pairs = statsArr.filter(s => s.type === 'candidate-pair' && s.state === 'succeeded');
    let activePair = pairs.find(p => p.nominated) || null;
    if (!activePair && pairs.length) {
      activePair = pairs.reduce((a, b) => ((a.bytesSent || 0) + (a.bytesReceived || 0) >= (b.bytesSent || 0) + (b.bytesReceived || 0) ? a : b));
    }
    if (activePair) {
      const localCand = statsArr.find(s => s.id === activePair.localCandidateId);
      const localType = localCand ? localCand.candidateType || '' : '';
      const localAddr = localCand ? localCand.address || localCand.ip || '' : '';
      const remoteAddr = statsArr.find(s => s.id === activePair.remoteCandidateId);
      const isIPv6 = localAddr.includes(':') || (remoteAddr && (remoteAddr.address || remoteAddr.ip || '').includes(':'));
      transportKind = localType === 'relay' ? 'relay' : localType ? 'direct' : 'unknown';
      console.log(`[QuickShare][P2P] transport=${transportKind} localType=${localType} ${isIPv6 ? '[IPv6]' : '[IPv4]'} local=${localAddr}`);
    }
  } catch (_) {}

  return { api, file, close: closeAll, transportKind };
}
