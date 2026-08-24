const tableConfig = require('../../../db/table/tableConfig');
const config = require('../../../config/config');

function buildFileServerConfigKey({ serverType, uid }) {
  return `fileServer:${serverType}:${uid}`;
}

function buildFileServerPortsKey({ serverType }) {
  return `fileServerPorts:${String(serverType)}`;
}

const SUPPORTED_SERVER_TYPES = ['WebDav', 'FTP', 'SFTP'];

function toPortNumber(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  if (i < 1 || i > 65535) return null;
  return i;
}

function buildBadRequestError(msgKey = 'validation.VALIDATION_ERROR') {
  const err = new Error(String(msgKey));
  err.statusCode = 400;
  return err;
}

// 端口设置的结构化校验错误（用于前端展示更友好的提示）
function buildPortValidationError({ code, msgKey, args, details }) {
  const err = new Error(String(msgKey || 'validation.VALIDATION_ERROR'));
  err.statusCode = 400;
  if (code) err.code = String(code);
  if (Array.isArray(args)) err.args = args;
  if (details && typeof details === 'object') err.details = details;
  return err;
}

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

class FileServerService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'file_server';
  }

  async list({ uid, serverType, status } = {}) {
    let q = this.knexMain(this.tableName).select('*');
    if (uid) q = q.where({ uid: String(uid) });
    if (serverType) q = q.where({ server_type: String(serverType) });
    if (status) q = q.where({ status: String(status) });
    return await q.orderBy('id', 'desc');
  }

  async getOne({ uid, serverType }) {
    return await this.knexMain(this.tableName)
      .where({ uid: String(uid), server_type: String(serverType) })
      .first();
  }

  async upsert({ uid, serverType, rootPath, httpPort, httpsPort, config }) {
    const now = new Date();
    const uidStr = String(uid);
    const serverTypeStr = String(serverType);
    const storedRootPath = Array.isArray(rootPath) ? JSON.stringify(rootPath) : String(rootPath);
    const row = {
      uid: uidStr,
      server_type: serverTypeStr,
      root_path: storedRootPath,
      http_port: httpPort === undefined ? null : Number(httpPort),
      https_port: httpsPort === undefined ? null : Number(httpsPort),
      config: config ? JSON.stringify(config) : null,
      update_time: now,
    };

    const exists = await this.getOne({ uid: uidStr, serverType: serverTypeStr });
    if (exists) {
      await this.knexMain(this.tableName).where({ id: exists.id }).update(row);
      return await this.knexMain(this.tableName).where({ id: exists.id }).first();
    }

    await this.knexMain(this.tableName).insert({ ...row, create_time: now, status: 'stopped' });
    return await this.getOne({ uid: uidStr, serverType: serverTypeStr });
  }

  async setStatus({ uid, serverType, status, lastError = null }) {
    const now = new Date();
    const existing = await this.getOne({ uid, serverType });
    if (!existing) return null;
    await this.knexMain(this.tableName)
      .where({ id: existing.id })
      .update({ status: String(status), last_error: lastError ? String(lastError) : null, update_time: now });
    return await this.knexMain(this.tableName).where({ id: existing.id }).first();
  }

  async delete({ uid, serverType }) {
    const existing = await this.getOne({ uid, serverType });
    if (!existing) return false;
    await this.knexMain(this.tableName).where({ id: existing.id }).delete();
    await this.deleteConfig({ uid, serverType });
    return true;
  }

  async setConfig({ uid, serverType, config }) {
    const key = buildFileServerConfigKey({ uid: String(uid), serverType: String(serverType) });
    const value = config ? JSON.stringify(config) : '';
    return await tableConfig.setConfigByKey(key, value, Number(uid) || 0);
  }

  async getConfig({ uid, serverType }) {
    const key = buildFileServerConfigKey({ uid: String(uid), serverType: String(serverType) });
    const raw = await tableConfig.getConfigByKey(key, Number(uid) || 0);
    if (!raw) return null;
    try {
      return JSON.parse(raw);
    } catch (_) {
      return null;
    }
  }

  async deleteConfig({ uid, serverType }) {
    const key = buildFileServerConfigKey({ uid: String(uid), serverType: String(serverType) });
    try {
      await this.knexMain('config')
        .where({ uid: Number(uid) || 0, key })
        .delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  async getGlobalPorts({ serverType }) {
    const serverTypeStr = String(serverType);
    const key = buildFileServerPortsKey({ serverType: serverTypeStr });
    const raw = await tableConfig.getConfigByKey(key, 0);
    const parsed = safeJsonParse(raw);

    const defaults = config && config.fileServer && config.fileServer.defaultPorts ? config.fileServer.defaultPorts : {};
    const defaultForType = defaults && typeof defaults === 'object' ? defaults[serverTypeStr] : null;
    const defaultHttp = toPortNumber(defaultForType && defaultForType.http_port);
    const defaultHttps = toPortNumber(defaultForType && defaultForType.https_port);

    const httpPort = toPortNumber(parsed && parsed.http_port);
    const httpsPort = toPortNumber(parsed && parsed.https_port);

    return {
      server_type: serverTypeStr,
      http_port: httpPort || defaultHttp,
      https_port: httpsPort || defaultHttps,
    };
  }

  async setGlobalPorts({ serverType, httpPort, httpsPort }) {
    const serverTypeStr = String(serverType);
    if (!SUPPORTED_SERVER_TYPES.includes(serverTypeStr)) throw buildBadRequestError();
    const key = buildFileServerPortsKey({ serverType: serverTypeStr });

    const currentRaw = await tableConfig.getConfigByKey(key, 0);
    const currentParsed = safeJsonParse(currentRaw) || {};

    const nextHttpPortNum = httpPort === undefined ? toPortNumber(currentParsed.http_port) : toPortNumber(httpPort);
    const nextHttpsPortNum = httpsPort === undefined ? toPortNumber(currentParsed.https_port) : toPortNumber(httpsPort);

    const suggestedRange = { min: 1024, max: 65535 };
    if (httpPort !== undefined && httpPort !== null && httpPort !== '' && nextHttpPortNum === null) {
      throw buildPortValidationError({
        code: 'PORT_INVALID',
        msgKey: 'fileServer.PORT_INVALID',
        args: ['http', String(httpPort)],
        details: { field: 'http_port', value: httpPort, suggestedRange },
      });
    }
    if (httpsPort !== undefined && httpsPort !== null && httpsPort !== '' && nextHttpsPortNum === null) {
      throw buildPortValidationError({
        code: 'PORT_INVALID',
        msgKey: 'fileServer.PORT_INVALID',
        args: ['https', String(httpsPort)],
        details: { field: 'https_port', value: httpsPort, suggestedRange },
      });
    }

    const defaults = config && config.fileServer && config.fileServer.defaultPorts ? config.fileServer.defaultPorts : {};
    const defaultForType = defaults && typeof defaults === 'object' ? defaults[serverTypeStr] : null;
    const defaultHttp = toPortNumber(defaultForType && defaultForType.http_port);
    const defaultHttps = toPortNumber(defaultForType && defaultForType.https_port);

    const effectiveHttp = nextHttpPortNum || defaultHttp;
    const effectiveHttps = nextHttpsPortNum || defaultHttps;

    const effectivePorts = [effectiveHttp, effectiveHttps].filter(Boolean);
    if (effectivePorts.length >= 2 && new Set(effectivePorts).size !== effectivePorts.length) {
      throw buildPortValidationError({
        code: 'PORT_DUPLICATE',
        msgKey: 'fileServer.PORT_DUPLICATE',
        args: [String(effectiveHttp), String(effectiveHttps)],
        details: { ports: effectivePorts, suggestedRange },
      });
    }

    const forbiddenList = Array.isArray(config && config.forbiddenPorts) ? config.forbiddenPorts : [];
    const forbiddenPorts = new Set(forbiddenList.map(p => toPortNumber(p)).filter(Boolean));
    for (const p of effectivePorts) {
      if (forbiddenPorts.has(p)) {
        const fields = [];
        if (effectiveHttp === p) fields.push('http_port');
        if (effectiveHttps === p) fields.push('https_port');
        throw buildPortValidationError({
          code: 'PORT_DISABLED',
          msgKey: 'fileServer.PORT_DISABLED',
          args: [String(p)],
          details: { port: p, fields, forbiddenPorts: Array.from(forbiddenPorts), suggestedRange },
        });
      }
    }

    const rawApiHttpPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTP, 0);
    const rawApiHttpsPort = await tableConfig.getConfigByKey(tableConfig.KEY_API_PORT_HTTPS, 0);
    const apiHttpPort = toPortNumber(rawApiHttpPort) || toPortNumber(config && config.app && config.app.port);
    const apiHttpsPort = toPortNumber(rawApiHttpsPort) || toPortNumber(config && config.app && config.app.httpsPort);
    const reservedApiPorts = new Set([apiHttpPort, apiHttpsPort].filter(Boolean));
    for (const p of effectivePorts) {
      if (reservedApiPorts.has(p)) {
        const fields = [];
        if (effectiveHttp === p) fields.push('http_port');
        if (effectiveHttps === p) fields.push('https_port');
        throw buildPortValidationError({
          code: 'PORT_RESERVED',
          msgKey: 'fileServer.PORT_RESERVED',
          args: [String(p)],
          details: { port: p, fields, reservedPorts: Array.from(reservedApiPorts), suggestedRange },
        });
      }
    }

    for (const otherType of SUPPORTED_SERVER_TYPES) {
      if (otherType === serverTypeStr) continue;
      const other = await this.getGlobalPorts({ serverType: otherType });
      const otherHttp = toPortNumber(other && other.http_port);
      const otherHttps = toPortNumber(other && other.https_port);
      const otherPorts = new Set([otherHttp, otherHttps].filter(Boolean));
      for (const p of effectivePorts) {
        if (otherPorts.has(p)) {
          const fields = [];
          if (effectiveHttp === p) fields.push('http_port');
          if (effectiveHttps === p) fields.push('https_port');
          throw buildPortValidationError({
            code: 'PORT_CONFLICT',
            msgKey: 'fileServer.PORT_CONFLICT',
            args: [String(p), String(otherType)],
            details: { port: p, fields, conflictWith: otherType, suggestedRange },
          });
        }
      }
    }

    const payload = {
      http_port: nextHttpPortNum,
      https_port: nextHttpsPortNum,
    };
    const ok = await tableConfig.setConfigByKey(key, JSON.stringify(payload), 0);
    if (!ok) {
      const err = new Error('common.ERROR');
      err.statusCode = 500;
      throw err;
    }
    return await this.getGlobalPorts({ serverType: serverTypeStr });
  }
}

module.exports = { FileServerService, buildFileServerConfigKey, buildFileServerPortsKey };
