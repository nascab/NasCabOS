const fs = require('fs');
const config = require('../../../config/config');
const tableConfig = require('../../../db/table/tableConfig');
const jwtUtil = require('../../../utils/jwtUtil');
const {
  loadConfig,
  saveConfig,
  normalizeConfig,
  ensureRpcCredentials,
  encryptRpcPassword,
  sanitizeConfigForClient,
  toPortNumber,
  isRpcReachable,
  buildSessionSetArgs,
  writeSettingsFile,
  ensureTrackersResolved,
} = require('../../../workers/transmission/transmissionConfig');

function buildPortValidationError({ code, msgKey, args, details, statusCode = 400 }) {
  const err = new Error(msgKey || 'common.ERROR');
  err.statusCode = statusCode;
  err.code = code;
  err.msgKey = msgKey;
  err.msgArgs = args;
  err.details = details;
  return err;
}

class TransmissionService {
  async getConfig() {
    const cfg = await loadConfig();
    return sanitizeConfigForClient(cfg);
  }

  async saveConfig(partial) {
    const current = await loadConfig();
    const merged = normalizeConfig({ ...current, ...(partial || {}) });
    if (partial && partial.rpc_password && partial.rpc_password !== '******') {
      merged.rpc_password = encryptRpcPassword(partial.rpc_password);
    } else {
      merged.rpc_password = current.rpc_password;
    }
    const withCreds = ensureRpcCredentials(merged);
    if (withCreds.rpc_password && !jwtUtil.isEncryptedPassword(withCreds.rpc_password)) {
      withCreds.rpc_password = encryptRpcPassword(withCreds.rpc_password);
    }
    const rpcChanged =
      partial && partial.rpc_port !== undefined && toPortNumber(partial.rpc_port) !== current.rpc_port;
    const peerChanged =
      partial && partial.peer_port !== undefined && toPortNumber(partial.peer_port) !== current.peer_port;
    if (rpcChanged || peerChanged) {
      withCreds.actual_rpc_port = null;
    }
    let saved = await saveConfig(withCreds);
    if (partial && partial.default_trackers !== undefined) {
      saved = await ensureTrackersResolved(saved, { force: true });
    }
    if (rpcChanged || peerChanged) {
      await writeSettingsFile(saved, saved.rpc_port).catch(() => {});
    }
    return sanitizeConfigForClient(saved);
  }

  async applyRuntimeSettings(rpc, partial) {
    if (!rpc || typeof rpc.call !== 'function') return null;
    const cfg = await loadConfig();
    const reachable = await isRpcReachable(cfg);
    if (!reachable) return null;
    const keys = [
      'peer_limit_global',
      'peer_limit_per_torrent',
      'default_trackers',
      'tracker_url_fetch_timeout_ms',
      'speed_limit_down',
      'speed_limit_up',
      'dht_enabled',
      'pex_enabled',
      'utp_enabled',
      'port_forwarding',
    ];
    const touched = keys.some(k => partial && Object.prototype.hasOwnProperty.call(partial, k));
    if (!touched) return null;
    return rpc.call('session-set', buildSessionSetArgs(cfg));
  }

  async setRpcPort(rpcPort) {
    const port = toPortNumber(rpcPort);
    const suggestedRange = { min: 1024, max: 65535 };
    if (!port) {
      throw buildPortValidationError({
        code: 'PORT_INVALID',
        msgKey: 'transmission.PORT_INVALID',
        args: [String(rpcPort)],
        details: { field: 'rpc_port', value: rpcPort, suggestedRange },
      });
    }

    const forbiddenList = Array.isArray(config && config.forbiddenPorts) ? config.forbiddenPorts : [];
    const forbiddenPorts = new Set(forbiddenList.map(p => toPortNumber(p)).filter(Boolean));
    if (forbiddenPorts.has(port)) {
      throw buildPortValidationError({
        code: 'PORT_DISABLED',
        msgKey: 'transmission.PORT_DISABLED',
        args: [String(port)],
        details: { port, forbiddenPorts: Array.from(forbiddenPorts), suggestedRange },
      });
    }

    const rawApiHttpPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP, 0);
    const rawApiHttpsPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS, 0);
    const apiHttpPort = toPortNumber(rawApiHttpPort) || toPortNumber(config && config.app && config.app.port);
    const apiHttpsPort = toPortNumber(rawApiHttpsPort) || toPortNumber(config && config.app && config.app.httpsPort);
    const reservedApiPorts = new Set([apiHttpPort, apiHttpsPort].filter(Boolean));
    if (reservedApiPorts.has(port)) {
      throw buildPortValidationError({
        code: 'PORT_RESERVED',
        msgKey: 'transmission.PORT_RESERVED',
        args: [String(port)],
        details: { port, reservedPorts: Array.from(reservedApiPorts), suggestedRange },
      });
    }

    const current = await loadConfig();
    const saved = await saveConfig({ ...current, rpc_port: port, actual_rpc_port: null });
    await writeSettingsFile(saved, saved.rpc_port).catch(() => {});
    return sanitizeConfigForClient(saved);
  }

  async assertDaemonRunning() {
    const cfg = await loadConfig();
    const rpcUp = await isRpcReachable(cfg);
    if (rpcUp) return cfg;
    const err = new Error('transmission.SERVICE_UNAVAILABLE');
    err.statusCode = 503;
    throw err;
  }

  async readTorrentFileBase64(filePath) {
    const buf = await fs.promises.readFile(filePath);
    return buf.toString('base64');
  }
}

module.exports = { TransmissionService };
