'use strict';
const os = require('os');
const si = require('systeminformation');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const ffmpegPath = require('../libsPath/ffmpegPath');

const Logger = require('../utils/logger');
const dbUtil = require('../db/dbUtil');
const knexUtil = require('../db/knexUtil');
const tableConfig = require('../db/table/tableConfig');
const config = require('../config/config');
const {
  buildAvailableHwAccelList,
  combineHwAccelEntryToConfig,
  findAvailableHwAccelEntry,
  getHwAccelGroupMeta,
  normalizeAvailableHwAccelList,
} = require('../utils/transcodeHwAccelUtil');

const HW_ACCEL_PROBE_SCHEMA_VERSION = 2;

// 该 Worker 用于“启动时一次性检测”转码硬件加速能力：
// - 在独立进程中执行，避免阻塞主进程启动
// - 通过实际跑一条短 FFmpeg 命令来验证可用性（比仅看设备/编码器名称更可靠）
// - 将检测报告和最终选中的硬件方案写入数据库配置表

function runFfmpeg(args, timeoutMs = 15000) {
  // 这里使用 spawnSync：
  // - 检测 Worker 只跑一次并退出，同步执行更简单可控
  // - 通过 timeout 防止驱动/FFmpeg 在异常情况下卡死
  try {
    const res = spawnSync(ffmpegPath.path, args, {
      encoding: 'utf8',
      timeout: timeoutMs,
      windowsHide: true,
    });
    // console.log('ffmpeg command:', ffmpegPath.path, ...args);

    return {
      ok: res.status === 0,
      status: res.status,
      stdout: res.stdout || '',
      stderr: res.stderr || '',
      error: res.error ? String(res.error.message || res.error) : null,
    };
  } catch (e) {
    return { ok: false, status: null, stdout: '', stderr: '', error: String(e.message || e) };
  }
}

function findLinuxRenderDevice() {
  // Linux 下 VAAPI/QSV 通常依赖 /dev/dri 下的 render 节点
  const candidates = ['/dev/dri/renderD128', '/dev/dri/renderD129', '/dev/dri/card0'];
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return p;
    } catch (_) {}
  }
  return null;
}

async function run() {
  // 入口：初始化数据库连接 -> 执行检测 -> 正常退出
  try {
    await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    const report = await _readHwAccelReportFromDb();
    const hardwareSame = await _isHardwareFingerprintSame(report);
    if (hardwareSame) {
      const repairedOrOk = await _ensureHwAccelConfigKeys(report);
      if (repairedOrOk) {
        process.exit(0);
      }
    }

    await detectAndSaveTranscodeHwAccel();
    process.exit(0);
  } catch (err) {
    Logger.error('❌ FFmpeg HW probe failed, using CPU', err);
    try {
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
      await tableConfig.setConfigByKey('transcode_hwaccel_available', JSON.stringify([]));
      await tableConfig.setConfigByKey('transcode_hwaccel_selected', JSON.stringify(null));
      await tableConfig.setConfigByKey('transcode_hwaccel_preferred', '');
    } catch (e) {
      Logger.error('❌ Failed to write CPU fallback transcode config', e);
    }
    process.exit(0);
  }
}

function normalizeGpuControllers(controllers) {
  const list = Array.isArray(controllers) ? controllers : [];
  const mapped = list.map(g => ({
    vendor: g && g.vendor ? String(g.vendor) : '',
    model: g && g.model ? String(g.model) : '',
    vram: g && (g.vram || g.vramTotal || g.memoryTotal) ? Number(g.vram || g.vramTotal || g.memoryTotal) : null,
  }));
  mapped.sort((a, b) => {
    const ak = `${a.vendor}||${a.model}||${a.vram ?? ''}`.toLowerCase();
    const bk = `${b.vendor}||${b.model}||${b.vram ?? ''}`.toLowerCase();
    return ak.localeCompare(bk);
  });
  return mapped;
}

async function buildHardwareSnapshot() {
  const platform = os.platform();
  const arch = os.arch();
  const cpu = await si.cpu().catch(() => null);
  const graphics = await si.graphics().catch(() => ({ controllers: [] }));
  const controllers = Array.isArray(graphics.controllers) ? graphics.controllers : [];

  const cpuInfo = cpu
    ? {
        manufacturer: cpu.manufacturer ? String(cpu.manufacturer) : null,
        brand: cpu.brand ? String(cpu.brand) : null,
        family: cpu.family ? String(cpu.family) : null,
        model: cpu.model ? String(cpu.model) : null,
        stepping: cpu.stepping ? String(cpu.stepping) : null,
        physicalCores: Number.isFinite(Number(cpu.physicalCores)) ? Number(cpu.physicalCores) : null,
      }
    : null;

  return {
    platform,
    arch,
    cpu: cpuInfo,
    gpus: normalizeGpuControllers(controllers),
  };
}

async function computeHardwareFingerprint() {
  const snapshot = await buildHardwareSnapshot();
  const raw = JSON.stringify({ schema: HW_ACCEL_PROBE_SCHEMA_VERSION, snapshot });
  const hash = crypto.createHash('sha256').update(raw).digest('hex');
  return { fingerprint: `sha256:${hash}`, snapshot };
}

function _safeJsonParse(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const v = raw.trim();
  if (!v) return null;
  try {
    return JSON.parse(v);
  } catch (_) {
    return null;
  }
}

async function _readHwAccelReportFromDb() {
  const reportRaw = await tableConfig.getConfigByKey('transcode_hwaccel_report');
  if (!reportRaw) return null;
  const report = _safeJsonParse(String(reportRaw));
  return report && typeof report === 'object' ? report : null;
}

async function _isHardwareFingerprintSame(report) {
  if (!report || typeof report !== 'object') return false;
  if (Number(report.probeSchemaVersion || 0) !== HW_ACCEL_PROBE_SCHEMA_VERSION) return false;
  const reportFp = report && report.hardwareFingerprint ? String(report.hardwareFingerprint) : '';
  if (!reportFp) return false;
  const { fingerprint } = await computeHardwareFingerprint();
  return reportFp === fingerprint;
}

async function _ensureHwAccelConfigKeys(report) {
  const candidates = report && Array.isArray(report.candidates) ? report.candidates : [];
  if (candidates.length === 0) return false;

  const [availableRaw, selectedRaw, preferredRaw] = await Promise.all([
    tableConfig.getConfigByKey('transcode_hwaccel_available'),
    tableConfig.getConfigByKey('transcode_hwaccel_selected'),
    tableConfig.getConfigByKey('transcode_hwaccel_preferred'),
  ]);

  const existingAvailable = normalizeAvailableHwAccelList(availableRaw);
  const available = existingAvailable.length > 0 ? existingAvailable : buildAvailableHwAccelList(candidates);
  const shouldWriteAvailable = existingAvailable.length === 0 && available.length > 0;

  const preferredKey = preferredRaw ? String(preferredRaw).trim() : '';
  const preferredExists = preferredKey ? !!findAvailableHwAccelEntry(available, preferredKey) : false;
  const nextPreferredKey = preferredExists ? preferredKey : '';

  const selectedParsed = _safeJsonParse(typeof selectedRaw === 'string' ? selectedRaw : selectedRaw ? String(selectedRaw) : '');
  const selectedHasKey = selectedParsed && typeof selectedParsed === 'object' && typeof selectedParsed.key === 'string' && selectedParsed.key.trim();

  let nextSelected = selectedHasKey ? selectedParsed : null;
  if (!nextSelected) {
    const reportSelected = report && report.selected && typeof report.selected === 'object' ? report.selected : null;
    const profiles = reportSelected && reportSelected.profiles && typeof reportSelected.profiles === 'object' ? reportSelected.profiles : null;
    const baseProfile =
      (profiles && profiles.h264 && typeof profiles.h264 === 'object' ? profiles.h264 : null) ||
      (profiles && profiles.h265 && typeof profiles.h265 === 'object' ? profiles.h265 : null) ||
      reportSelected;
    if (baseProfile) {
      const groupMeta = getHwAccelGroupMeta(baseProfile);
      const entryKey = groupMeta && groupMeta.key ? String(groupMeta.key) : '';
      const entry = entryKey ? findAvailableHwAccelEntry(available, entryKey) : null;
      nextSelected = entry ? combineHwAccelEntryToConfig(entry) : null;
      if (nextSelected && profiles) {
        nextSelected.profiles = {
          h264: profiles.h264 && typeof profiles.h264 === 'object' ? profiles.h264 : null,
          h265: profiles.h265 && typeof profiles.h265 === 'object' ? profiles.h265 : null,
        };
      }
    }
  }

  const savePairs = [];
  if (shouldWriteAvailable) {
    savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_available', JSON.stringify(available)));
  }
  if (nextPreferredKey !== preferredKey) {
    savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_preferred', nextPreferredKey));
  }
  if (!selectedHasKey && nextSelected) {
    savePairs.push(tableConfig.setConfigByKey('transcode_hwaccel_selected', JSON.stringify(nextSelected)));
  }
  if (savePairs.length === 0) return true;
  const results = await Promise.all(savePairs);
  return results.every(Boolean);
}

async function detectAndSaveTranscodeHwAccel() {
  // 说明：
  // - 候选方案（candidates）只是“可能可用”的组合
  // - 最终是否可用，以 ffmpeg 实测结果为准
  const platform = os.platform();
  const arch = os.arch();
  const now = Date.now();

  const { fingerprint: hardwareFingerprint, snapshot: hardwareSnapshot } = await computeHardwareFingerprint();

  const graphics = await si.graphics().catch(() => ({ controllers: [] }));
  const controllers = Array.isArray(graphics.controllers) ? graphics.controllers : [];

  const normalize = v => String(v || '').toLowerCase();
  const isNvidia = g => normalize(g.vendor).includes('nvidia') || normalize(g.model).includes('nvidia');
  const isAmd = g => normalize(g.vendor).includes('amd') || normalize(g.vendor).includes('ati') || normalize(g.model).includes('radeon');
  const isIntel = g => normalize(g.vendor).includes('intel') || normalize(g.model).includes('intel');

  const hasNvidia = controllers.some(isNvidia);
  const hasAmd = controllers.some(isAmd);
  const hasIntel = controllers.some(isIntel);

  const candidates = [];

  if (platform === 'darwin') {
    // macOS：VideoToolbox
    candidates.push({
      name: 'videotoolbox_h264_full',
      kind: hasAmd || hasNvidia ? 'discrete' : 'integrated',
      decodeArgs: ['-hwaccel', 'videotoolbox'],
      encoder: 'h264_videotoolbox',
    });
    candidates.push({
      name: 'videotoolbox_h265_full',
      kind: hasAmd || hasNvidia ? 'discrete' : 'integrated',
      decodeArgs: ['-hwaccel', 'videotoolbox'],
      encoder: 'hevc_videotoolbox',
    });
  } else if (platform === 'win32') {
    // Windows：优先离散显卡（NVIDIA/AMD），其次集显（Intel QSV）
    if (hasNvidia) {
      candidates.push({
        name: 'nvidia_cuda_nvenc_full',
        kind: 'discrete',
        decodeArgs: ['-hwaccel', 'cuda', '-hwaccel_output_format', 'cuda'],
        encoder: 'h264_nvenc',
      });
      candidates.push({
        name: 'nvidia_cuda_hevc_nvenc_full',
        kind: 'discrete',
        decodeArgs: ['-hwaccel', 'cuda', '-hwaccel_output_format', 'cuda'],
        encoder: 'hevc_nvenc',
      });
      candidates.push({
        name: 'nvidia_nvenc_encode_only',
        kind: 'discrete',
        decodeArgs: null,
        encoder: 'h264_nvenc',
      });
      candidates.push({
        name: 'nvidia_hevc_nvenc_encode_only',
        kind: 'discrete',
        decodeArgs: null,
        encoder: 'hevc_nvenc',
      });
    }
    if (hasAmd) {
      candidates.push({
        name: 'amd_d3d11va_amf_full',
        kind: 'discrete',
        decodeArgs: ['-hwaccel', 'd3d11va'],
        encoder: 'h264_amf',
      });
      candidates.push({
        name: 'amd_d3d11va_hevc_amf_full',
        kind: 'discrete',
        decodeArgs: ['-hwaccel', 'd3d11va'],
        encoder: 'hevc_amf',
      });
      candidates.push({
        name: 'amd_amf_encode_only',
        kind: 'discrete',
        decodeArgs: null,
        encoder: 'h264_amf',
      });
      candidates.push({
        name: 'amd_hevc_amf_encode_only',
        kind: 'discrete',
        decodeArgs: null,
        encoder: 'hevc_amf',
      });
    }
    if (hasIntel) {
      candidates.push({
        name: 'intel_qsv_full',
        kind: 'integrated',
        decodeArgs: ['-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'],
        encoder: 'h264_qsv',
      });
      candidates.push({
        name: 'intel_hevc_qsv_full',
        kind: 'integrated',
        decodeArgs: ['-hwaccel', 'qsv', '-hwaccel_output_format', 'qsv'],
        encoder: 'hevc_qsv',
      });
      candidates.push({
        name: 'intel_qsv_encode_only',
        kind: 'integrated',
        decodeArgs: null,
        encoder: 'h264_qsv',
      });
      candidates.push({
        name: 'intel_hevc_qsv_encode_only',
        kind: 'integrated',
        decodeArgs: null,
        encoder: 'hevc_qsv',
      });
    }
  } else {
    // Linux/Docker：
    // - NVIDIA: NVENC (encode only)
    // - Intel/AMD: VAAPI
    // - Intel: QSV
    const renderDevice = findLinuxRenderDevice();

    candidates.push({
      name: 'nvidia_nvenc_encode_only',
      kind: 'discrete',
      decodeArgs: null,
      encoder: 'h264_nvenc',
      hwType: 'nvenc',
    });
    candidates.push({
      name: 'nvidia_hevc_nvenc_encode_only',
      kind: 'discrete',
      decodeArgs: null,
      encoder: 'hevc_nvenc',
      hwType: 'nvenc',
    });

    if (renderDevice) {
      candidates.push({
        name: 'linux_vaapi_h264',
        kind: 'integrated',
        decodeArgs: null,
        encoder: 'h264_vaapi',
        hwType: 'vaapi',
        device: renderDevice,
        hwUploadFilter: 'format=nv12,hwupload',
        inputArgs: ['-vaapi_device', renderDevice],
      });
      candidates.push({
        name: 'linux_vaapi_h265',
        kind: 'integrated',
        decodeArgs: null,
        encoder: 'hevc_vaapi',
        hwType: 'vaapi',
        device: renderDevice,
        hwUploadFilter: 'format=nv12,hwupload',
        inputArgs: ['-vaapi_device', renderDevice],
      });

      candidates.push({
        name: 'linux_qsv_h264',
        kind: 'integrated',
        decodeArgs: null,
        encoder: 'h264_qsv',
        hwType: 'qsv',
        device: renderDevice,
        initDeviceArgs: ['-init_hw_device', `qsv=hw:${renderDevice}`, '-filter_hw_device', 'hw'],
        hwUploadFilter: 'format=nv12,hwupload=extra_hw_frames=64',
      });
      candidates.push({
        name: 'linux_qsv_h265',
        kind: 'integrated',
        decodeArgs: null,
        encoder: 'hevc_qsv',
        hwType: 'qsv',
        device: renderDevice,
        initDeviceArgs: ['-init_hw_device', `qsv=hw:${renderDevice}`, '-filter_hw_device', 'hw'],
        hwUploadFilter: 'format=nv12,hwupload=extra_hw_frames=64',
      });
    }
  }

  const preferOrder = p => {
    if (p.kind === 'discrete') return 0;
    if (p.kind === 'integrated') return 1;
    return 2;
  };

  candidates.sort((a, b) => {
    const ak = preferOrder(a);
    const bk = preferOrder(b);
    if (ak !== bk) return ak - bk;
    const af = a.decodeArgs ? 0 : 1;
    const bf = b.decodeArgs ? 0 : 1;
    if (af !== bf) return af - bf;
    return a.name.localeCompare(b.name);
  });

  const serverRoot = config.appRootPath;
  const cacheBase = process.env.PATH_CACHE || config.getCachePath();

  // 检测输入：
  // 1) 优先使用内置的真实文件样本（覆盖“文件解码 -> 编码”路径）
  // 2) 同时追加 lavfi testsrc（覆盖“编码器是否可用”的兜底路径，避免样本文件导致误判）
  // lavfi 这里显式转成 yuv420p，避免部分硬件编码器对输入像素格式挑剔导致误判。
  const testH264 = path.join(serverRoot, 'libs', 'transcodetest_h264');
  const testH265 = path.join(serverRoot, 'libs', 'transcodetest_h265');
  const testInputs = [testH264, testH265].filter(p => fs.existsSync(p));
  const testCases = testInputs.map(p => ({ type: 'file', input: p }));
  testCases.push({ type: 'lavfi', input: 'testsrc=size=1280x720:rate=30,format=yuv420p' });

  const testDir = path.join(cacheBase, 'hwaccel_test');
  try {
    if (!fs.existsSync(testDir)) fs.mkdirSync(testDir, { recursive: true });
  } catch (_) {}

  const attempts = [];
  const selectedByCodec = { h264: null, h265: null };

  for (const cand of candidates) {
    let ok = false;
    let lastError = null;
    let okType = null;
    let lastArgs = null;
    let lastStderr = null;

    const decodeArgs = Array.isArray(cand.decodeArgs) ? cand.decodeArgs : [];
    const isCudaDecode = decodeArgs.includes('-hwaccel') && decodeArgs.includes('cuda') && decodeArgs.includes('-hwaccel_output_format') && decodeArgs.includes('cuda');

    const vfParts = [];
    const candEncoderLower = String(cand && cand.encoder ? cand.encoder : '').toLowerCase();
    const isNvenc = candEncoderLower.endsWith('_nvenc');
    if (isNvenc) {
      if (isCudaDecode) {
        vfParts.push('scale_cuda=w=1280:h=720:format=nv12');
      } else {
        vfParts.push('scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2');
      }
    }
    if (!isCudaDecode && cand && typeof cand.hwUploadFilter === 'string' && cand.hwUploadFilter.length > 0) {
      vfParts.push(cand.hwUploadFilter);
    }
    const vf = vfParts.length > 0 ? vfParts.join(',') : null;

    for (const tc of testCases) {
      const args = ['-hide_banner', '-y', '-loglevel', 'error', ...(Array.isArray(cand.decodeArgs) && tc.type === 'file' ? cand.decodeArgs : [])];

      let out = null;

      if (tc.type === 'file') {
        out = path.join(testDir, `${cand.name}_${now}_${path.basename(tc.input)}.mp4`);
        if (Array.isArray(cand.inputArgs) && cand.inputArgs.length > 0) {
          args.push(...cand.inputArgs);
        }
        if (Array.isArray(cand.initDeviceArgs) && cand.initDeviceArgs.length > 0) {
          args.push(...cand.initDeviceArgs);
        }
        args.push('-i', tc.input);
        const pixArgs = isNvenc && isCudaDecode ? [] : ['-pix_fmt', 'yuv420p'];
        args.push('-t', '1', '-an', '-sn', ...(vf ? ['-vf', vf] : []), '-c:v', cand.encoder, ...pixArgs, '-f', 'mp4', out);
      } else {
        // lavfi 统一输出到 mp4 文件：
        // - 有些硬件编码器在 null muxer 下行为不一致
        // - mp4 输出更接近真实转码路径
        out = path.join(testDir, `${cand.name}_${now}_lavfi.mp4`);
        if (Array.isArray(cand.inputArgs) && cand.inputArgs.length > 0) {
          args.push(...cand.inputArgs);
        }
        if (Array.isArray(cand.initDeviceArgs) && cand.initDeviceArgs.length > 0) {
          args.push(...cand.initDeviceArgs);
        }
        const pixArgs = isNvenc && isCudaDecode ? [] : ['-pix_fmt', 'yuv420p'];
        args.push('-f', 'lavfi', '-i', tc.input, '-t', '1', '-an', '-sn', ...(vf ? ['-vf', vf] : []), '-c:v', cand.encoder, ...pixArgs, '-f', 'mp4', out);
      }

      lastArgs = args;
      const res = runFfmpeg(args, 20000);
      lastStderr = res.stderr || null;
      if (out) {
        try {
          fs.rmSync(out, { force: true });
        } catch (_) {}
      }

      if (res.ok) {
        ok = true;
        okType = tc.type;
        break;
      }
      lastError = res.error || res.stderr || `ffmpeg exited with ${res.status}`;
    }

    if (!ok && !lastError) lastError = 'ffmpeg test failed';

    const record = {
      name: cand.name,
      kind: cand.kind,
      encoder: cand.encoder,
      decodeArgs: cand.decodeArgs,
      hwType: cand.hwType || null,
      device: cand.device || null,
      hwUploadFilter: cand.hwUploadFilter || null,
      inputArgs: Array.isArray(cand.inputArgs) ? cand.inputArgs : null,
      initDeviceArgs: Array.isArray(cand.initDeviceArgs) ? cand.initDeviceArgs : null,
      ok,
      okType,
      lastArgs: Array.isArray(lastArgs) ? lastArgs : null,
      lastStderr: typeof lastStderr === 'string' ? lastStderr.slice(0, 2000) : null,
      error: ok ? null : lastError,
    };
    attempts.push(record);

    if (ok) {
      const codecKey = candEncoderLower.includes('hevc') || candEncoderLower.includes('265') ? 'h265' : 'h264';
      // 如果候选包含 decodeArgs（通常表示“硬件解码+硬件编码”），
      // 则必须在 file 测试通过，才允许作为最终默认方案。
      // 原因：lavfi 没有“文件解码”阶段，无法验证 decodeArgs 是否真的可用。
      if (Array.isArray(cand.decodeArgs) && cand.decodeArgs.length > 0 && okType !== 'file') {
        continue;
      }
      if (selectedByCodec[codecKey]) continue;
      selectedByCodec[codecKey] = {
        name: cand.name,
        kind: cand.kind,
        encoder: cand.encoder,
        decodeArgs: cand.decodeArgs,
        hwType: cand.hwType || null,
        device: cand.device || null,
        hwUploadFilter: cand.hwUploadFilter || null,
        inputArgs: Array.isArray(cand.inputArgs) ? cand.inputArgs : null,
        initDeviceArgs: Array.isArray(cand.initDeviceArgs) ? cand.initDeviceArgs : null,
      };
    }
  }

  const selectedH264 = selectedByCodec.h264;
  const selectedH265 = selectedByCodec.h265;
  const available = buildAvailableHwAccelList(attempts);
  const baseSelectedProfile = selectedH264 || selectedH265;
  let selected = null;
  if (baseSelectedProfile) {
    const groupMeta = getHwAccelGroupMeta(baseSelectedProfile);
    const entryKey = groupMeta && groupMeta.key ? String(groupMeta.key) : '';
    const entry = entryKey ? findAvailableHwAccelEntry(available, entryKey) : null;
    selected = entry ? combineHwAccelEntryToConfig(entry) : null;
    if (!selected) {
      selected = {
        key: entryKey || null,
        displayName: groupMeta && groupMeta.label ? String(groupMeta.label) : null,
        name: baseSelectedProfile.name || null,
        kind: baseSelectedProfile.kind || null,
        encoder: baseSelectedProfile.encoder || null,
        decodeArgs: baseSelectedProfile.decodeArgs || null,
        hwType: baseSelectedProfile.hwType || null,
        device: baseSelectedProfile.device || null,
        hwUploadFilter: baseSelectedProfile.hwUploadFilter || null,
        inputArgs: baseSelectedProfile.inputArgs || null,
        initDeviceArgs: baseSelectedProfile.initDeviceArgs || null,
        profiles: { h264: selectedH264 || null, h265: selectedH265 || null },
      };
    } else {
      selected.profiles = { h264: selectedH264 || null, h265: selectedH265 || null };
    }
  }
  const preferredRaw = await tableConfig.getConfigByKey('transcode_hwaccel_preferred');
  const preferredKey = preferredRaw ? String(preferredRaw).trim() : '';
  const preferredExists = preferredKey ? !!findAvailableHwAccelEntry(available, preferredKey) : false;
  const nextPreferredKey = preferredExists ? preferredKey : '';

  const report = {
    platform,
    arch,
    updatedAt: now,
    probeSchemaVersion: HW_ACCEL_PROBE_SCHEMA_VERSION,
    hardwareFingerprint,
    hardwareSnapshot,
    controllers: controllers.map(g => ({
      vendor: g.vendor || null,
      model: g.model || null,
      vram: g.vram || g.vramTotal || g.memoryTotal || null,
    })),
    candidates: attempts,
    available,
    selected,
    fallback: { name: 'cpu', encoder: 'libx264', decodeArgs: null },
  };

  await tableConfig.setConfigByKey('transcode_hwaccel_report', JSON.stringify(report));
  await tableConfig.setConfigByKey('transcode_hwaccel_available', JSON.stringify(available));
  await tableConfig.setConfigByKey('transcode_hwaccel_selected', JSON.stringify(selected || null));
  await tableConfig.setConfigByKey('transcode_hwaccel_preferred', nextPreferredKey);
  await tableConfig.setConfigByKey('transcode_hwaccel_updated_at', String(now));

  if (selected) {
    Logger.info(`✅ Transcode HW accel available: ${selected.name}`);
  } else {
    Logger.info('ℹ️ No transcode HW accel, using CPU');
  }
}

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ FFmpeg HW probe worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ FFmpeg HW probe worker unhandledRejection', reason);
  process.exit(0);
});

run();
