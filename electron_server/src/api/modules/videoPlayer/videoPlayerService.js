const path = require('path');
const fs = require('fs');
const Logger = require('../../../utils/logger');
const config = require('../../../config/config');
const tableConfig = require('../../../db/table/tableConfig');
const FileUtil = require('../../../utils/fileUtil');
const VideoFfprobeUtil = require('../../../utils/videoFfprobeUtil');

/** 顶层 box 声明尺寸超过剩余字节时，其后多为厂商私有尾巴；低于此阈值不触发 remux，避免误伤极小填充。 */
const NON_ISO_TRAILING_TAIL_REMUX_THRESHOLD_BYTES = 64 * 1024;

function needsPlaybackHintsTailRefresh(hints, playableFilePath) {
  const ext = path.extname(String(playableFilePath || '')).toLowerCase();
  if (ext !== '.mp4' && ext !== '.mov') return false;
  if (!hints || typeof hints !== 'object') return true;
  // 旧缓存无尾部检测字段时重算一次并写回 DB。
  return !Object.prototype.hasOwnProperty.call(hints, 'largeNonIsoTrailingTail');
}

async function inspectTopLevelBoxes(filePath, maxBoxes = 8) {
  const fullPath = String(filePath || '').trim();
  if (!fullPath) return null;
  let handle = null;
  try {
    handle = await fs.promises.open(fullPath, 'r');
    const stat = await handle.stat();
    const fileSize = Number(stat.size) || 0;
    if (fileSize <= 8) return null;
    const boxes = [];
    let offset = 0;
    let moovBox = null;
    let mdatBox = null;
    let nonIsoTrailingTailBytes = 0;
    let nonIsoTrailingTailStartsAt = null;
    while (offset + 8 <= fileSize) {
      const header = Buffer.alloc(16);
      const { bytesRead } = await handle.read(header, 0, 16, offset);
      if (bytesRead < 8) break;
      let size = header.readUInt32BE(0);
      const type = header.subarray(4, 8).toString('latin1');
      let headerSize = 8;
      if (size === 1) {
        if (bytesRead < 16) break;
        size = Number(header.readBigUInt64BE(8));
        headerSize = 16;
      } else if (size === 0) {
        size = fileSize - offset;
      }
      if (!Number.isFinite(size) || size < headerSize) break;
      const remaining = fileSize - offset;
      if (size > remaining) {
        nonIsoTrailingTailBytes = remaining;
        nonIsoTrailingTailStartsAt = offset;
        break;
      }
      const box = { type, offset, size };
      if (type === 'ftyp') {
        const brandBytes = Buffer.alloc(4);
        const brandRead = await handle.read(brandBytes, 0, 4, offset + headerSize);
        if (brandRead.bytesRead === 4) {
          box.majorBrand = brandBytes.toString('latin1');
        }
      }
      if (type === 'moov' && !moovBox) moovBox = { type, offset, size };
      if (type === 'mdat' && !mdatBox) mdatBox = { type, offset, size };
      if (boxes.length < maxBoxes) boxes.push(box);
      offset += size;
    }
    const largeNonIsoTrailingTail = nonIsoTrailingTailBytes >= NON_ISO_TRAILING_TAIL_REMUX_THRESHOLD_BYTES;
    return {
      fileSize,
      boxes,
      moovBox,
      mdatBox,
      nonIsoTrailingTailBytes,
      nonIsoTrailingTailStartsAt,
      largeNonIsoTrailingTail,
    };
  } catch (_) {
    return null;
  } finally {
    if (handle) {
      try {
        await handle.close();
      } catch (_) { }
    }
  }
}

function _sortDiscFilesByNumericBasename(items) {
  return [...(items || [])].sort((a, b) => {
    const aName = path.basename(String((a && a.path) || '')).toLowerCase();
    const bName = path.basename(String((b && b.path) || '')).toLowerCase();
    const aNum = Number.parseInt(aName.replace(/\D+/g, ''), 10);
    const bNum = Number.parseInt(bName.replace(/\D+/g, ''), 10);
    if (Number.isFinite(aNum) && Number.isFinite(bNum) && aNum !== bNum) return aNum - bNum;
    return aName.localeCompare(bName);
  });
}

class VideoPlayerService {
  constructor() {
    this.transcodeTempRootDir = config.getTranscodeTempPath();
    if (!fs.existsSync(this.transcodeTempRootDir)) {
      fs.mkdirSync(this.transcodeTempRootDir, { recursive: true });
    }
    this._transcodeBaseDirCache = null;
  }

  async listLocalDiscPlayableFiles(filePath) {
    const resolved = path.resolve(String(filePath || '').trim());
    if (!resolved) return [];
    const normalized = resolved.replace(/\\/g, '/');

    const bdmvMatch = normalized.match(/^(.*?)(?:\/BDROM|\/BD_ROM|\/BD-ROM)?\/BDMV\/STREAM\/[^/]+$/i);
    if (bdmvMatch) {
      const discRoot = bdmvMatch[1];
      const streamDir = path.dirname(resolved);
      let entries = [];
      try {
        entries = await fs.promises.readdir(streamDir, { withFileTypes: true });
      } catch (_) {
        entries = [];
      }
      const items = entries
        .filter(ent => ent && ent.isFile() && /\.(m2ts|mts|ssif)$/i.test(String(ent.name || '')))
        .map(ent => ({
          path: path.join(streamDir, ent.name),
          name: ent.name,
          discGroupKey: `bdmv:${discRoot}`,
          discType: 'bdmv',
          selected: path.join(streamDir, ent.name) === resolved,
        }));
      return _sortDiscFilesByNumericBasename(items);
    }

    const videoTsMatch = normalized.match(/^(.*)\/VIDEO_TS\/[^/]+$/i);
    if (videoTsMatch) {
      const videoTsDir = path.dirname(resolved);
      const discRoot = videoTsMatch[1];
      let entries = [];
      try {
        entries = await fs.promises.readdir(videoTsDir, { withFileTypes: true });
      } catch (_) {
        entries = [];
      }
      const items = entries
        .filter(ent => ent && ent.isFile() && /^VTS_\d{2}_\d+\.VOB$/i.test(String(ent.name || '')))
        .filter(ent => {
          const match = /^VTS_\d{2}_(\d+)\.VOB$/i.exec(String(ent.name || ''));
          return match && Number(match[1]) > 0;
        })
        .map(ent => ({
          path: path.join(videoTsDir, ent.name),
          name: ent.name,
          discGroupKey: `video_ts:${discRoot}`,
          discType: 'video_ts',
          selected: path.join(videoTsDir, ent.name) === resolved,
        }));
      return _sortDiscFilesByNumericBasename(items);
    }

    return [];
  }

  async resolvePlaybackSource(filePath) {
    const logicalFilePath = path.resolve(String(filePath || '').trim());
    if (!logicalFilePath) throw new Error('Invalid file path');
    const playableFiles = await this.listLocalDiscPlayableFiles(logicalFilePath).catch(() => []);
    return {
      logicalFilePath,
      playableFilePath: logicalFilePath,
      sourceType: 'file',
      internalPath: '',
      playableFiles,
    };
  }

  async _testWritableDir(dir) {
    const raw = String(dir || '').trim();
    if (!raw) return { ok: false };
    try {
      const st = await fs.promises.stat(raw);
      if (!st.isDirectory()) return { ok: false };
      await fs.promises.access(raw, fs.constants.W_OK);
      const name = `.nascabos_write_test_${Date.now()}_${Math.random().toString(16).slice(2)}.tmp`;
      const p = path.join(raw, name);
      await fs.promises.writeFile(p, 'ok', 'utf8');
      await fs.promises.unlink(p);
      return { ok: true, resolved: raw };
    } catch (_) {
      return { ok: false };
    }
  }

  async resolveTranscodeBaseDir({ force = false } = {}) {
    const safeFolderName = config.getTranscodeTempSafeFolderName();
    const now = Date.now();
    if (!force && this._transcodeBaseDirCache && now - this._transcodeBaseDirCache.checkedAt < 30000) {
      return this._transcodeBaseDirCache.baseDir;
    }

    let configured = '';
    try {
      const v = tableConfig.getConfigByKey('transcodeTempDir');
      configured = v ? String(v).trim() : '';
    } catch (_) { }

    let rootDir = this.transcodeTempRootDir;
    if (configured) {
      const test = await this._testWritableDir(configured);
      if (test.ok && test.resolved) rootDir = test.resolved;
    }

    const baseDir = path.join(rootDir, safeFolderName);
    try {
      await fs.promises.mkdir(baseDir, { recursive: true });
    } catch (_) { }

    this._transcodeBaseDirCache = {
      baseDir,
      checkedAt: now,
      configured,
    };

    return baseDir;
  }

  async getTranscodeOutDirCandidates(playId) {
    const safePlayId = String(playId || '').trim();
    const baseDir = await this.resolveTranscodeBaseDir();
    const candidates = [];
    const safeFolderName = config.getTranscodeTempSafeFolderName();
    const add = v => {
      const p = String(v || '').trim();
      if (!p) return;
      if (candidates.includes(p)) return;
      candidates.push(p);
    };

    add(path.join(baseDir, safePlayId));
    add(path.join(this.transcodeTempRootDir, safeFolderName, safePlayId));
    add(path.join(this.transcodeTempRootDir, safePlayId));
    return candidates;
  }

  /**
   * Get video metadata (streams, duration, etc.)
   * Checks database first, then falls back to ffprobe
   */
  async getCachedOrProbeVideoInfo(db, filePath) {
    const source = await this.resolvePlaybackSource(filePath);
    const logicalFilePath = source.logicalFilePath;
    const playableFilePath = source.playableFilePath;
    const logicalFileHash = await FileUtil.getFileHash(logicalFilePath);
    if (!logicalFileHash) throw new Error('File not found or inaccessible');
    const playbackFileHash = logicalFileHash;
    let videoInfo = null;
    if (db) {
      const cached = await db('video_ffmpeg_info').where({ id: playbackFileHash }).first().catch(() => null);
      if (cached) {
        try {
          const normalized = VideoFfprobeUtil.normalizeCacheRow(cached);
          if (normalized) {
            videoInfo = {
              streams: normalized.streams,
              duration: normalized.duration,
              format: normalized.format,
              width: normalized.width,
              height: normalized.height,
              size: cached.size != null ? Number(cached.size) : undefined,
              source: 'cache',
              meta: normalized.meta,
              playbackHints: normalized.playbackHints || undefined,
            };
          }
        } catch (e) {
          Logger.warn('Failed to parse cached video info', e);
        }
      }
    }

    if (!videoInfo) {
      const probed = await VideoFfprobeUtil.probeVideo(playableFilePath);
      const info = {
        streams: probed.streams,
        duration: probed.duration,
        format: probed.format,
        width: probed.width,
        height: probed.height,
        meta: probed.meta,
      };

      let fileSize;
      try {
        const stat = await fs.promises.stat(playableFilePath);
        fileSize = stat.size;
        if (db) {
          await VideoFfprobeUtil.upsertFfmpegVideoInfo(db, playbackFileHash, {
            streamInfo: probed.streamInfo,
            duration: info.duration,
            format: info.format,
            size: stat.size,
            mtime: stat.mtimeMs,
            width: info.width,
            height: info.height,
            create_time: Date.now(),
          });
        }
      } catch (e) {
        Logger.error('Failed to cache video info', e);
      }

      videoInfo = { ...info, size: fileSize, source: 'probe' };
    } else {
      const streams = Array.isArray(videoInfo.streams) ? videoInfo.streams : [];
      const videoStream = streams.find(s => s && s.codec_type === 'video');
      if (videoStream && VideoFfprobeUtil.cachedVideoStreamMissingDoviProbeFields(videoStream)) {
        const probed = await VideoFfprobeUtil.probeVideo(playableFilePath);
        if (probed && Array.isArray(probed.streams) && probed.streams.length > 0) {
          videoInfo.streams = probed.streams;
          videoInfo.duration = probed.duration || videoInfo.duration;
          videoInfo.format = probed.format || videoInfo.format;
          videoInfo.width = probed.width || videoInfo.width;
          videoInfo.height = probed.height || videoInfo.height;
          videoInfo.meta = probed.meta;
          videoInfo.source = 'probe-refresh-dovi';
          if (db) {
            await VideoFfprobeUtil.upsertFfmpegVideoInfo(db, playbackFileHash, {
              streamInfo: probed.streamInfo,
              duration: probed.duration,
              format: probed.format,
              width: probed.width,
              height: probed.height,
            }).catch(() => null);
          }
        }
      }
    }

    return { videoInfo, source, logicalFilePath, playableFilePath, logicalFileHash, playbackFileHash };
  }

  async getVideoInfo(db, filePath, opts = {}) {
    const { videoInfo, source, logicalFilePath, playableFilePath, logicalFileHash } = await this.getCachedOrProbeVideoInfo(db, filePath);

    // Build / reuse playback hints (cached in video_ffmpeg_info by file_hash).
    if (!videoInfo.playbackHints || needsPlaybackHintsTailRefresh(videoInfo.playbackHints, playableFilePath)) {
      try {
        const ext = path.extname(playableFilePath).toLowerCase();
        const formatTags =
          videoInfo.meta && videoInfo.meta.format && videoInfo.meta.format.tags
            ? videoInfo.meta.format.tags
            : {};
        const majorBrandRaw =
          formatTags && formatTags.major_brand != null
            ? String(formatTags.major_brand)
            : '';
        const atomInfo = await inspectTopLevelBoxes(playableFilePath);
        const atomBoxes = atomInfo && Array.isArray(atomInfo.boxes) ? atomInfo.boxes : [];
        const atomMajorBrand =
          atomBoxes.find(box => box && box.type === 'ftyp' && box.majorBrand)?.majorBrand || '';
        const isMp4OrMov = ext === '.mov' || ext === '.mp4';
        const isMov = ext === '.mov'
        const moovBox = atomInfo && atomInfo.moovBox;
        const mdatBox = atomInfo && atomInfo.mdatBox;
        const moovAtTail = isMp4OrMov && Boolean(moovBox && mdatBox && moovBox.offset > mdatBox.offset);
        const largeNonIsoTrailingTail =
          isMp4OrMov && Boolean(atomInfo && atomInfo.largeNonIsoTrailingTail);
        const nonIsoTrailingTailBytes =
          atomInfo && Number.isFinite(atomInfo.nonIsoTrailingTailBytes)
            ? Math.trunc(atomInfo.nonIsoTrailingTailBytes)
            : 0;
        // 仅 mdat 后存在大块非标尾部（如部分机录 MP4 的厂商元数据）时 remux；
        // moov 在尾部仍走 rawFile，客户端一次 Range 读 moov 即可。
        const preferRemuxMp4 = largeNonIsoTrailingTail || (isMp4OrMov && moovAtTail);
        const playbackHints = {
          majorBrand: majorBrandRaw || atomMajorBrand || '',
          moovAtTail,
          largeNonIsoTrailingTail,
          nonIsoTrailingTailBytes,
          preferRemuxMp4,
          preferredOriginalMode: preferRemuxMp4 ? 'remux_mp4' : 'raw',
          sourceType: source.sourceType,
        };
        videoInfo.playbackHints = playbackHints;

        // Cache hints for next open (best-effort).
        if (db && logicalFileHash) {
          let hintsJson = '';
          try {
            hintsJson = JSON.stringify(playbackHints || {});
          } catch (_) {
            hintsJson = '';
          }
          await VideoFfprobeUtil.upsertFfmpegVideoInfo(db, logicalFileHash, {
            playback_hints: hintsJson,
          }).catch(() => null);
        }
      } catch (err) {
        Logger.warn('Failed to build playback hints', err);
      }
    }

    const ignoreFindSub = opts && String(opts.ignoreFindSub || '').trim() === '1';
    // 查找同一文件夹下的外挂字幕（可跳过以提升打开速度；不影响用户上传字幕）
    if (!ignoreFindSub) {
      console.log("查找外挂字幕")
      try {
        const dir = path.dirname(logicalFilePath);
        const ext = path.extname(logicalFilePath);
        const basename = path.basename(logicalFilePath, ext); // 不含后缀的文件名

        const files = await fs.promises.readdir(dir);
        const subtitleExts = ['.srt', '.ass', '.vtt', '.mks', '.sub', '.ssa'];
        const externalSubtitles = [];

        for (const file of files) {
          const fileExt = path.extname(file).toLowerCase();
          if (subtitleExts.includes(fileExt)) {
            const fileBasename = path.basename(file, fileExt);
            // 匹配规则：字幕文件名必须以视频基础名开头
            // 例如 video.mkv -> video.srt, video.zh.srt
            if (fileBasename.startsWith(basename)) {
              const suffix = fileBasename.slice(basename.length);
              if (suffix === '' || suffix.startsWith('.')) {
                const subPath = path.join(dir, file);
                externalSubtitles.push({
                  path: subPath,
                  filename: file,
                  ext: fileExt,
                });
              }
            }
          }
        }

        if (externalSubtitles.length > 0) {
          videoInfo.externalSubtitles = externalSubtitles;
        }
      } catch (e) {
        Logger.warn('Failed to scan external subtitles', e);
      }
    }

    // 查找该用户曾上传的外挂字幕（同一视频）：纯文件系统扫描 subtitleUpload/<videoHash>/<uid>/
    try {
      const uid = opts && opts.uid != null ? Number(opts.uid) : 0;
      if (uid && logicalFileHash) {
        const base = config.getSubtitleUploadPath();
        const uploadDir = path.join(base, String(logicalFileHash), String(uid));
        const subtitleExts = new Set(['.srt', '.ass', '.vtt', '.mks', '.sub', '.ssa']);
        let entries = [];
        try {
          entries = await fs.promises.readdir(uploadDir, { withFileTypes: true });
        } catch (_) {
          entries = [];
        }
        if (entries && entries.length > 0) {
          const uploaded = [];
          for (const ent of entries) {
            if (!ent || !ent.isFile()) continue;
            const name = String(ent.name || '').trim();
            if (!name) continue;
            const ext = path.extname(name).toLowerCase();
            if (!subtitleExts.has(ext)) continue;
            const p = path.join(uploadDir, name);
            uploaded.push({
              path: p,
              filename: name,
              ext,
              source: 'uploaded',
            });
          }
          if (uploaded.length > 0) {
            const existing = Array.isArray(videoInfo.externalSubtitles)
              ? videoInfo.externalSubtitles
              : [];
            const seen = new Set(existing.map(s => (s && s.path ? String(s.path).trim() : '')));
            for (const s of uploaded) {
              if (!s || !s.path) continue;
              if (seen.has(s.path)) continue;
              existing.push(s);
              seen.add(s.path);
            }
            if (existing.length > 0) {
              videoInfo.externalSubtitles = existing;
            }
          }
        }
      }
    } catch (e) {
      Logger.warn('Failed to scan uploaded subtitles', e);
    }

    if (videoInfo && Object.prototype.hasOwnProperty.call(videoInfo, 'meta')) {
      delete videoInfo.meta;
    }
    const indexRow = await db('video_index')
      .where({ file_hash: logicalFileHash, is_file: 1 })
      .first('open_skip_start_sec', 'open_skip_end_sec')
      .catch(() => null);
    videoInfo.openSkip = {
      startSec: Math.max(0, Number(indexRow && indexRow.open_skip_start_sec) || 0),
      endSec: Math.max(0, Number(indexRow && indexRow.open_skip_end_sec) || 0),
    };
    if (Array.isArray(source.playableFiles) && source.playableFiles.length > 0) {
      videoInfo.playableFiles = source.playableFiles;
    }
    // 与缓存字段对齐：仅非标尾部触发 remux_mp4（避免旧缓存里 moovAtTail 误开 remux）
    if (videoInfo.playbackHints && typeof videoInfo.playbackHints === 'object') {
      const ext = path.extname(playableFilePath).toLowerCase();
      const isMovOrMp4 = ext === '.mov' || ext === '.mp4'
      const useRemux =
        (videoInfo.playbackHints.largeNonIsoTrailingTail === true)
        || (isMovOrMp4 && videoInfo.playbackHints.moovAtTail)
      videoInfo.playbackHints.preferRemuxMp4 = useRemux;
      videoInfo.playbackHints.preferredOriginalMode = useRemux ? 'remux_mp4' : 'raw';
    }
    const streams = Array.isArray(videoInfo.streams) ? videoInfo.streams : [];
    const videoStream = streams.find(s => s && s.codec_type === 'video') || null;
    videoInfo.isDolbyVision = VideoFfprobeUtil.isDolbyVisionStream(videoStream);
    return videoInfo;
  }
  safeGetTrim(str) {
    const s = String(str || '').trim();
    return s.length > 0 ? s : "";
  }
  /**
   * Start or get existing HLS transcoding session
   * Deprecated: Use IPC to start transcode worker
   */
  async startTranscoding(_filePath, _playId, _options = {}) {
    throw new Error('Deprecated: Use IPC');
  }

  stopTranscoding(_playId) {
    // Deprecated
  }

  async getTranscodeOutDir(playId) {
    const candidates = await this.getTranscodeOutDirCandidates(playId);
    for (const dir of candidates) {
      try {
        if (fs.existsSync(dir)) return dir;
      } catch (_) { }
    }
    const baseDir = await this.resolveTranscodeBaseDir();
    return path.join(baseDir, String(playId || '').trim());
  }

  async saveVideoPreference(db, uid, filePath, preference) {
    const logicalFilePath = path.resolve(String(filePath || '').trim());
    const logicalFileHash = await FileUtil.getFileHash(logicalFilePath);
    if (!logicalFileHash) throw new Error('File not found');
    const fileHash = logicalFileHash;
    await db('video_play_preference')
      .insert({
        uid: uid,
        file_hash: fileHash,
        playback_position: preference.playback_position || 0,
        subtitle_label: preference.subtitle_label,
        audio_label: preference.audio_label,
        last_watched_at: db.fn.now(),
      })
      .onConflict(['uid', 'file_hash'])
      .merge();
  }

  async getVideoPreference(db, uid, filePath) {
    const logicalFilePath = path.resolve(String(filePath || '').trim());
    const logicalFileHash = await FileUtil.getFileHash(logicalFilePath);
    if (!logicalFileHash) return null;
    const fileHash = logicalFileHash;

    return await db('video_play_preference').where({ uid, file_hash: fileHash }).first();
  }
}

module.exports = new VideoPlayerService();
