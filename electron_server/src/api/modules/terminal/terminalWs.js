const crypto = require('crypto');
const Logger = require('../../../utils/logger');
const { getLocalizedMessage } = require('../../../utils/i18nUtil');
const jwtUtil = require('../../../utils/jwtUtil');
const userUtil = require('../../../utils/userUtil');
const { parseAnyOrArray, matchApi } = require('../../../utils/permissionUtil');
const { isAppTerminalEnabled } = require('../../../utils/appAccessScopeUtil');

const WS_CLOSE_UNAUTHORIZED = 4403;
const WS_CLOSE_SERVER_ERROR = 4500;
const HEARTBEAT_INTERVAL_MS = 25 * 1000;
const HEARTBEAT_TIMEOUT_MS = 40 * 1000;
const DEFAULT_COLS = 100;
const DEFAULT_ROWS = 30;

const activeConnections = new Map();
let processMessageBound = false;

function toInt(value, fallback) {
  const n = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(n) ? n : fallback;
}

function decryptAesParams(ciphertextBase64, serverId) {
  try {
    const key = crypto.createHash('sha256').update(serverId).digest();
    const inputBuffer = Buffer.from(String(ciphertextBase64), 'base64');
    if (inputBuffer.length < 17) return null;
    const iv = inputBuffer.subarray(0, 16);
    const encrypted = inputBuffer.subarray(16);
    const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
    let decrypted = decipher.update(encrypted);
    decrypted = Buffer.concat([decrypted, decipher.final()]);
    return JSON.parse(decrypted.toString('utf8'));
  } catch (_) {
    return null;
  }
}

function decryptWsQuery(req, _res, next) {
  try {
    const serverId = process.env.SERVER_ID;
    if (!serverId) return next();
    if (req.query && req.query.aes) {
      const decrypted = decryptAesParams(req.query.aes, serverId);
      if (decrypted && typeof decrypted === 'object') {
        Object.assign(req.query, decrypted);
        delete req.query.aes;
      }
    }
  } catch (_) {}
  next();
}

function parseClientMessage(raw) {
  try {
    const txt = typeof raw === 'string' ? raw : raw.toString('utf8');
    const obj = JSON.parse(txt);
    if (obj && typeof obj === 'object') return obj;
  } catch (_) {}
  return null;
}

function safeSendJson(ws, obj) {
  try {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify(obj));
    }
  } catch (_) {}
}

function safeClose(ws, code, reason) {
  try {
    ws.close(code, reason);
  } catch (_) {}
}

function waitForIpcResponse({ requestId, responseType, timeoutMs }) {
  return new Promise((resolve, reject) => {
    if (typeof process.send !== 'function') {
      reject(new Error('ipc_unavailable'));
      return;
    }

    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        process.removeListener('message', onMessage);
      } catch (_) {}
      reject(new Error('ipc_timeout'));
    }, Math.max(500, Number(timeoutMs || 0) || 0));

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

function localizeMessage(req, code) {
  switch (String(code || '').trim().toUpperCase()) {
    case 'TOKEN_EXPIRED':
      return getLocalizedMessage(req, 'auth.TOKEN_EXPIRED');
    case 'TERMINAL_AUTH_REQUIRED':
      return getLocalizedMessage(req, 'auth.AUTHENTICATION_REQUIRED');
    case 'TERMINAL_INVALID_TOKEN':
      return getLocalizedMessage(req, 'auth.INVALID_TOKEN');
    case 'TERMINAL_AUTH_ERROR':
      return getLocalizedMessage(req, 'auth.AUTHENTICATION_ERROR');
    case 'TERMINAL_API_NOT_ALLOWED':
      return getLocalizedMessage(req, 'auth.API_NOT_ALLOWED');
    case 'TERMINAL_ADMIN_ONLY':
      return getLocalizedMessage(req, 'auth.INSUFFICIENT_ADMIN_PERMISSION');
    case 'TERMINAL_DISABLED':
      return getLocalizedMessage(req, 'terminal.DISABLED');
    case 'TERMINAL_SESSION_LIMIT_REACHED':
      return getLocalizedMessage(req, 'terminal.SESSION_LIMIT_REACHED');
    case 'TERMINAL_COMMAND_BLOCKED':
      return getLocalizedMessage(req, 'terminal.COMMAND_BLOCKED');
    case 'TERMINAL_OUTPUT_RATE_LIMIT':
      return getLocalizedMessage(req, 'terminal.OUTPUT_OVERFLOW');
    case 'TERMINAL_SESSION_EXPIRED':
      return getLocalizedMessage(req, 'terminal.SESSION_EXPIRED');
    case 'TERMINAL_SESSION_TIMEOUT':
      return getLocalizedMessage(req, 'terminal.SESSION_TIMEOUT');
    default:
      return getLocalizedMessage(req, 'terminal.START_FAILED');
  }
}

function normalizeConnectErrorCode(error) {
  const normalized = String(error || '').trim().toLowerCase();
  if (normalized === 'session_limit_reached') return 'TERMINAL_SESSION_LIMIT_REACHED';
  return 'TERMINAL_START_FAILED';
}

function sendIpcMessage(type, data) {
  if (typeof process.send !== 'function') return false;
  try {
    process.send({ type, data, timestamp: Date.now() });
    return true;
  } catch (_) {
    return false;
  }
}

function detachConnection(sessionId, { notifyMain } = {}) {
  const connection = activeConnections.get(sessionId);
  if (!connection) return;
  activeConnections.delete(sessionId);
  try {
    if (connection.heartbeatTimer) clearInterval(connection.heartbeatTimer);
  } catch (_) {}
  connection.heartbeatTimer = null;
  if (notifyMain) {
    sendIpcMessage('terminalDetachSession', {
      sessionId,
      workerPid: process.pid,
    });
  }
}

function bindConnectionSocket(sessionId, connection) {
  const { ws } = connection;

  ws.on('message', msg => {
    connection.lastSeenAt = Date.now();
    connection.isAlive = true;

    const obj = parseClientMessage(msg);
    if (obj && obj.type) {
      if (obj.type === 'ping') {
        return safeSendJson(ws, { type: 'pong', t: Date.now() });
      }
      if (obj.type === 'resize') {
        const cols = Math.max(20, Math.min(400, toInt(obj.cols, connection.cols || DEFAULT_COLS)));
        const rows = Math.max(5, Math.min(200, toInt(obj.rows, connection.rows || DEFAULT_ROWS)));
        connection.cols = cols;
        connection.rows = rows;
        return sendIpcMessage('terminalResize', { sessionId, cols, rows });
      }
      if (obj.type === 'input') {
        return sendIpcMessage('terminalInput', { sessionId, data: obj.data });
      }
      if (obj.type === 'terminate') {
        connection.suppressDetach = true;
        return sendIpcMessage('terminalTerminateSession', { sessionId });
      }
      if (obj.type === 'close') {
        const reason = String(obj.reason || '').trim().toLowerCase();
        if (reason === 'terminate') {
          connection.suppressDetach = true;
          sendIpcMessage('terminalTerminateSession', { sessionId });
        }
        return safeClose(ws, 1000, 'client close');
      }
    }

    const raw = typeof msg === 'string' ? msg : msg.toString('utf8');
    if (raw && raw.startsWith('nastermresize-')) {
      const arr = raw.split('-');
      const rows = toInt(arr[1], connection.rows || DEFAULT_ROWS);
      const cols = toInt(arr[2], connection.cols || DEFAULT_COLS);
      connection.cols = cols;
      connection.rows = rows;
      return sendIpcMessage('terminalResize', { sessionId, cols, rows });
    }

    sendIpcMessage('terminalInput', { sessionId, data: raw });
  });

  ws.on('pong', () => {
    connection.lastSeenAt = Date.now();
    connection.isAlive = true;
  });

  ws.on('close', () => {
    detachConnection(sessionId, { notifyMain: true });
  });

  ws.on('error', err => {
    Logger.error('Terminal ws error', err, {
      sessionId,
      userId: connection.req && connection.req.user && connection.req.user.id,
    });
    detachConnection(sessionId, { notifyMain: true });
    safeClose(ws, WS_CLOSE_SERVER_ERROR, 'ws error');
  });

  connection.heartbeatTimer = setInterval(() => {
    if (!activeConnections.has(sessionId)) return;
    const now = Date.now();
    if (!connection.isAlive && now - connection.lastSeenAt > HEARTBEAT_TIMEOUT_MS) {
      safeClose(ws, 1006, 'heartbeat timeout');
      detachConnection(sessionId, { notifyMain: true });
      return;
    }
    connection.isAlive = false;
    try {
      ws.ping();
    } catch (_) {}
    safeSendJson(ws, { type: 'ping', t: Date.now() });
  }, HEARTBEAT_INTERVAL_MS);
}

function closeExistingConnection(sessionId) {
  const existing = activeConnections.get(sessionId);
  if (!existing) return;
  existing.suppressDetach = true;
  try {
    safeClose(existing.ws, 1000, 'reattached');
  } catch (_) {}
  detachConnection(sessionId, { notifyMain: false });
}

function handleTerminalSessionEvent(data) {
  const sessionId = String((data && data.sessionId) || '').trim();
  if (!sessionId) return;
  const connection = activeConnections.get(sessionId);
  if (!connection) return;
  const event = data && data.event && typeof data.event === 'object' ? data.event : {};
  const { ws, req } = connection;

  if (event.type === 'output') {
    safeSendJson(ws, { type: 'output', data: event.data || '' });
    return;
  }

  if (event.type === 'disconnect') {
    connection.suppressDetach = true;
    const reason = String(event.reason || '').trim().toLowerCase();
    if (reason === 'taken_over') {
      safeSendJson(ws, {
        type: 'error',
        code: 'TERMINAL_TAKEN_OVER',
        message: '终端已在其他页面打开',
      });
    }
    safeClose(ws, 1000, event.reason || 'reattached');
    detachConnection(sessionId, { notifyMain: false });
    return;
  }

  if (event.type === 'error') {
    const code = String(event.code || 'TERMINAL_START_FAILED').trim().toUpperCase();
    safeSendJson(ws, { type: 'error', code, message: localizeMessage(req, code) });
    if (event.close) {
      connection.suppressDetach = true;
      safeClose(ws, 1000, code);
      detachConnection(sessionId, { notifyMain: false });
    }
    return;
  }

  if (event.type === 'exit') {
    safeSendJson(ws, {
      type: 'exit',
      exitCode: event.exitCode,
      signal: event.signal,
    });
    connection.suppressDetach = true;
    safeClose(ws, 1000, 'terminal exited');
    detachConnection(sessionId, { notifyMain: false });
  }
}

function bindProcessMessageHandler() {
  if (processMessageBound) return;
  processMessageBound = true;
  process.on('message', message => {
    if (!message || message.type !== 'terminalSessionEvent') return;
    handleTerminalSessionEvent(message.data || {});
  });
}

async function connectTerminalSession({ userId, username, clientDeviceId, terminalSlotId, terminalConnId, shellQuery, cols, rows, forceNew }) {
  const requestId = `terminalConnect_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  const wait = waitForIpcResponse({
    requestId,
    responseType: 'terminalConnectSessionResponse',
    timeoutMs: 5000,
  });
  const sent = sendIpcMessage('terminalConnectSession', {
    requestId,
    userId,
    username,
    clientDeviceId,
    terminalSlotId,
    terminalConnId,
    shellQuery,
    cols,
    rows,
    forceNew: !!forceNew,
    workerPid: process.pid,
  });
  if (!sent) throw new Error('ipc_unavailable');
  return await wait;
}

function logStep(step, msg, data = {}) {
  const extra = Object.keys(data).length ? ` ${JSON.stringify(data)}` : '';
  console.log(`[TerminalWs] ${step}: ${msg}${extra}`);
}

function buildLegacyClientDeviceId(req, userId) {
  const uid = String(userId || '').trim() || 'unknown';
  const forwarded = String(req?.headers?.['x-forwarded-for'] || '').trim();
  const remoteAddress = String(req?.socket?.remoteAddress || '').trim();
  const ua = String(req?.headers?.['user-agent'] || '').trim();
  const seed = `${uid}|${forwarded}|${remoteAddress}|${ua}`;
  const hash = crypto.createHash('sha1').update(seed).digest('hex').slice(0, 16);
  return `legacy_${hash}`;
}

module.exports = app => {
  bindProcessMessageHandler();
  app.ws('/api/terminal/connect', decryptWsQuery, async (ws, req) => {
    logStep('步骤1', 'WebSocket 连接已建立');
    try {
      const accessToken = req.query && req.query.accessToken ? String(req.query.accessToken) : '';
      const cols = Math.max(20, Math.min(400, toInt(req.query && req.query.cols, DEFAULT_COLS)));
      const rows = Math.max(5, Math.min(200, toInt(req.query && req.query.rows, DEFAULT_ROWS)));
      const shellQuery = req.query && req.query.shell ? String(req.query.shell) : '';
      const clientDeviceId = req.query && (req.query.clientDeviceId || req.query.clientInstanceId)
        ? String(req.query.clientDeviceId || req.query.clientInstanceId).trim()
        : '';
      const terminalSlotId = req.query && req.query.terminalSlotId ? String(req.query.terminalSlotId).trim() : 'default';
      const terminalConnId = req.query && req.query.terminalConnId ? String(req.query.terminalConnId).trim() : '';
      const forceNew = String((req.query && req.query.forceNew) || '') === '1';
      logStep('步骤2', 'query 解析完成', {
        hasAccessToken: !!accessToken?.trim(),
        cols,
        rows,
        shellQuery: shellQuery || '(default)',
        clientDeviceId: clientDeviceId || '(missing)',
        terminalSlotId: terminalSlotId || 'default',
        forceNew,
      });

      if (!accessToken || !accessToken.trim()) {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_AUTH_REQUIRED',
          message: localizeMessage(req, 'TERMINAL_AUTH_REQUIRED'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'authentication required');
      }

      try {
        req.user = jwtUtil.verifyToken(process.env.JWT_SECRET, accessToken);
      } catch (jwtErr) {
        const isExpired = jwtErr && jwtErr.name === 'TokenExpiredError';
        safeSendJson(ws, {
          type: 'error',
          code: isExpired ? 'TOKEN_EXPIRED' : 'TERMINAL_INVALID_TOKEN',
          message: localizeMessage(req, isExpired ? 'TOKEN_EXPIRED' : 'TERMINAL_INVALID_TOKEN'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, isExpired ? 'token expired' : 'invalid token');
      }

      if (req.user && req.user.tokenType && req.user.tokenType !== 'scoped' && req.user.tokenType !== 'access') {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_INVALID_TOKEN',
          message: localizeMessage(req, 'TERMINAL_INVALID_TOKEN'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'invalid token');
      }

      req.user.id = req.user.userId || req.user.id || req.user.uid || req.user.user_id;
      if (!req.dbMain) {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_AUTH_ERROR',
          message: localizeMessage(req, 'TERMINAL_AUTH_ERROR'),
        });
        return safeClose(ws, WS_CLOSE_SERVER_ERROR, 'auth error');
      }

      const now = new Date();
      const tokenRecord = await req.dbMain('user_token')
        .where({ token: accessToken, is_valid: true })
        .andWhere('expire_time', '>', now)
        .first();

      if (!tokenRecord) {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_INVALID_TOKEN',
          message: localizeMessage(req, 'TERMINAL_INVALID_TOKEN'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'invalid token');
      }

      if (req.user.tokenType === 'scoped' && tokenRecord.type !== 'scoped') {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_INVALID_TOKEN',
          message: localizeMessage(req, 'TERMINAL_INVALID_TOKEN'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'invalid token');
      }

      if (tokenRecord.type === 'scoped') {
        const allowApi = parseAnyOrArray(tokenRecord.allow_api);
        if (!matchApi(allowApi, '/api/terminal/connect')) {
          safeSendJson(ws, {
            type: 'error',
            code: 'TERMINAL_API_NOT_ALLOWED',
            message: localizeMessage(req, 'TERMINAL_API_NOT_ALLOWED'),
          });
          return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'api not allowed');
        }
        req.user.allow_api = allowApi;
        req.user.allow_path = parseAnyOrArray(tokenRecord.allow_path);
      }

      try {
        await req.dbMain('user_token').where({ id: tokenRecord.id }).update({ last_active_time: new Date() });
      } catch (_) {}

      if (!userUtil.isAdmin(req.user)) {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_ADMIN_ONLY',
          message: localizeMessage(req, 'TERMINAL_ADMIN_ONLY'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'admin only');
      }

      if (!(await isAppTerminalEnabled())) {
        safeSendJson(ws, {
          type: 'error',
          code: 'TERMINAL_DISABLED',
          message: localizeMessage(req, 'TERMINAL_DISABLED'),
        });
        return safeClose(ws, WS_CLOSE_UNAUTHORIZED, 'terminal disabled');
      }

      const userId = req.user.id;
      const username = req.user && req.user.username ? String(req.user.username) : '';
      const compatibleClientDeviceId = clientDeviceId || buildLegacyClientDeviceId(req, userId);
      const compatibleTerminalSlotId = terminalSlotId || 'default';
      const connectResult = await connectTerminalSession({
        userId,
        username,
        clientDeviceId: compatibleClientDeviceId,
        terminalSlotId: compatibleTerminalSlotId,
        terminalConnId,
        shellQuery,
        cols,
        rows,
        forceNew,
      });

      if (!connectResult || !connectResult.ok || !connectResult.sessionId) {
        const code = normalizeConnectErrorCode(connectResult && connectResult.error);
        safeSendJson(ws, {
          type: 'error',
          code,
          message: localizeMessage(req, code),
        });
        return safeClose(ws, code === 'TERMINAL_SESSION_LIMIT_REACHED' ? 1013 : WS_CLOSE_SERVER_ERROR, code);
      }

      const sessionId = String(connectResult.sessionId);
      closeExistingConnection(sessionId);
      const connection = {
        sessionId,
        ws,
        req,
        cols: connectResult.cols || cols,
        rows: connectResult.rows || rows,
        lastSeenAt: Date.now(),
        isAlive: true,
        suppressDetach: false,
        heartbeatTimer: null,
      };
      activeConnections.set(sessionId, connection);
      bindConnectionSocket(sessionId, connection);

      safeSendJson(ws, {
        type: 'ready',
        sessionId,
        reused: !!connectResult.reused,
      });

      if (connectResult.restoreData) {
        safeSendJson(ws, {
          type: 'restore',
          sessionId,
          data: String(connectResult.restoreData),
        });
      }
    } catch (e) {
      Logger.error('Terminal session attach failed', e);
      safeSendJson(ws, {
        type: 'error',
        code: 'TERMINAL_START_FAILED',
        message: localizeMessage(req, 'TERMINAL_START_FAILED'),
      });
      safeClose(ws, WS_CLOSE_SERVER_ERROR, 'terminal start failed');
    }
  });
};
