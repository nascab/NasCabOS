const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const portfinder = require('portfinder');
const Logger = require('../../utils/logger');
const jwtUtil = require('../../utils/jwtUtil');
const sftpgoPath = require('../../libsPath/sftpgoPath');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const config = require('../../config/config');
const certUtil = require('../../utils/certUtil');

function safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function decryptIfEncrypted(value) {
  const text = ensureString(value);
  if (!text) return '';
  if (!jwtUtil.isEncryptedPassword(text)) return text;
  return jwtUtil.decryptPassword(text) || '';
}

function toPortNumber(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.trunc(n);
  if (i < 1 || i > 65535) return null;
  return i;
}

async function getFreePort(basePort) {
  const startPort = toPortNumber(basePort);
  if (!startPort) return null;
  try {
    return await portfinder.getPortPromise({ port: startPort, stopPort: 65535 });
  } catch (_) {
    return null;
  }
}

async function ensureMainDbReady() {
  const dbPath = dbUtil.DB_PATHS.MAIN_DB;
  if (!knexUtil.hasConnection(dbPath)) {
    await knexUtil.init(dbPath);
  }
}

async function ensureSftpgoEmailTemplates(workDir) {
  const base = ensureString(workDir).trim();
  if (!base) return;
  const emailDir = path.join(base, 'templates', 'email');
  await fs.promises.mkdir(emailDir, { recursive: true });

  const templates = [
    {
      name: 'reset-password.html',
      content: '<!doctype html><html><body><p>Password reset code: {{.Code}}</p></body></html>\n',
    },
    {
      name: 'reset-password.txt',
      content: 'Password reset code: {{.Code}}\n',
    },
    {
      name: 'password-expiration.html',
      content: '<!doctype html><html><body><p>Password expiration notice</p></body></html>\n',
    },
    {
      name: 'password-expiration.txt',
      content: 'Password expiration notice\n',
    },
  ];

  for (const t of templates) {
    const target = path.join(emailDir, t.name);
    const exists = await fs.promises
      .access(target, fs.constants.F_OK)
      .then(() => true)
      .catch(() => false);
    if (!exists) {
      await fs.promises.writeFile(target, t.content, 'utf8');
    }
  }
}

function toBoolFlag(v, defaultValue = 1) {
  if (v === undefined || v === null || v === '') return defaultValue;
  if (typeof v === 'boolean') return v ? 1 : 0;
  const n = Number(v);
  if (n === 0 || n === 1) return n;
  return defaultValue;
}

function normalizeRootPathEntries(rootPath) {
  if (!rootPath) return [];

  if (Array.isArray(rootPath)) {
    const out = [];
    for (const it of rootPath) {
      if (typeof it === 'string') {
        const p = ensureString(it).trim();
        if (!p) continue;
        out.push({ path: p, write: 1, update: 1, delete: 1 });
        continue;
      }
      if (it && typeof it === 'object') {
        const p = ensureString(it.path).trim();
        if (!p) continue;
        out.push({
          path: p,
          write: toBoolFlag(it.write, 1),
          update: toBoolFlag(it.update, 1),
          delete: toBoolFlag(it.delete, 1),
        });
        continue;
      }
    }
    return out;
  }

  const text = ensureString(rootPath).trim();
  if (!text) return [];

  const parsed = safeJsonParse(text);
  if (Array.isArray(parsed)) return normalizeRootPathEntries(parsed);
  return [{ path: text, write: 1, update: 1, delete: 1 }];
}

function basenameForVirtualName(p) {
  let v = ensureString(p).trim();
  while (v.endsWith('/') || v.endsWith('\\')) {
    v = v.slice(0, -1);
  }
  if (!v) return '';
  const i1 = v.lastIndexOf('/');
  const i2 = v.lastIndexOf('\\');
  const i = i1 > i2 ? i1 : i2;
  const base = i < 0 ? v : v.slice(i + 1);
  return ensureString(base).replaceAll('/', '_').replaceAll('\\', '_').trim();
}

function uniqueVirtualNames(paths) {
  const used = new Set();
  const result = [];
  for (const p of paths) {
    const base = basenameForVirtualName(p) || 'root';
    let name = base;
    let i = 1;
    while (used.has(name)) {
      name = `${base}(${i})`;
      i += 1;
    }
    used.add(name);
    result.push(name);
  }
  return result;
}

function buildPermissionsForVirtualFolders({ entries, refs }) {
  const permissionMap = { '/': ['list'] };
  const list = Array.isArray(entries) ? entries : [];
  const folders = Array.isArray(refs) ? refs : [];

  const count = Math.min(list.length, folders.length);
  for (let i = 0; i < count; i += 1) {
    const entry = list[i] || {};
    const virtualPath = ensureString(folders[i] && folders[i].virtual_path).trim();
    if (!virtualPath || virtualPath === '/') continue;

    const perms = ['list', 'download'];
    if (toBoolFlag(entry.write, 1)) {
      perms.push('upload', 'create_dirs', 'overwrite');
    }
    if (toBoolFlag(entry.update, 1)) {
      perms.push('rename');
    }
    if (toBoolFlag(entry.delete, 1)) {
      perms.push('delete');
    }
    permissionMap[virtualPath] = perms;
  }

  return permissionMap;
}

function buildFolderData({ rootPaths, startId }) {
  const folders = [];
  const refs = [];
  let id = Number(startId || 1) || 1;

  const paths = Array.isArray(rootPaths) ? rootPaths : [];
  const names = uniqueVirtualNames(paths);
  for (let idx = 0; idx < paths.length; idx += 1) {
    const mappedPath = ensureString(paths[idx]).trim();
    const virtualPath = `/${ensureString(names[idx]).trim()}`;
    if (!mappedPath) continue;
    if (virtualPath === '/') continue;

    const folderName = `vf_${id}`;
    folders.push({
      id,
      name: folderName,
      mapped_path: mappedPath,
      description: '',
      filesystem: {
        provider: 0,
        osconfig: {
          path: mappedPath,
        },
      },
      quota_size: 0,
      quota_files: 0,
      used_quota_size: 0,
      used_quota_files: 0,
      last_quota_update: 0,
    });
    refs.push({
      name: folderName,
      virtual_path: virtualPath,
      quota_size: 0,
      quota_files: 0,
    });

    id += 1;
  }

  return { folders, refs, nextId: id };
}

async function buildUsersDump({ homeDir, items }) {
  const users = [];
  const folders = [];
  const seenUsernames = new Set();

  let userId = 1;
  let folderId = 1;

  const list = Array.isArray(items) ? items : [];
  for (const it of list) {
    if (!it || typeof it !== 'object') continue;

    const rootPathEntries = normalizeRootPathEntries(it.rootPath);
    const rootPaths = rootPathEntries.map(r => ensureString(r && r.path).trim()).filter(Boolean);
    if (rootPaths.length === 0) {
      const err = new Error('invalid_params');
      err.code = 'invalid_params';
      throw err;
    }

    const config = safeJsonParse(it.config) || (it.config && typeof it.config === 'object' ? it.config : {});
    let configUsers = config && Array.isArray(config.users) ? config.users : [];

    const fallbackHomeDir = ensureString(homeDir).trim();

    const folderData = buildFolderData({ rootPaths, startId: folderId });
    folderId = folderData.nextId;
    folders.push(...folderData.folders);
    const basePermissions = (config && config.permissions) || buildPermissionsForVirtualFolders({ entries: rootPathEntries, refs: folderData.refs });

    if (configUsers.length === 0) {
      const uidNum = Number(ensureString(it.uid)) || 0;
      if (uidNum > 0) {
        await ensureMainDbReady();
        const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
        const row = await knex('user')
          .select('username', 'password')
          .where({ id: uidNum })
          .first()
          .catch(() => null);
        if (row && row.username && row.password) {
          configUsers = [{ username: ensureString(row.username), password: ensureString(row.password) }];
        }
      }
    }

    for (const u of configUsers) {
      if (!u || typeof u !== 'object') continue;
      const username = ensureString(u.username).trim();
      if (!username) continue;
      if (seenUsernames.has(username)) {
        const err = new Error('duplicate_username');
        err.code = 'duplicate_username';
        throw err;
      }
      seenUsernames.add(username);

      const decryptedPassword = decryptIfEncrypted(u.password);
      if (!decryptedPassword) continue;
      u.password = decryptedPassword;

      const resolvedHomeDir = ensureString(u.home_dir || u.homeDir || fallbackHomeDir).trim() || fallbackHomeDir;
      const permissionOverride = u.permissions && typeof u.permissions === 'object' ? u.permissions : null;
      const permissions = permissionOverride || basePermissions || { '/': ['*'] };

      users.push({
        id: userId++,
        status: 1,
        username,
        password: u.password,
        home_dir: resolvedHomeDir,
        uid: 0,
        gid: 0,
        permissions,
        expiration_date: 0,
        max_sessions: 0,
        quota_size: 0,
        quota_files: 0,
        used_quota_size: 0,
        used_quota_files: 0,
        last_quota_update: 0,
        upload_bandwidth: 0,
        download_bandwidth: 0,
        description: '',
        virtual_folders: folderData.refs,
      });
    }
  }

  if (users.length === 0) {
    const err = new Error('no_users');
    err.code = 'no_users';
    throw err;
  }

  if (folders.length > 0) return { users, folders };
  return { users };
}

function buildSftpgoConfig({ serverType, httpPort, httpsPort, certFile, keyFile }) {
  const config = {
    common: {
      idle_timeout: 15,
    },
    data_provider: {
      driver: 'memory',
    },
    sftpd: {
      host_keys: [],
      bindings: [],
    },
    ftpd: {
      bindings: [],
    },
    webdavd: {
      bindings: [],
    },
    httpd: {
      enable_rest_api: false,
      templates_path: '',
      static_files_path: '',
      // 空 bindings：不启用 SFTPGo 自带的管理/REST HTTP（与 WebDAV/FTP/SFTP 无关）
      bindings: [],
    },
  };

  const serverTypeStr = ensureString(serverType);
  const httpPortNum = httpPort === undefined || httpPort === null ? null : Number(httpPort);
  const httpsPortNum = httpsPort === undefined || httpsPort === null ? null : Number(httpsPort);

  if (serverTypeStr === 'SFTP') {
    config.sftpd.bindings = [
      {
        port: httpPortNum || 2022,
        address: '',
        apply_proxy_config: true,
        tls_mode: 0,
      },
    ];
    return config;
  }

  if (serverTypeStr === 'FTP') {
    config.ftpd.bindings = [
      {
        port: httpPortNum || 21,
        address: '',
        apply_proxy_config: true,
        tls_mode: 0,
      },
    ];
    return config;
  }

  if (serverTypeStr === 'WebDav') {
    const bindings = [];
    if (httpPortNum) {
      bindings.push({
        port: httpPortNum,
        address: '',
        enable_https: false,
        certificate_file: '',
        certificate_key_file: '',
        min_tls_version: 12,
      });
    }
    if (httpsPortNum && certFile && keyFile) {
      bindings.push({
        port: httpsPortNum,
        address: '',
        enable_https: true,
        certificate_file: certFile || '',
        certificate_key_file: keyFile || '',
        min_tls_version: 12,
      });
    }
    if (bindings.length === 0) {
      bindings.push({
        port: 10080,
        address: '',
        enable_https: false,
        certificate_file: '',
        certificate_key_file: '',
        min_tls_version: 12,
      });
    }
    config.webdavd.bindings = bindings;
    return config;
  }

  config.webdavd.bindings = [
    {
      port: 10080,
      address: '',
      enable_https: false,
      certificate_file: '',
      certificate_key_file: '',
      min_tls_version: 12,
    },
  ];
  return config;
}

let sftpgoProcess = null;
let stopping = false;

async function startServer({ requestId, serverType, items, httpPort, httpsPort }) {
  await sftpgoPath.ensureReady();
  const serverTypeStr = ensureString(serverType).trim();
  const list = Array.isArray(items) ? items : [];
  if (!serverTypeStr || list.length === 0) {
    process.send?.({
      type: 'fileServerStartResponse',
      data: { requestId, ok: false, error: 'invalid_params' },
    });
    return;
  }

  let resolvedHttpPort = null;
  let resolvedHttpsPort = null;
  const requestedHttpPort = toPortNumber(httpPort);
  const requestedHttpsPort = toPortNumber(httpsPort);

  if (serverTypeStr === 'SFTP') {
    resolvedHttpPort = await getFreePort(requestedHttpPort || 2022);
  } else if (serverTypeStr === 'FTP') {
    resolvedHttpPort = await getFreePort(requestedHttpPort || 2121);
  } else if (serverTypeStr === 'WebDav') {
    if (requestedHttpPort) resolvedHttpPort = await getFreePort(requestedHttpPort);
    if (requestedHttpsPort) resolvedHttpsPort = await getFreePort(requestedHttpsPort);
    if (!resolvedHttpPort && !resolvedHttpsPort) resolvedHttpPort = await getFreePort(10080);
    if (resolvedHttpPort && resolvedHttpsPort && resolvedHttpPort === resolvedHttpsPort) {
      resolvedHttpsPort = await getFreePort(resolvedHttpsPort + 1);
    }
  } else {
    resolvedHttpPort = await getFreePort(requestedHttpPort || 10080);
  }

  if (!resolvedHttpPort && !resolvedHttpsPort) {
    process.send?.({
      type: 'fileServerStartResponse',
      data: { requestId, ok: false, error: 'no_free_port' },
    });
    return;
  }

  for (const it of list) {
    if (!it || typeof it !== 'object') continue;
    const rootEntries = normalizeRootPathEntries(it.rootPath);
    for (const entry of rootEntries) {
      const p0 = entry && entry.path;
      const p = ensureString(p0).trim();
      if (!p) continue;
      try {
        const st = await fs.promises.stat(p);
        if (!st || !st.isDirectory()) {
          process.send?.({
            type: 'fileServerStartResponse',
            data: { requestId, ok: false, error: 'root_path_invalid' },
          });
          return;
        }
      } catch (_) {
        process.send?.({
          type: 'fileServerStartResponse',
          data: { requestId, ok: false, error: 'root_path_not_exists' },
        });
        return;
      }
    }
  }

  const baseDir = ensureString(process.env.PATH_CACHE).trim() || ensureString(process.env.PATH_DATABASE).trim() || process.cwd();
  const workDir = path.join(baseDir, 'fileServer', `${serverTypeStr}`);
  await fs.promises.mkdir(workDir, { recursive: true });
  const homeDir = path.join(workDir, 'home');
  await fs.promises.mkdir(homeDir, { recursive: true });
  await ensureSftpgoEmailTemplates(workDir);

  let certFile = '';
  let keyFile = '';
  let selectedTls = null;
  for (const it of list) {
    const cfg = safeJsonParse(it && it.config) || (it && typeof it.config === 'object' ? it.config : null);
    if (!cfg || typeof cfg !== 'object') continue;
    const cert = decryptIfEncrypted(cfg.tls_cert_pem);
    const key = decryptIfEncrypted(cfg.tls_key_pem);
    if (cert && key) {
      selectedTls = { cert, key };
      break;
    }
  }

  if (!selectedTls) {
    try {
      // 确保证书存在（首次启动自动生成自签名证书）
      const { keyPath, certPath } = certUtil.ensureCert();
      const certText = await fs.promises.readFile(certPath, 'utf8');
      const keyText = await fs.promises.readFile(keyPath, 'utf8');
      if (certText && keyText) {
        selectedTls = { cert: certText, key: keyText };
      }
    } catch (_) {}
  }

  const rawCertPem = selectedTls ? selectedTls.cert : '';
  const rawKeyPem = selectedTls ? selectedTls.key : '';
  if ((!rawCertPem || !rawKeyPem) && resolvedHttpsPort) {
    resolvedHttpsPort = null;
  }
  if (rawCertPem && rawKeyPem) {
    certFile = path.join(workDir, 'cert.pem');
    keyFile = path.join(workDir, 'key.pem');
    await fs.promises.writeFile(certFile, rawCertPem, 'utf8');
    await fs.promises.writeFile(keyFile, rawKeyPem, 'utf8');
  }

  const sftpgoConfig = buildSftpgoConfig({
    serverType: serverTypeStr,
    httpPort: resolvedHttpPort,
    httpsPort: resolvedHttpsPort,
    certFile,
    keyFile,
  });
  const configFilePath = path.join(workDir, 'sftpgo.json');
  await fs.promises.writeFile(configFilePath, JSON.stringify(sftpgoConfig, null, 2), 'utf8');

  const dump = await buildUsersDump({ homeDir, items: list });
  const dumpPath = path.join(workDir, 'loaddata.json');
  await fs.promises.writeFile(dumpPath, JSON.stringify(dump, null, 2), 'utf8');

  const args = ['serve', '--config-dir', workDir, '--config-file', configFilePath, '--loaddata-from', dumpPath, '--loaddata-mode', '0', '--loaddata-scan', '0'];
  sftpgoProcess = spawn(sftpgoPath.path, args, {
    cwd: workDir,
    stdio: ['ignore', 'pipe', 'pipe'],
    windowsHide: true,
    env: {
      ...process.env,
      SFTPGO_CONFIG_DIR: workDir,
      SFTPGO_CONFIG_FILE: configFilePath,
    },
  });

  const startupLogChunks = [];
  const appendStartupLog = text => {
    const t = ensureString(text);
    if (!t) return;
    startupLogChunks.push(t);
    if (startupLogChunks.join('').length > 12000) {
      startupLogChunks.shift();
    }
  };

  function classifySftpgoStartFailure(logText) {
    const t = ensureString(logText);
    if (/address already in use|bind:\s*address already in use|EADDRINUSE/i.test(t)) return 'port_bind_failed';
    if (/could not start (WebDAV|FTP|SFTP) server/i.test(t)) return 'service_bind_failed';
    return 'sftpgo_start_failed';
  }

  let startResponseSent = false;
  let startConfirmTimer = null;

  function sendFileServerStartResponse(payload) {
    if (startResponseSent) return;
    startResponseSent = true;
    try {
      clearTimeout(startConfirmTimer);
    } catch (_) {}
    process.send?.({
      type: 'fileServerStartResponse',
      data: payload,
    });
  }

  sftpgoProcess.stdout?.on('data', chunk => {
    const text = ensureString(chunk);
    appendStartupLog(text);
    if (text) Logger.info(text.trim());
  });
  sftpgoProcess.stderr?.on('data', chunk => {
    const text = ensureString(chunk);
    appendStartupLog(text);
    if (text) Logger.warn(text.trim());
  });

  sftpgoProcess.once('spawn', () => {
    // 不能在 spawn 立刻判定成功：sftpgo 可能在绑定 WebDAV/FTP/SFTP 端口失败后才退出（例如端口被占用）。
    startConfirmTimer = setTimeout(() => {
      if (!sftpgoProcess || sftpgoProcess.exitCode !== null) return;
      Logger.info(
        `File share service is ready（${serverTypeStr}）。`,
      );
      sendFileServerStartResponse({
        requestId,
        ok: true,
        pid: sftpgoProcess.pid,
        workDir,
        httpPort: resolvedHttpPort,
        httpsPort: resolvedHttpsPort,
      });
    }, 500);
  });

  sftpgoProcess.once('error', err => {
    sendFileServerStartResponse({
      requestId,
      ok: false,
      error: ensureString(err && err.message ? err.message : err),
    });
    try {
      process.exit(1);
    } catch (_) {}
  });

  sftpgoProcess.once('exit', (code, signal) => {
    const exitCode = Number(code || 0) || 0;
    try {
      clearTimeout(startConfirmTimer);
    } catch (_) {}

    if (!startResponseSent) {
      if (exitCode !== 0) {
        const logTail = startupLogChunks.join('').slice(-2000);
        sendFileServerStartResponse({
          requestId,
          ok: false,
          error: classifySftpgoStartFailure(logTail),
        });
      } else {
        sendFileServerStartResponse({
          requestId,
          ok: false,
          error: 'sftpgo_exited_before_ready',
        });
      }
    }

    if (!stopping && exitCode !== 0) {
      Logger.error(`fileServer sftpgo exited: ${serverTypeStr}`, code, signal);
    }
    try {
      process.exit(exitCode);
    } catch (_) {}
  });
}

function stopServer() {
  stopping = true;
  if (!sftpgoProcess) {
    process.exit(0);
    return;
  }

  try {
    sftpgoProcess.kill('SIGTERM');
  } catch (_) {}

  setTimeout(() => {
    try {
      sftpgoProcess.kill('SIGKILL');
    } catch (_) {}
  }, 2000);
}

process.on('message', async message => {
  if (!message || !message.type) return;
  if (message.type === 'start') {
    const { requestId, serverType, items, httpPort, httpsPort } = message.data || {};
    try {
      Logger.info("START FILE SHARE SERVICE")
      await startServer({ requestId, serverType, items, httpPort, httpsPort });
    } catch (e) {
      process.send?.({
        type: 'fileServerStartResponse',
        data: { requestId, ok: false, error: ensureString(e && e.message ? e.message : e) },
      });
      process.exit(1);
    }
  } else if (message.type === 'stop') {
    stopServer();
  }
});

process.on('uncaughtException', err => {
  Logger.error('fileServerWorker uncaughtException', err);
  process.exit(1);
});

process.on('unhandledRejection', reason => {
  Logger.error('fileServerWorker unhandledRejection', reason);
  process.exit(1);
});
