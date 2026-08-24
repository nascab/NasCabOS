'use strict';

const fs = require('fs');
const path = require('path');
const jsmediatags = require('jsmediatags');
const VideoFfprobeUtil = require('../../utils/videoFfprobeUtil');

class MusicTagReader {
  _toInt(v) {
    const n = Number(v || 0);
    if (!Number.isFinite(n)) return 0;
    return Math.trunc(n);
  }

  _toStr(v) {
    if (v === undefined || v === null) return '';
    return String(v);
  }

  _safeJsonStringify(v) {
    if (v === undefined) return '';
    try {
      return JSON.stringify(v);
    } catch (_) {
      return '';
    }
  }

  _tryDecode(bytes, encoding) {
    try {
      const dec = new TextDecoder(encoding, { fatal: false });
      return dec.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  _hasReplacementChar(text) {
    return typeof text === 'string' && text.includes('\uFFFD');
  }

  _scoreText(s) {
    const text = this._toStr(s);
    if (!text) return -1000;
    const replacement = (text.match(/\uFFFD/g) || []).length;
    const controls = (text.match(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g) || []).length;
    const cjk = (text.match(/[\u4E00-\u9FFF]/g) || []).length;
    const printable = (text.match(/[\p{L}\p{N}\p{P}\p{S}\s]/gu) || []).length;
    const score = printable - replacement * 20 - controls * 10 + cjk * 2;
    return score;
  }

  normalizeTagValueToString(input) {
    if (input === undefined || input === null) return '';

    if (typeof input === 'string') return input;
    if (typeof input === 'number' || typeof input === 'boolean') return String(input);

    if (Buffer.isBuffer(input) || input instanceof Uint8Array) {
      return input;
    }

    if (Array.isArray(input)) {
      const parts = input
        .map(v => this.normalizeTagText(v))
        .map(v => String(v || '').trim())
        .filter(Boolean);
      return parts.join('\n');
    }

    if (typeof input === 'object') {
      const obj = input;
      const candidates = [];
      if (typeof obj.lyrics === 'string') candidates.push(obj.lyrics);
      if (typeof obj.text === 'string') candidates.push(obj.text);
      if (typeof obj.value === 'string') candidates.push(obj.value);
      if (typeof obj.data === 'string' || Buffer.isBuffer(obj.data) || obj.data instanceof Uint8Array) candidates.push(obj.data);
      if (candidates.length > 0) {
        const parts = candidates
          .map(v => this.normalizeTagText(v))
          .map(v => String(v || '').trim())
          .filter(Boolean);
        if (parts.length > 0) return parts.join('\n');
      }

      try {
        return JSON.stringify(obj);
      } catch (_) {
        return '';
      }
    }

    return '';
  }

  normalizeTagText(input) {
    if (input === undefined || input === null) return '';
    const raw = this.normalizeTagValueToString(input);

    if (Buffer.isBuffer(raw) || raw instanceof Uint8Array) {
      const bytes = Buffer.isBuffer(raw) ? raw : Buffer.from(raw);
      const tryList = ['utf-8', 'utf-16le', 'gb18030', 'gbk', 'big5', 'shift_jis', 'euc-kr', 'windows-1252', 'latin1'];
      let bestText = '';
      let bestScore = -10000;
      for (const enc of tryList) {
        const decoded = this._tryDecode(bytes, enc);
        if (!decoded) continue;
        const t = decoded.trim();
        if (!t) continue;
        const score = this._scoreText(t);
        if (score > bestScore) {
          bestScore = score;
          bestText = t;
        }
      }
      return bestText;
    }

    const s = String(raw);
    const trimmed = s.trim();
    if (!trimmed) return '';

    const isAscii = /^[\x00-\x7F]*$/.test(trimmed);
    if (isAscii) return trimmed;

    const hasReplacement = trimmed.includes('\uFFFD');
    if (hasReplacement) return trimmed;
    const latin1ish = (trimmed.match(/[\u00A0-\u00FF]/g) || []).length;
    const nonAscii = (trimmed.match(/[^\x00-\x7F]/g) || []).length;
    const shouldTryReDecode = nonAscii >= 2 && latin1ish / Math.max(1, nonAscii) > 0.8;

    if (!shouldTryReDecode) return trimmed;

    const bytes = Buffer.from(trimmed, 'latin1');
    const candidates = [
      { enc: 'utf-8' },
      { enc: 'utf-16le' },
      { enc: 'gb18030' },
      { enc: 'gbk' },
      { enc: 'big5' },
      { enc: 'shift_jis' },
      { enc: 'euc-kr' },
      { enc: 'windows-1252' },
      { enc: 'latin1' },
      { enc: 'iso-8859-1' },
    ];

    let bestText = trimmed;
    let bestScore = this._scoreText(trimmed);
    for (const c of candidates) {
      const decoded = this._tryDecode(bytes, c.enc);
      if (!decoded) continue;
      const t = decoded.trim();
      if (!t) continue;
      const score = this._scoreText(t);
      if (score > bestScore) {
        bestScore = score;
        bestText = t;
      }
    }

    return bestText;
  }

  _extractTextFromTags(tags, indexKey, firstKey, secondKey, secondKeyword) {
    const t = tags && typeof tags === 'object' ? tags : {};
    const current = this.normalizeTagText(t[indexKey]);
    if (current) return current;

    const first = this.normalizeTagText(t[firstKey]);
    if (first) return first;

    if (!secondKey) return '';
    const alt = t[secondKey];
    const data = alt && typeof alt === 'object' ? alt.data : null;
    const desc = alt && typeof alt === 'object' ? alt.description : null;
    const descOk = desc && typeof desc === 'string' && secondKeyword ? desc.toLowerCase().includes(String(secondKeyword).toLowerCase()) : true;
    if (!descOk) return '';

    let pick = data;
    if (pick && typeof pick === 'object' && !Buffer.isBuffer(pick) && !(pick instanceof Uint8Array)) {
      if (typeof pick.lyrics === 'string') pick = pick.lyrics;
      else if (typeof pick.text === 'string') pick = pick.text;
      else if (typeof pick.data === 'string' || Buffer.isBuffer(pick.data) || pick.data instanceof Uint8Array) pick = pick.data;
    }

    const second = this.normalizeTagText(pick);
    return second || '';
  }

  _pickBestText(...candidates) {
    const list = candidates
      .map(v => (v === undefined || v === null ? '' : String(v)))
      .map(v => v.trim())
      .filter(Boolean);
    if (list.length === 0) return '';

    let best = list[0];
    let bestScore = this._scoreText(best);
    for (let i = 1; i < list.length; i += 1) {
      const s = list[i];
      const score = this._scoreText(s);
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  _isGarbledText(text) {
    const s = text === undefined || text === null ? '' : String(text).trim();
    if (!s) return false;
    if (this._hasReplacementChar(s)) return true;
    const q = (s.match(/\?/g) || []).length;
    const hasAnyLetterOrCjk = /[\p{L}\u4E00-\u9FFF]/u.test(s);
    if (!hasAnyLetterOrCjk && q >= 2) return true;
    if (q >= Math.max(3, Math.floor(s.length / 2))) return true;
    const cjk = (s.match(/[\u4E00-\u9FFF]/g) || []).length;
    const latin1ish = (s.match(/[\u00A0-\u00FF]/g) || []).length;
    const asciiAlnum = (s.match(/[A-Za-z0-9]/g) || []).length;
    if (cjk === 0 && latin1ish >= 3 && latin1ish >= Math.max(3, asciiAlnum * 2)) return true;
    return false;
  }

  _readSynchsafeInt32(buf, offset) {
    if (!buf) return 0;
    const b0 = buf[offset] & 0x7f;
    const b1 = buf[offset + 1] & 0x7f;
    const b2 = buf[offset + 2] & 0x7f;
    const b3 = buf[offset + 3] & 0x7f;
    const n = (b0 << 21) | (b1 << 14) | (b2 << 7) | b3;
    return Number.isFinite(n) && n > 0 ? n : 0;
  }

  _removeUnsync(buf) {
    if (!Buffer.isBuffer(buf) || buf.length < 2) return buf;
    const out = Buffer.allocUnsafe(buf.length);
    let j = 0;
    for (let i = 0; i < buf.length; i += 1) {
      const b = buf[i];
      if (b === 0xff && i + 1 < buf.length && buf[i + 1] === 0x00) {
        out[j++] = 0xff;
        i += 1;
        continue;
      }
      out[j++] = b;
    }
    return out.subarray(0, j);
  }

  _decodeUtf16BytesToString(bytes, { bigEndian = false } = {}) {
    const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
    if (buf.length === 0) return '';
    let b = buf;
    if (bigEndian) {
      const swapped = Buffer.allocUnsafe(b.length);
      for (let i = 0; i + 1 < b.length; i += 2) {
        swapped[i] = b[i + 1];
        swapped[i + 1] = b[i];
      }
      b = swapped;
    }
    const decoded = this._tryDecode(b, 'utf-16le');
    return decoded ? decoded : '';
  }

  _decodeTextBytes(encodingByte, bytes) {
    const enc = Number(encodingByte);
    const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || []);
    if (buf.length === 0) return '';

    const stripNull = s => {
      const idx = s.indexOf('\u0000');
      return (idx >= 0 ? s.slice(0, idx) : s).trim();
    };

    if (enc === 3) {
      const decoded = this._tryDecode(buf, 'utf-8');
      const text = decoded ? stripNull(decoded) : '';
      if (text && !this._isGarbledText(text)) return text;

      const candidates = ['gb18030', 'gbk', 'big5', 'shift_jis', 'euc-kr', 'windows-1252', 'latin1', 'utf-8'];
      let best = text || '';
      let bestScore = this._scoreText(best);
      for (const c of candidates) {
        const dec = this._tryDecode(buf, c);
        const t = dec ? stripNull(String(dec)) : '';
        if (!t) continue;
        const score = this._scoreText(t);
        if (score > bestScore) {
          bestScore = score;
          best = t;
        }
      }
      return best;
    }

    if (enc === 1 || enc === 2) {
      let b = buf;
      let bigEndian = enc === 2;
      if (enc === 1 && b.length >= 2) {
        if (b[0] === 0xfe && b[1] === 0xff) {
          bigEndian = true;
          b = b.subarray(2);
        } else if (b[0] === 0xff && b[1] === 0xfe) {
          bigEndian = false;
          b = b.subarray(2);
        }
      }
      if (enc === 1 && b.length >= 2 && !(buf[0] === 0xfe && buf[1] === 0xff) && !(buf[0] === 0xff && buf[1] === 0xfe)) {
        const le = this._decodeUtf16BytesToString(b, { bigEndian: false });
        const be = this._decodeUtf16BytesToString(b, { bigEndian: true });
        const leText = le ? stripNull(le) : '';
        const beText = be ? stripNull(be) : '';
        if (!leText) return beText;
        if (!beText) return leText;
        return this._scoreText(beText) > this._scoreText(leText) ? beText : leText;
      }

      const decoded = this._decodeUtf16BytesToString(b, { bigEndian });
      return decoded ? stripNull(decoded) : '';
    }

    const candidates = ['gb18030', 'gbk', 'big5', 'shift_jis', 'euc-kr', 'windows-1252', 'latin1', 'utf-8'];
    let best = '';
    let bestScore = -10000;
    for (const c of candidates) {
      const decoded = this._tryDecode(buf, c);
      const t = decoded ? stripNull(String(decoded)) : '';
      if (!t) continue;
      const score = this._scoreText(t);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  _findNullTerminatorIndex(buf, encodingByte) {
    const enc = Number(encodingByte);
    const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf || []);
    if (b.length === 0) return -1;
    if (enc === 1 || enc === 2) {
      for (let i = 0; i + 1 < b.length; i += 2) {
        if (b[i] === 0x00 && b[i + 1] === 0x00) return i;
      }
      return -1;
    }
    return b.indexOf(0x00);
  }

  async readId3v2Tags(fullPath) {
    const p = fullPath ? String(fullPath) : '';
    if (!p) return null;

    let fd = null;
    try {
      fd = await fs.promises.open(p, 'r');
      const header = Buffer.alloc(10);
      const r0 = await fd.read(header, 0, 10, 0);
      if (!r0 || r0.bytesRead !== 10) return null;
      if (header.toString('latin1', 0, 3) !== 'ID3') return null;

      const verMajor = header[3];
      const flags = header[5];
      const tagSize = this._readSynchsafeInt32(header, 6);
      if (!tagSize || tagSize <= 0) return null;
      const safeSize = Math.min(tagSize, 1024 * 1024);

      const tagBuf = Buffer.alloc(10 + safeSize);
      header.copy(tagBuf, 0);
      const r1 = await fd.read(tagBuf, 10, safeSize, 10);
      const total = 10 + (r1 && r1.bytesRead ? r1.bytesRead : 0);
      let payload = tagBuf.subarray(0, total);
      if (flags & 0x80) {
        payload = Buffer.concat([payload.subarray(0, 10), this._removeUnsync(payload.subarray(10))]);
      }

      let offset = 10;
      if (flags & 0x40) {
        if (verMajor === 4) {
          const extSize = this._readSynchsafeInt32(payload, offset);
          if (extSize > 0) offset += extSize;
        } else if (verMajor === 3) {
          const extSize = payload.readUInt32BE(offset);
          if (extSize > 0) offset += extSize;
        }
      }

      const want = new Set(['TIT2', 'TPE1', 'TALB', 'TYER', 'TDRC', 'TCON', 'USLT']);
      const frames = new Map();

      while (offset + 10 <= payload.length) {
        const id = payload.toString('latin1', offset, offset + 4);
        if (!id || id === '\u0000\u0000\u0000\u0000') break;
        if (!/^[A-Z0-9]{4}$/.test(id)) break;

        const size = verMajor === 4 ? this._readSynchsafeInt32(payload, offset + 4) : payload.readUInt32BE(offset + 4);
        if (!size || size <= 0) break;
        const dataStart = offset + 10;
        const dataEnd = dataStart + size;
        if (dataEnd > payload.length) break;
        if (want.has(id)) {
          frames.set(id, payload.subarray(dataStart, dataEnd));
        }
        offset = dataEnd;
      }

      const out = {};
      const decodeTextFrame = id => {
        const data = frames.get(id);
        if (!data || data.length < 2) return '';
        const encByte = data[0];
        return this._decodeTextBytes(encByte, data.subarray(1));
      };

      out.title = decodeTextFrame('TIT2');
      out.artist = decodeTextFrame('TPE1');
      out.album = decodeTextFrame('TALB');
      out.year = decodeTextFrame('TYER') || decodeTextFrame('TDRC');
      out.genre = decodeTextFrame('TCON');

      const uslt = frames.get('USLT');
      if (uslt && uslt.length >= 5) {
        const encByte = uslt[0];
        const rest = uslt.subarray(1);
        const body = rest.subarray(3);
        const descEnd = this._findNullTerminatorIndex(body, encByte);
        const termLen = encByte === 1 || encByte === 2 ? 2 : 1;
        const lyricsBytes = descEnd >= 0 ? body.subarray(descEnd + termLen) : body;
        out.lyrics = this._decodeTextBytes(encByte, lyricsBytes);
      }

      return out;
    } catch (_) {
      return null;
    } finally {
      try {
        if (fd) await fd.close();
      } catch (_) {}
    }
  }

  async readFlacVorbisCommentTags(fullPath) {
    const p = fullPath ? String(fullPath) : '';
    if (!p) return null;

    let fd = null;
    try {
      fd = await fs.promises.open(p, 'r');
      const magic = Buffer.alloc(4);
      const r0 = await fd.read(magic, 0, 4, 0);
      if (!r0 || r0.bytesRead !== 4) return null;
      if (magic.toString('latin1') !== 'fLaC') return null;

      let offset = 4;
      let out = null;
      let isLast = false;
      while (!isLast) {
        const header = Buffer.alloc(4);
        const rh = await fd.read(header, 0, 4, offset);
        if (!rh || rh.bytesRead !== 4) break;

        isLast = (header[0] & 0x80) !== 0;
        const blockType = header[0] & 0x7f;
        const blockLen = (header[1] << 16) | (header[2] << 8) | header[3];
        offset += 4;
        if (blockLen < 0) break;

        if (blockType !== 4) {
          offset += blockLen;
          continue;
        }

        if (blockLen === 0) break;
        const buf = Buffer.alloc(blockLen);
        const rb = await fd.read(buf, 0, blockLen, offset);
        if (!rb || rb.bytesRead !== blockLen) break;

        let pos = 0;
        if (pos + 4 > buf.length) break;
        const vendorLen = buf.readUInt32LE(pos);
        pos += 4;
        if (vendorLen < 0 || pos + vendorLen > buf.length) break;
        pos += vendorLen;

        if (pos + 4 > buf.length) break;
        const userCommentListLen = buf.readUInt32LE(pos);
        pos += 4;

        const commentMap = new Map();
        const append = (k, v) => {
          const key = String(k || '').trim().toUpperCase();
          const val = v === undefined || v === null ? '' : String(v);
          if (!key) return;
          if (!val.trim()) return;
          const list = commentMap.get(key) || [];
          list.push(val);
          commentMap.set(key, list);
        };

        for (let i = 0; i < userCommentListLen; i += 1) {
          if (pos + 4 > buf.length) break;
          const len = buf.readUInt32LE(pos);
          pos += 4;
          if (len <= 0 || pos + len > buf.length) break;
          const text = buf.subarray(pos, pos + len).toString('utf8');
          pos += len;
          const eq = text.indexOf('=');
          if (eq <= 0) continue;
          const k = text.slice(0, eq);
          const v = text.slice(eq + 1);
          append(k, v);
        }

        const joinFirst = keys => {
          for (const k of keys) {
            const list = commentMap.get(k) || [];
            for (const v of list) {
              const s = this.normalizeTagText(v);
              if (s) return s;
            }
          }
          return '';
        };

        const joinAll = (keys, sep) => {
          const res = [];
          for (const k of keys) {
            const list = commentMap.get(k) || [];
            for (const v of list) {
              const s = this.normalizeTagText(v);
              if (s) res.push(s);
            }
          }
          const deduped = [];
          const seen = new Set();
          for (const s of res) {
            if (seen.has(s)) continue;
            seen.add(s);
            deduped.push(s);
          }
          return deduped.join(sep);
        };

        const lyricsKeys = ['LYRICS', 'UNSYNCEDLYRICS', 'UNSYNCED LYRICS', 'LYRIC', 'LRC'];

        out = {
          title: joinFirst(['TITLE']),
          artist: joinAll(['ARTIST'], ' / '),
          album: joinFirst(['ALBUM']),
          year: joinFirst(['DATE', 'YEAR']),
          genre: joinAll(['GENRE'], ' / '),
          lyrics: joinAll(lyricsKeys, '\n'),
        };

        break;
      }

      return out;
    } catch (_) {
      return null;
    } finally {
      try {
        if (fd) await fd.close();
      } catch (_) {}
    }
  }

  async readAudioTags(fullPath) {
    const p = fullPath ? String(fullPath) : '';
    if (!p) return null;
    const timeoutMs = 5000;
    const jsTags = await new Promise(resolve => {
      let done = false;
      const timer = setTimeout(() => {
        if (done) return;
        done = true;
        resolve(null);
      }, timeoutMs);

      try {
        jsmediatags.read(p, {
          onSuccess: tag => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            resolve(tag && tag.tags ? tag.tags : null);
          },
          onError: () => {
            if (done) return;
            done = true;
            clearTimeout(timer);
            resolve(null);
          },
        });
      } catch (_) {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(null);
      }
    });

    const ext = path.extname(p).toLowerCase();
    const flacTags = ext === '.flac' ? await this.readFlacVorbisCommentTags(p) : null;
    const rawTags = await this.readId3v2Tags(p);
    if (!jsTags && !rawTags && !flacTags) return null;

    const merged = jsTags && typeof jsTags === 'object' ? { ...jsTags } : {};
    const overlay = {
      ...(rawTags && typeof rawTags === 'object' ? rawTags : {}),
      ...(flacTags && typeof flacTags === 'object' ? flacTags : {}),
    };

    const keys = ['title', 'artist', 'album', 'year', 'genre', 'lyrics'];
    for (const k of keys) {
      const jsVal = this.normalizeTagText(merged[k]);
      const rawVal = this.normalizeTagText(overlay[k]);
      const candidates = [jsVal, rawVal].map(v => (v ? String(v).trim() : '')).filter(Boolean);
      const good = candidates.filter(v => !this._isGarbledText(v));
      const finalVal = this._pickBestText(...(good.length > 0 ? good : candidates));
      if (finalVal) merged[k] = finalVal;
    }

    return merged;
  }

  async probeAudio(fullPath) {
    const p = fullPath ? String(fullPath) : '';
    if (!p) return null;
    try {
      return await VideoFfprobeUtil.probeVideo(p);
    } catch (_) {
      return null;
    }
  }

  extractInnerCoverBuffer(tags) {
    const t = tags && typeof tags === 'object' ? tags : {};

    let cover = null;
    if (t.picture && t.picture.data) cover = t.picture.data;
    if (!cover && t.APIC && t.APIC.data && t.APIC.data.data) cover = t.APIC.data.data;
    if (!cover && t.APIC && t.APIC.data) cover = t.APIC.data;
    if (!cover && t.apic && t.apic.data) cover = t.apic.data;

    return this._toCoverBuffer(cover);
  }

  _toCoverBuffer(input) {
    if (!input) return null;
    if (Buffer.isBuffer(input)) return input;
    if (input instanceof Uint8Array) return Buffer.from(input);
    if (Array.isArray(input)) return Buffer.from(input);
    if (typeof input === 'string') {
      const s = String(input || '').trim();
      if (!s) return null;
      const match = s.match(/^data:.*?;base64,(.*)$/i);
      const base64 = match ? match[1] : s;
      try {
        const buf = Buffer.from(base64, 'base64');
        return buf.length > 0 ? buf : null;
      } catch (_) {
        return null;
      }
    }
    if (typeof input === 'object' && input.data) return this._toCoverBuffer(input.data);
    return null;
  }
}

module.exports = MusicTagReader;
