'use strict';

const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');
const config = require('../../config/config');
const Logger = require('../../utils/logger');

/** 将文件路径转为 file: URL，供动态 import() 使用（Node 要求传 URL 不能传裸路径） */
function toFileUrl(absolutePath) {
  return pathToFileURL(path.resolve(absolutePath)).href;
}

function _pickText(v) {
  if (v === undefined || v === null) return '';
  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return String(v).trim();
  if (Array.isArray(v)) {
    for (const item of v) {
      const t = _pickText(item);
      if (t) return t;
    }
    return '';
  }
  if (typeof v === 'object') {
    const keys = Object.keys(v);
    for (const k of keys) {
      const t = _pickText(v[k]);
      if (t) return t;
    }
    return '';
  }
  return '';
}

function _pickList(v) {
  if (v === undefined || v === null) return [];
  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
    const t = String(v).trim();
    return t ? [t] : [];
  }
  if (Array.isArray(v)) {
    const out = [];
    for (const item of v) {
      const t = _pickText(item);
      if (t) out.push(t);
    }
    return out;
  }
  if (typeof v === 'object') {
    const t = _pickText(v);
    return t ? [t] : [];
  }
  return [];
}

function _yearFromText(text) {
  const s = String(text || '').trim();
  if (!s) return '';
  const m = s.match(/\b(1[0-9]{3}|20[0-9]{2})\b/);
  return m ? String(m[1]) : '';
}

function _isbnFromText(text) {
  const s = String(text || '')
    .replace(/[^0-9Xx]/g, '')
    .trim();
  if (!s) return '';
  if (s.length === 10 || s.length === 13) return s.toUpperCase();
  return '';
}

function _stripTags(text) {
  return String(text || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function _decodeXmlEntities(text) {
  const s = String(text || '');
  if (!s) return '';
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .trim();
}

function _normalizeXmlValue(text) {
  return _decodeXmlEntities(_stripTags(text));
}

function _firstMatch(text, re) {
  const m = String(text || '').match(re);
  return m && m[1] !== undefined ? _normalizeXmlValue(m[1]) : '';
}

function _allMatches(text, re) {
  const s = String(text || '');
  const out = [];
  for (const m of s.matchAll(re)) {
    if (!m) continue;
    const v = m[1] !== undefined ? _normalizeXmlValue(m[1]) : '';
    if (v) out.push(v);
  }
  return out;
}

class DiskFile {
  constructor(filePath, stat) {
    this._filePath = filePath;
    this.name = path.basename(filePath);
    this.size = Number(stat && stat.size ? stat.size : 0) || 0;
    this.type = '';
  }

  slice(start = 0, end = undefined) {
    const s = Math.max(0, Number(start || 0) || 0);
    const e = end === undefined || end === null ? this.size : Math.min(this.size, Math.max(0, Number(end) || 0));
    return new DiskSlice(this._filePath, s, e);
  }

  async arrayBuffer() {
    return await this.slice(0, this.size).arrayBuffer();
  }
}

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

async function _toBuffer(value) {
  if (!value) return null;
  if (Buffer.isBuffer(value)) return value;
  if (value instanceof ArrayBuffer) return Buffer.from(new Uint8Array(value));
  if (ArrayBuffer.isView(value)) return Buffer.from(value.buffer, value.byteOffset, value.byteLength);
  if (value && typeof value === 'object' && typeof value.arrayBuffer === 'function') {
    const ab = await value.arrayBuffer();
    return Buffer.from(new Uint8Array(ab));
  }
  return null;
}

async function makeZipLoader(file, zipJsUrl) {
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
  return { entries, loadText, loadBlob, loadUint8Array, getSize, close: () => reader.close().catch(() => {}) };
}

async function makeRarLoader(filePath, stat) {
  const maxBytes = 300 * 1024 * 1024;
  const size = Number(stat && stat.size ? stat.size : 0) || 0;
  if (size <= 0 || size > maxBytes) return null;

  let buf;
  try {
    buf = await fs.promises.readFile(filePath);
  } catch (_) {
    return null;
  }
  if (!buf || buf.length === 0) return null;

  let unrar;
  try {
    unrar = require('node-unrar-js');
  } catch (_) {
    return null;
  }

  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  let extractor;
  try {
    extractor = await unrar.createExtractorFromData({ data: ab });
  } catch (_) {
    return null;
  }

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

  return { entries, loadText, loadBlob: null, loadUint8Array, getSize, close: () => {} };
}

function _findZipEntryName(loader, wantedLower) {
  const w = String(wantedLower || '').toLowerCase();
  if (!w) return '';
  const entries = loader && Array.isArray(loader.entries) ? loader.entries : [];
  for (const e of entries) {
    const name = e && e.filename ? String(e.filename) : '';
    if (name.toLowerCase() === w) return name;
  }
  for (const e of entries) {
    const name = e && e.filename ? String(e.filename) : '';
    const lower = name.toLowerCase();
    if (lower.endsWith(`/${w}`) || lower.endsWith(`\\${w}`)) return name;
  }
  return '';
}

function _isSupportedImageName(name) {
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
}

function _countComicPagesFromLoader(loader) {
  const entries = loader && Array.isArray(loader.entries) ? loader.entries : [];
  const set = new Set();
  for (const e of entries) {
    const name = e && e.filename ? String(e.filename) : '';
    if (!name) continue;
    if (!_isSupportedImageName(name)) continue;
    set.add(name.toLowerCase());
  }
  return set.size;
}

function _looksLikeImage(buf) {
  if (!buf || buf.length < 8) return false;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return true;
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return true;
  if (buf[0] === 0x47 && buf[1] === 0x49 && buf[2] === 0x46) return true;
  if (buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 && buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50) return true;
  if (buf[0] === 0x42 && buf[1] === 0x4d) return true;
  if ((buf[0] === 0x49 && buf[1] === 0x49 && buf[2] === 0x2a && buf[3] === 0x00) || (buf[0] === 0x4d && buf[1] === 0x4d && buf[2] === 0x00 && buf[3] === 0x2a)) return true;
  return false;
}

async function _extractFirstImageFromZip(loader) {
  if (!loader) return null;
  const entries = loader && Array.isArray(loader.entries) ? loader.entries : [];
  const candidates = entries
    .map(e => (e && e.filename ? String(e.filename) : ''))
    .filter(n => n && _isSupportedImageName(n))
    .sort();
  if (candidates.length === 0) return null;
  const name = candidates[0];

  try {
    if (typeof loader.loadUint8Array === 'function') {
      const bytes = await loader.loadUint8Array(name);
      if (!bytes) return null;
      return Buffer.from(bytes);
    }
  } catch (_) {}

  try {
    if (typeof loader.loadBlob === 'function') {
      const blob = await loader.loadBlob(name);
      return await _toBuffer(blob);
    }
  } catch (_) {}

  return null;
}

async function _extractEpubOpfFallback(loader) {
  if (!loader || typeof loader.loadText !== 'function') return {};
  let containerXml = '';
  try {
    const containerName = _findZipEntryName(loader, 'meta-inf/container.xml');
    if (!containerName) return {};
    containerXml = await loader.loadText(containerName);
  } catch (_) {
    return {};
  }

  const fullPath = _firstMatch(containerXml, /full-path\s*=\s*["']([^"']+)["']/i);
  if (!fullPath) return {};
  const normalizedFull = fullPath.replace(/^\/+/, '');

  let opfText = '';
  try {
    opfText = await loader.loadText(normalizedFull);
  } catch (_) {
    try {
      const opfName = _findZipEntryName(loader, normalizedFull.toLowerCase());
      if (opfName) opfText = await loader.loadText(opfName);
    } catch (_) {}
  }
  if (!opfText) return {};

  const title = _firstMatch(opfText, /<dc:title\b[^>]*>([\s\S]*?)<\/dc:title>/i) || _firstMatch(opfText, /<title\b[^>]*>([\s\S]*?)<\/title>/i);
  const creators = _allMatches(opfText, /<dc:creator\b[^>]*>([\s\S]*?)<\/dc:creator>/gi).concat(_allMatches(opfText, /<creator\b[^>]*>([\s\S]*?)<\/creator>/gi));
  const language = _firstMatch(opfText, /<dc:language\b[^>]*>([\s\S]*?)<\/dc:language>/i) || _firstMatch(opfText, /<language\b[^>]*>([\s\S]*?)<\/language>/i);
  const publisher = _firstMatch(opfText, /<dc:publisher\b[^>]*>([\s\S]*?)<\/dc:publisher>/i) || _firstMatch(opfText, /<publisher\b[^>]*>([\s\S]*?)<\/publisher>/i);
  const description = _firstMatch(opfText, /<dc:description\b[^>]*>([\s\S]*?)<\/dc:description>/i) || _firstMatch(opfText, /<description\b[^>]*>([\s\S]*?)<\/description>/i);
  const publishDate = _firstMatch(opfText, /<dc:date\b[^>]*>([\s\S]*?)<\/dc:date>/i) || _firstMatch(opfText, /<date\b[^>]*>([\s\S]*?)<\/date>/i);
  const subjects = _allMatches(opfText, /<dc:subject\b[^>]*>([\s\S]*?)<\/dc:subject>/gi).concat(_allMatches(opfText, /<subject\b[^>]*>([\s\S]*?)<\/subject>/gi));
  const identifier = _firstMatch(opfText, /<dc:identifier\b[^>]*>([\s\S]*?)<\/dc:identifier>/i) || _firstMatch(opfText, /<identifier\b[^>]*>([\s\S]*?)<\/identifier>/i);

  return {
    title,
    authors: creators,
    language,
    publisher,
    description,
    publishDate,
    subjects,
    identifier,
  };
}

async function _extractEpubCoverFallback(loader) {
  if (!loader || typeof loader.loadText !== 'function') return null;

  let containerXml = '';
  try {
    const containerName = _findZipEntryName(loader, 'meta-inf/container.xml');
    if (!containerName) return null;
    containerXml = await loader.loadText(containerName);
  } catch (_) {
    return null;
  }

  const fullPath = _firstMatch(containerXml, /full-path\s*=\s*["']([^"']+)["']/i);
  if (!fullPath) return null;
  const normalizedFull = fullPath.replace(/^\/+/, '');

  let opfText = '';
  try {
    opfText = await loader.loadText(normalizedFull);
  } catch (_) {
    try {
      const opfName = _findZipEntryName(loader, normalizedFull.toLowerCase());
      if (opfName) opfText = await loader.loadText(opfName);
    } catch (_) {}
  }
  if (!opfText) return null;

  const getAttr = (tag, attr) => {
    const re = new RegExp(`${attr}\\s*=\\s*["']([^"']+)["']`, 'i');
    return _firstMatch(tag, re);
  };

  let href = '';
  const coverItemWithProp = opfText.match(/<item\b[^>]*\bproperties\s*=\s*["'][^"']*\bcover-image\b[^"']*["'][^>]*>/i);
  if (coverItemWithProp && coverItemWithProp[0]) {
    href = getAttr(coverItemWithProp[0], 'href');
  }

  if (!href) {
    const coverId = _firstMatch(opfText, /<meta\b[^>]*\bname\s*=\s*["']cover["'][^>]*\bcontent\s*=\s*["']([^"']+)["'][^>]*\/?>/i);
    if (coverId) {
      const itemRe = new RegExp(`<item\\b[^>]*\\bid\\s*=\\s*["']${coverId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}["'][^>]*>`, 'i');
      const item = opfText.match(itemRe);
      if (item && item[0]) href = getAttr(item[0], 'href');
    }
  }

  if (!href) return null;
  href = _decodeXmlEntities(href).split('#')[0].split('?')[0];
  href = href.replace(/^\/+/, '');
  if (!href) return null;

  const baseDir = path.posix.dirname(normalizedFull.replace(/\\/g, '/'));
  const full = path.posix.normalize(path.posix.join(baseDir === '.' ? '' : baseDir, href));
  const entryName = _findZipEntryName(loader, full.toLowerCase()) || full;

  try {
    if (typeof loader.loadUint8Array === 'function') {
      const bytes = await loader.loadUint8Array(entryName);
      if (bytes) return Buffer.from(bytes);
    }
  } catch (_) {}

  try {
    if (typeof loader.loadBlob === 'function') {
      const blob = await loader.loadBlob(entryName);
      return await _toBuffer(blob);
    }
  } catch (_) {}

  return null;
}

async function _extractComicInfoFallback(loader) {
  if (!loader || typeof loader.loadText !== 'function') return {};
  const entries = loader && Array.isArray(loader.entries) ? loader.entries : [];
  let comicInfoName = '';
  for (const e of entries) {
    const name = e && e.filename ? String(e.filename) : '';
    if (name && name.toLowerCase().endsWith('comicinfo.xml')) {
      comicInfoName = name;
      break;
    }
  }
  if (!comicInfoName) return {};

  let xml = '';
  try {
    xml = await loader.loadText(comicInfoName);
  } catch (_) {
    return {};
  }
  if (!xml) return {};

  const title = _firstMatch(xml, /<Title\b[^>]*>([\s\S]*?)<\/Title>/i);
  const writer = _firstMatch(xml, /<Writer\b[^>]*>([\s\S]*?)<\/Writer>/i);
  const penciller = _firstMatch(xml, /<Penciller\b[^>]*>([\s\S]*?)<\/Penciller>/i);
  const inker = _firstMatch(xml, /<Inker\b[^>]*>([\s\S]*?)<\/Inker>/i);
  const authors = [writer, penciller, inker].filter(Boolean);
  const language = _firstMatch(xml, /<LanguageISO\b[^>]*>([\s\S]*?)<\/LanguageISO>/i);
  const publisher = _firstMatch(xml, /<Publisher\b[^>]*>([\s\S]*?)<\/Publisher>/i);
  const description = _firstMatch(xml, /<Summary\b[^>]*>([\s\S]*?)<\/Summary>/i);
  const publishDate = _firstMatch(xml, /<(?:Year|Date)\b[^>]*>([\s\S]*?)<\/(?:Year|Date)>/i);
  const genre = _firstMatch(xml, /<Genre\b[^>]*>([\s\S]*?)<\/Genre>/i);
  const tags = _firstMatch(xml, /<Tags\b[^>]*>([\s\S]*?)<\/Tags>/i);
  const isbn = _firstMatch(xml, /<ISBN\b[^>]*>([\s\S]*?)<\/ISBN>/i);

  return {
    title,
    authors,
    language,
    publisher,
    description,
    publishDate,
    genre,
    tag: tags,
    isbn: _isbnFromText(isbn),
  };
}

async function extractMetadata(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const defaultTitle = path.parse(filePath).name || path.basename(filePath);
  let stat;
  try {
    stat = await fs.promises.stat(filePath);
  } catch (_) {
    return { ok: false, error: 'file_not_found' };
  }
  if (!stat.isFile()) return { ok: false, error: 'not_a_file' };

  const foliateRoot = typeof globalThis.__foliateRoot === 'string' && globalThis.__foliateRoot ? path.resolve(globalThis.__foliateRoot) : config.getFoliateRootPath();
  const zipJsUrl = toFileUrl(path.join(foliateRoot, 'vendor', 'zip.js'));
  const epubUrl = toFileUrl(path.join(foliateRoot, 'epub.js'));
  const mobiUrl = toFileUrl(path.join(foliateRoot, 'mobi.js'));
  const fflateUrl = toFileUrl(path.join(foliateRoot, 'vendor', 'fflate.js'));

  globalThis.self = globalThis;
  if (!globalThis.document) {
    const decodeHtml = input => {
      let s = String(input || '');
      if (!s) return '';
      s = s
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&nbsp;/g, ' ');
      s = s.replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => {
        const code = parseInt(hex, 16);
        if (!Number.isFinite(code)) return '';
        try {
          return String.fromCodePoint(code);
        } catch (_) {
          return '';
        }
      });
      s = s.replace(/&#([0-9]+);/g, (_, num) => {
        const code = parseInt(num, 10);
        if (!Number.isFinite(code)) return '';
        try {
          return String.fromCodePoint(code);
        } catch (_) {
          return '';
        }
      });
      return s;
    };
    globalThis.document = {
      createElement: () => {
        let _html = '';
        return {
          set innerHTML(v) {
            _html = String(v || '');
          },
          get value() {
            return decodeHtml(_html);
          },
        };
      },
    };
  }

  try {
    const xmldom = require('@xmldom/xmldom');
    if (xmldom && xmldom.DOMParser) {
      const QuietDOMParser = function (options = {}) {
        const baseOptions = options && typeof options === 'object' ? options : {};
        const errorHandler =
          baseOptions.errorHandler && typeof baseOptions.errorHandler === 'object'
            ? {
                warning: () => {},
                error: () => {},
                fatalError: () => {},
                ...baseOptions.errorHandler,
              }
            : { warning: () => {}, error: () => {}, fatalError: () => {} };
        return new xmldom.DOMParser({ ...baseOptions, errorHandler });
      };
      globalThis.DOMParser = QuietDOMParser;
    }
    if (xmldom && xmldom.XMLSerializer) globalThis.XMLSerializer = xmldom.XMLSerializer;
  } catch (_) {}

  const file = new DiskFile(filePath, stat);
  let book = null;
  let cleanup = null;
  let zipLoader = null;
  let rarLoader = null;

  if (ext === '.epub' || ext === '.cbz' || ext === '.zip') {
    zipLoader = await makeZipLoader(file, zipJsUrl);
    cleanup = zipLoader && typeof zipLoader.close === 'function' ? zipLoader.close : null;
    if (ext === '.epub') {
      const { EPUB } = await import(epubUrl);
      try {
        book = await new EPUB(zipLoader).init();
      } catch (_) {
        book = null;
      }
    } else if (ext === '.zip') {
      try {
        const { EPUB } = await import(epubUrl);
        book = await new EPUB(zipLoader).init();
      } catch (_) {
        book = null;
      }
    }
  } else if (ext === '.mobi' || ext === '.azw3' || ext === '.azw') {
    try {
      const { isMOBI, MOBI } = await import(mobiUrl);
      const fflate = await import(fflateUrl);
      try {
        if (typeof isMOBI === 'function') await isMOBI(file);
      } catch (_) {}

      const openWith = async f => await new MOBI({ unzlib: fflate.unzlibSync }).open(f);
      try {
        book = await openWith(file);
      } catch (_) {
        const makeMemoryFile = buffer => {
          const b = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer || []);
          const size = b.length;
          return {
            name: path.basename(filePath),
            size,
            type: '',
            slice: (start = 0, end = undefined) => {
              const s = Math.max(0, Number(start || 0) || 0);
              const e = end === undefined || end === null ? size : Math.min(size, Math.max(0, Number(end) || 0));
              return {
                size: Math.max(0, e - s),
                type: '',
                slice: (subStart = 0, subEnd = undefined) => {
                  const ss = Math.max(0, Number(subStart || 0) || 0);
                  const ee = subEnd === undefined || subEnd === null ? e - s : Math.max(0, Number(subEnd || 0) || 0);
                  return {
                    size: Math.max(0, Math.min(e, s + ee) - (s + ss)),
                    type: '',
                    arrayBuffer: async () => {
                      const start2 = s + ss;
                      const end2 = Math.min(e, s + ee);
                      const sub = b.subarray(start2, end2);
                      return sub.buffer.slice(sub.byteOffset, sub.byteOffset + sub.byteLength);
                    },
                  };
                },
                arrayBuffer: async () => {
                  const sub = b.subarray(s, e);
                  return sub.buffer.slice(sub.byteOffset, sub.byteOffset + sub.byteLength);
                },
              };
            },
            arrayBuffer: async () => {
              return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
            },
          };
        };

        try {
          const raw = await fs.promises.readFile(filePath);
          book = await openWith(makeMemoryFile(raw));
        } catch (_) {
          book = null;
        }
      }
    } catch (mobiErr) {
      Logger.warn('bookMetaExtractWorker mobi/fflate import failed', mobiErr && mobiErr.message ? mobiErr.message : mobiErr, { mobiUrl, foliateRoot });
      book = null;
    }
  } else if (ext === '.cbr' || ext === '.rar') {
    rarLoader = await makeRarLoader(filePath, stat);
  } else {
    return { ok: false, error: 'unsupported_ext' };
  }

  const metadata = (book && book.metadata && typeof book.metadata === 'object' ? book.metadata : {}) || {};

  let title = _pickText(metadata.title);
  let authorList = _pickList(metadata.author);
  let author = authorList.length > 0 ? authorList.join('; ') : '';
  let language = _pickText(metadata.language);
  let publisher = _pickText(metadata.publisher);
  let description = _pickText(metadata.description);
  let publishDate = _pickText(metadata.published || metadata.date);
  let year = _yearFromText(publishDate);

  let subjects = _pickList(metadata.subject);
  let tag = subjects.length > 0 ? subjects.join('; ') : '';
  let genre = subjects.length > 0 ? subjects[0] : '';

  let identifier = _pickText(metadata.identifier);
  let isbn = _isbnFromText(identifier);

  const comicLoader = zipLoader || rarLoader;
  if (comicLoader && (ext === '.cbz' || ext === '.zip' || ext === '.cbr' || ext === '.rar')) {
    const comicInfo = await _extractComicInfoFallback(comicLoader);
    if (comicInfo && typeof comicInfo === 'object') {
      title = title || _pickText(comicInfo.title);
      const authors = Array.isArray(comicInfo.authors) ? comicInfo.authors : [];
      if (!author && authors.length > 0) author = authors.join('; ');
      language = language || _pickText(comicInfo.language);
      publisher = publisher || _pickText(comicInfo.publisher);
      description = description || _pickText(comicInfo.description);
      publishDate = publishDate || _pickText(comicInfo.publishDate);
      year = year || _yearFromText(publishDate);
      genre = genre || _pickText(comicInfo.genre);
      tag = tag || _pickText(comicInfo.tag);
      isbn = isbn || _pickText(comicInfo.isbn);
    }
  }

  if (zipLoader && (ext === '.epub' || ext === '.zip') && !title) {
    const opf = await _extractEpubOpfFallback(zipLoader);
    if (opf && typeof opf === 'object') {
      title = title || _pickText(opf.title);
      if (!author) {
        const authors = Array.isArray(opf.authors) ? opf.authors : [];
        authorList = authorList.length > 0 ? authorList : authors;
        author = authorList.length > 0 ? authorList.join('; ') : '';
      }
      language = language || _pickText(opf.language);
      publisher = publisher || _pickText(opf.publisher);
      description = description || _pickText(opf.description);
      publishDate = publishDate || _pickText(opf.publishDate);
      year = year || _yearFromText(publishDate);
      if (!tag || !genre) {
        const ss = Array.isArray(opf.subjects) ? opf.subjects : [];
        if (subjects.length === 0) subjects = ss;
        if (!tag && ss.length > 0) tag = ss.join('; ');
        if (!genre && ss.length > 0) genre = ss[0];
      }
      if (!isbn) {
        identifier = identifier || _pickText(opf.identifier);
        isbn = _isbnFromText(identifier);
      }
    }
  }

  title = title || defaultTitle;

  let coverBuffer = null;
  try {
    if (book && typeof book.getCover === 'function') {
      const cover = await book.getCover();
      coverBuffer = await _toBuffer(cover);
      const maxBytes = 50 * 1024 * 1024;
      if (coverBuffer && coverBuffer.length > maxBytes) coverBuffer = null;
      if (coverBuffer && !_looksLikeImage(coverBuffer)) coverBuffer = null;
    }
  } catch (_) {}

  if (!coverBuffer && (ext === '.mobi' || ext === '.azw3' || ext === '.azw')) {
    const mobi = book && book.mobi ? book.mobi : null;
    const numRecords = mobi && mobi.pdb && mobi.pdb.numRecords ? Number(mobi.pdb.numRecords || 0) || 0 : 0;
    const resourceStart = mobi && mobi.headers && mobi.headers.mobi && mobi.headers.mobi.resourceStart !== undefined ? Number(mobi.headers.mobi.resourceStart || 0) || 0 : 0;
    if (mobi && typeof mobi.loadResource === 'function' && numRecords > 0 && resourceStart > 0 && resourceStart < numRecords) {
      const maxBytes = 50 * 1024 * 1024;
      const maxScan = Math.min(512, Math.max(0, numRecords - resourceStart));
      let best = null;
      for (let i = 0; i < maxScan; i += 1) {
        let raw;
        try {
          raw = await mobi.loadResource(i);
        } catch (_) {
          break;
        }
        const b = Buffer.from(new Uint8Array(raw));
        if (b.length === 0 || b.length > maxBytes) continue;
        if (!_looksLikeImage(b)) continue;
        if (!best || b.length > best.length) best = b;
      }
      if (best) coverBuffer = best;
    }
  }

  if (!coverBuffer && zipLoader && (ext === '.epub' || (ext === '.zip' && book))) {
    try {
      const buf = await _extractEpubCoverFallback(zipLoader);
      const maxBytes = 50 * 1024 * 1024;
      if (buf && buf.length <= maxBytes) coverBuffer = buf;
    } catch (_) {}
  }

  if (!coverBuffer && zipLoader && (ext === '.cbz' || ext === '.zip')) {
    try {
      const buf = await _extractFirstImageFromZip(zipLoader);
      const maxBytes = 50 * 1024 * 1024;
      if (buf && buf.length <= maxBytes) coverBuffer = buf;
    } catch (_) {}
  }

  if (!coverBuffer && rarLoader && (ext === '.cbr' || ext === '.rar')) {
    try {
      const buf = await _extractFirstImageFromZip(rarLoader);
      const maxBytes = 50 * 1024 * 1024;
      if (buf && buf.length <= maxBytes) coverBuffer = buf;
    } catch (_) {}
  }

  try {
    if (book && typeof book.destroy === 'function') book.destroy();
  } catch (_) {}
  if (cleanup) await cleanup();

  let totalPage = 0;
  try {
    const isComicArchive = ext === '.cbz' || ext === '.cbr' || ext === '.rar' || (ext === '.zip' && !book);
    if (isComicArchive) {
      totalPage = _countComicPagesFromLoader(comicLoader);
    }
  } catch (_) {
    totalPage = 0;
  }

  return {
    ok: true,
    data: {
      title,
      author,
      language,
      publisher,
      description,
      publishDate,
      year,
      genre,
      tag,
      isbn,
      coverBuffer,
      totalPage,
    },
  };
}

function sendResult(data) {
  return new Promise(resolve => {
    if (typeof process.send !== 'function') return resolve(false);
    try {
      process.send({ type: 'result', data }, err => resolve(!err));
    } catch (_) {
      resolve(false);
    }
  });
}

async function main(message) {
  const filePath = message && message.data && message.data.filePath ? String(message.data.filePath) : '';
  if (message && message.data && typeof message.data.foliateRoot === 'string') {
    globalThis.__foliateRoot = message.data.foliateRoot;
  }
  if (!filePath) {
    await sendResult({ ok: false, error: 'invalid_file_path' });
    process.exitCode = 1;
    return;
  }

  try {
    const res = await extractMetadata(filePath);
    await sendResult(res);
    process.exitCode = res && res.ok ? 0 : 1;
  } catch (err) {
    Logger.error('❌ bookMetaExtractWorker failed', err && err.message ? err.message : err);
    await sendResult({ ok: false, error: err && err.message ? String(err.message) : String(err) });
    process.exitCode = 1;
  }
}

async function mainCover(message) {
  if (message && message.data && typeof message.data.foliateRoot === 'string') {
    globalThis.__foliateRoot = message.data.foliateRoot;
  }
  const filePath = message && message.data && message.data.filePath ? String(message.data.filePath) : '';
  if (!filePath) {
    await sendResult({ ok: false, error: 'invalid_file_path' });
    process.exitCode = 1;
    return;
  }

  try {
    const res = await extractMetadata(filePath);
    const coverBuffer = res && res.ok && res.data ? res.data.coverBuffer : null;
    await sendResult({ ok: true, coverBuffer });
    process.exitCode = 0;
  } catch (err) {
    Logger.error('❌ bookMetaExtractWorker cover failed', err && err.message ? err.message : err);
    await sendResult({ ok: false, error: err && err.message ? String(err.message) : String(err) });
    process.exitCode = 1;
  }
}

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'stop') {
    process.exit(0);
    return;
  }
  if (message.type === 'extract') return main(message);
  if (message.type === 'extract_cover') return mainCover(message);
});

process.on('uncaughtException', err => {
  Logger.error('❌ bookMetaExtractWorker uncaughtException', err);
  process.exit(1);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ bookMetaExtractWorker unhandledRejection', reason);
  process.exit(1);
});
