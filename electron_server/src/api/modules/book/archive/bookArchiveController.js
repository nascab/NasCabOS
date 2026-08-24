const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const { Blob } = require('buffer');
const config = require('../../../../config/config');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const BookListService = require('../list/bookListService');
const { hasPermission } = require('../../../../utils/permissionUtil');

const _isSupportedImageName = name => {
  const lower = String(name || '').toLowerCase();
  return (
    lower.endsWith('.jpg') ||
    lower.endsWith('.jpeg') ||
    lower.endsWith('.png') ||
    lower.endsWith('.webp') ||
    lower.endsWith('.gif') ||
    lower.endsWith('.bmp') ||
    lower.endsWith('.tif') ||
    lower.endsWith('.tiff') ||
    lower.endsWith('.avif')
  );
};

const _mimeFromName = name => {
  const lower = String(name || '').toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.tif') || lower.endsWith('.tiff')) return 'image/tiff';
  if (lower.endsWith('.avif')) return 'image/avif';
  return 'application/octet-stream';
};

class DiskSlice {
  constructor(filePath, start, end) {
    this._filePath = filePath;
    this._start = start;
    this._end = end;
    this.size = Math.max(0, (Number(end || 0) || 0) - (Number(start || 0) || 0));
    this.type = '';
  }

  slice(start = 0, end = undefined) {
    const s = Math.max(0, Number(start || 0) || 0);
    const e = end === undefined || end === null ? this.size : Math.max(0, Number(end || 0) || 0);
    return new DiskSlice(this._filePath, this._start + s, Math.min(this._start + e, this._end));
  }

  async arrayBuffer() {
    const fd = await fs.promises.open(this._filePath, 'r');
    try {
      const buf = Buffer.allocUnsafe(this.size);
      const { bytesRead } = await fd.read(buf, 0, this.size, this._start);
      const out = bytesRead === buf.length ? buf : buf.subarray(0, bytesRead);
      return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength);
    } finally {
      await fd.close().catch(() => {});
    }
  }
}

async function _makeZipLoaderFromDisk(filePath) {
  const foliateRoot = config.getFoliateRootPath();
  const zipJsUrl = pathToFileURL(path.join(foliateRoot, 'vendor', 'zip.js')).href;

  globalThis.self = globalThis;
  if (!globalThis.Blob) globalThis.Blob = Blob;

  const zipMod = await import(zipJsUrl);
  const configure = zipMod.configure;
  const ZipReader = zipMod.ZipReader;
  const BlobReader = zipMod.BlobReader;
  const TextWriter = zipMod.TextWriter;
  const BlobWriter = zipMod.BlobWriter;
  const Uint8ArrayWriter = zipMod.Uint8ArrayWriter;

  if (typeof configure === 'function') {
    try {
      configure({ useWebWorkers: false });
    } catch (_) {}
  }

  const stat = await fs.promises.stat(filePath);
  const file = new DiskSlice(filePath, 0, stat.size);
  const reader = new ZipReader(new BlobReader(file));
  const entries = await reader.getEntries();
  const map = new Map(entries.map(entry => [entry.filename, entry]));
  const lowerMap = new Map();

  const safeDecode = s => {
    try {
      return decodeURIComponent(s);
    } catch (_) {
      return s;
    }
  };

  const normalizeKey = input => {
    let s = String(input || '');
    if (!s) return '';
    s = s.replace(/\\/g, '/');
    s = s.replace(/^\.\/+/, '');
    s = s.replace(/^\/+/, '');
    s = s.replace(/\/{2,}/g, '/');
    s = safeDecode(s);
    return s.toLowerCase();
  };

  for (const e of entries) {
    const name = e && e.filename ? String(e.filename) : '';
    if (!name) continue;
    const k1 = normalizeKey(name);
    const k2 = normalizeKey(name.replace(/\\/g, '/'));
    if (k1 && !lowerMap.has(k1)) lowerMap.set(k1, name);
    if (k2 && !lowerMap.has(k2)) lowerMap.set(k2, name);
  }

  const resolveEntry = name => {
    const raw = String(name || '');
    if (!raw) return null;
    if (map.has(raw)) return map.get(raw);
    const candidates = [raw, raw.replace(/\\/g, '/'), raw.replace(/^\.\/+/, ''), raw.replace(/^\/+/, ''), safeDecode(raw), safeDecode(raw.replace(/\\/g, '/'))];
    for (const c of candidates) {
      const key = normalizeKey(c);
      if (!key) continue;
      const real = lowerMap.get(key);
      if (real && map.has(real)) return map.get(real);
    }
    return null;
  };

  const load =
    f =>
    async (name, ...args) => {
      const entry = resolveEntry(name);
      return entry ? await f(entry, ...args) : null;
    };

  const loadText = load(entry => entry.getData(new TextWriter()));
  const loadBlob = load((entry, type) => entry.getData(new BlobWriter(type)));
  const loadUint8Array = Uint8ArrayWriter ? load(entry => entry.getData(new Uint8ArrayWriter())) : null;
  const getSize = name => resolveEntry(name)?.uncompressedSize ?? 0;

  return {
    kind: 'zip',
    entries,
    loadText,
    loadBlob,
    loadUint8Array,
    getSize,
    close: () => reader.close().catch(() => {}),
  };
}

async function _makeRarLoaderFromDisk(filePath) {
  let unrar;
  try {
    unrar = require('node-unrar-js');
  } catch (_) {
    return null;
  }

  const stat = await fs.promises.stat(filePath);
  const maxBytes = 300 * 1024 * 1024;
  const size = Number(stat && stat.size ? stat.size : 0) || 0;
  if (size <= 0 || size > maxBytes) return null;

  const buf = await fs.promises.readFile(filePath).catch(() => null);
  if (!buf || buf.length === 0) return null;

  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  const extractor = await unrar.createExtractorFromData({ data: ab }).catch(() => null);
  if (!extractor) return null;

  let fileHeaders = [];
  try {
    const list = extractor.getFileList();
    fileHeaders = list && list.fileHeaders ? [...list.fileHeaders] : [];
  } catch (_) {
    fileHeaders = [];
  }

  const map = new Map();
  const entries = [];
  for (const h of fileHeaders) {
    const name = h && h.name ? String(h.name) : '';
    if (!name) continue;
    map.set(name, h);
    entries.push({ filename: name });
  }

  const loadUint8Array = async name => {
    if (!name) return null;
    try {
      const extracted = extractor.extract({ files: [name] });
      const files = extracted && extracted.files ? [...extracted.files] : [];
      const first = files && files.length > 0 ? files[0] : null;
      const bytes = first && first.extraction ? first.extraction : null;
      return bytes || null;
    } catch (_) {
      return null;
    }
  };

  const loadText = async name => {
    const bytes = await loadUint8Array(name);
    if (!bytes) return '';
    try {
      return Buffer.from(bytes).toString('utf8');
    } catch (_) {
      return '';
    }
  };

  const getSize = name => {
    const h = map.get(name);
    return h && h.unpSize ? Number(h.unpSize || 0) || 0 : 0;
  };

  return { kind: 'rar', entries, loadText, loadBlob: null, loadUint8Array, getSize, close: () => {} };
}

function _tarReadString(buf, start, len) {
  const slice = buf.subarray(start, start + len);
  const nul = slice.indexOf(0);
  const out = (nul >= 0 ? slice.subarray(0, nul) : slice).toString('utf8');
  return out.replace(/\0/g, '').trim();
}

function _tarReadOctal(buf, start, len) {
  const s = _tarReadString(buf, start, len).replace(/\0/g, '').trim();
  if (!s) return 0;
  const n = parseInt(s, 8);
  return Number.isFinite(n) ? n : 0;
}

function _normalizeInnerPath(input) {
  let s = String(input || '');
  s = s.replace(/\\/g, '/');
  s = s.replace(/^\.\/+/, '');
  s = s.replace(/^\/+/, '');
  s = s.replace(/\/{2,}/g, '/');
  return s;
}

async function _makeTarLoaderFromDisk(filePath) {
  const stat = await fs.promises.stat(filePath).catch(() => null);
  if (!stat || !stat.isFile()) return null;

  const maxBytes = 1024 * 1024 * 1024;
  const sizeBytes = Number(stat.size || 0) || 0;
  if (sizeBytes <= 0 || sizeBytes > maxBytes) return null;

  const fd = await fs.promises.open(filePath, 'r').catch(() => null);
  if (!fd) return null;

  const entries = [];
  const index = new Map();

  let offset = 0;
  let gnuLongName = '';
  let paxPath = '';

  try {
    const header = Buffer.allocUnsafe(512);
    while (offset + 512 <= sizeBytes) {
      const { bytesRead } = await fd.read(header, 0, 512, offset);
      if (bytesRead !== 512) break;

      let allZero = true;
      for (let i = 0; i < 512; i++) {
        if (header[i] !== 0) {
          allZero = false;
          break;
        }
      }
      if (allZero) break;

      const name = _tarReadString(header, 0, 100);
      const prefix = _tarReadString(header, 345, 155);
      const typeflag = _tarReadString(header, 156, 1);
      const fileSize = _tarReadOctal(header, 124, 12);

      const rawPath = prefix ? `${prefix}/${name}` : name;
      const basePath = _normalizeInnerPath(rawPath);

      const dataOffset = offset + 512;
      const dataPadded = Math.ceil(fileSize / 512) * 512;
      const nextOffset = dataOffset + dataPadded;

      if (typeflag === 'L') {
        const buf = Buffer.allocUnsafe(fileSize);
        const read = await fd.read(buf, 0, fileSize, dataOffset).catch(() => ({ bytesRead: 0 }));
        const text = read && read.bytesRead > 0 ? buf.subarray(0, read.bytesRead).toString('utf8') : '';
        gnuLongName = _normalizeInnerPath(text.replace(/\0/g, '').trim());
        offset = nextOffset;
        continue;
      }

      if (typeflag === 'x') {
        const buf = Buffer.allocUnsafe(fileSize);
        const read = await fd.read(buf, 0, fileSize, dataOffset).catch(() => ({ bytesRead: 0 }));
        const text = read && read.bytesRead > 0 ? buf.subarray(0, read.bytesRead).toString('utf8') : '';
        const lines = text.split('\n');
        for (const line of lines) {
          const eq = line.indexOf(' path=');
          if (eq > 0) {
            const p = line.substring(eq + ' path='.length).trim();
            if (p) paxPath = _normalizeInnerPath(p);
          } else if (line.includes('path=')) {
            const idx = line.indexOf('path=');
            if (idx >= 0) {
              const p = line.substring(idx + 'path='.length).trim();
              if (p) paxPath = _normalizeInnerPath(p);
            }
          }
        }
        offset = nextOffset;
        continue;
      }

      let finalPath = basePath;
      if (gnuLongName) {
        finalPath = gnuLongName;
        gnuLongName = '';
      } else if (paxPath) {
        finalPath = paxPath;
        paxPath = '';
      }
      finalPath = _normalizeInnerPath(finalPath);
      if (!finalPath) {
        offset = nextOffset;
        continue;
      }

      const isDir = typeflag === '5' || finalPath.endsWith('/');
      const storedPath = isDir ? (finalPath.endsWith('/') ? finalPath : `${finalPath}/`) : finalPath;

      entries.push({ filename: storedPath });
      if (!isDir) {
        index.set(storedPath, { offset: dataOffset, size: fileSize });
      }

      offset = nextOffset;
    }
  } finally {
    await fd.close().catch(() => {});
  }

  const getSize = name => {
    const k = _normalizeInnerPath(name);
    const v = index.get(k) || index.get(`${k}`);
    return v ? Number(v.size || 0) || 0 : 0;
  };

  const loadUint8Array = async name => {
    const k = _normalizeInnerPath(name);
    const v = index.get(k);
    if (!v) return null;

    const maxEntryBytes = 500 * 1024 * 1024;
    const entrySize = Number(v.size || 0) || 0;
    if (entrySize <= 0 || entrySize > maxEntryBytes) return null;

    const fd2 = await fs.promises.open(filePath, 'r').catch(() => null);
    if (!fd2) return null;
    try {
      const buf = Buffer.allocUnsafe(entrySize);
      const { bytesRead } = await fd2.read(buf, 0, entrySize, v.offset);
      const out = bytesRead === buf.length ? buf : buf.subarray(0, bytesRead);
      return new Uint8Array(out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength));
    } finally {
      await fd2.close().catch(() => {});
    }
  };

  return { kind: 'tar', entries, loadText: null, loadBlob: null, loadUint8Array, getSize, close: () => {} };
}

const _archiveCache = new Map();

function _cleanupArchiveCache() {
  const now = Date.now();
  for (const [key, v] of _archiveCache.entries()) {
    if (!v || !v.expiresAt || v.expiresAt <= now) {
      try {
        v && v.loader && typeof v.loader.close === 'function' && v.loader.close();
      } catch (_) {}
      _archiveCache.delete(key);
    }
  }
}

async function _getArchiveLoader({ cacheKey, filePath }) {
  _cleanupArchiveCache();
  const key = String(cacheKey || '');
  const stat = await fs.promises.stat(filePath).catch(() => null);
  if (!stat || !stat.isFile()) return null;

  const existing = _archiveCache.get(key);
  if (existing && existing.filePath === filePath && existing.size === stat.size && existing.mtimeMs === stat.mtimeMs) {
    existing.expiresAt = Date.now() + 2 * 60 * 1000;
    return existing.loader;
  }

  if (existing) {
    try {
      existing.loader && typeof existing.loader.close === 'function' && existing.loader.close();
    } catch (_) {}
    _archiveCache.delete(key);
  }

  const ext = path.extname(filePath).toLowerCase();
  let loader = null;
  if (ext === '.cbz' || ext === '.zip') {
    loader = await _makeZipLoaderFromDisk(filePath).catch(() => null);
  } else if (ext === '.cbr' || ext === '.rar') {
    loader = await _makeRarLoaderFromDisk(filePath).catch(() => null);
  } else if (ext === '.tar') {
    loader = await _makeTarLoaderFromDisk(filePath).catch(() => null);
  }

  if (!loader) return null;

  _archiveCache.set(key, {
    filePath,
    size: stat.size,
    mtimeMs: stat.mtimeMs,
    expiresAt: Date.now() + 2 * 60 * 1000,
    loader,
  });
  return loader;
}

function _listEntries({ loader, onlyImg }) {
  const entries = loader && Array.isArray(loader.entries) ? loader.entries : [];
  const names = [];
  const seen = new Set();
  for (const e of entries) {
    const name = e && e.filename ? String(e.filename) : '';
    if (!name) continue;
    if (name.endsWith('/')) continue;
    if (onlyImg && !_isSupportedImageName(name)) continue;
    const lower = name.toLowerCase();
    if (seen.has(lower)) continue;
    seen.add(lower);
    names.push(name);
  }
  names.sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));
  return names.map(n => ({ path: n, size: Number(loader.getSize ? loader.getSize(n) : 0) || 0 }));
}

async function _readEntryBytes(loader, name) {
  if (!loader) return null;
  if (typeof loader.loadUint8Array === 'function') {
    const bytes = await loader.loadUint8Array(name);
    return bytes ? Buffer.from(bytes) : null;
  }
  if (typeof loader.loadBlob === 'function') {
    const blob = await loader.loadBlob(name, _mimeFromName(name));
    if (!blob) return null;
    const ab = await blob.arrayBuffer();
    return Buffer.from(new Uint8Array(ab));
  }
  return null;
}

class BookArchiveController {
  async listArchiveImages(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const fileHash = body.file_hash === undefined || body.file_hash === null ? '' : String(body.file_hash).trim();
      const filePathRaw = body.file_path === undefined || body.file_path === null ? '' : String(body.file_path).trim();
      const onlyImg = body.only_img === undefined ? true : !!body.only_img;
      if (!fileHash && !filePathRaw) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      let fullPath = '';
      let cacheKey = '';

      if (fileHash) {
        const indexRow = await req
          .dbBook('book_index')
          .where({ file_hash: fileHash, is_file: 1 })
          .first('id', 'path', 'filename', 'file_hash', 'type', 'ext')
          .catch(() => null);
        if (!indexRow) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

        const service = new BookListService(req.dbBook);
        const can = await service.canUserAccessIndex({ user, indexRow });
        if (!can) return ResponseUtil.forbidden(req, res);

        fullPath = path.join(String(indexRow.path), String(indexRow.filename));
        cacheKey = `hash:${fileHash}`;
      } else {
        fullPath = path.resolve(filePathRaw);
        const ok = await hasPermission(req.dbMain, user, ['download', 'view'], fullPath);
        if (!ok) return ResponseUtil.forbidden(req, res);
        cacheKey = `path:${fullPath}`;
      }

      const stat = await fs.promises.stat(fullPath).catch(() => null);
      if (!stat || !stat.isFile()) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const loader = await _getArchiveLoader({ cacheKey, filePath: fullPath });
      if (!loader) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const items = _listEntries({ loader, onlyImg });
      return ResponseUtil.success(req, res, { items, size: stat.size }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, 500);
    }
  }

  async getArchiveFile(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const fileHash = req.query && req.query.file_hash !== undefined && req.query.file_hash !== null ? String(req.query.file_hash).trim() : '';
      const filePathRaw = req.query && req.query.file_path !== undefined && req.query.file_path !== null ? String(req.query.file_path).trim() : '';
      const innerPath = req.query && req.query.inner_path !== undefined && req.query.inner_path !== null ? String(req.query.inner_path) : '';
      if ((!fileHash && !filePathRaw) || !innerPath) return res.status(404).end();

      let fullPath = '';
      let cacheKey = '';

      if (fileHash) {
        const indexRow = await req
          .dbBook('book_index')
          .where({ file_hash: fileHash, is_file: 1 })
          .first('id', 'path', 'filename', 'file_hash', 'type', 'ext')
          .catch(() => null);
        if (!indexRow) return res.status(404).end();

        const service = new BookListService(req.dbBook);
        const can = await service.canUserAccessIndex({ user, indexRow });
        if (!can) return res.status(403).end();

        fullPath = path.join(String(indexRow.path), String(indexRow.filename));
        cacheKey = `hash:${fileHash}`;
      } else {
        fullPath = path.resolve(filePathRaw);
        const ok = await hasPermission(req.dbMain, user, ['download', 'view'], fullPath);
        if (!ok) return res.status(403).end();
        cacheKey = `path:${fullPath}`;
      }

      const stat = await fs.promises.stat(fullPath).catch(() => null);
      if (!stat || !stat.isFile()) return res.status(404).end();

      const loader = await _getArchiveLoader({ cacheKey, filePath: fullPath });
      if (!loader) return res.status(404).end();

      const bytes = await _readEntryBytes(loader, innerPath);
      if (!bytes || bytes.length === 0) return res.status(404).end();

      res.setHeader('Content-Type', _mimeFromName(innerPath));
      res.setHeader('Cache-Control', 'private, max-age=3600');
      return res.status(200).send(bytes);
    } catch (_) {
      return res.status(404).end();
    }
  }
}

module.exports = new BookArchiveController();
