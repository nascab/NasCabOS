const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('../libsPath/ffmpegPath');
const ffprobePath = require('../libsPath/ffprobePath');

ffmpeg.setFfmpegPath(ffmpegPath.path);
ffmpeg.setFfprobePath(ffprobePath.path);

function _toInt(v) {
  const n = Number(v || 0) || 0;
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function _extractFromMeta(meta) {
  const m = meta && typeof meta === 'object' ? meta : null;
  if (!m) {
    return {
      width: 0,
      height: 0,
      duration: 0,
      format: '',
      streams: [],
    };
  }

  let width = 0;
  let height = 0;
  const streams = Array.isArray(m.streams) ? m.streams : [];
  const videoStream = streams.find(s => s && s.codec_type === 'video');
  if (videoStream) {
    width = _toInt(videoStream.width);
    height = _toInt(videoStream.height);
  }

  let duration = 0;
  let format = '';
  const fmt = m.format && typeof m.format === 'object' ? m.format : null;
  if (fmt) {
    duration = Math.max(0, Math.floor(Number(fmt.duration || 0) || 0));
    format = fmt.format_name ? String(fmt.format_name) : '';
  }

  return { width, height, duration, format, streams };
}

function _safeJsonParse(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * 判断视频流是否为 Dolby Vision。
 * 仅依据 ffprobe 返回的流元数据（codec tag / side data / DOVI 配置），不使用文件名。
 */
function isDolbyVisionStream(videoStream) {
  if (!videoStream || typeof videoStream !== 'object') return false;
  const tag = String(videoStream.codec_tag_string || '').toLowerCase();
  if (tag === 'dvhe' || tag === 'dvh1') return true;
  const encoder = videoStream.tags && videoStream.tags.encoder ? String(videoStream.tags.encoder) : '';
  if (/dovi/i.test(encoder)) return true;
  // fluent-ffmpeg/ffprobe 常把 DOVI side data 平铺在 stream 上（MKV Profile 5 常见 hevc + side_data_type）
  const sideDataType = String(videoStream.side_data_type || '').toLowerCase();
  if (sideDataType.includes('dovi') || sideDataType.includes('dolby')) return true;
  const dvProfile = Number(videoStream.dv_profile);
  if (Number.isFinite(dvProfile) && dvProfile > 0) return true;
  if (Number(videoStream.rpu_present_flag) === 1) return true;
  const sideData = Array.isArray(videoStream.side_data_list) ? videoStream.side_data_list : [];
  for (const sd of sideData) {
    const t = String((sd && sd.side_data_type) || '').toLowerCase();
    if (t.includes('dovi') || t.includes('dolby')) return true;
    const profile = Number(sd && sd.dv_profile);
    if (Number.isFinite(profile) && profile > 0) return true;
  }
  return false;
}

/** 缓存的 stream 是否缺少 ffprobe 可提供的 DOVI 探测字段（需 live probe 补全，非文件名推断） */
function cachedVideoStreamMissingDoviProbeFields(videoStream) {
  if (!videoStream || typeof videoStream !== 'object') return false;
  if (isDolbyVisionStream(videoStream)) return false;
  const hasDoviSideData =
    videoStream.side_data_type ||
    videoStream.dv_profile ||
    (Array.isArray(videoStream.side_data_list) && videoStream.side_data_list.length > 0);
  if (hasDoviSideData) return false;
  const codec = String(videoStream.codec_name || '').toLowerCase();
  return codec === 'hevc' || codec === 'h265';
}

function normalizeCacheRow(row) {
  if (!row) return null;
  const widthFromCol = _toInt(row.width);
  const heightFromCol = _toInt(row.height);
  const durationFromCol = _toInt(row.duration);
  const formatFromCol = row.format ? String(row.format) : '';

  const playbackHints = (() => {
    // Preferred: JSON column.
    const jsonText = row.playback_hints != null ? String(row.playback_hints) : '';
    const parsed = _safeJsonParse(jsonText);
    if (parsed && typeof parsed === 'object') return parsed;

    // Backward-compat: older installs may have split columns.
    const majorBrand = row.playback_major_brand != null ? String(row.playback_major_brand) : '';
    const moovAtTail =
      row.playback_moov_at_tail != null ? _toInt(row.playback_moov_at_tail) === 1 : null;
    const preferRemuxMp4 =
      row.playback_prefer_remux_mp4 != null ? _toInt(row.playback_prefer_remux_mp4) === 1 : null;
    const preferredOriginalMode =
      row.playback_preferred_original_mode != null ? String(row.playback_preferred_original_mode) : '';
    const sourceType = row.playback_source_type != null ? String(row.playback_source_type) : '';
    const hasAny =
      !!majorBrand ||
      moovAtTail !== null ||
      preferRemuxMp4 !== null ||
      !!preferredOriginalMode ||
      !!sourceType;
    if (!hasAny) return null;
    return {
      majorBrand,
      moovAtTail: moovAtTail === true,
      preferRemuxMp4: preferRemuxMp4 === true,
      preferredOriginalMode:
        preferredOriginalMode || (preferRemuxMp4 === true ? 'remux_mp4' : 'raw'),
      sourceType,
    };
  })();

  const rawStreams = row.streams ? String(row.streams) : '';
  const parsed = _safeJsonParse(rawStreams);

  if (Array.isArray(parsed)) {
    return {
      width: widthFromCol,
      height: heightFromCol,
      duration: durationFromCol,
      format: formatFromCol,
      streams: parsed,
      streamInfo: rawStreams,
      meta: null,
      fileHash: row.id ? String(row.id) : '',
      playbackHints,
    };
  }

  if (parsed && typeof parsed === 'object') {
    const extracted = _extractFromMeta(parsed);
    return {
      width: widthFromCol || extracted.width,
      height: heightFromCol || extracted.height,
      duration: durationFromCol || extracted.duration,
      format: formatFromCol || extracted.format,
      streams: extracted.streams,
      streamInfo: rawStreams,
      meta: parsed,
      fileHash: row.id ? String(row.id) : '',
      playbackHints,
    };
  }

  return {
    width: widthFromCol,
    height: heightFromCol,
    duration: durationFromCol,
    format: formatFromCol,
    streams: [],
    streamInfo: rawStreams,
    meta: null,
    fileHash: row.id ? String(row.id) : '',
    playbackHints,
  };
}

async function probeVideo(filePath) {
  const full = String(filePath || '');
  if (!full) {
    return {
      width: 0,
      height: 0,
      duration: 0,
      format: '',
      streams: [],
      streamInfo: '',
      meta: null,
    };
  }

  const meta = await new Promise(resolve => {
    ffmpeg.ffprobe(full, (err, data) => {
      if (err) return resolve(null);
      resolve(data);
    });
  });

  if (!meta) {
    return {
      width: 0,
      height: 0,
      duration: 0,
      format: '',
      streams: [],
      streamInfo: '',
      meta: null,
    };
  }

  const extracted = _extractFromMeta(meta);
  let streamInfo = '';
  try {
    streamInfo = JSON.stringify(meta);
  } catch {
    streamInfo = '';
  }

  return { ...extracted, streamInfo, meta };
}

async function upsertFfmpegVideoInfo(knex, fileHash, payload) {
  const k = knex;
  const id = fileHash ? String(fileHash) : '';
  if (!k || !id) return false;

  const v = payload && typeof payload === 'object' ? payload : {};
  // Important: only include keys provided in payload to avoid wiping older columns.
  const row = { id };
  if (v.streamInfo !== undefined) row.streams = v.streamInfo ? String(v.streamInfo) : '';
  if (v.duration !== undefined) row.duration = _toInt(v.duration);
  if (v.format !== undefined) row.format = v.format ? String(v.format) : '';
  if (v.size !== undefined) row.size = _toInt(v.size);
  if (v.mtime !== undefined) row.mtime = _toInt(v.mtime);
  if (v.width !== undefined) row.width = _toInt(v.width);
  if (v.height !== undefined) row.height = _toInt(v.height);
  if (v.create_time !== undefined) row.create_time = _toInt(v.create_time);

  if (v.playback_hints !== undefined) {
    row.playback_hints = v.playback_hints ? String(v.playback_hints) : '';
  }

  // Always set create_time on first insert; don't overwrite if not provided.
  if (row.create_time === undefined) row.create_time = _toInt(Date.now());

  await k('video_ffmpeg_info').insert(row).onConflict('id').merge(row);
  return true;
}

module.exports = {
  normalizeCacheRow,
  probeVideo,
  upsertFfmpegVideoInfo,
  isDolbyVisionStream,
  cachedVideoStreamMissingDoviProbeFields,
};
