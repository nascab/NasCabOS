const ResponseUtil = require('../../apiUtils/responseUtil');
const videoPlayerService = require('./videoPlayerService');
const fs = require('fs');
const path = require('path');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('../../../libsPath/ffmpegPath');
const ffprobePath = require('../../../libsPath/ffprobePath');
const transCodeUtil = require('../../../utils/transCodeUtil');
const tableVideoTranscodeSession = require('../../../db/table/tableVideoTranscodeSession');
const multer = require('multer');
const fsExtra = require('fs-extra');
const { spawnSync } = require('node:child_process');
const config = require('../../../config/config');
const FileUtil = require('../../../utils/fileUtil');
const { hasPermission } = require('../../../utils/permissionUtil');
const thunderSubtitleService = require('./thunderSubtitleService');

ffmpeg.setFfmpegPath(ffmpegPath.path);
ffmpeg.setFfprobePath(ffprobePath.path);

function _isBitmapSubtitleCodec(codecName) {
  const v = String(codecName || '').toLowerCase();
  return (
    v === 'pgssub' ||
    v === 'hdmv_pgs_subtitle' ||
    v === 'vobsub' ||
    v === 'dvd_subtitle' ||
    v === 'dvdsub' ||
    v === 'dvb_subtitle' ||
    v === 'xsub'
  );
}

async function _fileExistsNonEmpty(p) {
  try {
    const st = await fs.promises.stat(p);
    return st && st.isFile() && Number(st.size) > 0;
  } catch (_) {
    return false;
  }
}

function _scoreFilenameText(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (!text) return Number.NEGATIVE_INFINITY;
  let score = 0;
  const cjk = (text.match(/[\u3400-\u9FFF\uF900-\uFAFF]/g) || []).length;
  const asciiWord = (text.match(/[A-Za-z0-9._()\-[\] ]/g) || []).length;
  const latin1ish = (text.match(/[\u00A0-\u00FF]/g) || []).length;
  const replacement = (text.match(/\uFFFD/g) || []).length;
  score += cjk * 6;
  score += asciiWord;
  score -= latin1ish * 2;
  score -= replacement * 8;
  return score;
}

// 修复常见“UTF-8 被当 latin1 解码”的文件名乱码（与 notes 上传保持一致的策略）
function normalizeUploadedOriginalName(raw) {
  const name = typeof raw === 'string' ? raw.trim() : '';
  if (!name) return '';
  if (/^[\x00-\x7F]*$/.test(name)) return name;
  if (/[\u3400-\u9FFF\uF900-\uFAFF]/.test(name)) return name;

  // 尽量强制尝试 latin1 -> utf8（常见 multipart filename 乱码来源）
  const decoded = Buffer.from(name, 'latin1').toString('utf8').trim();
  if (!decoded || decoded.includes('\uFFFD')) return name;
  if (/[\u3400-\u9FFF\uF900-\uFAFF]/.test(decoded)) return decoded;

  // 回退到评分机制：选“更像文件名”的那一个
  return _scoreFilenameText(decoded) > _scoreFilenameText(name) ? decoded : name;
}

function buildStaticVodM3u8({ playId, durationSeconds, seekSeconds, segmentDurationSeconds, baseUrl }) {
  const segDur = Number(segmentDurationSeconds) > 0 ? Number(segmentDurationSeconds) : 2;
  const total = Number(durationSeconds) > 0 ? Number(durationSeconds) : 0;
  const seek = Number(seekSeconds) > 0 ? Number(seekSeconds) : 0;
  const remaining = Math.max(0, total - seek);
  const segmentCount = Math.max(1, Math.ceil((remaining || segDur) / segDur));
  const lastDuration = segmentCount <= 1 ? remaining || segDur : remaining - (segmentCount - 1) * segDur;
  const targetDuration = Math.ceil(segDur);

  const prefix = `/api/videoPlayer/hls/${playId}/`;

  let m3u8 = `#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:${targetDuration}
#EXT-X-MEDIA-SEQUENCE:0
`;

  for (let i = 0; i < segmentCount; i++) {
    const isLast = i === segmentCount - 1;
    const d = isLast ? (lastDuration > 0 ? lastDuration : segDur) : segDur;
    const name = `segment_${String(i).padStart(3, '0')}.ts`;
    m3u8 += `#EXTINF:${Number(d).toFixed(3)},
${prefix}${name}
`;
  }

  m3u8 += `#EXT-X-ENDLIST
`;
  return m3u8;
}

function _normalizeText(v) {
  if (v === undefined || v === null) return '';
  return String(v).trim();
}

function _isMp4CompatibleAudioCodec(codecName) {
  const codec = _normalizeText(codecName).toLowerCase();
  if (!codec) return true;
  return new Set(['aac', 'alac', 'ac3', 'eac3', 'ec3', 'mp3', 'mp2']).has(codec);
}

async function _shouldFallbackMovCopyAudio(db, filePath) {
  const ext = path.extname(_normalizeText(filePath)).toLowerCase();
  if (ext !== '.mov') return false;

  const result = await videoPlayerService.getCachedOrProbeVideoInfo(db, filePath).catch(() => null);
  const streams = result && result.videoInfo && Array.isArray(result.videoInfo.streams) ? result.videoInfo.streams : [];
  const audioStream = streams.find(s => s && s.codec_type === 'audio');
  if (!audioStream) return false;

  return !_isMp4CompatibleAudioCodec(audioStream.codec_name);
}

/** Subtitle codecs that can be remuxed into MP4 with -c copy (bitmap / exotic subs still excluded). */
const _MP4_COPY_SAFE_SUBTITLE_CODECS = new Set(['mov_text', 'tx3g']);
/** Text subs we re-encode to mov_text so they stay in the fMP4 stream for the client. */
const _MP4_COPY_SUBTITLE_TO_MOV_TEXT = new Set(['ass', 'ssa', 'subrip', 'srt']);

/** External subtitle files allowed to mux into stream-mp4 (same family as getVideoInfo scan). */
const _STREAM_MP4_EXTERNAL_SUB_EXTS = new Set(['.srt', '.ass', '.ssa', '.vtt']);

function _parseQuerySubtitlePath(req) {
  let raw =
    req.query && req.query.subtitlePath != null ? String(req.query.subtitlePath).trim() : '';
  if (!raw) return '';
  try {
    raw = decodeURIComponent(raw);
  } catch (_) {}
  return String(raw || '').trim();
}

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
  // If one side is very "null-heavy", it's likely UTF-16 text.
  if (oddRate > 0.35 && evenRate < 0.1) return 'utf16le';
  if (evenRate > 0.35 && oddRate < 0.1) return 'utf16be';
  return null;
}

function _tryIconvToUtf8({ inputPath, outputPath, fromEncoding }) {
  const enc = _normalizeText(fromEncoding);
  if (!enc) return false;
  if (process.platform === 'win32') return false;
  const iconv = fs.existsSync('/usr/bin/iconv') ? '/usr/bin/iconv' : 'iconv';
  const r = spawnSync(iconv, ['-f', enc, '-t', 'utf-8', inputPath], {
    encoding: 'buffer',
    maxBuffer: 32 * 1024 * 1024,
  });
  if (!r || r.status !== 0 || !r.stdout || r.stdout.length === 0) return false;
  try {
    fs.writeFileSync(outputPath, r.stdout);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Some external subtitles are UTF-16 ("Unicode") which can break mov_text muxing / decoding.
 * Best-effort:
 * - if BOM indicates UTF-16, rewrite to a UTF-8 temp file and return it.
 * - if not valid UTF-8, try iconv from common encodings (GB18030/GBK/Big5) into UTF-8.
 */
async function _maybeRewriteSubtitleToUtf8(filePath) {
  const p = _normalizeText(filePath);
  if (!p) return '';
  const ext = path.extname(p).toLowerCase();
  if (ext !== '.srt') return p;
  if (!fs.existsSync(p)) return p;

  let fd = null;
  try {
    fd = fs.openSync(p, 'r');
    const head = Buffer.allocUnsafe(4);
    const n = fs.readSync(fd, head, 0, head.length, 0);
    const b0 = n > 0 ? head[0] : 0;
    const b1 = n > 1 ? head[1] : 0;

    const isUtf16Le = b0 === 0xff && b1 === 0xfe;
    const isUtf16Be = b0 === 0xfe && b1 === 0xff;
    const st = fs.statSync(p);
    const dir = path.dirname(p);
    const base = path.basename(p, ext);
    const outPath = path.join(dir, `${base}.utf8_${st.size}_${Math.floor(st.mtimeMs)}${ext}`);

    const raw = fs.readFileSync(p);
    const assumedUtf16 = isUtf16Le ? 'utf16le' : isUtf16Be ? 'utf16be' : _looksUtf16WithoutBom(raw);
    if (assumedUtf16) {
      if (fs.existsSync(outPath)) return outPath;
      let body = raw;
      if (isUtf16Le || isUtf16Be) {
        // drop BOM
        if (raw.length >= 2) body = raw.subarray(2);
      }
      if (assumedUtf16 === 'utf16be') body = _bufSwap16(body);
      const text = body.toString('utf16le');
      fs.writeFileSync(outPath, Buffer.from(text, 'utf8'));
      return outPath;
    }

    // Not UTF-16: check whether it's valid UTF-8; if not, try iconv.
    const decodedUtf8 = raw.toString('utf8');
    if (!_utf8HasReplacementChar(decodedUtf8)) return p;
    if (fs.existsSync(outPath)) return outPath;
    const encCandidates = ['gb18030', 'gbk', 'big5'];
    for (const enc of encCandidates) {
      const ok = _tryIconvToUtf8({ inputPath: p, outputPath: outPath, fromEncoding: enc });
      if (ok) return outPath;
    }
    return p;
  } catch (e) {
    console.warn('[stream-mp4] Rewrite subtitle to UTF-8 failed, keep original:', e && e.message);
    return p;
  } finally {
    try {
      if (fd != null) fs.closeSync(fd);
    } catch (_) {}
  }
}

function _looksLikeSubtitleError(err, stderrText) {
  const msg = _normalizeText(err && err.message ? err.message : err);
  const s = `${msg}\n${_normalizeText(stderrText)}`.toLowerCase();
  if (!s) return false;
  return (
    s.includes('subtitle') ||
    s.includes('subrip') ||
    s.includes('.srt') ||
    s.includes('mov_text') ||
    s.includes('invalid utf-8') ||
    s.includes('utf-8') ||
    s.includes('utf8') ||
    s.includes('decode') ||
    s.includes('decoding') ||
    s.includes('error while decoding') ||
    s.includes('conversion failed') ||
    s.includes('unable to open') ||
    s.includes('assertion') ||
    s.includes('could not find codec parameters')
  );
}

/**
 * 外挂字幕仅作增强：路径无效、无法探测或不含字幕轨时返回空字符串，主视频 stream 仍按无外挂路径继续。
 */
async function _streamMp4ResolveExternalSubtitlePath(candidate) {
  const empty = '';
  if (!candidate) return empty;
  if (!fs.existsSync(candidate)) {
    console.warn('[stream-mp4] External subtitle missing, streaming without subs:', candidate);
    return empty;
  }
  let st;
  try {
    st = fs.statSync(candidate);
  } catch (e) {
    console.warn(
      '[stream-mp4] External subtitle stat error, streaming without subs:',
      e && e.message
    );
    return empty;
  }
  if (!st.isFile()) {
    console.warn('[stream-mp4] External subtitle not a file, streaming without subs:', candidate);
    return empty;
  }
  const subExt = path.extname(candidate).toLowerCase();
  if (!_STREAM_MP4_EXTERNAL_SUB_EXTS.has(subExt)) {
    console.warn('[stream-mp4] External subtitle ext unsupported, streaming without subs:', subExt);
    return empty;
  }
  // If it's UTF-16 "Unicode" SRT, rewrite to UTF-8 for better compatibility.
  const normalizedCandidate = await _maybeRewriteSubtitleToUtf8(candidate);
  return new Promise(resolve => {
    ffmpeg.ffprobe(normalizedCandidate, (err, data) => {
      if (err) {
        console.warn(
          '[stream-mp4] ffprobe external subtitle failed, streaming without subs:',
          err.message
        );
        return resolve(empty);
      }
      const streams = data && Array.isArray(data.streams) ? data.streams : [];
      const hasSub = streams.some(s => s && s.codec_type === 'subtitle');
      if (!hasSub) {
        console.warn(
          '[stream-mp4] No subtitle stream in external file, streaming without subs:',
          normalizedCandidate
        );
        return resolve(empty);
      }
      resolve(normalizedCandidate);
    });
  });
}

function _streamMp4CopySubtitlePlanFromStreams(streams, noSubtitle) {
  const empty = { mapOptions: [], subtitleCodecOptions: [] };
  if (noSubtitle || !Array.isArray(streams)) return empty;

  const tracks = [];
  for (const s of streams) {
    if (!s || s.codec_type !== 'subtitle') continue;
    const name = String(s.codec_name || '').toLowerCase();
    const idx = Number(s.index);
    if (!Number.isFinite(idx) || idx < 0) continue;

    if (_MP4_COPY_SAFE_SUBTITLE_CODECS.has(name)) {
      tracks.push({ idx, mode: 'copy' });
    } else if (_MP4_COPY_SUBTITLE_TO_MOV_TEXT.has(name)) {
      tracks.push({ idx, mode: 'mov_text' });
    }
  }

  const mapOptions = [];
  for (const t of tracks) {
    mapOptions.push('-map', `0:${t.idx}`);
  }
  const subtitleCodecOptions = [];
  tracks.forEach((t, i) => {
    subtitleCodecOptions.push(`-c:s:${i}`, t.mode === 'copy' ? 'copy' : 'mov_text');
  });
  return { mapOptions, subtitleCodecOptions };
}

/** 只 mux 指定 ffprobe stream index 的一条内嵌字幕（与客户端 subtitleStreamIndex 一致） */
function _streamMp4SingleSubtitlePlanFromStreams(streams, streamIndex) {
  const empty = { mapOptions: [], subtitleCodecOptions: [] };
  if (!Array.isArray(streams) || !Number.isFinite(streamIndex) || streamIndex < 0) return empty;
  const want = Math.floor(streamIndex);
  const s = streams.find(x => x && x.codec_type === 'subtitle' && Number(x.index) === want);
  if (!s) return empty;
  const name = String(s.codec_name || '').toLowerCase();
  const idx = Number(s.index);
  if (!Number.isFinite(idx) || idx < 0) return empty;
  let mode = null;
  if (_MP4_COPY_SAFE_SUBTITLE_CODECS.has(name)) mode = 'copy';
  else if (_MP4_COPY_SUBTITLE_TO_MOV_TEXT.has(name)) mode = 'mov_text';
  if (!mode) return empty;
  return {
    mapOptions: ['-map', `0:${idx}`],
    subtitleCodecOptions: ['-c:s:0', mode === 'copy' ? 'copy' : 'mov_text'],
  };
}

async function _streamMp4CopySubtitlePlan(db, filePath, noSubtitle, subtitleStreamIndex) {
  if (noSubtitle) return { mapOptions: [], subtitleCodecOptions: [] };
  const result = await videoPlayerService.getCachedOrProbeVideoInfo(db, filePath).catch(() => null);
  const streams = result && result.videoInfo && Array.isArray(result.videoInfo.streams) ? result.videoInfo.streams : [];
  if (
    subtitleStreamIndex != null &&
    Number.isFinite(subtitleStreamIndex) &&
    Math.floor(subtitleStreamIndex) >= 0
  ) {
    return _streamMp4SingleSubtitlePlanFromStreams(streams, Math.floor(subtitleStreamIndex));
  }
  return _streamMp4CopySubtitlePlanFromStreams(streams, false);
}

function _parseSegmentIndex(filename) {
  const name = _normalizeText(filename).toLowerCase();
  const m = name.match(/^segment_(\d+)\.ts$/);
  if (!m) return null;
  const n = Number(m[1]);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.floor(n);
}

async function _waitForTranscodeStopped(playId, timeoutMs = 6000) {
  const pid = _normalizeText(playId);
  if (!pid) return false;
  if (typeof process.send !== 'function') return false;

  return new Promise(resolve => {
    let done = false;
    const timer = setTimeout(
      () => {
        if (done) return;
        done = true;
        process.removeListener('message', onMessage);
        resolve(false);
      },
      Math.max(300, Number(timeoutMs || 0) || 0)
    );

    const onMessage = message => {
      if (!message || message.type !== 'transcodeStopped') return;
      if (!message.data || message.data.playId !== pid) return;
      if (done) return;
      done = true;
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(!!message.data.stopped);
    };
    process.on('message', onMessage);

    try {
      process.send({ type: 'stopTranscode', data: { playId: pid } });
    } catch (_) {
      clearTimeout(timer);
      process.removeListener('message', onMessage);
      resolve(false);
    }
  });
}

async function _stopTranscodeSession({ playId, clean, knexVideo }) {
  const pid = _normalizeText(playId);
  if (!pid) return false;

  const outDir = await videoPlayerService.getTranscodeOutDir(pid);
  const stopped = await _waitForTranscodeStopped(pid, 6000);

  if (knexVideo) {
    await tableVideoTranscodeSession.setRunning(pid, 0, knexVideo).catch(() => null);
  }

  if (clean) {
    for (let i = 0; i < 30; i++) {
      try {
        await fs.promises.rm(outDir, { recursive: true, force: true });
        break;
      } catch (_) {
        await new Promise(r => setTimeout(r, stopped ? 100 : 200));
      }
    }
  }

  return stopped;
}

class VideoPlayerController {
  /**
   * Get video metadata
   * Query: filePath
   */
  async getVideoInfo(req, res) {
    try {
      const { filePath } = req.query;
      console.log('获取视频信息请求参数', filePath);
      if (!filePath) {
        return ResponseUtil.error(req, res, 'file.INVALID_PATH');
      }

      // Permission check could be done here or in middleware
      // For now assuming middleware handles general auth, but file-level access might need checks
      // Using dbMain from req as configured in app.js

      const info = await videoPlayerService.getVideoInfo(req.dbVideo, filePath, {
        uid: req.user && req.user.id ? req.user.id : undefined,
        ignoreFindSub: req.query && req.query.ignoreFindSub != null ? req.query.ignoreFindSub : undefined,
      });
      console.log('获取视频信息', info);
      // Get user preference if user is logged in
      if (req.user && req.user.id) {
        const preference = await videoPlayerService.getVideoPreference(req.dbVideo, req.user.id, filePath);
        if (preference) {
          info.preference = preference;
        }
      }
      return ResponseUtil.success(req, res, info);
    } catch (e) {
      return ResponseUtil.error(req, res, 'videoPlayer.GET_INFO_FAILED', 500, { error: e.message });
    }
  }

  /**
   * Export one embedded subtitle track as WebVTT.
   * Query: filePath, subtitleIndex (index within subtitle streams, consistent with /transcode)
   */
  async getSubtitleVtt(req, res) {
    try {
      const filePathRaw = req.query && req.query.filePath != null ? String(req.query.filePath).trim() : '';
      const subtitlePathRaw = req.query && req.query.subtitlePath != null ? String(req.query.subtitlePath).trim() : '';
      const subtitleIndexRaw =
        req.query && req.query.subtitleIndex != null ? Number(req.query.subtitleIndex) : NaN;
      const subtitleIndex =
        Number.isFinite(subtitleIndexRaw) && subtitleIndexRaw >= 0 ? Math.floor(subtitleIndexRaw) : null;

      if ((!filePathRaw && !subtitlePathRaw) || subtitleIndex == null) {
        return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');
      }

      // source can be a video file (embedded tracks) or an external subtitle file
      let sourcePath = '';
      let isExternalSubtitleFile = false;
      if (subtitlePathRaw) {
        try {
          sourcePath = path.resolve(decodeURIComponent(subtitlePathRaw));
        } catch (_) {
          sourcePath = path.resolve(subtitlePathRaw);
        }
        isExternalSubtitleFile = true;
      } else {
        sourcePath = path.resolve(filePathRaw);
      }
      if (!sourcePath || !fs.existsSync(sourcePath)) {
        return ResponseUtil.error(req, res, 'file.FILE_NOT_EXIST');
      }

      // For embedded subtitles, validate codec (bitmap not supported as VTT)
      let embeddedSubtitleCodecs = null;
      if (!isExternalSubtitleFile) {
        const probe = await videoPlayerService
          .getCachedOrProbeVideoInfo(req.dbVideo, sourcePath)
          .catch(() => null);
        const streams =
          probe && probe.videoInfo && Array.isArray(probe.videoInfo.streams) ? probe.videoInfo.streams : [];
        const subtitleStreams = streams.filter(s => s && s.codec_type === 'subtitle');
        embeddedSubtitleCodecs = subtitleStreams.map(s => (s && s.codec_name ? String(s.codec_name) : ''));
        const subStream = subtitleStreams[subtitleIndex] || null;
        if (!subStream) {
          return res.status(404).json({
            success: false,
            code: 'SUBTITLE_NOT_FOUND',
            message: 'subtitle track not found',
          });
        }
        const codecName = subStream && subStream.codec_name ? String(subStream.codec_name) : '';
        if (_isBitmapSubtitleCodec(codecName)) {
          return res.status(415).json({
            success: false,
            code: 'BITMAP_SUBTITLE_UNSUPPORTED',
            message: 'bitmap subtitle cannot be exported as vtt',
          });
        }
      }

      const fileHash = await FileUtil.getFileHash(sourcePath);
      if (!fileHash) {
        return ResponseUtil.error(req, res, 'file.INVALID_PATH');
      }

      const cacheDir = path.join(config.getCachePath(), 'subtitleVtt', String(fileHash));
      await fs.promises.mkdir(cacheDir, { recursive: true });
      const outPath = path.join(cacheDir, `s_${subtitleIndex}.vtt`);

      if (await _fileExistsNonEmpty(outPath)) {
        res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        return res.sendFile(outPath);
      }

      // Delegate generation to a singleton worker (avoid duplicate triggers without lock files)
      if (typeof process.send !== 'function') {
        return res.status(500).json({
          success: false,
          code: 'IPC_UNAVAILABLE',
          message: 'ipc unavailable',
        });
      }

      const requestId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
      const result = await new Promise(resolve => {
        let done = false;
        const timer = setTimeout(() => {
          if (done) return;
          done = true;
          process.removeListener('message', onMessage);
          resolve({ ok: false, code: 'SUBTITLE_VTT_TIMEOUT', message: 'subtitle vtt generation timeout' });
        }, 60000);

        const onMessage = message => {
          if (!message || message.type !== 'subtitleVtt:result') return;
          const data = message.data && typeof message.data === 'object' ? message.data : {};
          if (String(data.id || '') !== requestId) return;
          if (done) return;
          done = true;
          clearTimeout(timer);
          process.removeListener('message', onMessage);
          resolve(data);
        };
        process.on('message', onMessage);

        try {
          process.send({
            type: 'subtitleVtt:generate',
            data: {
              id: requestId,
              filePath: sourcePath,
              fileHash,
              subtitleIndex,
              // for embedded subtitles, provide cached codec list so worker can skip ffprobe
              subtitleCodecs: Array.isArray(embeddedSubtitleCodecs) ? embeddedSubtitleCodecs : null,
            },
          });
        } catch (e) {
          if (done) return;
          done = true;
          clearTimeout(timer);
          process.removeListener('message', onMessage);
          resolve({ ok: false, code: 'IPC_SEND_FAILED', message: e && e.message ? e.message : String(e) });
        }
      });

      if (!result || result.ok !== true) {
        return res.status(result && result.code === 'SUBTITLE_VTT_TIMEOUT' ? 504 : 500).json({
          success: false,
          code: (result && result.code) || 'SUBTITLE_VTT_FAILED',
          message: (result && result.message) || 'subtitle vtt failed',
        });
      }

      if (!(await _fileExistsNonEmpty(outPath))) {
        return res.status(500).json({
          success: false,
          code: 'SUBTITLE_VTT_MISSING',
          message: 'subtitle vtt missing after generation',
        });
      }

      res.setHeader('Content-Type', 'text/vtt; charset=utf-8');
      res.setHeader('Cache-Control', 'no-store');
      return res.sendFile(outPath);
    } catch (e) {
      return ResponseUtil.error(req, res, 'common.ERROR', 500, { error: e && e.message ? e.message : String(e) });
    }
  }

  /**
   * Start or Restart Transcoding (HLS)
   * Query: filePath, playId, seek, quality, bitrate, audioIndex, subtitleIndex
   * Returns: m3u8 playlist content or redirect
   */
  async transcode(req, res) {
    try {
      await tableVideoTranscodeSession.deleteOlderThanMs(24 * 60 * 60 * 1000, req.dbVideo).catch(() => null);
      const { filePath, playId, seek, width, resolution, bitrate, audioIndex, subtitleIndex, subtitlePath, subtitleBurn, client, device_id, deviceId } = req.query;

      if (!filePath || !playId) {
        return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');
      }
      // console.log('转码请求参数', req.query);

      const deviceIdStr = _normalizeText(device_id || deviceId);
      const playIdStr = _normalizeText(playId);
      const seekSeconds = Number(seek) || 0;
      const audioTrackIndex = audioIndex !== undefined ? Number(audioIndex) : undefined;
      const subtitleTrackIndex = subtitleIndex !== undefined ? Number(subtitleIndex) : undefined;

      const w = width !== undefined ? Number(width) : undefined;
      const playbackSource = await videoPlayerService.resolvePlaybackSource(filePath);
      const transcodeInputPath = playbackSource.playableFilePath;

      // Text embedded subtitles are NOT burned into HLS (performance). Bitmap subs keep burn/overlay.
      let effectiveSubtitleBurn = subtitleBurn === 'true';
      if (subtitleIndex !== undefined) {
        const subtitleIndexNum = Number(subtitleIndex);
        const subtitleTrackIndex =
          Number.isFinite(subtitleIndexNum) && subtitleIndexNum >= 0 ? Math.floor(subtitleIndexNum) : null;
        if (subtitleTrackIndex != null) {
          const probe = await videoPlayerService
            .getCachedOrProbeVideoInfo(req.dbVideo, transcodeInputPath)
            .catch(() => null);
          const streams =
            probe && probe.videoInfo && Array.isArray(probe.videoInfo.streams) ? probe.videoInfo.streams : [];
          const subtitleStreams = streams.filter(s => s && s.codec_type === 'subtitle');
          const subStream = subtitleStreams[subtitleTrackIndex] || null;
          const codecName = subStream && subStream.codec_name ? String(subStream.codec_name) : '';
          if (subStream && codecName && !_isBitmapSubtitleCodec(codecName)) {
            effectiveSubtitleBurn = false;
          }
        }
      }
      const baseOptions = {
        seek: seekSeconds,
        width: Number.isFinite(w) && w > 0 ? w : undefined,
        resolution,
        bitrate,
        audioIndex: audioTrackIndex,
        subtitleIndex: subtitleTrackIndex,
        subtitlePath,
        subtitleBurn: effectiveSubtitleBurn,
        segmentDurationSeconds: 2,
      };

      const optionsJson = (() => {
        try {
          return JSON.stringify(baseOptions || {});
        } catch (_) {
          return '';
        }
      })();

      if (deviceIdStr) {
        const running = await tableVideoTranscodeSession.listRunningByDeviceId(deviceIdStr, playIdStr, req.dbVideo);
        for (const row of running || []) {
          const otherPlayId = _normalizeText(row && row.play_id);
          if (!otherPlayId || otherPlayId === playIdStr) continue;
          await _stopTranscodeSession({ playId: otherPlayId, clean: true, knexVideo: req.dbVideo }).catch(() => null);
        }
      }

      await tableVideoTranscodeSession
        .upsertSession(
          {
            deviceId: deviceIdStr,
            playId: playIdStr,
            filePath: transcodeInputPath,
            optionsJson,
            baseSeekSeconds: seekSeconds,
            isRunning: 1,
            lastGetHlsTime: Date.now(),
            lastGetHlsFilename: 'index.m3u8',
          },
          req.dbVideo
        )
        .catch(() => null);

      // Start transcoding via IPC to Main Process
      if (process.send) {
        process.send({
          type: 'startTranscode',
          data: {
            playId: playIdStr,
            filePath: transcodeInputPath,
            options: baseOptions,
          },
        });
      }
      let durationSeconds = 0;
      try {
        const info = await videoPlayerService.getVideoInfo(req.dbVideo, filePath);
        durationSeconds = info && info.duration ? Number(info.duration) || 0 : 0;
      } catch (_) {
        durationSeconds = 0;
      }

      const m3u8 = buildStaticVodM3u8({
        playId: playIdStr,
        durationSeconds,
        seekSeconds,
        segmentDurationSeconds: 2,
        baseUrl: '',
      });
      res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).send(m3u8);
    } catch (e) {
      console.log(e);
      return ResponseUtil.error(req, res, 'videoPlayer.TRANSCODE_FAILED', 500, {
        error: e.message,
      });
    }
  }

  /**
   * Serve HLS Segments (.ts)
   * Path param: playId, filename
   */
  async serveSegment(req, res) {
    try {
      const { playId, filename } = req.params;
      if (playId.includes('..') || /[\\/]/.test(playId)) {
        return res.status(400).send('Bad Request');
      }
      if (path.basename(filename) !== filename) {
        return res.status(400).send('Bad Request');
      }
      const session = await tableVideoTranscodeSession.getByPlayId(playId, req.dbVideo);

      if (!session) return res.status(404).send('Not Found');
      const dir = await videoPlayerService.getTranscodeOutDir(playId);
      const filePath = path.join(dir, filename);
      const nowMs = Date.now();
      await tableVideoTranscodeSession.updateHeartbeat(playId, { lastGetHlsTime: nowMs, lastGetHlsFilename: filename }, req.dbVideo).catch(() => null);

      const lower = filename.toLowerCase();
      const isM3u8 = lower.endsWith('.m3u8');
      const isTs = lower.endsWith('.ts');
      if (isM3u8) {
        res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
        res.setHeader('Cache-Control', 'no-store');
      } else if (isTs) {
        res.setHeader('Content-Type', 'video/mp2t');
        res.setHeader('Cache-Control', 'no-store');
      }

      let ok = false;

      if (fs.existsSync(filePath)) {
        const stat = fs.statSync(filePath);
        if (stat.size > 0) ok = true;
      }

      if (!ok && isTs) {
        const segmentIndex = _parseSegmentIndex(filename);
        if (segmentIndex !== null) {
          const row = await tableVideoTranscodeSession.getByPlayId(playId, req.dbVideo);
          const paused = row && Number(row.is_running) === 0;
          const savedPath = row && row.file_path ? String(row.file_path) : '';
          const savedOptionsRaw = row && row.options_json ? String(row.options_json) : '';
          if (paused && savedPath) {
            let savedOptions = {};
            try {
              savedOptions = savedOptionsRaw ? JSON.parse(savedOptionsRaw) : {};
            } catch (_) {
              savedOptions = {};
            }
            const baseSeek = row && row.base_seek_seconds !== undefined ? Number(row.base_seek_seconds) || 0 : 0;
            const segDur = 2;
            const resumeSeek = Math.max(0, Math.floor(baseSeek + segmentIndex * segDur));
            const tsOffsetSeconds = Math.max(0, Math.floor(segmentIndex * segDur));
            const resumeOptions = {
              ...(savedOptions && typeof savedOptions === 'object' ? savedOptions : {}),
              seek: resumeSeek,
              startNumber: segmentIndex,
              outputTsOffset: tsOffsetSeconds,
              clean: false,
            };

            await _stopTranscodeSession({ playId, clean: false, knexVideo: req.dbVideo }).catch(() => null);
            await tableVideoTranscodeSession.setRunning(playId, 1, req.dbVideo).catch(() => null);

            if (process.send) {
              console.log('重新开启转码', playId, resumeOptions);
              process.send({
                type: 'startTranscode',
                data: {
                  playId,
                  filePath: savedPath,
                  options: resumeOptions,
                },
              });
            }

            const retryDeadline = Date.now() + 15000;
            while (Date.now() < retryDeadline) {
              if (fs.existsSync(filePath)) {
                const st = fs.statSync(filePath);
                if (st.size > 0) {
                  ok = true;
                  break;
                }
              }
              await new Promise(r => setTimeout(r, 200));
            }
          }
        }
      }

      if (!ok) {
        const maxWaitMs = isM3u8 ? 20000 : 60000;
        const deadline = Date.now() + maxWaitMs;
        while (Date.now() < deadline) {
          if (fs.existsSync(filePath)) {
            const stat = fs.statSync(filePath);
            if (stat.size > 0) {
              ok = true;
              break;
            }
          }
          await new Promise(r => setTimeout(r, 200));
        }
      }

      if (!ok) return res.status(404).send('Not Found');
      if (isM3u8) {
        const m3u8Raw = fs.readFileSync(filePath, 'utf8');
        const protoRaw = req.get('x-forwarded-proto') || req.protocol;
        const proto = protoRaw ? String(protoRaw).split(',')[0].trim() : 'http';
        const host = req.get('host') || '';
        const base = host ? `${proto}://${host}` : '';
        const hlsBasePath = `${base}/api/videoPlayer/hls/${playId}/`;

        const m3u8 = m3u8Raw
          .split(/\r?\n/)
          .map(line => {
            const trimmed = line.trim();
            if (!trimmed) return line;
            if (trimmed.startsWith('#')) return line;
            if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
              return line;
            }
            if (trimmed.startsWith('/')) {
              return base ? `${base}${trimmed}` : trimmed;
            }
            return `${hlsBasePath}${trimmed}`;
          })
          .join('\n');

        return res.status(200).send(m3u8);
      }

      return res.sendFile(filePath);
    } catch (e) {
      res.status(500).send(e.message);
    }
  }

  /**
   * Stream video as MP4 (single file, no m3u8). For web or when source format is not playable.
   * Query: filePath
   */
  async streamMp4(req, res) {
    let command = null;
    try {
      const filePath = req.query && req.query.filePath ? String(req.query.filePath).trim() : '';
      const mode = req.query && req.query.mode ? String(req.query.mode).trim().toLowerCase() : '';
      const seekRaw = req.query && req.query.seek !== undefined ? Number(req.query.seek) : NaN;
      const seek = Number.isFinite(seekRaw) && seekRaw > 0 ? Math.floor(seekRaw) : 0;
      const noSubtitleRaw = req.query && req.query.noSubtitle !== undefined ? String(req.query.noSubtitle).trim() : '';
      const noSubtitle = noSubtitleRaw === '1' || noSubtitleRaw.toLowerCase() === 'true';
      const audioMapRaw =
        req.query && req.query.audioMapIndex !== undefined ? Number(req.query.audioMapIndex) : NaN;
      let audioMapSpec = '0:a?';
      if (Number.isFinite(audioMapRaw) && audioMapRaw >= 0) {
        audioMapSpec = `0:a:${Math.floor(audioMapRaw)}?`;
      }
      const subtitleStreamRaw =
        req.query && req.query.subtitleStreamIndex !== undefined ? Number(req.query.subtitleStreamIndex) : NaN;
      const subtitleStreamIndex =
        !noSubtitle && Number.isFinite(subtitleStreamRaw) && subtitleStreamRaw >= 0
          ? Math.floor(subtitleStreamRaw)
          : null;
      const subtitlePathRaw = _parseQuerySubtitlePath(req);
      let resolvedSubtitlePath = '';
      if (subtitlePathRaw) {
        resolvedSubtitlePath = await _streamMp4ResolveExternalSubtitlePath(
          path.resolve(subtitlePathRaw)
        );
      }
      const useExternalSubtitle = !!resolvedSubtitlePath;
      if (!filePath) {
        res.status(400).send('Missing filePath');
        return;
      }
      const resolvedPath = path.resolve(filePath);
      if (!fs.existsSync(resolvedPath)) {
        res.status(404).send('Not Found');
        return;
      }
      const inputPath = transCodeUtil.dealFfmpegPath(resolvedPath);
      const subInputPathBase =
        useExternalSubtitle && resolvedSubtitlePath
          ? transCodeUtil.dealFfmpegPath(resolvedSubtitlePath)
          : null;

      let retriedWithoutSubtitle = false;
      let stderrTail = [];
      const pushStderr = line => {
        if (!line) return;
        stderrTail.push(String(line));
        if (stderrTail.length > 80) stderrTail = stderrTail.slice(-80);
      };

      const buildAndStart = async ({ disableSubtitle }) => {
        const actuallyUseExternalSubtitle = !!subInputPathBase && !disableSubtitle;

        // 外挂字幕：第二路输入与主视频使用相同 -ss，时间轴与续播点对齐
        const cmd = ffmpeg();
        cmd.input(inputPath);
        if (seek > 0) {
          cmd.inputOptions([`-ss ${seek}`]);
        }
        if (actuallyUseExternalSubtitle) {
          cmd.input(subInputPathBase);
          if (seek > 0) {
            cmd.inputOptions([`-ss ${seek}`]);
          }
        }
        cmd.outputOptions(['-movflags', 'frag_keyframe+empty_moov+delay_moov']).outputFormat('mp4');
        if (mode === 'copy') {
          const fallbackMovAudio = await _shouldFallbackMovCopyAudio(req.dbVideo, resolvedPath);
          const subPlan =
            actuallyUseExternalSubtitle
              ? { mapOptions: [], subtitleCodecOptions: [] }
              : await _streamMp4CopySubtitlePlan(
                  req.dbVideo,
                  resolvedPath,
                  noSubtitle,
                  subtitleStreamIndex,
                );
          const outputOptions = ['-map', '0:v:0?', '-map', audioMapSpec];
          if (actuallyUseExternalSubtitle) {
            // 外挂文件一般为单路字幕轨，用 1:0 兼容性优于 1:s:0（部分 demux 无 s 选择器）
            outputOptions.push('-map', '1:0');
          } else if (noSubtitle) {
            outputOptions.unshift('-sn');
          } else if (subPlan.mapOptions.length) {
            outputOptions.push(...subPlan.mapOptions);
          }

          const hasEmbeddedSubs =
            !actuallyUseExternalSubtitle && !noSubtitle && subPlan.mapOptions.length > 0;
          const hasExternalSubs = actuallyUseExternalSubtitle;
          const hasMappedSubs = hasEmbeddedSubs || hasExternalSubs;
          if (!hasMappedSubs) {
            if (fallbackMovAudio) {
              outputOptions.push('-c:v', 'copy', '-c:a', 'aac');
            } else {
              outputOptions.push('-strict', 'unofficial', '-c', 'copy');
            }
          } else {
            outputOptions.push('-c:v', 'copy', '-c:a', fallbackMovAudio ? 'aac' : 'copy');
            outputOptions.push('-strict', 'unofficial');
            if (hasEmbeddedSubs) {
              outputOptions.push(...subPlan.subtitleCodecOptions);
            }
            if (hasExternalSubs) {
              outputOptions.push('-c:s:0', 'mov_text');
            }
          }
          cmd.outputOptions(outputOptions);
        } else {
          const outputOptions = ['-map', '0:v:0?', '-map', audioMapSpec];
          if (actuallyUseExternalSubtitle) {
            outputOptions.push('-map', '1:0');
            outputOptions.push('-c:s:0', 'mov_text');
          } else if (noSubtitle) {
            outputOptions.unshift('-sn');
          }
          cmd.videoCodec('libx264').audioCodec('aac').outputOptions(outputOptions);
        }

        cmd.on('start', cmdline => {
          console.log(cmdline);
        });
        cmd.on('stderr', line => {
          pushStderr(line);
        });

        command = cmd;
        cmd.pipe(res, { end: true });
        return { cmd, actuallyUseExternalSubtitle };
      };

      let clientGone = false;
      const killFfmpegOnDisconnect = () => {
        if (clientGone) return;
        clientGone = true;
        if (command) {
          try {
            command.kill('SIGKILL');
          } catch (_) {}
          command = null;
        }
      };
      res.on('close', killFfmpegOnDisconnect);
      req.on('close', killFfmpegOnDisconnect);
      req.on('aborted', killFfmpegOnDisconnect);

      res.setHeader('Content-Type', 'video/mp4');
      res.setHeader('Cache-Control', 'no-store');
      // 声明不支持 Range，避免部分客户端在收到 200 整流后又发二次 Range 请求导致重复起播
      res.setHeader('Accept-Ranges', 'none');
      res.setHeader('Connection', 'close');

      const first = await buildAndStart({ disableSubtitle: false });
      first.cmd.on('error', (err, stdout, stderr) => {
        const stderrText = _normalizeText(stderr) || stderrTail.join('\n');
        // console.log(err);
        // if (stderrText) {
        //   console.warn('[stream-mp4] ffmpeg stderr (tail):\n' + stderrText);
        // }

        const canFallback =
          !clientGone &&
          !retriedWithoutSubtitle &&
          (first.actuallyUseExternalSubtitle || (!noSubtitle && subtitleStreamIndex != null)) &&
          (_looksLikeSubtitleError(err, stderrText) ||
            // SIGABRT is often caused by subtitle decode -> mov_text assertion failures
            (String(err && err.message ? err.message : '')
              .toLowerCase()
              .includes('sigabrt') &&
              first.actuallyUseExternalSubtitle));

        if (canFallback) {
          retriedWithoutSubtitle = true;
          console.warn('[stream-mp4] Subtitle failed, retry streaming without subs:', {
            message: err && err.message,
          });
          try {
            if (command) command.kill('SIGKILL');
          } catch (_) {}
          // best-effort restart without external subtitle (and rely on noSubtitle=true semantics for embedded)
          buildAndStart({ disableSubtitle: true }).catch(e => {
            console.warn('[stream-mp4] Retry without subtitle failed:', e && e.message);
            try {
              if (!res.headersSent) res.status(500).end();
              else if (!res.writableEnded) res.end();
            } catch (_) {}
          });
          return;
        }

        if (err && err.message && err.message.indexOf('killed') === -1) {
          try {
            if (!res.headersSent) res.status(500).end();
            else if (!res.writableEnded) res.end();
          } catch (_) {}
        }
      });
      first.cmd.on('end', () => {
        console.log('ffmpeg stream end!!!');
        try {
          if (!res.writableEnded) res.end();
        } catch (_) {}
      });
    } catch (e) {
      if (command) {
        try {
          command.kill('SIGKILL');
        } catch (_) {}
      }
      try {
        if (!res.headersSent) res.status(500).send(e.message || 'Internal Server Error');
      } catch (_) {}
    }
  }

  /**
   * Stop Transcoding
   */
  async stopTranscode(req, res) {
    const playId = req.query.playId || req.body?.playId;
    console.log('暂停转码', playId);
    if (playId) {
      const outDir = await videoPlayerService.getTranscodeOutDir(playId);
      const waitStopped = new Promise(resolve => {
        if (!process.send) return resolve(false);
        let done = false;
        const timer = setTimeout(() => {
          if (done) return;
          done = true;
          process.removeListener('message', onMessage);
          resolve(false);
        }, 6000);

        const onMessage = message => {
          if (!message || message.type !== 'transcodeStopped') return;
          if (!message.data || message.data.playId !== playId) return;
          if (done) return;
          done = true;
          clearTimeout(timer);
          process.removeListener('message', onMessage);
          resolve(!!message.data.stopped);
        };
        process.on('message', onMessage);

        try {
          process.send({ type: 'stopTranscode', data: { playId } });
        } catch (_) {
          clearTimeout(timer);
          process.removeListener('message', onMessage);
          resolve(false);
        }
      });

      setImmediate(async () => {
        const stopped = await waitStopped;
        if (stopped) {
          let deleteResult = await tableVideoTranscodeSession.deleteByPlayId(playId, req.dbVideo).catch(() => null);
          console.log('删除转码session', playId, deleteResult);
        }
        for (let i = 0; i < 30; i++) {
          try {
            await fs.promises.rm(outDir, { recursive: true, force: true });
            break;
          } catch (_) {
            await new Promise(r => setTimeout(r, stopped ? 100 : 200));
          }
        }
      });
    }
    return ResponseUtil.success(req, res, { ok: true });
  }

  /**
   * Save video playback preference
   * Body: filePath, playback_position, subtitle_index, audio_index
   */
  async saveVideoPreference(req, res) {
    try {
      const { filePath, internalPath, playback_position, subtitle_label, audio_label } = req.body || {};
      console.log('saveVideoPreference', filePath, playback_position);
      if (!filePath) {
        return ResponseUtil.error(req, res, 'file.INVALID_PATH');
      }

      await videoPlayerService.saveVideoPreference(req.dbVideo, req.user.id, filePath, {
        playback_position,
        subtitle_label,
        audio_label,
        internalPath,
      });

      return ResponseUtil.success(req, res);
    } catch (e) {
      console.log(e);
      return ResponseUtil.error(req, res, 'videoPlayer.SAVE_PREFERENCE_FAILED', 500, {
        error: e.message,
      });
    }
  }

  /**
   * Upload external subtitle for a video and remember it per-user.
   * Saved under: subtitleUpload/<videoHash>/<uid>/<subtitleFile>
   * Body (multipart): filePath, file
   */
  async uploadSubtitle(req, res) {
    const uid = req.user && req.user.id ? Number(req.user.id) : 0;
    if (!uid) return ResponseUtil.error(req, res, 'auth.UNAUTHORIZED', 401);

    const allowedExts = new Set(['.srt', '.ass', '.vtt', '.ssa', '.sub', '.mks']);

    const storage = multer.diskStorage({
      destination: async function (req2, _file, cb) {
        try {
          const filePath = req2.body && req2.body.filePath ? String(req2.body.filePath).trim() : '';
          if (!filePath) return cb(new Error('videoPlayer.INVALID_PARAMS'));
          const resolved = path.resolve(filePath);
          const videoHash = await FileUtil.getFileHash(resolved);
          if (!videoHash) return cb(new Error('file.INVALID_PATH'));
          const base = config.getSubtitleUploadPath();
          const targetDir = path.join(base, videoHash, String(uid));
          await fsExtra.ensureDir(targetDir);
          cb(null, targetDir);
        } catch (e) {
          cb(e);
        }
      },
      filename: function (_req2, file, cb) {
        const raw = file && file.originalname ? String(file.originalname) : 'subtitle.srt';
        const normalized = normalizeUploadedOriginalName(raw) || raw;
        const base = path
          .basename(normalized)
          .replace(/[\\/:*?"<>|]/g, '_')
          .trim() || 'subtitle.srt';
        cb(null, base);
      },
    });

    const uploader = multer({ storage }).single('file');

    return uploader(req, res, async err => {
      try {
        if (err) {
          return ResponseUtil.error(req, res, err.message || 'operation_failed');
        }
        const filePath = req.body && req.body.filePath ? String(req.body.filePath).trim() : '';
        if (!filePath) return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');
        const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], filePath, 'file');
        if (!ok) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
        const uploaded = req.file;
        if (!uploaded || !uploaded.path) return ResponseUtil.error(req, res, 'operation_failed');

        let savedPath = path.resolve(String(uploaded.path));
        const ext = path.extname(savedPath).toLowerCase();
        if (!allowedExts.has(ext)) {
          try {
            await fsExtra.remove(savedPath);
          } catch (_) {}
          return ResponseUtil.error(req, res, 'videoPlayer.SUBTITLE_UNSUPPORTED');
        }

        // 处理同名冲突：存在则自动加后缀
        try {
          const dir = path.dirname(savedPath);
          const base = path.basename(savedPath, ext);
          let candidate = savedPath;
          for (let i = 1; i <= 50; i++) {
            if (!fs.existsSync(candidate)) break;
            // candidate 已存在（可能是历史文件），尝试新的名字
            candidate = path.join(dir, `${base}_${i}${ext}`);
          }
          if (candidate !== savedPath) {
            await fsExtra.move(savedPath, candidate, { overwrite: false });
            savedPath = candidate;
          }
        } catch (_) {}

        const resolved = path.resolve(filePath);
        const videoHash = await FileUtil.getFileHash(resolved);
        if (!videoHash) return ResponseUtil.error(req, res, 'file.INVALID_PATH');

        const originalNameRaw = uploaded.originalname
          ? String(uploaded.originalname).trim()
          : path.basename(savedPath);
        const originalName = normalizeUploadedOriginalName(originalNameRaw) || originalNameRaw;

        return ResponseUtil.success(req, res, {
          path: savedPath,
          filename: originalName,
          ext,
        });
      } catch (e) {
        return ResponseUtil.error(
          req,
          res,
          'videoPlayer.UPLOAD_SUBTITLE_FAILED',
          500,
          { error: e.message },
        );
      }
    });
  }

  /**
   * Clear all uploaded subtitles for this user+video.
   * Body: filePath
   */
  async clearUploadedSubtitles(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.error(req, res, 'auth.UNAUTHORIZED', 401);
      const filePath = req.body && req.body.filePath ? String(req.body.filePath).trim() : '';
      if (!filePath) return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');
      const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], filePath, 'file');
      if (!ok) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      const resolved = path.resolve(filePath);
      const videoHash = await FileUtil.getFileHash(resolved);
      if (!videoHash) return ResponseUtil.error(req, res, 'file.INVALID_PATH');

      const base = config.getSubtitleUploadPath();
      const dir = path.join(base, String(videoHash), String(uid));
      let deletedFiles = 0;
      try {
        if (fs.existsSync(dir)) {
          // best-effort count
          try {
            const entries = await fs.promises.readdir(dir, { withFileTypes: true });
            deletedFiles = (entries || []).filter(e => e && e.isFile()).length;
          } catch (_) {}
          await fsExtra.remove(dir);
        }
      } catch (_) {}

      return ResponseUtil.success(req, res, {
        deletedRows: 0,
        deletedFiles,
      });
    } catch (e) {
      return ResponseUtil.error(req, res, 'videoPlayer.CLEAR_UPLOADED_SUBTITLE_FAILED', 500, {
        error: e.message,
      });
    }
  }

  /**
   * Search subtitles for a movie file via Thunder service.
   * Body: filePath, searchType('feature'|'keyword'), keyword?
   */
  async searchSubtitle(req, res) {
    try {
      const filePath = req.body && req.body.filePath ? String(req.body.filePath).trim() : '';
      if (!filePath) return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');

      const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], filePath, 'file');
      if (!ok) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      const rawType = req.body && req.body.searchType != null ? String(req.body.searchType).trim() : '';
      const searchType = rawType ? rawType.toLowerCase() : 'feature';

      if (searchType === 'keyword') {
        const keywordRaw = req.body && req.body.keyword != null ? String(req.body.keyword).trim() : '';
        const fallbackKeyword = path.basename(filePath, path.extname(filePath || ''));
        const keyword = keywordRaw || String(fallbackKeyword || '').trim();
        const list = await thunderSubtitleService.searchSubtitlesByKeyword(keyword).catch(() => null);
        return ResponseUtil.success(req, res, {
          items: Array.isArray(list) ? list : [],
          searchType: 'keyword',
          keyword,
        });
      }

      const list = await thunderSubtitleService.searchSubtitlesByMovieFile(filePath).catch(() => null);
      return ResponseUtil.success(req, res, {
        items: Array.isArray(list) ? list : [],
        searchType: 'feature',
      });
    } catch (e) {
      return ResponseUtil.error(req, res, 'videoPlayer.SUBTITLE_SEARCH_FAILED', 500, { error: e.message });
    }
  }

  /**
   * Download one subtitle into configured subtitle upload dir.
   * Body: filePath, surl, sname, language
   */
  async downloadSearchedSubtitle(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.error(req, res, 'auth.UNAUTHORIZED', 401);

      const filePath = req.body && req.body.filePath ? String(req.body.filePath).trim() : '';
      const surl = req.body && req.body.surl ? String(req.body.surl).trim() : '';
      const sname = req.body && req.body.sname ? String(req.body.sname).trim() : '';
      const language = req.body && req.body.language ? String(req.body.language).trim() : '';
      if (!filePath || !surl) return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');

      const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], filePath, 'file');
      if (!ok) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      const saved = await thunderSubtitleService.downloadSubtitleToUploadDir({
        uid,
        filePath,
        subtitle: { surl, sname, language },
      });

      return ResponseUtil.success(req, res, saved);
    } catch (e) {
      if (e && e.code === 'SUBTITLE_NO_SUCH_KEY') {
        return ResponseUtil.error(req, res, 'videoPlayer.SUBTITLE_EXPIRED', 410);
      }
      return ResponseUtil.error(req, res, 'videoPlayer.SUBTITLE_DOWNLOAD_FAILED', 500, { error: e.message });
    }
  }

  /**
   * Delete one external subtitle for current user+video.
   * Only allows deleting files under: subtitleUpload/<videoHash>/<uid>/
   * Body: filePath, subtitlePath
   */
  async deleteExternalSubtitle(req, res) {
    try {
      const uid = req.user && req.user.id ? Number(req.user.id) : 0;
      if (!uid) return ResponseUtil.error(req, res, 'auth.UNAUTHORIZED', 401);

      const filePath = req.body && req.body.filePath ? String(req.body.filePath).trim() : '';
      const subtitlePathRaw =
        req.body && req.body.subtitlePath ? String(req.body.subtitlePath).trim() : '';
      if (!filePath || !subtitlePathRaw) return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');

      const ok = await hasPermission(req.dbMain, req.user, ['download', 'view'], filePath, 'file');
      if (!ok) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      let subtitlePath = subtitlePathRaw;
      try {
        subtitlePath = decodeURIComponent(subtitlePathRaw);
      } catch (_) {}
      const resolvedSub = path.resolve(String(subtitlePath || '').trim());
      if (!resolvedSub) return ResponseUtil.error(req, res, 'videoPlayer.INVALID_PARAMS');

      const resolvedVideo = path.resolve(String(filePath).trim());
      const videoHash = await FileUtil.getFileHash(resolvedVideo);
      if (!videoHash) return ResponseUtil.error(req, res, 'file.INVALID_PATH');

      const base = config.getSubtitleUploadPath();
      const allowedDir = path.join(base, String(videoHash), String(uid));
      const rel = path.relative(allowedDir, resolvedSub);
      const inside = rel && !rel.startsWith('..') && !path.isAbsolute(rel);
      if (!inside) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      // best-effort delete
      try {
        if (fs.existsSync(resolvedSub)) {
          await fsExtra.remove(resolvedSub);
        }
      } catch (e) {
        return ResponseUtil.error(req, res, 'videoPlayer.SUBTITLE_DELETE_FAILED', 500, { error: e.message });
      }

      return ResponseUtil.success(req, res, { ok: true });
    } catch (e) {
      return ResponseUtil.error(req, res, 'videoPlayer.SUBTITLE_DELETE_FAILED', 500, { error: e.message });
    }
  }
}

module.exports = new VideoPlayerController();
