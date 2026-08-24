const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const Database = require('better-sqlite3');

const folderSignString = 'nascabisthebest';
const folderSignFileName = 'nascabconfigenc';
const configFolderName = 'nascabconfig';
const indexDbFileName = 'dbnascab';
const noCheckFileList = ['.DS_Store'];

const algorithm = 'aes-128-cbc';
const keyLength = 16;
const salt = 'nascabisthebestanascabisthebesta';
const iv = Buffer.from('nascabisthebesta', 'utf8');

const _keyCache = new Map();

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function tryDecodeBase64(input) {
  const s = ensureString(input).trim();
  if (!s) return null;
  if (s.length % 4 !== 0) return null;
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(s)) return null;
  try {
    const buf = Buffer.from(s, 'base64');
    if (!buf || buf.length <= 0) return null;
    const reEncoded = buf.toString('base64').replace(/=+$/g, '');
    const normalized = s.replace(/=+$/g, '');
    if (reEncoded !== normalized) return null;
    const out = buf.toString('utf8');
    return out ? out : null;
  } catch (_) {
    return null;
  }
}

function getKeyByPwd(pwd) {
  const k = ensureString(pwd);
  if (_keyCache.has(k)) return _keyCache.get(k);
  const key = crypto.scryptSync(k, salt, keyLength);
  _keyCache.set(k, key);
  return key;
}

async function resolveSpacePwdForSign(inputPwd, signEncryptedHex) {
  const raw = ensureString(inputPwd).trim();
  const sign = ensureString(signEncryptedHex).trim();
  if (!raw || !sign) return null;

  const candidates = [raw];
  const decodedBase64 = tryDecodeBase64(raw);
  if (decodedBase64 && decodedBase64 !== raw) candidates.push(decodedBase64);
  const encodedBase64 = Buffer.from(raw, 'utf8').toString('base64');
  if (encodedBase64 && encodedBase64 !== raw) candidates.push(encodedBase64);

  for (const pwd of candidates) {
    try {
      const deResult = await decryptString(pwd, sign);
      if (deResult === folderSignString) return pwd;
    } catch (_) {}
  }
  return null;
}

function encryptString(pwd, rawStr) {
  return new Promise((resolve, reject) => {
    try {
      const key = getKeyByPwd(pwd);
      const cipher = crypto.createCipheriv(algorithm, key, iv);
      let encryptedData = cipher.update(String(rawStr), 'utf8', 'hex');
      encryptedData += cipher.final('hex');
      resolve(encryptedData);
    } catch (e) {
      reject(e);
    }
  });
}

function decryptString(pwd, encryptedHex) {
  return new Promise((resolve, reject) => {
    try {
      const key = getKeyByPwd(pwd);
      const decipher = crypto.createDecipheriv(algorithm, key, iv);
      decipher.on('error', reject);
      let decryptedData = decipher.update(String(encryptedHex), 'hex', 'utf8');
      decryptedData += decipher.final('utf8');
      resolve(decryptedData);
    } catch (e) {
      reject(e);
    }
  });
}

function encryptFileFromInputPipe(pwd, inputPipe, enPath) {
  return new Promise((resolve, reject) => {
    try {
      const key = getKeyByPwd(pwd);
      const cipher = crypto.createCipheriv(algorithm, key, iv);
      cipher.on('error', reject);
      const output = fs.createWriteStream(enPath);
      output.on('error', reject);
      output.on('finish', () => resolve(enPath));
      inputPipe.pipe(cipher).pipe(output);
    } catch (e) {
      reject(e);
    }
  });
}

function encryptFile(pwd, rawPath, enPath) {
  return new Promise((resolve, reject) => {
    try {
      const key = getKeyByPwd(pwd);
      const input = fs.createReadStream(rawPath);
      const cipher = crypto.createCipheriv(algorithm, key, iv);
      const output = fs.createWriteStream(enPath);
      const onErr = err => reject(err);
      input.on('error', onErr);
      cipher.on('error', onErr);
      output.on('error', onErr);
      output.on('finish', () => resolve(enPath));
      input.pipe(cipher).pipe(output);
    } catch (e) {
      reject(e);
    }
  });
}

function getInitialIv() {
  return Buffer.from(iv);
}

function encryptFileChunkAppend(pwd, rawPath, enPath, options = {}) {
  return new Promise((resolve, reject) => {
    try {
      const key = getKeyByPwd(pwd);
      const ivOverride = options && options.iv ? options.iv : iv;
      const append = !!(options && options.append);
      const isLast = !!(options && options.isLast);

      const input = fs.createReadStream(rawPath);
      const cipher = crypto.createCipheriv(algorithm, key, ivOverride);
      if (!isLast) cipher.setAutoPadding(false);

      fs.mkdirSync(path.dirname(enPath), { recursive: true });
      const output = fs.createWriteStream(enPath, { flags: append ? 'a' : 'w' });
      const onErr = err => reject(err);
      input.on('error', onErr);
      cipher.on('error', onErr);
      output.on('error', onErr);
      output.on('finish', () => resolve(enPath));
      input.pipe(cipher).pipe(output);
    } catch (e) {
      reject(e);
    }
  });
}

function decryptFileToStream(pwd, enPath, outStream) {
  return new Promise((resolve, reject) => {
    try {
      const key = getKeyByPwd(pwd);
      const input = fs.createReadStream(enPath);
      const decipher = crypto.createDecipheriv(algorithm, key, iv);
      const onErr = err => reject(err);
      input.on('error', onErr);
      decipher.on('error', onErr);
      outStream.on('error', onErr);
      outStream.on('finish', () => resolve('finish'));
      input.pipe(decipher).pipe(outStream, { end: true });
    } catch (e) {
      reject(e);
    }
  });
}

function decryptFileGetStream(pwd, enPath) {
  const key = getKeyByPwd(pwd);
  const input = fs.createReadStream(enPath);
  const decipher = crypto.createDecipheriv(algorithm, key, iv);
  return input.pipe(decipher);
}

function createDecipherByPwd(pwd, ivOverride) {
  const key = getKeyByPwd(pwd);
  return crypto.createDecipheriv(algorithm, key, ivOverride || iv);
}

async function getDecryptedFileSize(pwd, enPath) {
  const st = await fs.promises.stat(enPath).catch(() => null);
  const cipherSize = st && st.isFile && st.isFile() ? Number(st.size) : 0;
  if (!Number.isFinite(cipherSize) || cipherSize <= 0) return 0;
  if (cipherSize % 16 !== 0) return cipherSize;
  if (cipherSize < 16) return cipherSize;

  const lastBlockPos = cipherSize - 16;
  const prevBlockPos = cipherSize - 32;

  const fd = await fs.promises.open(enPath, 'r');
  try {
    const prev = Buffer.alloc(16);
    if (prevBlockPos >= 0) {
      const r = await fd.read(prev, 0, 16, prevBlockPos);
      if (!r || r.bytesRead !== 16) return cipherSize;
    } else {
      Buffer.from(iv).copy(prev, 0, 0, 16);
    }

    const lastCipher = Buffer.alloc(16);
    const r2 = await fd.read(lastCipher, 0, 16, lastBlockPos);
    if (!r2 || r2.bytesRead !== 16) return cipherSize;

    const decipher = createDecipherByPwd(pwd, prev);
    decipher.setAutoPadding(false);
    const plainLast = Buffer.concat([decipher.update(lastCipher), decipher.final()]);
    if (!plainLast || plainLast.length !== 16) return cipherSize;

    const padLen = plainLast[15];
    if (!padLen || padLen < 1 || padLen > 16) return cipherSize;
    for (let i = 16 - padLen; i < 16; i += 1) {
      if (plainLast[i] !== padLen) return cipherSize;
    }
    return cipherSize - padLen;
  } finally {
    await fd.close().catch(() => {});
  }
}

function decodePath(dealPath) {
  try {
    return decodeURIComponent(Buffer.from(String(dealPath), 'base64').toString());
  } catch (_) {
    return '';
  }
}

function formatJoin(base, rawRelPath) {
  const rel = ensureString(rawRelPath);
  const normalizedRel = path.normalize(rel.replace(/[\\/]/g, path.sep));
  return path.resolve(path.normalize(path.join(base, normalizedRel)));
}

function getSpaceConfigFolder(spaceFolderPath) {
  return path.join(spaceFolderPath, configFolderName);
}

function getIndexDbPath(spaceFolderPath) {
  return path.join(spaceFolderPath, configFolderName, indexDbFileName);
}

const _dbCache = new Map();

function getIndexDb(spaceFolderPath) {
  // 解析为文件系统真实路径，避免 macOS 上 NFC/NFD 等导致同一目录对应不同字符串，缓存键不一致而有时打开空库有时打开真实库
  let resolvedFolderPath = spaceFolderPath;
  try {
    resolvedFolderPath = fs.realpathSync(spaceFolderPath);
  } catch (_) {}
  const dbPath = getIndexDbPath(resolvedFolderPath);
  if (_dbCache.has(dbPath)) return _dbCache.get(dbPath);
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  const db = new Database(dbPath, {});
  try {
    db.pragma('journal_mode = WAL');
  } catch (_) {}
  _dbCache.set(dbPath, db);
  return db;
}

function ensureIndexDbSchema(privateIndexDb) {
  const hasTable = privateIndexDb.prepare(`SELECT COUNT(*) as count FROM sqlite_master where type='table' and name='private_space_index';`).get();
  if (!hasTable || Number(hasTable.count || 0) < 1) {
    privateIndexDb
      .prepare(
        `
        CREATE TABLE IF NOT EXISTS private_space_index
        (
          id INTEGER PRIMARY KEY,
          filename TEXT,
          show_name TEXT,
          remark TEXT,
          bak1 TEXT,
          bak2 TEXT,
          ext TEXT,
          filename_enc TEXT,
          tiny_path TEXT,
          file_type,
          check_time,
          original_time,
          size,
          duration,
          latitude,
          longitude,
          stream_info TEXT,
          create_time DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      `
      )
      .run();
    privateIndexDb.prepare(`CREATE INDEX private_space_index_ctime ON private_space_index (create_time);`).run();
    privateIndexDb.prepare(`CREATE INDEX private_space_index_check_time ON private_space_index (check_time);`).run();
    privateIndexDb.prepare(`CREATE INDEX private_space_index_original_time ON private_space_index (original_time);`).run();
    privateIndexDb.prepare(`CREATE INDEX private_space_index_filename ON private_space_index (filename,show_name);`).run();
  }
}

async function ensureSpaceFolderIsEmpty(folderPath) {
  const p = ensureString(folderPath).trim();
  if (!p) throw new Error('file.INVALID_PATH');
  const st = await fs.promises.stat(p).catch(() => null);
  if (!st || !st.isDirectory()) throw new Error('file.INVALID_PATH');
  const files = await fs.promises.readdir(p).catch(() => []);
  for (const f of files) {
    if (!f) continue;
    if (noCheckFileList.includes(f) || String(f).startsWith('.') || String(f).startsWith('@')) continue;
    throw new Error('mediaTool.TARGET_NOT_EMPTY');
  }
  return true;
}

async function ensureSpaceConfigFolders(spaceFolderPath) {
  const base = ensureString(spaceFolderPath).trim();
  const configFolder = getSpaceConfigFolder(base);
  const tinyFolder = path.join(configFolder, 'tiny');
  const tempFolder = path.join(configFolder, 'temp');
  await fs.promises.mkdir(configFolder, { recursive: true });
  await fs.promises.mkdir(tinyFolder, { recursive: true });
  await fs.promises.mkdir(tempFolder, { recursive: true });
  return { configFolder, tinyFolder, tempFolder };
}

module.exports = {
  folderSignString,
  folderSignFileName,
  configFolderName,
  indexDbFileName,
  ensureString,
  encryptString,
  decryptString,
  resolveSpacePwdForSign,
  getInitialIv,
  encryptFileFromInputPipe,
  encryptFile,
  encryptFileChunkAppend,
  decryptFileToStream,
  decryptFileGetStream,
  createDecipherByPwd,
  getDecryptedFileSize,
  decodePath,
  formatJoin,
  getSpaceConfigFolder,
  getIndexDbPath,
  getIndexDb,
  ensureIndexDbSchema,
  ensureSpaceFolderIsEmpty,
  ensureSpaceConfigFolders,
};
