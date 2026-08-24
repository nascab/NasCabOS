const os = require('os');
const path = require('path');
const crypto = require('crypto');
const pty = require('node-pty');
const Logger = require('../utils/logger');
const { withAugmentedPath } = require('../utils/shellEnvUtil');

const OUTPUT_WINDOW_MS = 10 * 1000;
const MAX_OUTPUT_BYTES_PER_WINDOW = 256 * 1024;
const DEFAULT_REPLAY_BYTES = 32 * 1024;
const MIN_REPLAY_BYTES = 16 * 1024;
const MAX_REPLAY_BYTES = Math.max(
  MIN_REPLAY_BYTES,
  toPositiveInt(process.env.TERMINAL_REPLAY_MAX_BYTES, DEFAULT_REPLAY_BYTES),
);
const SESSION_IDLE_TIMEOUT_MS = Math.max(
  5 * 60 * 1000,
  toPositiveInt(process.env.TERMINAL_SESSION_IDLE_TIMEOUT_MS, 2 * 60 * 60 * 1000),
);
const DEFAULT_COLS = 100;
const DEFAULT_ROWS = 30;
const MAX_CONCURRENT_SESSIONS = Math.max(1, toPositiveInt(process.env.TERMINAL_MAX_SESSIONS, 10));
const MAX_SESSIONS_PER_USER = Math.max(1, toPositiveInt(process.env.TERMINAL_MAX_SESSIONS_PER_USER, 10));

const WINDOWS_SHELLS = {
  powershell: 'powershell.exe',
  pwsh: 'pwsh.exe',
  cmd: 'cmd.exe',
};

const DANGEROUS_PATTERNS = [
  /(^|\s)(rm|unlink|rmdir)(\s|$)/i,
  /(^|\s)mkfs(\.[a-z0-9_]+)?(\s|$)/i,
  /(^|\s)(fdisk|cfdisk|sfdisk|parted|wipefs|shred|blkdiscard)(\s|$)/i,
  /(^|\s)dd(\s|$)/i,
  /(^|\s)(zpool|zfs|btrfs|lvremove|vgremove|pvremove|mdadm|cryptsetup|dmsetup)(\s|$)/i,
  /(^|\s)rm\s+-rf(\s|$)/i,
  /(^|\s)rm\s+-f(\s|$)/i,
  /(^|\s)rmdir\s+-p(\s|$)/i,
  /if=\/dev\/(zero|random)\b/i,
  /of=\/dev\/[a-z0-9/_-]+\b/i,
  /\bdd\s+[^#\n]*\bof=\/dev\//i,
  /\b(cat|echo)\s+\/dev\/null\s*>\s*/i,
  /\brsync\b[^#\n]*\s--delete(\s|$)/i,
  /\bfind\b[^#\n]*\s-delete(\s|$)/i,
  /\|\s*xargs\s+rm(\s|$)/i,
  /\bxargs\s+rm\b/i,
  />\s*\/dev\/(sd|vd|nvme|mmcblk|mapper)[a-z0-9/_-]*/i,
  /(^|\s)rm\s+-rf\s+\//i,
  /(^|\s)rm\s+-rf\s+\/*\*/i,
  /(^|\s)rm\s+-rf\s+--no-preserve-root/i,
  /(:\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;)/,
  /(^|\s)chmod\s+777\s+\//i,
  /(^|\s)chown\s+.+\s+\//i,
  /(^|\s)kill\s+-9\s+1(\s|$)/i,
];

const sessionsById = new Map();
const sessionIdByClientKey = new Map();

function sendResponse(ctx, type, payload) {
  const { expressWorker } = ctx || {};
  if (!expressWorker || typeof expressWorker.send !== 'function') return;
  try {
    expressWorker.send({ type, data: payload });
  } catch (_) {}
}

function sendToWorker(worker, type, payload) {
  if (!worker || typeof worker.send !== 'function') return false;
  try {
    worker.send({ type, data: payload });
    return true;
  } catch (_) {
    return false;
  }
}

function sanitizeString(value) {
  return value == null ? '' : String(value).trim();
}

function sanitizeUserId(value) {
  return sanitizeString(value);
}

function toPositiveInt(value, fallback) {
  const n = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function getDefaultShell(shellQuery) {
  if (os.platform() === 'win32') {
    const key = sanitizeString(shellQuery).toLowerCase();
    if (key && WINDOWS_SHELLS[key]) return WINDOWS_SHELLS[key];
    return process.env.TERMINAL_SHELL_WIN || 'powershell.exe';
  }
  return process.env.SHELL || 'bash';
}

const INTERACTIVE_SHELL_BASENAMES = new Set(['zsh', 'bash', 'sh']);

function shouldUseLoginShell() {
  if (os.platform() === 'win32') return false;
  const flag = sanitizeString(process.env.TERMINAL_LOGIN_SHELL).toLowerCase();
  // Opt-in: login shell reads ~/.zprofile; most macOS users keep PATH in ~/.zshrc.
  return flag === '1' || flag === 'true' || flag === 'yes';
}

function getShellSpawnConfig(shellPath) {
  const file = sanitizeString(shellPath) || getDefaultShell();
  if (os.platform() === 'win32') {
    return { file, args: [] };
  }
  const base = path.basename(file).toLowerCase();
  if (!INTERACTIVE_SHELL_BASENAMES.has(base)) {
    return { file, args: [] };
  }
  if (shouldUseLoginShell()) {
    return { file, args: ['-l'] };
  }
  // Non-login interactive shell: zsh/bash load ~/.zshrc / ~/.bashrc (macOS default).
  return { file, args: ['-i'] };
}

function buildTerminalEnv() {
  const home = process.env.HOME || os.homedir() || '';
  const env = withAugmentedPath({ ...process.env });
  if (home) env.HOME = home;
  if (!env.TERM) env.TERM = 'xterm-256color';
  return env;
}

function normalizeShellQuery(shellQuery) {
  return sanitizeString(shellQuery).toLowerCase();
}

function buildClientKey(userId) {
  const uid = sanitizeUserId(userId);
  if (!uid) return '';
  return uid;
}

function sanitizeCommandLine(line) {
  return String(line ?? '')
    .replace(/\r/g, '')
    .replace(/\n/g, '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .trim();
}

function extractCommandName(line) {
  const s = sanitizeCommandLine(line);
  if (!s) return '';
  return String(s.split(/\s+/)[0] || '').trim();
}

function isDangerous(line) {
  const s = sanitizeCommandLine(line);
  if (!s) return false;
  return DANGEROUS_PATTERNS.some(r => r.test(s));
}

function isAllowedCommand(line) {
  const cmd = extractCommandName(line);
  if (!cmd) return true;
  return !isDangerous(line);
}

function countUserSessions(userId) {
  const uid = sanitizeUserId(userId);
  if (!uid) return 0;
  let count = 0;
  for (const session of sessionsById.values()) {
    if (!session || session.userId !== uid) continue;
    if (!session.attachedWorker) continue;
    count += 1;
  }
  return count;
}

function countActiveSessions() {
  let count = 0;
  for (const session of sessionsById.values()) {
    if (!session) continue;
    if (!session.attachedWorker) continue;
    count += 1;
  }
  return count;
}

function safeWorkerPid(worker) {
  const pid = Number(worker && worker.process && worker.process.pid);
  return Number.isFinite(pid) && pid > 0 ? pid : 0;
}

class ManagedTerminalSession {
  constructor({ userId, username, clientDeviceId, terminalSlotId, shellQuery, cols, rows }) {
    this.id = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}_${Math.random().toString(16).slice(2)}`;
    this.userId = sanitizeUserId(userId);
    this.username = sanitizeString(username);
    this.clientDeviceId = sanitizeString(clientDeviceId);
    this.terminalSlotId = sanitizeString(terminalSlotId) || 'default';
    this.shellQuery = normalizeShellQuery(shellQuery);
    this.clientKey = buildClientKey(this.userId);
    this.shell = getDefaultShell(shellQuery);
    this.cols = Math.max(20, Math.min(400, toPositiveInt(cols, DEFAULT_COLS)));
    this.rows = Math.max(5, Math.min(200, toPositiveInt(rows, DEFAULT_ROWS)));
    this.createdAt = Date.now();
    this.lastActivityAt = Date.now();
    this.detachedAt = 0;
    this.currentLine = '';
    this.outputWindowStartAt = Date.now();
    this.outputWindowBytes = 0;
    this.replayChunks = [];
    this.replayBytes = 0;
    this.attachedWorker = null;
    this.attachedWorkerPid = 0;
    this.ownerConnId = '';
    this.timeoutTimer = null;
    this.term = null;
    this.disposed = false;
  }

  start() {
    const cwd = process.env.HOME || os.homedir() || '/';
    const env = buildTerminalEnv();
    const { file: shellFile, args: shellArgs } = getShellSpawnConfig(this.shell);
    this.term = pty.spawn(shellFile, shellArgs, {
      name: 'xterm-256color',
      cols: this.cols,
      rows: this.rows,
      cwd,
      env,
    });

    Logger.security('terminal.session_start', this.userId, {
      sessionId: this.id,
      username: this.username,
      shell: shellFile,
      shellArgs,
      cwd,
      cols: this.cols,
      rows: this.rows,
      clientDeviceId: this.clientDeviceId,
      terminalSlotId: this.terminalSlotId,
    });

    this.term.onData(data => {
      if (this.disposed) return;
      this.lastActivityAt = Date.now();
      const now = Date.now();
      if (now - this.outputWindowStartAt >= OUTPUT_WINDOW_MS) {
        this.outputWindowStartAt = now;
        this.outputWindowBytes = 0;
      }

      this.outputWindowBytes += Buffer.byteLength(data, 'utf8');
      if (this.outputWindowBytes > MAX_OUTPUT_BYTES_PER_WINDOW) {
        Logger.warn('Terminal output rate limit exceeded, disposing session', {
          sessionId: this.id,
          userId: this.userId,
        });
        this.sendEvent({ type: 'error', code: 'TERMINAL_OUTPUT_RATE_LIMIT' });
        this.dispose({ reason: 'output_limit' });
        return;
      }

      this.appendReplay(data);
      this.sendEvent({ type: 'output', data });
    });

    this.term.onExit(({ exitCode, signal }) => {
      Logger.info('Terminal exited', {
        sessionId: this.id,
        userId: this.userId,
        exitCode,
        signal,
      });
      this.sendEvent({ type: 'exit', exitCode, signal });
      this.dispose({ reason: 'term_exit' });
    });

    this.timeoutTimer = setInterval(() => {
      if (this.disposed) return;
      const now = Date.now();
      if (!this.attachedWorker && now - this.lastActivityAt > SESSION_IDLE_TIMEOUT_MS) {
        this.dispose({ reason: 'idle_timeout' });
      }
    }, 25 * 1000);
  }

  appendReplay(data) {
    const text = String(data ?? '');
    if (!text) return;
    const bytes = Buffer.byteLength(text, 'utf8');
    this.replayChunks.push(text);
    this.replayBytes += bytes;
    while (this.replayBytes > MAX_REPLAY_BYTES && this.replayChunks.length > 1) {
      const removed = this.replayChunks.shift();
      this.replayBytes -= Buffer.byteLength(String(removed || ''), 'utf8');
    }
  }

  getReplayText() {
    return this.replayChunks.join('');
  }

  attach(ctx, { cols, rows, terminalConnId }) {
    const nextWorker = ctx && ctx.expressWorker ? ctx.expressWorker : null;
    const nextWorkerPid = safeWorkerPid(nextWorker);
    const prevWorker = this.attachedWorker;
    const prevWorkerPid = this.attachedWorkerPid;
    const nextConnId = sanitizeString(terminalConnId);
    const prevConnId = this.ownerConnId;

    this.attachedWorker = nextWorker;
    this.attachedWorkerPid = nextWorkerPid;
    this.ownerConnId = nextConnId;
    this.detachedAt = 0;
    this.lastActivityAt = Date.now();
    this.resize(cols, rows);

    if (prevWorker && prevWorker !== nextWorker) {
      sendToWorker(prevWorker, 'terminalSessionEvent', {
        sessionId: this.id,
        event: { type: 'disconnect', reason: prevConnId && nextConnId && prevConnId !== nextConnId ? 'taken_over' : 'reattached' },
      });
    } else if (prevWorkerPid > 0 && prevWorkerPid !== nextWorkerPid) {
      this.attachedWorkerPid = nextWorkerPid;
    }
  }

  detach({ workerPid } = {}) {
    const pid = Number(workerPid);
    if (Number.isFinite(pid) && pid > 0 && this.attachedWorkerPid > 0 && this.attachedWorkerPid !== pid) {
      return;
    }
    this.attachedWorker = null;
    this.attachedWorkerPid = 0;
    this.detachedAt = Date.now();
  }

  sendEvent(event) {
    if (!this.attachedWorker) return;
    const ok = sendToWorker(this.attachedWorker, 'terminalSessionEvent', {
      sessionId: this.id,
      event,
    });
    if (!ok) this.detach();
  }

  resize(cols, rows) {
    const c = Math.max(20, Math.min(400, toPositiveInt(cols, this.cols)));
    const r = Math.max(5, Math.min(200, toPositiveInt(rows, this.rows)));
    this.cols = c;
    this.rows = r;
    try {
      if (this.term) this.term.resize(c, r);
    } catch (_) {}
  }

  handleInput(data) {
    if (!this.term || this.disposed) return;
    this.lastActivityAt = Date.now();

    const str = typeof data === 'string' ? data : String(data ?? '');
    const pieces = str.split('');
    for (const ch of pieces) {
      if (ch === '\r' || ch === '\n') {
        const line = this.currentLine;
        this.currentLine = '';

        if (!isAllowedCommand(line)) {
          Logger.security('terminal.command_blocked', this.userId, {
            sessionId: this.id,
            username: this.username,
            command: sanitizeCommandLine(line).slice(0, 512),
          });
          this.sendEvent({ type: 'error', code: 'TERMINAL_COMMAND_BLOCKED' });
          try {
            this.term.write('\x15');
            this.term.write('\r');
          } catch (_) {}
          continue;
        }

        Logger.security('terminal.command', this.userId, {
          sessionId: this.id,
          username: this.username,
          command: sanitizeCommandLine(line).slice(0, 512),
        });
        try {
          this.term.write('\r');
        } catch (_) {}
        continue;
      }

      if (ch === '\u007f' || ch === '\b') {
        if (this.currentLine.length > 0) {
          this.currentLine = this.currentLine.substring(0, this.currentLine.length - 1);
        }
        try {
          this.term.write(ch);
        } catch (_) {}
        continue;
      }

      if (ch === '\u001b') {
        this.currentLine = '';
        try {
          this.term.write(ch);
        } catch (_) {}
        continue;
      }

      if (ch.charCodeAt(0) < 32) {
        try {
          this.term.write(ch);
        } catch (_) {}
        continue;
      }

      this.currentLine += ch;
      try {
        this.term.write(ch);
      } catch (_) {}
    }
  }

  dispose({ reason } = {}) {
    if (this.disposed) return;
    this.disposed = true;

    try {
      if (this.timeoutTimer) clearInterval(this.timeoutTimer);
    } catch (_) {}
    this.timeoutTimer = null;

    try {
      if (this.term) this.term.kill();
    } catch (_) {}
    this.term = null;

    sessionsById.delete(this.id);
    if (this.clientKey) {
      const indexed = sessionIdByClientKey.get(this.clientKey);
      if (indexed === this.id) sessionIdByClientKey.delete(this.clientKey);
    }

    Logger.security('terminal.session_end', this.userId, {
      sessionId: this.id,
      username: this.username,
      reason: sanitizeString(reason) || 'disposed',
      clientDeviceId: this.clientDeviceId,
      terminalSlotId: this.terminalSlotId,
    });
    Logger.info('Terminal session count', {
      totalSessions: countActiveSessions(),
      action: 'close',
      sessionId: this.id,
      userId: this.userId,
    });
  }
}

function getSessionByClientKey(userId) {
  const clientKey = buildClientKey(userId);
  if (!clientKey) return null;
  const sessionId = sessionIdByClientKey.get(clientKey);
  if (!sessionId) return null;
  return sessionsById.get(sessionId) || null;
}

function createSession({ userId, username, clientDeviceId, terminalSlotId, shellQuery, cols, rows }) {
  const session = new ManagedTerminalSession({
    userId,
    username,
    clientDeviceId,
    terminalSlotId,
    shellQuery,
    cols,
    rows,
  });
  sessionsById.set(session.id, session);
  if (session.clientKey) sessionIdByClientKey.set(session.clientKey, session.id);
  session.start();
  return session;
}

function handleTerminalConnectSession(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const requestId = sanitizeString(data.requestId);
  const userId = sanitizeUserId(data.userId);
  const username = sanitizeString(data.username);
  const clientDeviceId = sanitizeString(data.clientDeviceId) || `legacy_${userId || 'unknown'}`;
  const terminalSlotId = sanitizeString(data.terminalSlotId) || 'default';
  const terminalConnId = sanitizeString(data.terminalConnId);
  const shellQuery = normalizeShellQuery(data.shellQuery);
  const forceNew = data.forceNew === true || String(data.forceNew || '') === '1';
  const cols = toPositiveInt(data.cols, DEFAULT_COLS);
  const rows = toPositiveInt(data.rows, DEFAULT_ROWS);

  if (!requestId) return;
  if (!userId) {
    return sendResponse(ctx, 'terminalConnectSessionResponse', {
      requestId,
      ok: false,
      error: 'invalid_params',
    });
  }

  try {
    let session = getSessionByClientKey(userId);
    if (session && forceNew) {
      session.dispose({ reason: 'force_new' });
      session = null;
    }

    if (!session) {
      const totalSessions = countActiveSessions();
      const perUserCount = countUserSessions(userId);
      if (totalSessions >= MAX_CONCURRENT_SESSIONS || perUserCount >= MAX_SESSIONS_PER_USER) {
        Logger.security('terminal.session_limit_reached', userId, {
          username,
          totalSessions,
          perUserCount,
          limitTotal: MAX_CONCURRENT_SESSIONS,
          limitPerUser: MAX_SESSIONS_PER_USER,
          clientDeviceId,
        });
        return sendResponse(ctx, 'terminalConnectSessionResponse', {
          requestId,
          ok: false,
          error: 'session_limit_reached',
          totalSessions,
          perUserCount,
          limitTotal: MAX_CONCURRENT_SESSIONS,
          limitPerUser: MAX_SESSIONS_PER_USER,
        });
      }

      session = createSession({ userId, username, clientDeviceId, terminalSlotId, shellQuery, cols, rows });
    }

    session.attach(ctx, { cols, rows, terminalConnId });
    Logger.info('Terminal session count', {
      totalSessions: countActiveSessions(),
      action: 'connect',
      sessionId: session.id,
      userId,
      shellQuery: session.shellQuery,
    });

    return sendResponse(ctx, 'terminalConnectSessionResponse', {
      requestId,
      ok: true,
      sessionId: session.id,
      reused: session.createdAt + 2000 < Date.now(),
      cols: session.cols,
      rows: session.rows,
      restoreData: session.getReplayText(),
    });
  } catch (err) {
    Logger.error('terminal connect session failed', err);
    return sendResponse(ctx, 'terminalConnectSessionResponse', {
      requestId,
      ok: false,
      error: 'connect_failed',
    });
  }
}

function handleTerminalDetachSession(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const sessionId = sanitizeString(data.sessionId);
  if (!sessionId) return;
  const session = sessionsById.get(sessionId);
  if (!session) return;
  session.detach({ workerPid: safeWorkerPid(ctx && ctx.expressWorker) });
  Logger.info('Terminal session count', {
    totalSessions: countActiveSessions(),
    action: 'detach',
    sessionId,
    userId: session.userId,
  });
}

function handleTerminalInput(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const sessionId = sanitizeString(data.sessionId);
  const session = sessionId ? sessionsById.get(sessionId) : null;
  if (!session) return;
  session.handleInput(data.data);
}

function handleTerminalResize(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const sessionId = sanitizeString(data.sessionId);
  const session = sessionId ? sessionsById.get(sessionId) : null;
  if (!session) return;
  session.resize(data.cols, data.rows);
}

function handleTerminalTerminateSession(ctx) {
  const data = (ctx && ctx.message && ctx.message.data) || {};
  const sessionId = sanitizeString(data.sessionId);
  const session = sessionId ? sessionsById.get(sessionId) : null;
  if (!session) return;
  session.sendEvent({ type: 'exit', exitCode: null, signal: 'terminated' });
  session.dispose({ reason: 'terminated_by_client' });
}

function detachSessionsByWorkerPid(workerPid) {
  const pid = Number(workerPid);
  if (!Number.isFinite(pid) || pid <= 0) return 0;
  let affected = 0;
  for (const session of sessionsById.values()) {
    if (!session || session.attachedWorkerPid !== pid) continue;
    session.detach({ workerPid: pid });
    affected += 1;
  }
  return affected;
}

module.exports = {
  handlers: {
    terminalConnectSession: handleTerminalConnectSession,
    terminalDetachSession: handleTerminalDetachSession,
    terminalInput: handleTerminalInput,
    terminalResize: handleTerminalResize,
    terminalTerminateSession: handleTerminalTerminateSession,
  },
  detachSessionsByWorkerPid,
};
