const fs = require('fs');
const path = require('path');
const config = require('../../config/config');
const { httpPort: OPENLIST_HTTP_PORT } = require('../../libsPath/openlistPath');

function getDataPath() {
  if (process.env.PATH_OPENLIST_DATA) {
    return path.resolve(process.env.PATH_OPENLIST_DATA);
  }
  // Worker 进程无 Electron，config.getUserDataPath() 会落到 cwd/data；与主进程数据库目录不一致。
  const dbPath = process.env.PATH_DATABASE;
  if (dbPath) {
    return path.join(path.dirname(path.resolve(dbPath)), 'openListData');
  }
  return config.getOpenListDataPath();
}

function readHttpPortFromConfig(dataPath) {
  try {
    const configPath = path.join(dataPath, 'config.json');
    if (!fs.existsSync(configPath)) return OPENLIST_HTTP_PORT;
    const raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const port = Number(raw && raw.scheme && raw.scheme.http_port);
    if (Number.isFinite(port) && port > 0 && port <= 65535) return port;
  } catch (_) {}
  return OPENLIST_HTTP_PORT;
}

function getBaseUrlForDataPath(dataPath) {
  const port = readHttpPortFromConfig(dataPath);
  return `http://127.0.0.1:${port}`;
}

function ensureDataDirs(dataPath) {
  fs.mkdirSync(dataPath, { recursive: true });
  fs.mkdirSync(path.join(dataPath, 'temp'), { recursive: true });
  fs.mkdirSync(path.join(dataPath, 'bleve'), { recursive: true });
  fs.mkdirSync(path.join(dataPath, 'log'), { recursive: true });
}

function buildConfigObject() {
  return {
    force: false,
    site_url: '',
    cdn: '',
    token_expires_in: 48,
    database: {
      type: 'sqlite3',
      host: '',
      port: 0,
      user: '',
      password: '',
      name: '',
      db_file: 'data.db',
      table_prefix: 'x_',
      ssl_mode: '',
      dsn: '',
    },
    scheme: {
      address: '127.0.0.1',
      http_port: OPENLIST_HTTP_PORT,
      https_port: -1,
      force_https: false,
      cert_file: '',
      key_file: '',
      unix_file: '',
      unix_file_perm: '',
      enable_h2c: false,
    },
    temp_dir: 'temp',
    bleve_dir: 'bleve',
    dist_dir: '',
    log: {
      enable: true,
      name: 'log/log.log',
      max_size: 50,
      max_backups: 5,
      max_age: 28,
      compress: false,
    },
    max_connections: 0,
    max_concurrency: 64,
    tls_insecure_skip_verify: true,
  };
}

function writeConfigIfNeeded(dataPath) {
  ensureDataDirs(dataPath);
  const configPath = path.join(dataPath, 'config.json');
  if (fs.existsSync(configPath)) {
    try {
      const existing = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      const merged = { ...buildConfigObject(), ...existing };
      merged.scheme = { ...buildConfigObject().scheme, ...(existing.scheme || {}) };
      merged.scheme.address = '127.0.0.1';
      merged.scheme.http_port = OPENLIST_HTTP_PORT;
      merged.database = { ...buildConfigObject().database, ...(existing.database || {}) };
      fs.writeFileSync(configPath, JSON.stringify(merged, null, 2), 'utf8');
    } catch (_) {
      fs.writeFileSync(configPath, JSON.stringify(buildConfigObject(), null, 2), 'utf8');
    }
    return configPath;
  }
  fs.writeFileSync(configPath, JSON.stringify(buildConfigObject(), null, 2), 'utf8');
  return configPath;
}

function getBaseUrl() {
  return getBaseUrlForDataPath(getDataPath());
}

function buildWebdavUrl(openlistMountPath, baseUrl) {
  const mp = String(openlistMountPath || '/').trim();
  const normalized = mp.startsWith('/') ? mp : `/${mp}`;
  const encoded = normalized
    .split('/')
    .filter(Boolean)
    .map(seg => encodeURIComponent(seg))
    .join('/');
  const suffix = encoded ? `/${encoded}` : '';
  const root = baseUrl || getBaseUrl();
  return `${root}/dav${suffix}`;
}

module.exports = {
  getDataPath,
  ensureDataDirs,
  writeConfigIfNeeded,
  getBaseUrl,
  getBaseUrlForDataPath,
  readHttpPortFromConfig,
  buildWebdavUrl,
  OPENLIST_HTTP_PORT,
};
