const fs = require('fs');
const path = require('path');
const { spawn, spawnSync } = require('child_process');
const portfinder = require('portfinder');
const axios = require('axios');
const Logger = require('../../utils/logger');
const config = require('../../config/config');
const tableConfig = require('../../db/table/tableConfig');
const transmissionPath = require('../../libsPath/transmissionPath');
const {
  ensureString,
  toPortNumber,
  getConfigDir,
  loadConfig,
  saveConfig,
  ensureRpcCredentials,
  writeSettingsFile,
  decryptRpcPassword,
  isRpcReachable,
  probeTransmissionRuntime,
  ensureTrackersResolved,
} = require('./transmissionConfig');
const { prepareTransmissionDaemonAfterReady, gracefulCloseTransmissionDaemon } = require('../../api/modules/transmission/transmissionTorrentUtil');

const WORKER_NAME = 'transmission';

function isPortForbidden(port) {
  const forbidden = new Set((config && config.forbiddenPorts) || []);
  return forbidden.has(port);
}

async function getFreePort(basePort, avoidPorts = new Set()) {
  const startPort = toPortNumber(basePort);
  if (!startPort) return null;
  let cursor = startPort;
  while (cursor <= 65535) {
    if (isPortForbidden(cursor) || avoidPorts.has(cursor)) {
      cursor += 1;
      continue;
    }
    try {
      const port = await portfinder.getPortPromise({ port: cursor, stopPort: 65535 });
      if (!port) return null;
      if (isPortForbidden(port) || avoidPorts.has(port)) {
        cursor = port + 1;
        continue;
      }
      return port;
    } catch (_) {
      return null;
    }
  }
  return null;
}

async function waitForRpcReady({ port, username, password, timeoutMs = 15000 }) {
  const deadline = Date.now() + Math.max(1000, Number(timeoutMs) || 15000);
  const url = `http://127.0.0.1:${port}/transmission/rpc`;
  while (Date.now() < deadline) {
    try {
      const res = await axios.post(
        url,
        { method: 'session-get', arguments: {} },
        {
          auth: { username, password },
          timeout: 3000,
          validateStatus: () => true,
        }
      );
      if (res.status === 200 || res.status === 409) return true;
    } catch (_) {}
    await new Promise(r => setTimeout(r, 300));
  }
  return false;
}

function awaitChildExit(child, timeoutMs = 8000) {
  return new Promise(resolve => {
    if (!child) return resolve(true);
    let done = false;
    const timer = setTimeout(() => {
      if (done) return;
      done = true;
      try {
        child.kill('SIGKILL');
      } catch (_) {}
      resolve(false);
    }, Math.max(500, Number(timeoutMs) || 8000));
    child.once('exit', () => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(true);
    });
  });
}

function parsePidList(text) {
  return [...new Set(
    ensureString(text)
      .split(/[\s,]+/)
      .map(v => Number(v.trim()))
      .filter(v => Number.isFinite(v) && v > 0 && v !== process.pid)
  )];
}

function findPidsOnPort(port) {
  const p = toPortNumber(port);
  if (!p) return [];
  try {
    if (process.platform === 'win32') {
      const r = spawnSync('cmd', ['/c', `netstat -ano | findstr :${p}`], {
        windowsHide: true,
        encoding: 'utf8',
      });
      const pids = new Set();
      for (const line of ensureString(r.stdout).split('\n')) {
        const parts = line.trim().split(/\s+/);
        const pid = Number(parts[parts.length - 1]);
        if (Number.isFinite(pid) && pid > 0) pids.add(pid);
      }
      return Array.from(pids).filter(pid => pid !== process.pid);
    }

    const lsof = spawnSync('lsof', ['-ti', `tcp:${p}`], { encoding: 'utf8' });
    const fromLsof = parsePidList(lsof.stdout);
    if (fromLsof.length) return fromLsof;

    const fuser = spawnSync('fuser', [`${p}/tcp`], { encoding: 'utf8' });
    const fromFuser = parsePidList(`${fuser.stdout}\n${fuser.stderr}`);
    if (fromFuser.length) return fromFuser;

    const ss = spawnSync('ss', ['-ltnp'], { encoding: 'utf8' });
    const pids = new Set();
    for (const line of ensureString(ss.stdout).split('\n')) {
      if (!line.includes(`:${p}`)) continue;
      const match = line.match(/pid=(\d+)/);
      if (match) {
        const pid = Number(match[1]);
        if (Number.isFinite(pid) && pid > 0 && pid !== process.pid) pids.add(pid);
      }
    }
    return Array.from(pids);
  } catch (_) {
    return [];
  }
}

async function killProcessesOnPort(port, { waitMs = 1500 } = {}) {
  const pids = findPidsOnPort(port);
  if (!pids.length) return;
  for (const pid of pids) {
    try {
      process.kill(pid, 'SIGTERM');
    } catch (_) {}
  }
  await new Promise(r => setTimeout(r, Math.max(200, Number(waitMs) || 1500)));
  for (const pid of findPidsOnPort(port)) {
    try {
      process.kill(pid, 'SIGKILL');
    } catch (_) {}
  }
}

function killTransmissionByConfigDir(configDir, { waitMs = 0 } = {}) {
  const dir = ensureString(configDir).trim();
  if (!dir) return [];
  const killed = [];
  try {
    if (process.platform === 'win32') {
      const r = spawnSync(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          `Get-CimInstance Win32_Process -Filter "Name='transmission-daemon.exe'" | Where-Object { $_.CommandLine -like '*${dir.replace(/'/g, "''")}*' } | ForEach-Object { $_.ProcessId }`,
        ],
        { windowsHide: true, encoding: 'utf8' }
      );
      const pids = ensureString(r.stdout)
        .split('\n')
        .map(v => Number(v.trim()))
        .filter(v => Number.isFinite(v) && v > 0 && v !== process.pid);
      for (const pid of pids) {
        try {
          process.kill(pid, 'SIGTERM');
          killed.push(pid);
        } catch (_) {}
      }
      return killed;
    }
    const r = spawnSync('pgrep', ['-f', dir], { encoding: 'utf8' });
    const pids = ensureString(r.stdout)
      .split('\n')
      .map(v => Number(v.trim()))
      .filter(v => Number.isFinite(v) && v > 0 && v !== process.pid);
    for (const pid of pids) {
      try {
        process.kill(pid, 'SIGTERM');
        killed.push(pid);
      } catch (_) {}
    }
    return killed;
  } catch (_) {
    return killed;
  }
}

function findTransmissionDaemonPids(configDir) {
  const dir = ensureString(configDir).trim();
  if (!dir) return [];
  try {
    const r = spawnSync('pgrep', ['-f', dir], { encoding: 'utf8' });
    return ensureString(r.stdout)
      .split('\n')
      .map(v => Number(v.trim()))
      .filter(v => Number.isFinite(v) && v > 0 && v !== process.pid);
  } catch (_) {
    return [];
  }
}

async function forceStopTransmissionProcesses(cfg, { child, actualRpcPort, adoptedPid, graceful = false } = {}) {
  const configObj = cfg || (await loadConfig().catch(() => null));
  const peerPort = configObj && toPortNumber(configObj.peer_port);
  const configDir = getConfigDir();
  const gracefulWaitMs = graceful ? 20000 : 5000;
  const portsToKill = new Set();
  const primary = toPortNumber(actualRpcPort);
  if (primary) portsToKill.add(primary);
  if (configObj) {
    const configured = toPortNumber(configObj.rpc_port);
    const stale = toPortNumber(configObj.actual_rpc_port);
    if (configured) portsToKill.add(configured);
    if (stale) portsToKill.add(stale);
  }

  if (graceful) {
    await gracefulCloseTransmissionDaemon(configObj, { timeoutMs: gracefulWaitMs }).catch(() => false);
  }

  if (child && child.exitCode === null && !child.killed) {
    try {
      child.kill('SIGTERM');
    } catch (_) {}
    await awaitChildExit(child, gracefulWaitMs);
  }

  if (adoptedPid && adoptedPid !== process.pid) {
    try {
      process.kill(adoptedPid, 'SIGTERM');
    } catch (_) {}
    await new Promise(r => setTimeout(r, graceful ? 3000 : 500));
    try {
      process.kill(adoptedPid, 0);
      process.kill(adoptedPid, 'SIGKILL');
    } catch (_) {}
  }

  const portWaitMs = graceful ? 4000 : 1500;
  for (const port of portsToKill) {
    if (port) await killProcessesOnPort(port, { waitMs: portWaitMs });
  }
  if (peerPort && !portsToKill.has(peerPort)) await killProcessesOnPort(peerPort, { waitMs: portWaitMs });

  killTransmissionByConfigDir(configDir);
  if (graceful) {
    await new Promise(r => setTimeout(r, 3000));
  }
  const remaining = findTransmissionDaemonPids(configDir);
  for (const pid of remaining) {
    try {
      process.kill(pid, 'SIGKILL');
    } catch (_) {}
  }
}

function killProcessesOnPortSync(port) {
  const pids = findPidsOnPort(port);
  for (const pid of pids) {
    try {
      process.kill(pid, process.platform === 'win32' ? undefined : 'SIGKILL');
    } catch (_) {}
  }
}

class TransmissionWorker {
  constructor() {
    this.daemonChild = null;
    this.adoptedPid = null;
    this.stopping = false;
    this.startedAt = null;
    this.actualRpcPort = null;
    this.lastError = null;
    this._startPromise = null;
  }

  getStatus() {
    const childAlive = !!(this.daemonChild && this.daemonChild.exitCode === null && !this.daemonChild.killed);
    const adoptedAlive =
      this.adoptedPid &&
      (() => {
        try {
          process.kill(this.adoptedPid, 0);
          return true;
        } catch (_) {
          return false;
        }
      })();
    const processRunning = childAlive || adoptedAlive;
    return {
      running: processRunning,
      pid: childAlive ? this.daemonChild.pid : adoptedAlive ? this.adoptedPid : null,
      actual_rpc_port: this.actualRpcPort,
      started_at: this.startedAt,
      last_error: this.lastError,
    };
  }

  async _resolveRpcPort(requestedPort) {
    const avoid = new Set();
    const apiHttp = toPortNumber(await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP, 0));
    const apiHttps = toPortNumber(await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS, 0));
    const defaultHttp = toPortNumber(config && config.app && config.app.port);
    const defaultHttps = toPortNumber(config && config.app && config.app.httpsPort);
    for (const p of [apiHttp, apiHttps, defaultHttp, defaultHttps]) {
      if (p) avoid.add(p);
    }
    return getFreePort(requestedPort, avoid);
  }

  async start({ requestId } = {}) {
    if (this._startPromise) return this._startPromise;
    this._startPromise = this._startInternal({ requestId }).finally(() => {
      this._startPromise = null;
    });
    return this._startPromise;
  }

  async _adoptExistingDaemon(cfg, requestId) {
    if (!cfg || !cfg.enabled) return null;
    const port = toPortNumber(cfg.rpc_port);
    if (!port || !(await isRpcReachable(cfg, port))) return null;
    const portPids = findPidsOnPort(port);
    this.adoptedPid = portPids.length ? portPids[0] : null;
    this.actualRpcPort = port;
    this.startedAt = cfg.started_at || new Date().toISOString();
    this.lastError = null;
    await saveConfig({
      status: 'running',
      enabled: true,
      actual_rpc_port: port,
      last_error: null,
      started_at: this.startedAt,
    });
    try {
      await prepareTransmissionDaemonAfterReady(cfg, { verifyTimeoutMs: 180000 });
    } catch (err) {
      Logger.warn('[transmissionWorker] post-start daemon prepare failed', err);
    }
    const status = {
      running: true,
      pid: this.daemonChild && !this.daemonChild.killed ? this.daemonChild.pid : this.adoptedPid,
      actual_rpc_port: port,
      started_at: this.startedAt,
      last_error: null,
      adopted: true,
    };
    this._sendStartResponse(requestId, { ok: true, running: true, ...status });
    return status;
  }

  async _startInternal({ requestId } = {}) {
    if (this.daemonChild && !this.daemonChild.killed) {
      const status = this.getStatus();
      this._sendStartResponse(requestId, { ok: true, running: true, ...status });
      return status;
    }

    this.stopping = false;
    this.lastError = null;

    let cfg = ensureRpcCredentials(await loadConfig());
    cfg = await ensureTrackersResolved(cfg);
    const configuredPort = toPortNumber(cfg.rpc_port);
    const stalePort = toPortNumber(cfg.actual_rpc_port);
    if (
      configuredPort &&
      stalePort &&
      stalePort !== configuredPort &&
      !(await isRpcReachable(cfg, configuredPort)) &&
      (await isRpcReachable(cfg, stalePort))
    ) {
      Logger.info('[transmissionWorker] stopping daemon on stale RPC port', stalePort);
      await forceStopTransmissionProcesses(cfg, { actualRpcPort: stalePort, graceful: true });
      cfg = await saveConfig({ actual_rpc_port: null, status: 'stopped' });
    }

    const adopted = await this._adoptExistingDaemon(cfg, requestId);
    if (adopted) return adopted;

    const resolvedPort = await this._resolveRpcPort(cfg.rpc_port);
    if (!resolvedPort) {
      this.lastError = 'no_free_port';
      await saveConfig({ status: 'error', last_error: this.lastError, enabled: false });
      this._sendStartResponse(requestId, { ok: false, error: 'no_free_port' });
      return { running: false, error: 'no_free_port' };
    }

    cfg = await saveConfig({
      ...cfg,
      actual_rpc_port: resolvedPort,
      status: 'starting',
      last_error: null,
    });

    try {
      await writeSettingsFile(cfg, resolvedPort);
    } catch (err) {
      this.lastError = 'settings_write_failed';
      await saveConfig({ status: 'error', last_error: this.lastError, enabled: false });
      this._sendStartResponse(requestId, { ok: false, error: this.lastError });
      return { running: false, error: this.lastError };
    }

    const configDir = getConfigDir();
    const binaryPath = transmissionPath.path;
    const cwd = transmissionPath.binaryDir && transmissionPath.binaryDir !== '.' ? transmissionPath.binaryDir : configDir;
    const args = ['-f', '--config-dir', configDir, '--port', String(resolvedPort), '--log-level', 'info'];

    if (await isRpcReachable(cfg, resolvedPort)) {
      await writeSettingsFile(cfg, resolvedPort).catch(() => {});
      return this._adoptExistingDaemon({ ...cfg, actual_rpc_port: resolvedPort }, requestId);
    }

    const child = spawn(binaryPath, args, {
      cwd,
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
      env: { ...process.env },
    });
    this.daemonChild = child;
    this.adoptedPid = null;
    this.actualRpcPort = resolvedPort;

    const startupLog = [];
    const appendLog = text => {
      const t = ensureString(text);
      if (!t) return;
      startupLog.push(t);
      if (startupLog.join('').length > 8000) startupLog.shift();
    };

    child.stdout?.on('data', chunk => {
      const text = ensureString(chunk).trim();
      if (text) Logger.info('[transmission]', text);
      appendLog(text);
    });
    child.stderr?.on('data', chunk => {
      const text = ensureString(chunk).trim();
      if (text) Logger.warn('[transmission]', text);
      appendLog(text);
    });

    child.on('exit', (code, signal) => {
      if (this.stopping) return;
      this.lastError = `daemon_exited_${code != null ? code : signal || 'unknown'}`;
      this.daemonChild = null;
      this.actualRpcPort = null;
      this.startedAt = null;
      saveConfig({ status: 'error', enabled: false, last_error: this.lastError }).catch(() => {});
      Logger.warn('[transmissionWorker] daemon exited unexpectedly', { code, signal });
    });

    const rpcPassword = decryptRpcPassword(cfg.rpc_password);
    const ready = await waitForRpcReady({
      port: resolvedPort,
      username: cfg.rpc_username,
      password: rpcPassword,
    });

    if (!ready || this.stopping) {
      this.lastError = 'rpc_start_timeout';
      try {
        child.kill('SIGTERM');
      } catch (_) {}
      await awaitChildExit(child, 5000);
      this.daemonChild = null;
      await saveConfig({ status: 'error', enabled: false, last_error: this.lastError });
      this._sendStartResponse(requestId, { ok: false, error: this.lastError, log: startupLog.join('\n').slice(-2000) });
      return { running: false, error: this.lastError };
    }

    this.startedAt = new Date().toISOString();
    await saveConfig({
      status: 'running',
      enabled: true,
      actual_rpc_port: resolvedPort,
      last_error: null,
      started_at: this.startedAt,
    });

    try {
      cfg = await ensureTrackersResolved(await loadConfig());
      await prepareTransmissionDaemonAfterReady(cfg, { verifyTimeoutMs: 180000 });
    } catch (err) {
      Logger.warn('[transmissionWorker] post-start daemon prepare failed', err);
    }

    const status = this.getStatus();
    this._sendStartResponse(requestId, { ok: true, running: true, ...status });
    return status;
  }

  _sendStartResponse(requestId, payload) {
    if (!requestId) return;
    process.send?.({
      type: 'transmissionStartResponse',
      data: { requestId, ...payload },
    });
  }

  async stop({ requestId } = {}) {
    this.stopping = true;
    const child = this.daemonChild;
    const adoptedPid = this.adoptedPid;
    const rpcPort = this.actualRpcPort;
    const cfg = await loadConfig().catch(() => null);

    await forceStopTransmissionProcesses(cfg, { child, actualRpcPort: rpcPort, adoptedPid, graceful: true });

    this.daemonChild = null;
    this.adoptedPid = null;
    this.actualRpcPort = null;
    this.startedAt = null;
    this.stopping = false;
    await saveConfig({ status: 'stopped', enabled: false, last_error: null, started_at: null, actual_rpc_port: null });
    const latestCfg = await loadConfig().catch(() => cfg);
    if (latestCfg && (await isRpcReachable(latestCfg))) {
      await forceStopTransmissionProcesses(latestCfg, { graceful: false });
    }
    const payload = { ok: true, stopped: true };
    if (requestId) {
      process.send?.({
        type: 'transmissionStopResponse',
        data: { requestId, ...payload },
      });
    }
    return payload;
  }

  async restart({ requestId } = {}) {
    await this.stop({});
    return this.start({ requestId });
  }

  sendStatusResponse(requestId) {
    if (!requestId) return;
    Promise.resolve()
      .then(async () => {
        const cfg = await loadConfig().catch(() => null);
        const probe = await probeTransmissionRuntime(cfg);
        if (!probe.running) {
          if (this.daemonChild && this.daemonChild.exitCode !== null) {
            this.daemonChild = null;
          }
          if (this.adoptedPid) {
            try {
              process.kill(this.adoptedPid, 0);
            } catch (_) {
              this.adoptedPid = null;
            }
          }
          if (!this.daemonChild && !this.adoptedPid) {
            this.actualRpcPort = null;
            this.startedAt = null;
          }
          const stopped = this.getStatus();
          process.send?.({
            type: 'transmissionStatusResponse',
            data: { requestId, ...stopped, running: false, pid: null },
          });
          return;
        }

        const port = probe.actual_rpc_port;
        let pid = null;
        if (this.daemonChild && this.daemonChild.exitCode === null) {
          pid = this.daemonChild.pid;
        } else if (this.adoptedPid) {
          pid = this.adoptedPid;
        } else if (port) {
          const pids = findPidsOnPort(port);
          pid = pids.length ? pids[0] : null;
        }

        process.send?.({
          type: 'transmissionStatusResponse',
          data: {
            requestId,
            running: true,
            pid,
            actual_rpc_port: port,
            started_at: this.startedAt || (cfg && cfg.started_at) || null,
            last_error: null,
          },
        });
      })
      .catch(() => {
        process.send?.({
          type: 'transmissionStatusResponse',
          data: { requestId, running: false, pid: null, last_error: 'status_probe_failed' },
        });
      });
  }
}

let worker = null;
let messageQueue = Promise.resolve();
let shuttingDown = false;

async function gracefulWorkerShutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  try {
    Logger.info(`[transmissionWorker] shutting down (${signal || 'unknown'})`);
    if (!worker) worker = new TransmissionWorker();
    await worker.stop({});
  } catch (err) {
    Logger.warn('[transmissionWorker] shutdown cleanup failed', err);
    try {
      const cfg = await loadConfig().catch(() => null);
      await forceStopTransmissionProcesses(cfg, { graceful: true });
    } catch (_) {}
  }
  process.exit(0);
}

function enqueueWorkerTask(task) {
  messageQueue = messageQueue
    .then(task)
    .catch(err => {
      Logger.error('[transmissionWorker] message task failed', err);
    });
  return messageQueue;
}

process.on('message', msg => {
  if (!msg || typeof msg !== 'object') return;
  if (msg.type === 'stop' && !msg.data) {
    enqueueWorkerTask(async () => {
      await gracefulWorkerShutdown('parent_stop');
    });
    return;
  }
  enqueueWorkerTask(async () => {
    try {
      if (msg.type === 'start') {
        if (!worker) worker = new TransmissionWorker();
        await worker.start({ requestId: msg.data && msg.data.requestId });
      } else if (msg.type === 'stop') {
        if (!worker) worker = new TransmissionWorker();
        await worker.stop({ requestId: msg.data && msg.data.requestId });
      } else if (msg.type === 'restart') {
        if (!worker) worker = new TransmissionWorker();
        await worker.restart({ requestId: msg.data && msg.data.requestId });
      } else if (msg.type === 'status') {
        if (!worker) worker = new TransmissionWorker();
        worker.sendStatusResponse(msg.data && msg.data.requestId);
      }
    } catch (err) {
      Logger.error('[transmissionWorker] message handler error', err);
      const requestId = msg.data && msg.data.requestId;
      if (msg.type === 'start' && requestId) {
        process.send?.({
          type: 'transmissionStartResponse',
          data: { requestId, ok: false, error: err && err.message ? String(err.message) : 'start_failed' },
        });
      } else if (msg.type === 'stop' && requestId) {
        process.send?.({
          type: 'transmissionStopResponse',
          data: { requestId, ok: false, stopped: false, error: err && err.message ? String(err.message) : 'stop_failed' },
        });
      } else if (msg.type === 'status' && requestId) {
        process.send?.({
          type: 'transmissionStatusResponse',
          data: { requestId, running: false, error: err && err.message ? String(err.message) : 'status_failed' },
        });
      }
    }
  });
});

process.on('SIGTERM', () => {
  gracefulWorkerShutdown('SIGTERM').catch(() => process.exit(0));
});
process.on('SIGINT', () => {
  gracefulWorkerShutdown('SIGINT').catch(() => process.exit(0));
});
process.on('disconnect', () => {
  gracefulWorkerShutdown('disconnect').catch(() => process.exit(0));
});

if (require.main === module) {
  worker = new TransmissionWorker();
}

module.exports = {
  TransmissionWorker,
  WORKER_NAME,
  forceStopTransmissionProcesses,
  findPidsOnPort,
  killProcessesOnPortSync,
};
