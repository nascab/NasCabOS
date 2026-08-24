const ffmpeg = require('fluent-ffmpeg');
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');
const Logger = require('../utils/logger');
const config = require('../config/config');
const ffmpegPath = require('../libsPath/ffmpegPath');
const ffprobePath = require('../libsPath/ffprobePath');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const tableConfig = require('../db/table/tableConfig');
const tableVideoTranscodeSession = require('../db/table/tableVideoTranscodeSession');
const FileUtil = require('../utils/fileUtil');
const VideoFfprobeUtil = require('../utils/videoFfprobeUtil');
const { normalizeAvailableHwAccelList, pickEffectiveHwAccelConfig } = require('../utils/transcodeHwAccelUtil');
// 字幕字体大小
const subtitleFontSize = 24;
// 说明：
// - 本 Worker 专门负责把单个视频文件转码成 HLS（m3u8 + ts 分片）
// - 上层通过 IPC 传入 playId / filePath / options
// - 为了避免画面变形，缩放只指定目标宽度，高度使用 -2 自适应并保持宽高比

// Set FFmpeg paths
ffmpeg.setFfmpegPath(ffmpegPath.path);
ffmpeg.setFfprobePath(ffprobePath.path);

let currentCommand = null;
let hwAccelConfigLoaded = false;
let hwAccelConfig = null;
let dbInitialized = false;
let knexVideo = null;
let currentPlayId = '';
let idleMonitorTimer = null;
let idleStopTriggered = false;
let READ_RATE = 5; // 读取文件倍率
/** CUDA 全链路 scale_cuda 需预分配 hw frame；64 对部分 HEVC（如剪映导出）会触发 hevc_cuvid 解码死循环 */
const CUDA_EXTRA_HW_FRAMES = 8;
const CUDA_CUVID_STALL_ERROR_THRESHOLD = 25;
async function ensureDbInit() {
  // 读取硬件加速配置需要访问本地数据库，这里做一次性初始化
  if (dbInitialized) return;
  try {
    await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);
    knexVideo = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    dbInitialized = true;
  } catch (e) {
    Logger.error('[TranscodeWorker] DB init failed', e);
    dbInitialized = true;
  }
}

async function getHwAccelConfig() {
  // 从配置表读取“自动选择 + 用户首选”的转码硬件方案，用户首选命中时优先使用
  if (hwAccelConfigLoaded) return hwAccelConfig;
  hwAccelConfigLoaded = true;
  try {
    await ensureDbInit();
    const [selectedRaw, availableRaw, preferredRaw] = await Promise.all([
      tableConfig.getConfigByKey('transcode_hwaccel_selected'),
      tableConfig.getConfigByKey('transcode_hwaccel_available'),
      tableConfig.getConfigByKey('transcode_hwaccel_preferred'),
    ]);
    try {
      hwAccelConfig = pickEffectiveHwAccelConfig({
        availableList: normalizeAvailableHwAccelList(availableRaw),
        preferredKey: preferredRaw ? String(preferredRaw).trim() : '',
        autoSelected: selectedRaw ? JSON.parse(String(selectedRaw)) : null,
      });
    } catch (e) {
      Logger.error('[TranscodeWorker] parse transcode HW config failed', e);
      hwAccelConfig = null;
    }
  } catch (e) {
    Logger.error('[TranscodeWorker] read transcode HW config failed', e);
    hwAccelConfig = null;
  }
  return hwAccelConfig;
}

function buildFfmpegOptionPairs(args) {
  // 把形如 ['-hwaccel','cuda','-extra_hw_frames','8'] 的数组，转换成 fluent-ffmpeg 可接受的参数
  if (!Array.isArray(args) || args.length === 0) return [];
  const result = [];
  for (let i = 0; i < args.length; i++) {
    const key = args[i];
    const value = args[i + 1];
    if (typeof key === 'string' && key.startsWith('-')) {
      if (typeof value === 'string' && !value.startsWith('-')) {
        result.push(`${key} ${value}`);
        i++;
      } else {
        result.push(key);
      }
    } else if (typeof key === 'string') {
      result.push(key);
    }
  }
  return result;
}

function escapeForSubtitlesFilter(filePath) {
  // subtitles 滤镜里路径需要做转义，否则 Windows 路径/冒号/引号容易导致 filter 解析失败
  let v = String(filePath);
  v = v.replace(/\\/g, '/');
  v = v.replace(/'/g, "\\\\'");
  v = v.replace(/:/g, '\\:');
  return v;
}

function parseTargetWidth(options) {
  // 兼容参数：优先使用 width（新协议），否则从 resolution（旧协议 1920x1080）里取宽度
  if (!options) return null;
  const w = Number(options.width);
  if (Number.isFinite(w) && w > 0) return Math.floor(w);
  const size = parseResolution(options.resolution);
  return size ? size.w : null;
}

function parseResolution(resolution) {
  if (!resolution) return null;
  const m = String(resolution)
    .trim()
    .match(/^(\d+)\s*x\s*(\d+)$/i);
  if (!m) return null;
  const w = Number(m[1]);
  const h = Number(m[2]);
  if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0) return null;
  return { w, h };
}

function toEvenNumber(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const i = Math.floor(n);
  if (i <= 0) return null;
  return i % 2 === 0 ? i : i - 1;
}

function parseFpsFromVideoStream(stream) {
  if (!stream || typeof stream !== 'object') return null;
  const raw = stream.avg_frame_rate || stream.r_frame_rate;
  if (!raw || raw === '0/0') return null;
  const m = String(raw).trim().match(/^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/);
  if (!m) return null;
  const num = Number(m[1]);
  const den = Number(m[2]);
  if (!Number.isFinite(num) || !Number.isFinite(den) || den === 0) return null;
  const fps = num / den;
  if (!Number.isFinite(fps) || fps < 1 || fps > 240) return null;
  return fps;
}

/** HLS 只在关键帧切片；硬件编码常忽略 force_key_frames，故 GOP 需 ≈ segDur×fps（未知 fps 按 24 估，略多插 I 帧） */
function computeHlsGopFrames(segDurSeconds, videoStream) {
  const seg = Number(segDurSeconds);
  if (!Number.isFinite(seg) || seg <= 0) return 48;
  const fps = parseFpsFromVideoStream(videoStream);
  const refFps = fps != null ? fps : 24;
  let gop = Math.round(seg * refFps);
  gop = Math.max(12, gop);
  gop = Math.min(gop, 720);
  if (gop % 2 !== 0) gop += 1;
  return gop;
}

function isQsvVideoEncoder(encoder) {
  const e = String(encoder || '').toLowerCase();
  return e === 'h264_qsv' || e === 'hevc_qsv';
}

function isVideotoolboxEncoder(encoder) {
  const e = String(encoder || '').toLowerCase();
  return e === 'h264_videotoolbox' || e === 'hevc_videotoolbox';
}

/** WMV/ASF 容器 + VC-1/WMV3 视频；音轨常见 wmapro。与 MP4/MKV 不同，ASF 上 input -ss 落点常非 IDR。 */
function isWmvFamilySource(filePath, videoStreamInfo) {
  const ext = path.extname(String(filePath || '')).toLowerCase();
  if (ext === '.wmv' || ext === '.asf' || ext === '.wma') return true;
  const codec = String((videoStreamInfo && videoStreamInfo.codec_name) || '').toLowerCase();
  return codec === 'vc1' || codec === 'wmv3' || codec === 'wmv2';
}

/**
 * WMV/VC-1 从头转码可走 VideoToolbox；带进度 seek 时 VT 常忽略 force_key_frames，
 * HLS 首段缺少 IDR 会导致播放器报错（其它 H.264 容器 seek 后仍较易出 I 帧）。
 */
function wmvSeekRequiresCpuEncode(filePath, videoStreamInfo, seekSeconds) {
  const seek = Number(seekSeconds);
  if (!Number.isFinite(seek) || seek <= 0) return false;
  return isWmvFamilySource(filePath, videoStreamInfo);
}

/**
 * ffprobe 视频轨上的宽高（含 coded_*，且 0 会视为无效并回退另一字段）。
 * 极少数容器/流 width、height 均缺失时返回 null，此时 CPU 侧 scale=w=iw*sar 仍依赖解码后的实际帧尺寸。
 */
function getVideoStreamPixelDimensions(videoStream) {
  if (!videoStream || typeof videoStream !== 'object') return { w: null, h: null };
  const wRaw = videoStream.width || videoStream.coded_width;
  const hRaw = videoStream.height || videoStream.coded_height;
  const w = toEvenNumber(wRaw);
  const h = toEvenNumber(hRaw);
  return { w, h };
}

/** 10/12-bit 源（如 x264 High 10 BDRip）：h264_cuvid + 输入侧 -ss + scale_cuda 易卡住或画面异常，禁止 CUDA cuvid 全链路 */
function isHighBitDepthVideoStream(videoStream) {
  if (!videoStream || typeof videoStream !== 'object') return false;
  const bits = Number(videoStream.bits_per_raw_sample);
  if (Number.isFinite(bits) && bits > 8) return true;
  const pixFmt = String(videoStream.pix_fmt || '').toLowerCase();
  if (/10le|12le|p010|p016|yuv444p1[02]|gbrap1[02]/.test(pixFmt)) return true;
  const profile = String(videoStream.profile || '').toLowerCase();
  if (/\b10\b|high 10|main 10|main10/.test(profile)) return true;
  return false;
}

function streamHasNonSquareSar(videoStream) {
  if (!videoStream || typeof videoStream !== 'object') return false;
  const sar = videoStream.sample_aspect_ratio;
  if (!sar || sar === 'N/A' || sar === '0:1') return false;
  const m = String(sar)
    .trim()
    .match(/^(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)$/);
  if (!m) return false;
  const num = Number(m[1]);
  const den = Number(m[2]);
  if (!Number.isFinite(num) || !Number.isFinite(den) || den === 0) return false;
  return Math.abs(num / den - 1) > 0.001;
}

const isDolbyVisionStream = VideoFfprobeUtil.isDolbyVisionStream;

function getHdrSourceRange(videoStream) {
  const r = String((videoStream && videoStream.color_range) || '').toLowerCase();
  if (r === 'pc' || r === 'jpeg' || r === 'full') return 'pc';
  if (r === 'tv' || r === 'mpeg' || r === 'limited') return 'tv';
  // DV P5 基底层常见为 full range，probe 未带 color_range 时按 pc 处理
  if (isDolbyVisionStream(videoStream)) return 'pc';
  return 'tv';
}

function streamNeedsHdrToSdr(videoStream) {
  if (!videoStream || typeof videoStream !== 'object') return false;
  if (isDolbyVisionStream(videoStream)) return true;
  const trc = String(videoStream.color_transfer || '').toLowerCase();
  if (trc === 'smpte2084' || trc === 'arib-std-b67') return true;
  const primaries = String(videoStream.color_primaries || '').toLowerCase();
  if (primaries === 'bt2020') return true;
  const space = String(videoStream.color_space || '').toLowerCase();
  return space === 'bt2020nc' || space === 'bt2020c';
}

const HDR_TONEMAP_LIBPLACEBO = 'libplacebo';
const HDR_TONEMAP_OPENCL = 'opencl';
const HDR_TONEMAP_VIDEOTOOLBOX = 'videotoolbox';
const HDR_TONEMAP_FALLBACK = 'fallback';

let hdrTonemapCapsCache = null;

function getHdrTonemapCapabilities() {
  if (hdrTonemapCapsCache) return hdrTonemapCapsCache;
  let filtersText = '';
  try {
    filtersText = execFileSync(ffmpegPath.path, ['-filters'], { encoding: 'utf8', timeout: 15000 });
  } catch (e) {
    filtersText = `${e.stdout || ''}${e.stderr || ''}`;
  }
  hdrTonemapCapsCache = {
    libplacebo: /\blibplacebo\b/.test(filtersText),
    tonemapOpencl: /\btonemap_opencl\b/.test(filtersText),
    tonemapVideotoolbox: /\btonemap_videotoolbox\b/.test(filtersText),
    scaleVt: /\bscale_vt\b/.test(filtersText),
  };
  return hdrTonemapCapsCache;
}

/**
 * Windows + NVIDIA/AMD：libplacebo + Vulkan。
 * Windows + Intel QSV：OpenCL tonemap（libplacebo Vulkan 直出 nv12 经 QSV 编码会严重偏绿）。
 * macOS：DV P5 优先 OpenCL apply_dovi；HDR10 走 VideoToolbox Metal。
 */
function pickHdrTonemapStrategy(videoStreamInfo, videoCodec) {
  const caps = getHdrTonemapCapabilities();
  if (process.platform === 'win32' && isQsvVideoEncoder(videoCodec) && caps.tonemapOpencl) {
    return HDR_TONEMAP_OPENCL;
  }
  if (caps.libplacebo) return HDR_TONEMAP_LIBPLACEBO;
  if (process.platform !== 'darwin') return HDR_TONEMAP_FALLBACK;
  if (isDolbyVisionStream(videoStreamInfo) && caps.tonemapOpencl) return HDR_TONEMAP_OPENCL;
  if (caps.tonemapVideotoolbox) return HDR_TONEMAP_VIDEOTOOLBOX;
  return HDR_TONEMAP_FALLBACK;
}

function getHdrTonemapFallbackStrategy(currentStrategy, videoStreamInfo, videoCodec) {
  const caps = getHdrTonemapCapabilities();
  if (currentStrategy === HDR_TONEMAP_OPENCL) {
    if (caps.libplacebo) return HDR_TONEMAP_LIBPLACEBO;
    return HDR_TONEMAP_FALLBACK;
  }
  if (currentStrategy === HDR_TONEMAP_LIBPLACEBO) {
    if (process.platform === 'darwin' && isDolbyVisionStream(videoStreamInfo) && caps.tonemapOpencl) {
      return HDR_TONEMAP_OPENCL;
    }
    return HDR_TONEMAP_FALLBACK;
  }
  if (currentStrategy === HDR_TONEMAP_VIDEOTOOLBOX) {
    return HDR_TONEMAP_FALLBACK;
  }
  return HDR_TONEMAP_FALLBACK;
}

function buildLibplaceboTonemapOptions({ applyDolbyVision = false, outputFormat = 'yuv420p' } = {}) {
  const opts = [];
  if (applyDolbyVision) {
    opts.push('apply_dolbyvision=1');
  }
  opts.push('tonemapping=hable');
  opts.push(applyDolbyVision ? 'peak_detect=true' : 'peak_detect=false');
  if (applyDolbyVision) {
    opts.push('smoothing_period=100');
  }
  opts.push(
    'colorspace=bt709',
    'color_primaries=bt709',
    'color_trc=bt709',
    'range=limited',
    `format=${outputFormat}`
  );
  return opts.join(':');
}

/** libplacebo Vulkan 帧必须先 hwdownload 为 yuv420p，不可直出 nv12（经 QSV 编码会严重偏绿） */
function buildLibplaceboPostTonemapSteps(videoCodec) {
  const steps = ['format=yuv420p', 'setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv'];
  if (isQsvVideoEncoder(videoCodec)) {
    steps.push('format=nv12');
  }
  return steps;
}

function buildLibplaceboHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo) {
  const steps = [];
  if (isVideotoolboxEncoder(videoCodec) && streamHasNonSquareSar(videoStreamInfo)) {
    steps.push('scale=w=iw*sar:h=ih');
  }
  const w = toEvenNumber(targetWidth);
  const placeboBase = buildLibplaceboTonemapOptions({ outputFormat: 'yuv420p' });
  const placebo = w ? `libplacebo=w=${w}:h=-2:${placeboBase}` : `libplacebo=${placeboBase}`;
  steps.push('hwupload=derive_device=vulkan', placebo, 'hwdownload', ...buildLibplaceboPostTonemapSteps(videoCodec));
  return steps;
}

/**
 * Dolby Vision Profile 5 使用 IPTPQc2，须 libplacebo apply_dolbyvision 解析 RPU。
 * Jellyfin FFmpeg 8.x 已能正确完成 DV→SDR tonemap，无需 colorchannelmixer / geq 补偿。
 */
function buildDolbyVisionP5LibplaceboSdrSteps(targetWidth, videoCodec, videoStreamInfo) {
  const steps = [];
  if (isVideotoolboxEncoder(videoCodec) && streamHasNonSquareSar(videoStreamInfo)) {
    steps.push('scale=w=iw*sar:h=ih');
  }
  const w = toEvenNumber(targetWidth);
  const placeboBase = buildLibplaceboTonemapOptions({ applyDolbyVision: true, outputFormat: 'yuv420p' });
  const placebo = w ? `libplacebo=w=${w}:h=-2:${placeboBase}` : `libplacebo=${placeboBase}`;
  steps.push('hwupload=derive_device=vulkan', placebo, 'hwdownload', ...buildLibplaceboPostTonemapSteps(videoCodec));
  return steps;
}

/**
 * macOS OpenCL：apply_dovi 可解析 DV RPU，是 libplacebo 不可用时的首选（Jellyfin 早期 Mac 方案）。
 */
function buildOpenClTonemapFilterOptions(videoStreamInfo, { applyDolbyVision = false, outputRange = null } = {}) {
  const range = outputRange || getHdrSourceRange(videoStreamInfo);
  const opts = ['tonemap=hable', 'p=bt709', 't=bt709', 'm=bt709', `range=${range}`, 'format=yuv420p'];
  if (applyDolbyVision) {
    opts.push('apply_dovi=1');
  }
  return opts.join(':');
}

function buildOpenClPostTonemapSteps(videoCodec) {
  const steps = ['hwdownload', 'format=yuv420p', 'setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv'];
  if (isQsvVideoEncoder(videoCodec)) {
    steps.push('format=nv12');
  }
  return steps;
}

function buildOpenClHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo, { applyDolbyVision = false } = {}) {
  const steps = [];
  if (isVideotoolboxEncoder(videoCodec) && streamHasNonSquareSar(videoStreamInfo)) {
    steps.push('scale=w=iw*sar:h=ih');
  }
  const w = toEvenNumber(targetWidth);
  if (w) {
    steps.push(`scale=w=${w}:h=-2`);
  }
  const outputRange = isQsvVideoEncoder(videoCodec) ? 'tv' : null;
  const tonemap = `tonemap_opencl=${buildOpenClTonemapFilterOptions(videoStreamInfo, { applyDolbyVision, outputRange })}`;
  steps.push(`format=p010le,hwupload=derive_device=opencl,${tonemap}`);
  steps.push(...buildOpenClPostTonemapSteps(videoCodec));
  return steps;
}

function buildDolbyVisionP5OpenClSdrSteps(targetWidth, videoCodec, videoStreamInfo) {
  return buildOpenClHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo, { applyDolbyVision: true });
}

/**
 * macOS VideoToolbox Metal tonemap（HDR10/HLG；Jellyfin 不推荐用于 DV P5 原生 VT，此处作 HDR 或兜底）。
 */
function buildVideotoolboxHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo) {
  const caps = getHdrTonemapCapabilities();
  const steps = [];
  if (isVideotoolboxEncoder(videoCodec) && streamHasNonSquareSar(videoStreamInfo)) {
    steps.push('scale=w=iw*sar:h=ih');
  }
  steps.push('format=nv12|p010le|videotoolbox_vld', 'hwupload');
  const w = toEvenNumber(targetWidth);
  if (w && caps.scaleVt) {
    steps.push(`scale_vt=w=${w}:h=-2:format=p010le`);
  } else if (w) {
    steps.push(`scale=w=${w}:h=-2`);
  }
  const range = getHdrSourceRange(videoStreamInfo);
  const tonemap = `tonemap_videotoolbox=format=nv12:p=bt709:t=bt709:m=bt709:tonemap=hable:range=${range}`;
  steps.push(tonemap);
  if (!isVideotoolboxEncoder(videoCodec)) {
    steps.push('hwdownload,format=nv12');
  }
  return steps;
}

function buildDolbyVisionP5VideotoolboxSdrSteps(targetWidth, videoCodec, videoStreamInfo) {
  return buildVideotoolboxHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo);
}

/** Vulkan/libplacebo 不可用时的 DV P5 兜底（无法解析 RPU，仅减弱偏紫） */
function buildDolbyVisionP5ColorfixFallbackSteps(targetWidth, videoCodec, videoStreamInfo) {
  const steps = [];
  if (isVideotoolboxEncoder(videoCodec) && streamHasNonSquareSar(videoStreamInfo)) {
    steps.push('scale=w=iw*sar:h=ih');
  }
  const w = toEvenNumber(targetWidth);
  if (w) {
    steps.push(`scale=w=${w}:h=-2`);
  }
  steps.push(
    'format=gbrp',
    'colorchannelmixer=rr=1:rg=-0.05:rb=-0.08:gr=0:gg=1.08:gb=0:br=-0.08:bg=0:bb=0.92'
  );
  const range = getHdrSourceRange(videoStreamInfo);
  steps.push(`format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=${range}`);
  return steps;
}

function buildZscaleHdrToSdrFallbackSteps(targetWidth, videoStreamInfo) {
  const range = getHdrSourceRange(videoStreamInfo);
  const steps = [
    `setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc:range=${range}`,
    'zscale=t=linear:npl=100',
    'format=gbrpf32le',
    'zscale=p=bt709',
    'tonemap=tonemap=hable:desat=0',
    'zscale=t=bt709:m=bt709:r=tv',
    'format=yuv420p',
  ];
  const w = toEvenNumber(targetWidth);
  if (w) {
    steps.push(`scale=w=${w}:h=-2`);
  }
  return steps;
}

function buildHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo, tonemapStrategy) {
  if (isDolbyVisionStream(videoStreamInfo)) {
    if (tonemapStrategy === HDR_TONEMAP_LIBPLACEBO) {
      return buildDolbyVisionP5LibplaceboSdrSteps(targetWidth, videoCodec, videoStreamInfo);
    }
    if (tonemapStrategy === HDR_TONEMAP_OPENCL) {
      return buildDolbyVisionP5OpenClSdrSteps(targetWidth, videoCodec, videoStreamInfo);
    }
    if (tonemapStrategy === HDR_TONEMAP_VIDEOTOOLBOX) {
      return buildDolbyVisionP5VideotoolboxSdrSteps(targetWidth, videoCodec, videoStreamInfo);
    }
    return buildDolbyVisionP5ColorfixFallbackSteps(targetWidth, videoCodec, videoStreamInfo);
  }
  if (tonemapStrategy === HDR_TONEMAP_LIBPLACEBO) {
    return buildLibplaceboHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo);
  }
  if (tonemapStrategy === HDR_TONEMAP_OPENCL) {
    return buildOpenClHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo);
  }
  if (tonemapStrategy === HDR_TONEMAP_VIDEOTOOLBOX) {
    return buildVideotoolboxHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo);
  }
  return buildZscaleHdrToSdrFallbackSteps(targetWidth, videoStreamInfo);
}

/**
 * CPU 侧缩放步骤：VideoToolbox 对「带非 1:1 SAR 的帧」再 scale 时易比例错误，先在像素上按 SAR 拉成方形像素（iw*sar × ih），再按目标宽度缩放。
 * QSV 仍用 force_divisible_by（若 FFmpeg 过旧无该选项需另处理）。
 * 首步 iw*sar 使用解码帧的 iw/ih，不依赖 probe 是否带 width/height。
 */
function buildCpuVideoScaleSteps(targetWidth, videoCodec, videoStreamInfo, options = {}) {
  const skipTargetScale = !!(options && options.skipTargetScale);
  const w = toEvenNumber(targetWidth);
  const steps = [];
  if (isVideotoolboxEncoder(videoCodec) && streamHasNonSquareSar(videoStreamInfo)) {
    steps.push('scale=w=iw*sar:h=ih');
  }
  if (w && !skipTargetScale) {
    if (isQsvVideoEncoder(videoCodec)) {
      steps.push(`scale=w=${w}:h=-2:force_divisible_by=2`);
    } else {
      steps.push(`scale=w=${w}:h=-2`);
    }
  }
  return steps;
}

function buildCudaScaleFilter({ width, resolution, videoStreamInfo }) {
  // CUDA 路线用 scale_cuda：仅指定宽度，高度用 -2 自动按比例计算并保持偶数
  const wFromParam = toEvenNumber(width);
  if (wFromParam) {
    return `scale_cuda=w=${wFromParam}:h=-2:format=nv12`;
  }

  const size = parseResolution(resolution);
  if (size) {
    const w = toEvenNumber(size.w);
    if (w) return `scale_cuda=w=${w}:h=-2:format=nv12`;
  }

  const { w: w0, h: h0 } = getVideoStreamPixelDimensions(videoStreamInfo);
  if (w0 && h0) return `scale_cuda=w=${w0}:h=${h0}:format=nv12`;
  if (videoStreamInfo && videoStreamInfo.codec_type === 'video') {
    Logger.warn(
      '[TranscodeWorker] Video probe missing usable width/height; CUDA path uses scale_cuda=format=nv12 only (no resize from stream metadata).'
    );
  }
  return 'scale_cuda=format=nv12';
}

function isBitmapSubtitleCodec(codecName) {
  const v = String(codecName || '').toLowerCase();
  return v === 'pgssub' || v === 'hdmv_pgs_subtitle' || v === 'vobsub' || v === 'dvd_subtitle' || v === 'dvdsub' || v === 'dvb_subtitle' || v === 'xsub';
}

async function _getCachedProbeInfo(filePath) {
  await ensureDbInit();
  const fp = String(filePath || '').trim();
  if (!fp) return null;

  const fileHash = await FileUtil.getFileHash(fp).catch(() => null);
  if (!fileHash || !knexVideo) return null;

  const row = await knexVideo('video_ffmpeg_info')
    .where({ id: fileHash })
    .first()
    .catch(() => null);
  if (!row) return null;

  const normalized = VideoFfprobeUtil.normalizeCacheRow(row);
  if (!normalized) return null;
  if (!Array.isArray(normalized.streams) || normalized.streams.length === 0) return null;
  return { ...normalized, fileHash };
}

async function _probeAndCacheInfo(filePath) {
  await ensureDbInit();
  const fp = String(filePath || '').trim();
  if (!fp) return null;

  const fileHash = await FileUtil.getFileHash(fp).catch(() => null);
  const probed = await VideoFfprobeUtil.probeVideo(fp).catch(() => null);
  if (!probed) return null;

  if (fileHash && knexVideo) {
    try {
      const stat = await fs.promises.stat(fp);
      await VideoFfprobeUtil.upsertFfmpegVideoInfo(knexVideo, fileHash, {
        streamInfo: probed.streamInfo,
        duration: probed.duration,
        format: probed.format,
        size: stat.size,
        mtime: stat.mtimeMs,
        width: probed.width,
        height: probed.height,
        create_time: Date.now(),
      });
    } catch (_) {}
  }

  return {
    width: probed.width,
    height: probed.height,
    duration: probed.duration,
    format: probed.format,
    streams: probed.streams,
    streamInfo: probed.streamInfo,
    meta: probed.meta,
    fileHash: fileHash || '',
  };
}

async function _getProbeInfoWithCache(filePath) {
  const cached = await _getCachedProbeInfo(filePath);
  if (cached) return cached;
  return await _probeAndCacheInfo(filePath);
}

async function getSubtitleStreamInfo(filePath, subtitleIndex) {
  if (!Number.isInteger(subtitleIndex) || subtitleIndex < 0) return null;
  const info = await _getProbeInfoWithCache(filePath);
  if (!info || !Array.isArray(info.streams)) return null;
  const subtitleStreams = info.streams.filter(s => s && s.codec_type === 'subtitle');
  return subtitleStreams[subtitleIndex] || null;
}

async function getVideoStreamInfo(filePath) {
  const info = await _getProbeInfoWithCache(filePath);
  if (!info || !Array.isArray(info.streams)) return null;
  let videoStream = info.streams.find(s => s && s.codec_type === 'video') || null;
  if (!videoStream) return null;
  // 旧索引缓存可能缺少 DOVI side_data，用 live ffprobe 补全（仍只读流元数据，不看文件名）
  if (VideoFfprobeUtil.cachedVideoStreamMissingDoviProbeFields(videoStream)) {
    const fresh = await _probeAndCacheInfo(filePath);
    const freshVideo =
      fresh && Array.isArray(fresh.streams) ? fresh.streams.find(s => s && s.codec_type === 'video') : null;
    if (freshVideo) videoStream = freshVideo;
  }
  return videoStream;
}

async function resolveTranscodeBaseDir() {
  await ensureDbInit();
  const safeFolderName = config.getTranscodeTempSafeFolderName();
  let configured = '';
  try {
    const v = await tableConfig.getConfigByKey('transcodeTempDir');
    configured = v ? String(v).trim() : '';
  } catch (_) {}
  const testSubDir = async rootDir => {
    const raw = String(rootDir || '').trim();
    if (!raw) return '';
    const root = path.resolve(raw);
    try {
      const st = await fs.promises.stat(root);
      if (!st.isDirectory()) return '';
      await fs.promises.access(root, fs.constants.W_OK);
      const safeDir = path.join(root, safeFolderName);
      await fs.promises.mkdir(safeDir, { recursive: true });
      await fs.promises.access(safeDir, fs.constants.W_OK);
      const name = `.nascabos_write_test_${Date.now()}_${Math.random().toString(16).slice(2)}.tmp`;
      const p = path.join(safeDir, name);
      await fs.promises.writeFile(p, 'ok', 'utf8');
      await fs.promises.unlink(p);
      return safeDir;
    } catch (_) {
      return '';
    }
  };

  const fromConfigured = await testSubDir(configured);
  if (fromConfigured) return fromConfigured;

  const fallbackRoot = config.getTranscodeTempPath();
  const fallback = await testSubDir(fallbackRoot);
  if (fallback) return fallback;

  const safeFallback = path.join(path.resolve(String(fallbackRoot || '')), safeFolderName);
  try {
    await fs.promises.mkdir(safeFallback, { recursive: true });
  } catch (_) {}
  return safeFallback;
}

process.on('message', async message => {
  if (message.type === 'start') {
    const { playId, filePath, options } = message.data;
    await startTranscoding(playId, filePath, options);
  } else if (message.type === 'stop') {
    await stopTranscoding();
  }
});

async function stopTranscoding() {
  // 收到 stop 消息后直接杀掉 ffmpeg 进程并退出 Worker
  idleStopTriggered = true;
  if (idleMonitorTimer) {
    try {
      clearInterval(idleMonitorTimer);
    } catch (_) {}
    idleMonitorTimer = null;
  }
  const pid = currentPlayId;
  if (pid && knexVideo) {
    await tableVideoTranscodeSession.setRunning(pid, 0, knexVideo).catch(() => null);
  }
  if (currentCommand) {
    try {
      currentCommand.kill('SIGKILL');
    } catch (e) {
      Logger.error(`[TranscodeWorker] Error killing process: ${e.message}`);
    }
    currentCommand = null;
  }
  process.exit(0);
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidPlayId(playId) {
  const s = String(playId || '').trim();
  if (!s) return false;
  return UUID_REGEX.test(s);
}

async function startTranscoding(playId, filePath, options = {}) {
  if (!isValidPlayId(playId)) {
    Logger.error(`[TranscodeWorker] Invalid playId format: ${playId}`);
    process.exit(1);
    return;
  }
  const baseDir = await resolveTranscodeBaseDir();
  const outputDir = path.join(baseDir, playId);
  currentPlayId = String(playId || '').trim();
  idleStopTriggered = false;
  if (idleMonitorTimer) {
    try {
      clearInterval(idleMonitorTimer);
    } catch (_) {}
    idleMonitorTimer = null;
  }
  try {
    const clean = options && options.clean !== false;
    if (clean && fs.existsSync(outputDir)) fs.rmSync(outputDir, { recursive: true, force: true });
  } catch (_) {}
  fs.mkdirSync(outputDir, { recursive: true });
  startIdleMonitor(currentPlayId);
  if (currentPlayId && knexVideo) {
    await tableVideoTranscodeSession.updateHeartbeat(currentPlayId, { lastGetHlsTime: Date.now(), lastGetHlsFilename: 'worker_start' }, knexVideo).catch(() => null);
    await tableVideoTranscodeSession.setRunning(currentPlayId, 1, knexVideo).catch(() => null);
  }

  const m3u8Path = path.join(outputDir, 'index.m3u8');
  const segmentPath = path.join(outputDir, 'segment_%03d.ts');

  Logger.info(`[TranscodeWorker] Starting for ${playId}`);

  const segmentDurationSeconds = Number(options.segmentDurationSeconds);
  const segDur = Number.isFinite(segmentDurationSeconds) && segmentDurationSeconds > 0 ? segmentDurationSeconds : 2;

  const audioIndex = Number.isInteger(options.audioIndex) ? options.audioIndex : options.audioIndex !== undefined ? Number(options.audioIndex) : 0;
  const subtitleIndex = Number.isInteger(options.subtitleIndex) ? options.subtitleIndex : options.subtitleIndex !== undefined ? Number(options.subtitleIndex) : undefined;

  const subtitlePath = options.subtitlePath;

  const profile = process.env.TRANSCODE_PROFILE === '1';
  const preflightStartedAt = Date.now();
  const subtitleStreamInfoPromise = subtitleIndex !== undefined ? getSubtitleStreamInfo(filePath, subtitleIndex) : Promise.resolve(null);
  const videoStreamInfoPromise = getVideoStreamInfo(filePath);
  const hwConfigPromise = getHwAccelConfig();
  const [subtitleStreamInfo, videoStreamInfo, hwConfig] = await Promise.all([subtitleStreamInfoPromise, videoStreamInfoPromise, hwConfigPromise]);
  const subtitleCodecName = subtitleStreamInfo ? subtitleStreamInfo.codec_name : undefined;
  const videoCodecName = videoStreamInfo ? videoStreamInfo.codec_name : null;
  // 如果指定了 subtitlePath (外挂)，也视为 burnSubtitle
  // 注意：对于内嵌字幕，必须验证 subtitleStreamInfo 存在，否则跳过字幕烧录
  let burnSubtitle = false;
  if (subtitlePath) {
    burnSubtitle = options.subtitleBurn !== false;
  } else if (subtitleIndex !== undefined) {
    if (subtitleStreamInfo) {
      burnSubtitle = options.subtitleBurn !== false;
    } else {
      Logger.warn(`[TranscodeWorker] subtitle stream index ${subtitleIndex} missing, skip burn playId=${playId}`);
    }
  }
  // 字幕如果是 PGS/VobSub 等位图字幕，需要用 overlay 方式烧录；文本字幕可用 subtitles 滤镜
  const useBitmapSubtitleOverlay = burnSubtitle && isBitmapSubtitleCodec(subtitleCodecName);
  if (profile) {
    Logger.info(`[TranscodeWorker] Preflight done in ${Date.now() - preflightStartedAt}ms playId=${playId} subtitleIndex=${subtitleIndex === undefined ? '' : subtitleIndex}`);
  }

  const targetWidth = toEvenNumber(parseTargetWidth(options));
  const gop = computeHlsGopFrames(segDur, videoStreamInfo);
  const needsHdrToSdr = streamNeedsHdrToSdr(videoStreamInfo);

  return new Promise((resolve, reject) => {
    let usedHwOnce = false;
    let usedHwEncodeFallback = false;
    let subtitleFallbackDone = false;
    let hdrTonemapFallbackDone = false;

    let ignoreNextSigKill = false;

    function triggerCudaCuvidStallFallback(reason, passSkipSubtitleBurn, passHdrTonemapStrategy) {
      if (usedHwEncodeFallback) return;
      usedHwEncodeFallback = true;
      Logger.warn(`[TranscodeWorker] CUDA cuvid stall (${reason}), fallback NVENC encode-only: ${playId}`);
      const cmd = currentCommand;
      currentCommand = null;
      ignoreNextSigKill = true;
      if (cmd) {
        try {
          cmd.kill('SIGKILL');
        } catch (_) {}
      }
      try {
        fs.rmSync(outputDir, { recursive: true, force: true });
      } catch (_) {}
      try {
        fs.mkdirSync(outputDir, { recursive: true });
      } catch (_) {}
      startOnePass('hw_encode', passSkipSubtitleBurn, passHdrTonemapStrategy);
    }

    function startOnePass(mode, skipSubtitleBurn = false, hdrTonemapStrategyOverride = null) {
      // mode:
      // - hw_full: CUDA 解码 + NVENC 编码（尽量全硬件链路）
      // - hw_encode: 仅硬件编码（可能 CPU 解码/滤镜）
      // - cpu: 全 CPU
      const effectiveBurnSubtitle = skipSubtitleBurn ? false : burnSubtitle;
      const effectiveUseBitmapSubtitleOverlay = skipSubtitleBurn ? false : useBitmapSubtitleOverlay;
      const useHwAccel = mode === 'hw_full' || mode === 'hw_encode' ? !!hwConfig && !!hwConfig.encoder : false;
      const videoCodec = useHwAccel ? hwConfig.encoder : 'libx264';
      const hdrTonemapStrategy = hdrTonemapStrategyOverride ?? pickHdrTonemapStrategy(videoStreamInfo, videoCodec);
      const hasCpuFilters = effectiveUseBitmapSubtitleOverlay || effectiveBurnSubtitle || needsHdrToSdr;
      const skipHdrTargetScale = needsHdrToSdr && !!toEvenNumber(targetWidth);
      const isDolbyVision = isDolbyVisionStream(videoStreamInfo);
      const hdrUsesLibplacebo = needsHdrToSdr && hdrTonemapStrategy === HDR_TONEMAP_LIBPLACEBO;
      const hdrUsesOpenClTonemap = needsHdrToSdr && hdrTonemapStrategy === HDR_TONEMAP_OPENCL;
      const hdrUsesVideotoolboxTonemap = needsHdrToSdr && hdrTonemapStrategy === HDR_TONEMAP_VIDEOTOOLBOX;
      // libplacebo(Vulkan)/OpenCL 与 CUDA/D3D11VA 硬解帧不兼容；DV/HDR10 均走软解 + GPU 滤镜
      const hdrSkipHwDecode = hdrUsesLibplacebo || hdrUsesOpenClTonemap;
      const hdrKeepsHwFramesForVtEncoder = hdrUsesVideotoolboxTonemap && isVideotoolboxEncoder(videoCodec);
      const useHwUploadAfterFilters =
        useHwAccel &&
        typeof hwConfig.hwUploadFilter === 'string' &&
        hwConfig.hwUploadFilter.length > 0 &&
        !hdrUsesLibplacebo &&
        !hdrUsesOpenClTonemap &&
        !hdrKeepsHwFramesForVtEncoder;
      const hwDecodeArgs = useHwAccel && Array.isArray(hwConfig.decodeArgs) ? hwConfig.decodeArgs : [];
      const useCudaFull =
        useHwAccel &&
        mode === 'hw_full' &&
        !isHighBitDepthVideoStream(videoStreamInfo) &&
        videoCodec === 'h264_nvenc' &&
        hwDecodeArgs.includes('-hwaccel') &&
        hwDecodeArgs.includes('cuda') &&
        hwDecodeArgs.includes('-hwaccel_output_format') &&
        hwDecodeArgs.includes('cuda');
      const inputOptions = [];
      const seekRaw = options && options.seek !== undefined ? Number(options.seek) : NaN;
      const seek = Number.isFinite(seekRaw) && seekRaw > 0 ? seekRaw : null;
      const wmvFamily = isWmvFamilySource(filePath, videoStreamInfo);
      if (seek !== null) {
        // ASF/WMV 大文件只能用 input 侧 seek；output 侧会从片头解码到目标点，过慢不可用
        inputOptions.push(`-ss ${seek}`);
      }
      if (wmvFamily && seek !== null) {
        inputOptions.push('-fflags', '+genpts');
      }
      // -probesize / -analyzeduration：提高探测上限，减少部分文件流信息不足导致的转码失败
      inputOptions.push('-probesize 100M', '-analyzeduration 100M');

      if (effectiveBurnSubtitle && !effectiveUseBitmapSubtitleOverlay && seek !== null) {
        // seek + subtitles 组合下，为了时间戳更稳定，增加 copyts
        inputOptions.push('-copyts');
      }

      const useHwUploadFilter = useHwAccel && typeof hwConfig.hwUploadFilter === 'string' && hwConfig.hwUploadFilter.length > 0;
      if (useHwAccel && Array.isArray(hwConfig.initDeviceArgs) && hwConfig.initDeviceArgs.length > 0) {
        inputOptions.push(...buildFfmpegOptionPairs(hwConfig.initDeviceArgs));
      }
      if (needsHdrToSdr && hdrUsesLibplacebo && !inputOptions.some(v => String(v).includes('init_hw_device'))) {
        inputOptions.push(...buildFfmpegOptionPairs(['-init_hw_device', 'vulkan']));
      }
      if (needsHdrToSdr && hdrUsesOpenClTonemap && !inputOptions.some(v => String(v).includes('init_hw_device'))) {
        inputOptions.push(...buildFfmpegOptionPairs(['-init_hw_device', 'opencl=ocl', '-filter_hw_device', 'ocl']));
      }
      if (needsHdrToSdr && hdrUsesVideotoolboxTonemap && !inputOptions.some(v => String(v).includes('init_hw_device'))) {
        inputOptions.push(...buildFfmpegOptionPairs(['-init_hw_device', 'videotoolbox']));
      }
      if (useHwAccel && !hasCpuFilters && hwDecodeArgs.length > 0) {
        if (mode === 'hw_full') {
          inputOptions.push(...buildFfmpegOptionPairs(hwDecodeArgs));
        }
      }

      const canUseCudaDecodeWithCpuFilters =
        useHwAccel &&
        hasCpuFilters &&
        !hdrSkipHwDecode &&
        videoCodec === 'h264_nvenc' &&
        hwDecodeArgs.includes('-hwaccel') &&
        hwDecodeArgs.includes('cuda');
      if (canUseCudaDecodeWithCpuFilters && !inputOptions.some(v => String(v).includes('-hwaccel'))) {
        inputOptions.push(...buildFfmpegOptionPairs(['-hwaccel', 'cuda']));
      }

      const canUseD3d11vaDecodeWithCpuFilters =
        useHwAccel &&
        hasCpuFilters &&
        !hdrSkipHwDecode &&
        (videoCodec === 'h264_amf' || videoCodec === 'hevc_amf') &&
        hwDecodeArgs.includes('-hwaccel') &&
        hwDecodeArgs.includes('d3d11va');
      const useD3d11vaDecodeWithCpuFilters =
        canUseD3d11vaDecodeWithCpuFilters && !inputOptions.some(v => String(v).includes('-hwaccel'));
      if (useD3d11vaDecodeWithCpuFilters) {
        inputOptions.push(...buildFfmpegOptionPairs(['-hwaccel', 'd3d11va']));
      }

      if (useCudaFull && !inputOptions.some(v => String(v).includes('-extra_hw_frames'))) {
        inputOptions.push(`-extra_hw_frames ${CUDA_EXTRA_HW_FRAMES}`);
      }
      if (useHwAccel && Array.isArray(hwConfig.inputArgs) && hwConfig.inputArgs.length > 0) {
        inputOptions.push(...buildFfmpegOptionPairs(hwConfig.inputArgs));
      }

      if (useCudaFull && videoCodecName) {
        const v = String(videoCodecName).toLowerCase();
        const cuvidMap = {
          h264: 'h264_cuvid',
          hevc: 'hevc_cuvid',
          vp9: 'vp9_cuvid',
          av1: 'av1_cuvid',
        };
        const decoder = cuvidMap[v] || null;
        if (decoder) {
          inputOptions.push(`-c:v ${decoder}`);
        }
      }
      // 文件读取速率 最大为5倍
      inputOptions.push(`-readrate ${READ_RATE}`);

      const command = ffmpeg(filePath);

      let capturedStderr = '';
      let cuvidErrorCount = 0;

      command.inputOptions(inputOptions);
      command.on('stderr', line => {
        if (!line) return;
        capturedStderr = `${capturedStderr}\n${line}`;
        if (capturedStderr.length > 8000) {
          capturedStderr = capturedStderr.slice(capturedStderr.length - 8000);
        }
        if (
          useCudaFull &&
          !usedHwEncodeFallback &&
          /cuvid decode callback error|cuvidCreateDecoder|Error submitting packet to decoder/i.test(String(line))
        ) {
          cuvidErrorCount += 1;
          if (cuvidErrorCount >= CUDA_CUVID_STALL_ERROR_THRESHOLD) {
            triggerCudaCuvidStallFallback(`cuvid errors=${cuvidErrorCount}`, skipSubtitleBurn, hdrTonemapStrategy);
          }
        }
      });

      if (options.bitrate) {
        command.videoBitrate(options.bitrate);
      }

      if (needsHdrToSdr) {
        const tonemapLabel = isDolbyVision
          ? hdrTonemapStrategy === HDR_TONEMAP_LIBPLACEBO
            ? 'dv_p5_libplacebo'
            : hdrTonemapStrategy === HDR_TONEMAP_OPENCL
              ? 'dv_p5_opencl'
              : hdrTonemapStrategy === HDR_TONEMAP_VIDEOTOOLBOX
                ? 'dv_p5_videotoolbox'
                : 'dv_p5_colorfix'
          : hdrTonemapStrategy === HDR_TONEMAP_LIBPLACEBO
            ? 'libplacebo'
            : hdrTonemapStrategy === HDR_TONEMAP_OPENCL
              ? 'opencl'
              : hdrTonemapStrategy === HDR_TONEMAP_VIDEOTOOLBOX
                ? 'videotoolbox'
                : 'zscale';
        Logger.info(`[TranscodeWorker] HDR/DV source detected, applying SDR tonemap (${tonemapLabel}) playId=${playId}`);
      }

      if (effectiveUseBitmapSubtitleOverlay) {
        // 内嵌位图字幕烧录 (overlay)
        const scaleSteps = buildCpuVideoScaleSteps(targetWidth, videoCodec, videoStreamInfo, { skipTargetScale: skipHdrTargetScale });
        const hdrSteps = needsHdrToSdr ? buildHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo, hdrTonemapStrategy) : [];
        const preSteps = [...hdrSteps, ...scaleSteps];
        const filters = [];
        if (preSteps.length > 0) {
          let label = '[0:v:0]';
          preSteps.forEach((step, i) => {
            const out = i === preSteps.length - 1 ? '[vs]' : `[vstep${i}]`;
            filters.push(`${label}${step}${out}`);
            label = out;
          });
          filters.push(
            `[0:s:${subtitleIndex}]format=rgba[subsrc]`,
            `[subsrc][vs]scale2ref[sub][ref]`,
            `[ref][sub]overlay=0:0:format=auto[v]`
          );
        } else {
          filters.push(
            `[0:s:${subtitleIndex}]format=rgba[subsrc]`,
            `[subsrc][0:v:0]scale2ref[sub][ref]`,
            `[ref][sub]overlay=0:0:format=auto[v]`
          );
        }
        const mapVideoLabel = useHwUploadAfterFilters ? '[v_hw]' : '[v]';
        if (useHwUploadAfterFilters) {
          filters.push(`[v]${hwConfig.hwUploadFilter}[v_hw]`);
        }
        command.complexFilter(filters);
        command.outputOptions([`-map ${mapVideoLabel}`, `-map 0:a:${Number.isNaN(audioIndex) ? 0 : audioIndex}?`]);
      } else {
        // 普通转码 (CPU滤镜 或 CUDA缩放)
        command.outputOptions(['-map 0:v:0', `-map 0:a:${Number.isNaN(audioIndex) ? 0 : audioIndex}?`]);

        if (useCudaFull) {
          // CUDA 全链路，如果有文本字幕需要烧录，不能走纯 CUDA 滤镜，因为 subtitles 滤镜是 CPU 的
          // 前面逻辑已经判断了 hasCpuFilters 会阻止进入 useCudaFull 模式
          // 但如果 subtitlePath 存在，也属于 hasCpuFilters
          command.videoFilters(
            buildCudaScaleFilter({
              width: targetWidth,
              resolution: options.resolution,
              videoStreamInfo,
            })
          );
        } else if (useHwUploadFilter) {
          const vf = [];
          if (useD3d11vaDecodeWithCpuFilters) {
            vf.push('hwdownload,format=nv12');
          }
          if (needsHdrToSdr) {
            vf.push(...buildHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo, hdrTonemapStrategy));
          }
          for (const step of buildCpuVideoScaleSteps(targetWidth, videoCodec, videoStreamInfo, { skipTargetScale: skipHdrTargetScale })) {
            vf.push(step);
          }
          if (effectiveBurnSubtitle) {
            if (useD3d11vaDecodeWithCpuFilters) {
              vf.push('format=yuv420p');
            }
            if (subtitlePath) {
              // 外挂字幕
              const subPath = escapeForSubtitlesFilter(subtitlePath);
              vf.push(`subtitles='${subPath}':force_style='FontSize=${subtitleFontSize}'`);
            } else {
              // 内嵌字幕
              const subPath = escapeForSubtitlesFilter(filePath);
              vf.push(`subtitles='${subPath}':si=${subtitleIndex}:force_style='FontSize=${subtitleFontSize}'`);
            }
          }
          if (useHwUploadAfterFilters) {
            vf.push(hwConfig.hwUploadFilter);
          }
          command.videoFilters(vf.join(','));
        } else {
          const vf = [];
          if (useD3d11vaDecodeWithCpuFilters) {
            vf.push('hwdownload,format=nv12');
          }
          if (needsHdrToSdr) {
            vf.push(...buildHdrToSdrSteps(targetWidth, videoCodec, videoStreamInfo, hdrTonemapStrategy));
          }
          for (const step of buildCpuVideoScaleSteps(targetWidth, videoCodec, videoStreamInfo, { skipTargetScale: skipHdrTargetScale })) {
            vf.push(step);
          }
          if (effectiveBurnSubtitle) {
            if (useD3d11vaDecodeWithCpuFilters) {
              vf.push('format=yuv420p');
            }
            if (subtitlePath) {
              // 外挂字幕
              const subPath = escapeForSubtitlesFilter(subtitlePath);
              vf.push(`subtitles='${subPath}':force_style='FontSize=${subtitleFontSize}'`);
            } else {
              // 内嵌字幕
              const subPath = escapeForSubtitlesFilter(filePath);
              vf.push(`subtitles='${subPath}':si=${subtitleIndex}:force_style='FontSize=${subtitleFontSize}'`);
            }
          }
          // libplacebo 路径已在 buildLibplaceboPostTonemapSteps 中输出 nv12；此处仅兜底非 HDR 场景
          if (isQsvVideoEncoder(videoCodec) && !needsHdrToSdr) {
            vf.push('format=nv12');
          }
          if (vf.length > 0) {
            command.videoFilters(vf.join(','));
          }
        }
      }

      const outputOptions = [`-c:v ${videoCodec}`, `-g ${gop}`, '-c:a aac', '-b:a 128k', '-ac 2'];
      if (wmvFamily && seek !== null) {
        outputOptions.push('-avoid_negative_ts', 'make_zero', '-max_muxing_queue_size', '1024');
      }
      if (videoCodec === 'libx264') {
        outputOptions.splice(1, 0, '-preset veryfast', '-sc_threshold 0');
      } else if (videoCodec === 'h264_nvenc') {
        if (useCudaFull) {
          outputOptions.splice(1, 0, '-preset fast');
        } else {
          outputOptions.splice(1, 0, '-preset fast', '-pix_fmt yuv420p');
        }
      } else if (videoCodec === 'h264_qsv' || videoCodec === 'hevc_qsv') {
        // QSV 上 force_key_frames 可能产生非 IDR 的 I 帧，HLS 只在 IDR 处切分；配合 temp_file 时会一直不写 .ts，杀进程才落盘超大 segment_000
        const qsvExtra =
          videoCodec === 'h264_qsv'
            ? ['-look_ahead_depth', '0', '-forced_idr', '1', '-bf', '0']
            : ['-look_ahead_depth', '0', '-forced_idr', '1'];
        outputOptions.splice(1, 0, ...qsvExtra);
      }
      if (needsHdrToSdr) {
        // tonemap 输出均为 bt709 limited(tv)；勿沿用 DV 源 full range(pc)，否则 QSV 色域换算错误会发绿
        outputOptions.splice(1, 0, '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709', '-color_range', 'tv');
      }
      const startNumberRaw = options && options.startNumber !== undefined ? Number(options.startNumber) : NaN;
      const startNumber = Number.isFinite(startNumberRaw) && startNumberRaw >= 0 ? Math.floor(startNumberRaw) : null;
      if (startNumber !== null) {
        outputOptions.push('-start_number', String(startNumber));
      }
      const tsOffsetRaw = options && options.outputTsOffset !== undefined ? Number(options.outputTsOffset) : NaN;
      const tsOffset = Number.isFinite(tsOffsetRaw) && tsOffsetRaw > 0 ? tsOffsetRaw : null;
      if (tsOffset !== null) {
        outputOptions.push('-output_ts_offset', String(tsOffset));
      }
      outputOptions.push(`-force_key_frames expr:gte(t,n_forced*${segDur})`);
      outputOptions.push('-f', 'hls', '-hls_time', String(segDur), '-hls_list_size', '0');

      command
        .outputOptions(outputOptions)
        // 带空格的路径必须作为独立参数传入，避免 fluent-ffmpeg 对数组字符串做兼容性拆分
        .outputOptions('-hls_segment_filename', segmentPath, '-hls_flags', 'independent_segments+temp_file')
        .output(m3u8Path);

      command.on('start', cmdLine => {
        if (useHwAccel) {
          Logger.info(`[TranscodeWorker] Started FFmpeg with HW accel (${hwConfig.name || hwConfig.encoder}): ${cmdLine}`);
        } else {
          Logger.info(`[TranscodeWorker] Started FFmpeg (CPU): ${cmdLine}`);
        }
      });

      command.on('error', (err, stdout, stderr) => {
        if (err && err.message && err.message.includes('SIGKILL')) {
          if (ignoreNextSigKill) {
            ignoreNextSigKill = false;
            return;
          }
          Logger.info(`[TranscodeWorker] Killed: ${playId}`);
          Promise.resolve()
            .then(async () => {
              if (currentPlayId && knexVideo) await tableVideoTranscodeSession.setRunning(currentPlayId, 0, knexVideo).catch(() => null);
            })
            .finally(() => process.exit(0));
          return;
        }

        // 字幕滤镜失败恢复：当 subtitles 滤镜无法定位字幕流（路径含非ASCII字符、编码不支持等）时，跳过字幕重试
        const errText = (stderr || '') + (capturedStderr || '');
        const isHdrTonemapError =
          needsHdrToSdr &&
          hdrTonemapStrategy !== HDR_TONEMAP_FALLBACK &&
          (errText.includes('libplacebo') ||
            errText.includes('vulkan') ||
            errText.includes('tonemap_opencl') ||
            errText.includes('tonemap_videotoolbox') ||
            errText.includes('hwupload') ||
            errText.includes('auto_scale') ||
            errText.includes('Failed to configure output pad on Parsed_hwdownload') ||
            errText.includes('Failed to configure output pad on Parsed_tonemap_videotoolbox') ||
            errText.includes('Failed to configure output pad on Parsed_tonemap_opencl'));
        if (isHdrTonemapError && !hdrTonemapFallbackDone) {
          try {
            fs.rmSync(outputDir, { recursive: true, force: true });
          } catch (_) {}
          try {
            fs.mkdirSync(outputDir, { recursive: true });
          } catch (_) {}
          currentCommand = null;
          const nextStrategy = getHdrTonemapFallbackStrategy(hdrTonemapStrategy, videoStreamInfo, videoCodec);
          if (nextStrategy !== HDR_TONEMAP_FALLBACK) {
            Logger.warn(
              `[TranscodeWorker] ${hdrTonemapStrategy} tonemap failed, retry ${nextStrategy} playId=${playId}`
            );
            if (errText) Logger.warn(`[TranscodeWorker] HDR tonemap details: ${errText.slice(-2000)}`);
            startOnePass(mode, skipSubtitleBurn, nextStrategy);
            return;
          }
          if (isDolbyVisionStream(videoStreamInfo)) {
            if (hdrTonemapStrategy === HDR_TONEMAP_LIBPLACEBO && mode !== 'cpu') {
              Logger.warn(`[TranscodeWorker] libplacebo DV tonemap failed on HW path, retry CPU decode playId=${playId}`);
              if (errText) Logger.warn(`[TranscodeWorker] HDR tonemap details: ${errText.slice(-2000)}`);
              startOnePass('cpu', skipSubtitleBurn, HDR_TONEMAP_LIBPLACEBO);
              return;
            }
            hdrTonemapFallbackDone = true;
            Logger.warn(`[TranscodeWorker] ${hdrTonemapStrategy} DV tonemap failed, fallback colorfix playId=${playId}`);
            if (errText) Logger.warn(`[TranscodeWorker] HDR tonemap details: ${errText.slice(-2000)}`);
            startOnePass('cpu', skipSubtitleBurn, HDR_TONEMAP_FALLBACK);
            return;
          }
          hdrTonemapFallbackDone = true;
          Logger.warn(`[TranscodeWorker] ${hdrTonemapStrategy} HDR tonemap failed, fallback zscale playId=${playId}`);
          if (errText) Logger.warn(`[TranscodeWorker] HDR tonemap details: ${errText.slice(-2000)}`);
          startOnePass(mode, skipSubtitleBurn, HDR_TONEMAP_FALLBACK);
          return;
        }

        const isSubtitleFilterError =
          errText.includes('Unable to locate subtitle stream') ||
          errText.includes("Error initializing filter 'subtitles'") ||
          errText.includes('subtitles filter') ||
          (err && err.message && (err.message.includes('Unable to locate subtitle stream') || err.message.includes('subtitles')));
        if (effectiveBurnSubtitle && isSubtitleFilterError && !subtitleFallbackDone) {
          subtitleFallbackDone = true;
          Logger.warn(`[TranscodeWorker] subtitle filter init failed, retry transcode without subs playId=${playId}`);
          if (errText) Logger.warn(`[TranscodeWorker] subtitle filter details: ${errText.slice(-2000)}`);
          try {
            fs.rmSync(outputDir, { recursive: true, force: true });
          } catch (_) {}
          try {
            fs.mkdirSync(outputDir, { recursive: true });
          } catch (_) {}
          currentCommand = null;
          startOnePass(mode, true, hdrTonemapStrategy);
          return;
        }

        if (useHwAccel && useCudaFull && !usedHwEncodeFallback) {
          // CUDA 全链路失败：优先回退到“仅硬件编码”，尽可能保留性能
          usedHwEncodeFallback = true;
          Logger.error(`[TranscodeWorker] CUDA decode+NVENC failed, fallback NVENC encode-only: ${playId}`, err || null);
          const errOut = stderr || capturedStderr;
          if (errOut) Logger.error(`[TranscodeWorker] CUDA+NVENC stderr: ${errOut}`);

          try {
            fs.rmSync(outputDir, { recursive: true, force: true });
          } catch (_) {}
          try {
            fs.mkdirSync(outputDir, { recursive: true });
          } catch (_) {}

          currentCommand = null;
          startOnePass('hw_encode', skipSubtitleBurn, hdrTonemapStrategy);
          return;
        }

        if (useHwAccel && !usedHwOnce) {
          // 硬件加速失败：再回退到纯 CPU（最稳妥）
          usedHwOnce = true;
          Logger.error(`[TranscodeWorker] HW accel failed, fallback CPU: ${playId}`, err || null);
          const errOut = stderr || capturedStderr;
          if (errOut) Logger.error(`[TranscodeWorker] HW accel stderr: ${errOut}`);

          try {
            fs.rmSync(outputDir, { recursive: true, force: true });
          } catch (_) {}
          try {
            fs.mkdirSync(outputDir, { recursive: true });
          } catch (_) {}

          currentCommand = null;
          startOnePass('cpu', skipSubtitleBurn, hdrTonemapStrategy);
          return;
        }

        Logger.error(`[TranscodeWorker] Error: ${playId}`, err);
        const errOut = stderr || capturedStderr;
        if (errOut) Logger.error(`[TranscodeWorker] Stderr: ${errOut}`);
        Promise.resolve()
          .then(async () => {
            if (currentPlayId && knexVideo) await tableVideoTranscodeSession.setRunning(currentPlayId, 0, knexVideo).catch(() => null);
          })
          .finally(() => process.exit(1));
      });

      command.on('end', () => {
        Logger.info(`[TranscodeWorker] Finished: ${playId}`);
        Promise.resolve()
          .then(async () => {
            if (currentPlayId && knexVideo) await tableVideoTranscodeSession.setRunning(currentPlayId, 0, knexVideo).catch(() => null);
          })
          .finally(() => process.exit(0));
      });

      currentCommand = command;
      command.run();
    }

    const seekForMode =
      options && options.seek !== undefined ? Number(options.seek) : 0;
    const forceCpuForWmvSeek = wmvSeekRequiresCpuEncode(filePath, videoStreamInfo, seekForMode);
    if (forceCpuForWmvSeek) {
      Logger.info(
        `[TranscodeWorker] WMV/VC-1 seek=${seekForMode}s: use libx264 (VideoToolbox may omit IDR after ASF seek) playId=${playId}`
      );
    }

    const skipCudaCuvidFullPath = isHighBitDepthVideoStream(videoStreamInfo);
    const canTryFull =
      !forceCpuForWmvSeek &&
      !skipCudaCuvidFullPath &&
      !!hwConfig &&
      !!hwConfig.encoder &&
      !useBitmapSubtitleOverlay &&
      !burnSubtitle &&
      !needsHdrToSdr &&
      hwConfig.encoder === 'h264_nvenc' &&
      Array.isArray(hwConfig.decodeArgs) &&
      hwConfig.decodeArgs.includes('-hwaccel') &&
      hwConfig.decodeArgs.includes('cuda') &&
      hwConfig.decodeArgs.includes('-hwaccel_output_format') &&
      hwConfig.decodeArgs.includes('cuda');

    if (skipCudaCuvidFullPath && hwConfig && hwConfig.encoder === 'h264_nvenc') {
      const pixFmt = videoStreamInfo && videoStreamInfo.pix_fmt ? String(videoStreamInfo.pix_fmt) : '';
      Logger.info(
        `[TranscodeWorker] High bit depth source (pix_fmt=${pixFmt || 'unknown'}) skips CUDA cuvid hw_full, use hw_encode playId=${playId}`
      );
    }

    if (canTryFull) {
      startOnePass('hw_full');
    } else if (!forceCpuForWmvSeek && hwConfig && hwConfig.encoder) {
      startOnePass('hw_encode');
    } else {
      startOnePass('cpu');
    }
  });
}

function startIdleMonitor(playId) {
  const pid = String(playId || '').trim();
  if (!pid) return;
  if (!knexVideo) return;
  if (idleMonitorTimer) {
    try {
      clearInterval(idleMonitorTimer);
    } catch (_) {}
    idleMonitorTimer = null;
  }
  idleMonitorTimer = setInterval(() => {
    if (idleStopTriggered) return;
    Promise.resolve()
      .then(async () => {
        const row = await tableVideoTranscodeSession.getByPlayId(pid, knexVideo);
        const last = row && row.last_get_hls_time !== undefined ? Number(row.last_get_hls_time) || 0 : 0;
        if (!last) return;
        const now = Date.now();
        if (now - last <= 60000) return;
        idleStopTriggered = true;
        await tableVideoTranscodeSession.setRunning(pid, 0, knexVideo).catch(() => null);
        console.log('转码超时，自动关闭', playId, row.last_get_hls_filename);
        await stopTranscoding();
      })
      .catch(() => null);
  }, 10000);
}
