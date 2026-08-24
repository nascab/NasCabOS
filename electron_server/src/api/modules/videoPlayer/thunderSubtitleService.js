const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const fsExtra = require('fs-extra');
const { spawnSync } = require('node:child_process');

const config = require('../../../config/config');
const FileUtil = require('../../../utils/fileUtil');

const CID_CHUNK_SIZE = 0x5000; // 20480
const CID_SMALL_FILE_LIMIT = 0xf000; // 61440

function _bufSwap16(buf) {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf || []);
  const out = Buffer.allocUnsafe(b.length);
  for (let i = 0; i + 1 < b.length; i += 2) {
    out[i] = b[i + 1];
    out[i + 1] = b[i];
  }
  if (b.length % 2 === 1) out[b.length - 1] = b[b.length - 1];
  return out;
}

function _utf8HasReplacementChar(s) {
  return typeof s === 'string' && s.includes('\uFFFD');
}

function _looksUtf16WithoutBom(buf) {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf || []);
  const len = Math.min(b.length, 4096);
  if (len < 32) return null;
  let evenNull = 0;
  let oddNull = 0;
  for (let i = 0; i < len; i += 1) {
    if (b[i] !== 0x00) continue;
    if (i % 2 === 0) evenNull += 1;
    else oddNull += 1;
  }
  const totalPairs = Math.floor(len / 2) || 1;
  const evenRate = evenNull / totalPairs;
  const oddRate = oddNull / totalPairs;
  if (oddRate > 0.35 && evenRate < 0.1) return 'utf16le';
  if (evenRate > 0.35 && oddRate < 0.1) return 'utf16be';
  return null;
}

function _tryIconvToUtf8({ inputPath, fromEncoding }) {
  const enc = String(fromEncoding || '').trim();
  const inPath = String(inputPath || '').trim();
  if (!enc || !inPath) return null;
  if (process.platform === 'win32') return null;
  const iconv = fs.existsSync('/usr/bin/iconv') ? '/usr/bin/iconv' : 'iconv';
  const r = spawnSync(iconv, ['-f', enc, '-t', 'utf-8', inPath], {
    encoding: 'buffer',
    maxBuffer: 32 * 1024 * 1024,
  });
  if (!r || r.status !== 0 || !r.stdout || r.stdout.length === 0) return null;
  return r.stdout;
}

/**
 * Subtitles from some sources are UTF-16 ("Unicode") and can break downstream ffmpeg muxing.
 * Best-effort:
 * - if BOM indicates UTF-16, rewrite file content to UTF-8 in-place.
 * - if not valid UTF-8, try iconv from common encodings (GB18030/GBK/Big5) into UTF-8.
 */
async function _rewriteSrtUtf16ToUtf8InPlace(filePath) {
  const p = String(filePath || '').trim();
  if (!p) return false;
  const ext = path.extname(p).toLowerCase();
  if (ext !== '.srt') return false;

  try {
    const raw = await fs.promises.readFile(p);
    if (!raw || raw.length < 2) return false;

    const b0 = raw[0];
    const b1 = raw[1];
    const isBomUtf16Le = b0 === 0xff && b1 === 0xfe;
    const isBomUtf16Be = b0 === 0xfe && b1 === 0xff;
    const assumedUtf16 = isBomUtf16Le ? 'utf16le' : isBomUtf16Be ? 'utf16be' : _looksUtf16WithoutBom(raw);

    if (assumedUtf16) {
      let body = raw;
      if (isBomUtf16Le || isBomUtf16Be) body = raw.subarray(2); // drop BOM
      if (assumedUtf16 === 'utf16be') body = _bufSwap16(body);
      const text = body.toString('utf16le');
      await fs.promises.writeFile(p, Buffer.from(text, 'utf8'));
      return true;
    }

    // Not UTF-16: if invalid UTF-8, try iconv from common encodings.
    const decodedUtf8 = raw.toString('utf8');
    if (!_utf8HasReplacementChar(decodedUtf8)) return false;
    const encCandidates = ['gb18030', 'gbk', 'big5'];
    for (const enc of encCandidates) {
      const outBuf = _tryIconvToUtf8({ inputPath: p, fromEncoding: enc });
      if (outBuf) {
        await fs.promises.writeFile(p, outBuf);
        return true;
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

function cidHashFile(filePath) {
  const stat = fs.statSync(filePath);
  const size = stat.size;

  const h = crypto.createHash('sha1');
  const fd = fs.openSync(filePath, 'r');
  try {
    if (size < CID_SMALL_FILE_LIMIT) {
      const buf = Buffer.allocUnsafe(size);
      const bytesRead = fs.readSync(fd, buf, 0, size, 0);
      h.update(buf.subarray(0, bytesRead));
    } else {
      const buf1 = Buffer.allocUnsafe(CID_CHUNK_SIZE);
      const n1 = fs.readSync(fd, buf1, 0, CID_CHUNK_SIZE, 0);
      h.update(buf1.subarray(0, n1));

      const midPos = Math.floor(size / 3);
      const buf2 = Buffer.allocUnsafe(CID_CHUNK_SIZE);
      const n2 = fs.readSync(fd, buf2, 0, CID_CHUNK_SIZE, midPos);
      h.update(buf2.subarray(0, n2));

      const tailPos = Math.max(0, size - CID_CHUNK_SIZE);
      const buf3 = Buffer.allocUnsafe(CID_CHUNK_SIZE);
      const n3 = fs.readSync(fd, buf3, 0, CID_CHUNK_SIZE, tailPos);
      h.update(buf3.subarray(0, n3));
    }
  } finally {
    fs.closeSync(fd);
  }

  return h.digest('hex').toUpperCase();
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchJson(url, { timeoutMs = 15000 } = {}) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) {
      const err = new Error(`HTTP ${res.status} fetching ${url}`);
      err.status = res.status;
      throw err;
    }
    return await res.json();
  } finally {
    clearTimeout(t);
  }
}

async function getSubInfoList(cid, maxRetryTimes = 15, opts = {}) {
  const url = `http://sub.xmp.sandai.net:8000/subxl/${cid}.json`;
  const { timeoutMs = 15000, retryDelayMs = 400 } = opts;

  const max = Number.isFinite(maxRetryTimes) ? Math.max(1, Math.floor(maxRetryTimes)) : 15;
  for (let i = 0; i < max; i++) {
    try {
      const data = await fetchJson(url, { timeoutMs });
      const list = Array.isArray(data && data.sublist) ? data.sublist : [];
      return list.filter(Boolean);
    } catch (e) {
      if (i < max - 1) await sleep(retryDelayMs);
    }
  }
  return null;
}

function _inferExtFromUrl(url) {
  const raw = String(url || '').trim();
  if (!raw) return '';
  try {
    const u = new URL(raw);
    const ext = path.extname(u.pathname || '').toLowerCase();
    return ext.startsWith('.') ? ext.slice(1) : ext;
  } catch (_) {
    const ext = path.extname(raw).toLowerCase();
    return ext.startsWith('.') ? ext.slice(1) : ext;
  }
}

function _safeFilename(input, fallbackBase = 'subtitle') {
  let raw = String(input || '').trim();
  if (!raw) raw = fallbackBase;

  // Try decodeURIComponent for Thunder-style percent-encoded paths.
  // e.g. "D%3A%5Cxxx%5Cname" -> "D:\\xxx\\name"
  // Do best-effort multi-pass decode.
  for (let i = 0; i < 2; i += 1) {
    if (!/%[0-9A-Fa-f]{2}/.test(raw)) break;
    try {
      raw = decodeURIComponent(raw);
    } catch (_) {
      break;
    }
  }

  // Normalize possible Windows path -> keep basename only.
  const normalized = raw.replace(/\\/g, '/');
  const base = path.posix.basename(normalized) || fallbackBase;
  return path
    .basename(base)
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 180);
}

function _pickFinalFilename({ sname, surl }) {
  const name = _safeFilename(sname, 'subtitle');
  const extFromUrl = _inferExtFromUrl(surl) || 'srt';
  const existingExt = path.extname(name).toLowerCase();
  if (existingExt) return name;
  return `${name}.${extFromUrl}`;
}

function _truncateFilenameForWindows({ dir, filename }) {
  if (process.platform !== 'win32') return filename;
  const d = String(dir || '').trim();
  const f = String(filename || '').trim();
  if (!f) return f;

  const ext = path.extname(f);
  const base = path.basename(f, ext);

  // Conservative: keep full path under ~240 chars (classic MAX_PATH safe zone)
  const maxFullPath = 240;
  const overhead = (d ? d.length + 1 : 0) + ext.length;
  const maxBaseCharsByPath = Math.max(24, maxFullPath - overhead);
  const maxBaseChars = Math.min(180, maxBaseCharsByPath);

  const chars = [...base];
  if (chars.length <= maxBaseChars) return f;

  // 超出时自动截取后面：保留前面，截断尾部，并保留扩展名
  const truncatedBase = chars.slice(0, maxBaseChars).join('').trim();
  const safeBase = truncatedBase || 'subtitle';
  return `${safeBase}${ext}`;
}

async function searchSubtitlesByMovieFile(movieFilePath, opts = {}) {
  const resolved = path.resolve(String(movieFilePath || '').trim());
  if (!resolved) return null;
  if (!fs.existsSync(resolved)) return null;
  const st = fs.statSync(resolved);
  if (!st.isFile()) return null;

  const cid = cidHashFile(resolved);
  const list = await getSubInfoList(cid, 15, opts);
  if (!list) return null;

  const normalized = list
    .map(x => {
      const sname = String(x && x.sname ? x.sname : '').trim();
      const displayName = _safeFilename(sname, 'subtitle');
      const language = String(x && x.language ? x.language : '').trim();
      const surl = String(x && x.surl ? x.surl : '').trim();
      const ext = _inferExtFromUrl(surl) || path.extname(sname).replace('.', '').toLowerCase() || '';
      const rate = String(x && x.rate != null ? x.rate : '').trim();
      const votes = String(x && x.svote != null ? x.svote : '').trim();
      if (!surl) return null;
      return {
        sname,
        displayName,
        language,
        surl,
        ext,
        rate,
        votes,
      };
    })
    .filter(Boolean);

  const toNum = v => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  };
  normalized.sort((a, b) => {
    const bv = toNum(b.votes);
    const av = toNum(a.votes);
    if (bv !== av) return bv - av;
    const br = toNum(b.rate);
    const ar = toNum(a.rate);
    if (br !== ar) return br - ar;
    return String(b.displayName || b.sname || '').localeCompare(String(a.displayName || a.sname || ''));
  });
  return normalized;
}

async function searchSubtitlesByKeyword(keyword, opts = {}) {
  const q = String(keyword || '').trim();
  if (!q) return null;
  const { timeoutMs = 15000 } = opts;
  const url = `https://api-shoulei-ssl.xunlei.com/oracle/subtitle?name=${encodeURIComponent(q)}`;
  const resp = await fetchJson(url, { timeoutMs }).catch(() => null);
  const code = resp && resp.code !== undefined ? Number(resp.code) : NaN;
  const data = resp && Array.isArray(resp.data) ? resp.data : [];
  if (!Number.isFinite(code) || code !== 0) return [];

  const normalized = (data || [])
    .filter(Boolean)
    .map(x => {
      const surl = String(x && x.url ? x.url : '').trim();
      if (!surl) return null;
      const sname = String(x && x.name ? x.name : '').trim();
      const displayName = _safeFilename(sname, 'subtitle');
      const ext = String(x && x.ext ? x.ext : '').trim().toLowerCase() || _inferExtFromUrl(surl) || '';
      const languages = x && Array.isArray(x.languages) ? x.languages : [];
      const language = languages && languages.length ? String(languages[0] || '').trim() : '';
      return {
        sname,
        displayName,
        language,
        surl,
        ext,
        // keep extra fields for potential future UI sorting / display
        cid: x && x.cid ? String(x.cid).trim() : '',
        gcid: x && x.gcid ? String(x.gcid).trim() : '',
        score: x && x.score != null ? String(x.score).trim() : '',
        source: 'keyword',
      };
    })
    .filter(Boolean);

  return normalized;
}

async function downloadSubtitleToUploadDir({ uid, filePath, subtitle }) {
  const userId = Number(uid);
  if (!Number.isFinite(userId) || userId <= 0) throw new Error('Invalid uid');
  const videoPath = path.resolve(String(filePath || '').trim());
  if (!videoPath) throw new Error('Invalid filePath');
  const okVideo = fs.existsSync(videoPath) && fs.statSync(videoPath).isFile();
  if (!okVideo) throw new Error('Video file not found');

  const surl = String(subtitle && subtitle.surl ? subtitle.surl : '').trim();
  if (!surl) throw new Error('Invalid subtitle url');

  const videoHash = await FileUtil.getFileHash(videoPath);
  if (!videoHash) throw new Error('Invalid video hash');

  const baseDir = config.getSubtitleUploadPath();
  const targetDir = path.join(baseDir, String(videoHash), String(userId));

  let finalName = _pickFinalFilename({
    sname: subtitle && subtitle.sname ? subtitle.sname : '',
    surl,
  });
  finalName = _truncateFilenameForWindows({ dir: targetDir, filename: finalName });
  const finalExt = path.extname(finalName).toLowerCase();
  const base = path.basename(finalName, finalExt);

  // resolve name conflict
  let finalPath = path.join(targetDir, finalName);
  for (let i = 1; i <= 50; i++) {
    if (!fs.existsSync(finalPath)) break;
    finalPath = path.join(targetDir, `${base}_${i}${finalExt}`);
  }

  const tmpName = `.downloadTmp_${Date.now()}_${Math.random().toString(16).slice(2)}.tmp`;
  const tmpPath = path.join(targetDir, tmpName);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const resp = await fetch(surl, { method: 'GET', signal: controller.signal });
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status} downloading subtitle`);
    }
    const ab = await resp.arrayBuffer();
    const buf = Buffer.from(ab);
    if (!buf || buf.length === 0) throw new Error('Empty subtitle file');

    // OSS may return XML error payload with HTTP 200
    try {
      const head = buf.subarray(0, Math.min(buf.length, 4096)).toString('utf8');
      const contentType = String(resp.headers && resp.headers.get ? resp.headers.get('content-type') : '').toLowerCase();
      const looksXml = contentType.includes('xml') || head.startsWith('<?xml') || head.includes('<Error>');
      if (looksXml && (head.includes('<Code>NoSuchKey</Code>') || (head.includes('NoSuchKey') && head.includes('<Error>')))) {
        const err = new Error('SUBTITLE_NO_SUCH_KEY');
        err.code = 'SUBTITLE_NO_SUCH_KEY';
        throw err;
      }
    } catch (e) {
      if (e && e.code === 'SUBTITLE_NO_SUCH_KEY') throw e;
    }

    await fsExtra.ensureDir(targetDir);
    await fs.promises.writeFile(tmpPath, buf);
    await fsExtra.move(tmpPath, finalPath, { overwrite: false });
  } finally {
    clearTimeout(timer);
    try {
      if (fs.existsSync(tmpPath)) await fs.promises.rm(tmpPath, { force: true });
    } catch (_) {}
  }

  // Ensure final file exists (avoid false-positive success)
  try {
    const st = await fs.promises.stat(finalPath);
    if (!st.isFile() || st.size <= 0) {
      throw new Error('Downloaded subtitle is empty');
    }
  } catch (e) {
    throw new Error(`Subtitle save failed: ${e && e.message ? e.message : 'unknown'}`);
  }

  // Normalize encoding at source: rewrite UTF-16 SRT to UTF-8 to avoid downstream failures.
  try {
    await _rewriteSrtUtf16ToUtf8InPlace(finalPath);
  } catch (_) {}

  return {
    path: finalPath,
    filename: path.basename(finalPath),
    ext: path.extname(finalPath).toLowerCase(),
    source: 'searched',
    baseDir,
    targetDir,
  };
}

module.exports = {
  searchSubtitlesByMovieFile,
  searchSubtitlesByKeyword,
  downloadSubtitleToUploadDir,
};

