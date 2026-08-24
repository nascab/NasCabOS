const path = require('path');
const fs = require('fs-extra');
const ffmpeg = require('fluent-ffmpeg');
const Logger = require('../../../utils/logger');
const config = require('../../../config/config');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableMediaToolAudioTrans = require('../../../db/table/tableMediaToolAudioTrans');
const ffmpegPath = require('../../../libsPath/ffmpegPath');
const ffprobePath = require('../../../libsPath/ffprobePath');
const { copyFileAtomic } = require('../../../api/modules/mediaTool/imageCompressCore');
const PathUtil = require('../../../utils/pathUtil');

ffmpeg.setFfmpegPath(ffmpegPath.path);
ffmpeg.setFfprobePath(ffprobePath.path);

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function safeTruncate(s, maxLen) {
  const t = ensureString(s);
  if (t.length <= maxLen) return t;
  return t.slice(0, Math.max(0, maxLen - 3)) + '...';
}

function normalizeConfig(raw) {
  if (raw === undefined || raw === null) return {};
  if (typeof raw === 'object') return raw || {};
  if (typeof raw === 'string') {
    try {
      const decoded = JSON.parse(raw);
      if (decoded && typeof decoded === 'object') return decoded;
    } catch (_) {}
  }
  return {};
}

function isAudioExt(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const list = Array.isArray(config.musicTypeList) ? config.musicTypeList : [];
  if (list.length > 0) {
    return list.map(v => String(v || '').toLowerCase()).includes(ext);
  }
  return ['.mp3', '.flac', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape', '.m4a'].includes(ext);
}

async function ensureMainDbReady() {
  await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
  const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  await knex.raw('SELECT 1');
  return knex;
}

async function getFileSize(p) {
  try {
    const stat = await fs.stat(p);
    return stat && stat.size ? Number(stat.size) : 0;
  } catch (_) {
    return 0;
  }
}

async function ensureTargetDirWritable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return 'target_not_found';
  try {
    await fs.ensureDir(p);
  } catch (_) {
    return 'target_not_found';
  }
  let stat;
  try {
    stat = await fs.stat(p);
  } catch (_) {
    return 'target_not_found';
  }
  if (!stat.isDirectory()) return 'target_not_dir';
  const mode = fs.constants.R_OK | fs.constants.W_OK | (fs.constants.X_OK || 0);
  try {
    await fs.access(p, mode);
  } catch (_) {
    return 'target_no_access';
  }
  return '';
}

async function countFilesRecursive({ root, shouldSkipDir, isStopRequested }) {
  let total = 0;
  const stack = [root];
  while (stack.length) {
    if (isStopRequested()) return total;
    const dir = stack.pop();
    let entries;
    try {
      entries = await fs.readdir(dir);
    } catch (_) {
      continue;
    }
    for (const name of entries) {
      if (isStopRequested()) return total;
      const full = path.join(dir, name);
      let stat;
      try {
        stat = await fs.lstat(full);
      } catch (_) {
        continue;
      }
      if (stat.isDirectory()) {
        if (shouldSkipDir && shouldSkipDir(full)) continue;
        stack.push(full);
      } else if (stat.isFile()) {
        total += 1;
      }
    }
  }
  return total;
}

async function walkFilesRecursive({ root, shouldSkipDir, isStopRequested, onFile }) {
  const stack = [root];
  while (stack.length) {
    if (isStopRequested()) return;
    const dir = stack.pop();
    let entries;
    try {
      entries = await fs.readdir(dir);
    } catch (_) {
      continue;
    }
    for (const name of entries) {
      if (isStopRequested()) return;
      const full = path.join(dir, name);
      let stat;
      try {
        stat = await fs.lstat(full);
      } catch (_) {
        continue;
      }
      if (stat.isDirectory()) {
        if (shouldSkipDir && shouldSkipDir(full)) continue;
        stack.push(full);
      } else if (stat.isFile()) {
        await onFile(full);
      }
    }
  }
}

function buildAudioCodecFromFormat(outFormat) {
  const f = ensureString(outFormat).trim().toLowerCase();
  if (f === 'mp3') return 'libmp3lame';
  if (f === 'flac') return 'flac';
  if (f === 'ogg') return 'libvorbis';
  if (f === 'opus') return 'libopus';
  if (f === 'wav') return 'pcm_s16le';
  if (f === 'wma') return 'wmav2';
  if (f === 'aac') return 'aac';
  return 'aac';
}

function buildOutputExt(outFormat) {
  const f = ensureString(outFormat).trim().toLowerCase();
  if (f === 'mp3') return '.mp3';
  if (f === 'flac') return '.flac';
  if (f === 'ogg') return '.ogg';
  if (f === 'wav') return '.wav';
  if (f === 'opus') return '.opus';
  if (f === 'wma') return '.wma';
  if (f === 'aac') return '.aac';
  return '.m4a';
}

function buildOutputFormat(outFormat) {
  const f = ensureString(outFormat).trim().toLowerCase();
  if (f === 'mp3') return 'mp3';
  if (f === 'flac') return 'flac';
  if (f === 'ogg') return 'ogg';
  if (f === 'wav') return 'wav';
  if (f === 'opus') return 'opus';
  if (f === 'wma') return 'asf';
  if (f === 'aac') return 'adts';
  return 'ipod';
}

function buildTmpOutputPath(outputPath) {
  const p = ensureString(outputPath).trim();
  return `${p}.${process.pid}.${Date.now()}.cab.tmp`;
}

async function cleanupCabTmpFiles(rootDir) {
  const root = ensureString(rootDir).trim();
  if (!root) return 0;
  const st = await fs.stat(root).catch(() => null);
  if (!st || !st.isDirectory()) return 0;

  let removed = 0;
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => null);
    if (!entries) continue;
    for (const ent of entries) {
      if (!ent || !ent.name) continue;
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        stack.push(full);
        continue;
      }
      if (ent.isFile() && ent.name.endsWith('.cab.tmp')) {
        const ok = await fs
          .remove(full)
          .then(() => true)
          .catch(() => false);
        if (ok) removed += 1;
      }
    }
  }
  return removed;
}

function parseTimemarkToSeconds(timemark) {
  const s = ensureString(timemark).trim();
  const m = s.match(/^(\d+):(\d+):(\d+)(?:\.(\d+))?$/);
  if (!m) return null;
  const hh = Number(m[1]);
  const mm = Number(m[2]);
  const ss = Number(m[3]);
  const frac = m[4] ? Number(`0.${m[4]}`) : 0;
  if (![hh, mm, ss, frac].every(v => Number.isFinite(v))) return null;
  return hh * 3600 + mm * 60 + ss + frac;
}

function formatSeconds(sec) {
  const s = Number(sec);
  if (!Number.isFinite(s) || s < 0) return '';
  const total = Math.floor(s);
  const hh = String(Math.floor(total / 3600)).padStart(2, '0');
  const mm = String(Math.floor((total % 3600) / 60)).padStart(2, '0');
  const ss = String(total % 60).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

async function getMediaDurationSec(filePath) {
  const p = ensureString(filePath).trim();
  if (!p) return null;
  return await new Promise(resolve => {
    ffmpeg.ffprobe(p, (err, metadata) => {
      if (err || !metadata) return resolve(null);
      const d = metadata && metadata.format && metadata.format.duration ? Number(metadata.format.duration) : null;
      if (d && Number.isFinite(d) && d > 0) return resolve(d);
      const streams = metadata && Array.isArray(metadata.streams) ? metadata.streams : [];
      const a = streams.find(s => s && s.codec_type === 'audio');
      const da = a && a.duration ? Number(a.duration) : null;
      if (da && Number.isFinite(da) && da > 0) return resolve(da);
      resolve(null);
    });
  });
}

async function transcodeOne({ inputPath, outputPath, cfg, stopSignal, onCommand, onProgress }) {
  const outDir = path.dirname(outputPath);
  await fs.ensureDir(outDir);

  const outFormat = ensureString(cfg.out_format).trim().toLowerCase() || 'mp3';
  const audioCodec = buildAudioCodecFromFormat(outFormat);
  const outputFormat = buildOutputFormat(outFormat);

  const ab = cfg.audio_bitrate_kbps !== undefined && cfg.audio_bitrate_kbps !== null ? Number(cfg.audio_bitrate_kbps) : null;
  const sampleRateRaw = ensureString(cfg.sample_rate).trim().toLowerCase();
  const channelsRaw = ensureString(cfg.channels).trim().toLowerCase();
  const threadsRaw = cfg.thread_count !== undefined && cfg.thread_count !== null ? Number(cfg.thread_count) : null;
  const threads = threadsRaw !== null && Number.isFinite(threadsRaw) ? Math.max(1, Math.min(50, Math.trunc(threadsRaw))) : null;

  const durationSec = await getMediaDurationSec(inputPath);
  const tmp = buildTmpOutputPath(outputPath);

  const inputOptions = ['-probesize 100M', '-analyzeduration 100M'];
  const outputOptions = [];
  outputOptions.push(`-f ${outputFormat}`);
  outputOptions.push('-vn');
  if (ab && Number.isFinite(ab) && ab > 0) outputOptions.push(`-b:a ${Math.trunc(ab)}k`);
  if (sampleRateRaw && sampleRateRaw !== 'source') {
    const sr = Number(sampleRateRaw);
    if (Number.isFinite(sr) && sr > 0) outputOptions.push(`-ar ${Math.trunc(sr)}`);
  }
  if (channelsRaw === 'mono') outputOptions.push('-ac 1');
  else if (channelsRaw === 'stereo') outputOptions.push('-ac 2');
  if (threads && Number.isFinite(threads) && threads > 0) outputOptions.push(`-threads ${threads}`);

  return await new Promise((resolve, reject) => {
    const cmd = ffmpeg(inputPath)
      .inputOptions(inputOptions)
      .outputOptions(outputOptions)
      .audioCodec(audioCodec)
      .on('start', cmdLine => {
        if (typeof onCommand === 'function') onCommand(cmd);
      })
      .on('progress', p => {
        if (typeof onProgress !== 'function') return;
        const timemark = p && p.timemark ? String(p.timemark) : '';
        const sec = parseTimemarkToSeconds(timemark);
        let percent = p && p.percent !== undefined && p.percent !== null ? Number(p.percent) : null;
        if ((!percent || !Number.isFinite(percent)) && durationSec && sec !== null && Number.isFinite(sec)) {
          percent = (sec / durationSec) * 100;
        }
        if (percent !== null && Number.isFinite(percent)) {
          if (percent < 0) percent = 0;
          if (percent > 100) percent = 100;
        } else {
          percent = null;
        }
        onProgress({
          timemark,
          durationSec,
          sec: sec !== null && Number.isFinite(sec) ? sec : null,
          percent,
        });
      })
      .on('error', err => {
        try {
          fs.removeSync(tmp);
        } catch (_) {}
        reject(err);
      })
      .on('end', async () => {
        if (stopSignal()) {
          try {
            await fs.remove(tmp);
          } catch (_) {}
          resolve({ ok: false, stopped: true });
          return;
        }
        try {
          await fs.move(tmp, outputPath, { overwrite: true });
          resolve({ ok: true });
        } catch (e) {
          reject(e);
        }
      })
      .output(tmp);

    try {
      cmd.run();
    } catch (e) {
      reject(e);
    }
  });
}

class AudioTransWorker {
  constructor() {
    this.taskId = null;
    this.knex = null;
    this.stopRequested = false;
    this.running = false;
    this.runningPromise = null;
    this._exiting = false;
    this._currentCommand = null;
    this._runningCommands = new Set();
    this._cleanupRoot = '';
    this._init();
  }

  _scheduleExit(delayMs = 80) {
    if (this._exiting) return;
    this._exiting = true;
    const ms = Math.max(0, Number(delayMs || 0) || 0);
    setTimeout(() => {
      const exitNow = () => {
        try {
          process.exit(0);
        } catch (_) {}
      };
      const root = ensureString(this._cleanupRoot).trim();
      if (!root) {
        exitNow();
        return;
      }
      cleanupCabTmpFiles(root)
        .catch(() => null)
        .finally(() => exitNow());
    }, ms);
  }

  async _init() {
    this.knex = await ensureMainDbReady();
    this._bindProcessEvents();
  }

  _reply(type, data) {
    if (typeof process.send !== 'function') return;
    try {
      process.send({ type, data });
    } catch (_) {}
  }

  async _updateTask(patch) {
    const idNum = Number(this.taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return;
    await this.knex('media_tool_audio_trans')
      .where({ id: idNum })
      .update({ ...patch, update_time: new Date() })
      .catch(() => null);
  }

  async _getTaskRow(taskId) {
    const idNum = Number(taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return null;
    return await this.knex('media_tool_audio_trans')
      .where({ id: idNum })
      .first()
      .catch(() => null);
  }

  async _prepareTaskId(taskId) {
    const idNum = Number(taskId);
    if (!Number.isFinite(idNum) || idNum <= 0) return { ok: false, error: 'invalid_params' };
    this.taskId = idNum;

    const row = await this._getTaskRow(idNum);
    if (!row) return { ok: false, error: 'invalid_params' };

    const sourcePath = ensureString(row.source_path).trim();
    const targetPath = ensureString(row.target_path).trim();
    const cfg = normalizeConfig(row.trans_config);
    const policy = ensureString(row.non_audio_policy).trim().toLowerCase();

    if (!sourcePath || !targetPath) return { ok: false, error: 'invalid_params' };
    if (![tableMediaToolAudioTrans.NON_AUDIO_SKIP, tableMediaToolAudioTrans.NON_AUDIO_COPY].includes(policy)) {
      return { ok: false, error: 'invalid_params' };
    }

    const sourceResolved = path.resolve(sourcePath);
    const targetResolved = path.resolve(targetPath);
    const conflict = PathUtil.isMutualConflictPath(sourceResolved, targetResolved);
    if (conflict) return { ok: false, error: 'invalid_path_relation' };

    let sourceStat;
    try {
      sourceStat = await fs.stat(sourceResolved);
    } catch (_) {
      return { ok: false, error: 'source_not_found' };
    }

    const tgtOk = await ensureTargetDirWritable(targetResolved);
    if (tgtOk) return { ok: false, error: tgtOk };

    if (sourceStat.isFile()) {
      return {
        ok: true,
        taskId: this.taskId,
        sourceType: 'file',
        sourceResolved,
        targetResolved,
        cfg,
        nonAudioPolicy: policy,
      };
    }

    if (!sourceStat.isDirectory()) return { ok: false, error: 'source_not_found' };

    const targetRootResolved = path.join(targetResolved, path.basename(sourceResolved));
    const tgtRootOk = await ensureTargetDirWritable(targetRootResolved);
    if (tgtRootOk) return { ok: false, error: tgtRootOk };

    return {
      ok: true,
      taskId: this.taskId,
      sourceType: 'dir',
      sourceResolved,
      targetResolved,
      targetRootResolved,
      cfg,
      nonAudioPolicy: policy,
    };
  }

  async start({ requestId, taskId }) {
    if (this.running) {
      this._reply('audioTransStartResponse', { requestId, ok: true, already_running: true, pid: process.pid });
      return;
    }

    const prepared = await this._prepareTaskId(taskId);
    if (!prepared.ok) {
      const err = ensureString(prepared.error || 'invalid_params').trim();
      if (['source_not_found', 'target_not_found', 'target_not_dir', 'target_no_access', 'invalid_path_relation'].includes(err)) {
        await this._updateTask({
          status: tableMediaToolAudioTrans.STATUS_ERROR,
          last_error: safeTruncate(err, 800),
          progress: '',
          last_end_time: new Date(),
        });
      }
      this._reply('audioTransStartResponse', { requestId, ok: false, error: prepared.error || 'invalid_params' });
      this._scheduleExit();
      return;
    }

    this.stopRequested = false;
    this.running = true;
    this._cleanupRoot = prepared.sourceType === 'dir' ? prepared.targetRootResolved : prepared.targetResolved;

    await this._updateTask({
      status: tableMediaToolAudioTrans.STATUS_RUNNING,
      last_error: null,
      progress: '',
      total_files: 0,
      done_files: 0,
      handled_input_bytes: 0,
      handled_output_bytes: 0,
      processed_count: 0,
      skipped_count: 0,
      non_audio_count: 0,
      last_start_time: new Date(),
      last_end_time: null,
    });

    this._reply('audioTransStartResponse', { requestId, ok: true, pid: process.pid });

    this.runningPromise = this._run(prepared)
      .catch(async () => {
        await this._updateTask({
          status: tableMediaToolAudioTrans.STATUS_STOPPED,
          last_error: null,
          progress: '',
          last_end_time: new Date(),
        });
      })
      .finally(async () => {
        this.running = false;
        this.runningPromise = null;
        await cleanupCabTmpFiles(this._cleanupRoot).catch(() => null);
        this._scheduleExit();
      });
  }

  async stop({ requestId }) {
    this.stopRequested = true;
    const cmds = [];
    try {
      if (this._currentCommand) cmds.push(this._currentCommand);
      if (this._runningCommands && this._runningCommands.size > 0) {
        cmds.push(...Array.from(this._runningCommands));
      }
    } catch (_) {}
    for (const cmd of cmds) {
      if (!cmd || typeof cmd.kill !== 'function') continue;
      try {
        cmd.kill('SIGKILL');
      } catch (_) {}
    }
    this._reply('audioTransStopResponse', { requestId, ok: true });
    if (!this.running) {
      await cleanupCabTmpFiles(this._cleanupRoot).catch(() => null);
      this._scheduleExit();
    }
  }

  async _run(prepared) {
    const isStopRequested = () => !!this.stopRequested;
    const cfg = prepared.cfg || {};
    const outExt = buildOutputExt(cfg.out_format);

    if (prepared.sourceType === 'file') {
      const base = path.basename(prepared.sourceResolved, path.extname(prepared.sourceResolved));
      const outputPath = path.join(prepared.targetResolved, `${base}${outExt}`);

      await this._updateTask({ total_files: 1 });

      const inputBytes = await getFileSize(prepared.sourceResolved);
      const isAud = isAudioExt(prepared.sourceResolved);
      if (!isAud) {
        let outputBytes = 0;
        if (prepared.nonAudioPolicy === tableMediaToolAudioTrans.NON_AUDIO_COPY) {
          const copyDst = path.join(prepared.targetResolved, path.basename(prepared.sourceResolved));
          const existed = await fs.pathExists(copyDst).catch(() => false);
          if (!existed) {
            await fs.ensureDir(path.dirname(copyDst));
            await copyFileAtomic({ sourcePath: prepared.sourceResolved, destPath: copyDst }).catch(() => null);
          }
          outputBytes = (await getFileSize(copyDst)) ?? 0;
        }
        await this._updateTask({
          done_files: 1,
          handled_input_bytes: inputBytes,
          handled_output_bytes: outputBytes,
          processed_count: 0,
          skipped_count: 1,
          non_audio_count: 1,
          status: tableMediaToolAudioTrans.STATUS_STOPPED,
          last_error: null,
          progress: '',
          last_end_time: new Date(),
        });
        return;
      }
      const outputExists = await fs.pathExists(outputPath).catch(() => false);
      if (outputExists) {
        const outputBytes = await getFileSize(outputPath);
        await this._updateTask({
          done_files: 1,
          handled_input_bytes: inputBytes,
          handled_output_bytes: outputBytes,
          processed_count: 0,
          skipped_count: 1,
          non_audio_count: 0,
          status: tableMediaToolAudioTrans.STATUS_STOPPED,
          last_error: null,
          progress: '',
          last_end_time: new Date(),
        });
        return;
      }
      const ok = await this._handleOneFile({
        inputPath: prepared.sourceResolved,
        outputPath,
        cfg,
        isStopRequested,
        relPath: path.basename(prepared.sourceResolved),
      });

      if (ok && !isStopRequested()) {
        const outputBytes = await getFileSize(outputPath);
        await this._updateTask({
          done_files: 1,
          handled_input_bytes: inputBytes,
          handled_output_bytes: outputBytes,
          processed_count: 1,
          status: tableMediaToolAudioTrans.STATUS_STOPPED,
          last_error: null,
          progress: '',
          last_end_time: new Date(),
        });
      }

      if (isStopRequested()) {
        await this._updateTask({
          status: tableMediaToolAudioTrans.STATUS_STOPPED,
          progress: '',
          last_end_time: new Date(),
        });
      }
      return;
    }

    const shouldSkipDir = p => PathUtil.isAncestorPath(PathUtil.normalizeFsPathForCompare(prepared.targetResolved), PathUtil.normalizeFsPathForCompare(p));
    const totalFiles = await countFilesRecursive({ root: prepared.sourceResolved, shouldSkipDir, isStopRequested });
    await this._updateTask({ total_files: totalFiles });

    let doneFiles = 0;
    let handledInputBytes = 0;
    let handledOutputBytes = 0;
    let processedCount = 0;
    let skippedCount = 0;
    let nonAudioCount = 0;
    let lastFlushTs = 0;

    const flush = async force => {
      const now = Date.now();
      if (!force && now - lastFlushTs < 600) return;
      lastFlushTs = now;
      const progress = totalFiles > 0 ? `${doneFiles}/${totalFiles}` : `${doneFiles}`;
      await this._updateTask({
        progress,
        done_files: doneFiles,
        handled_input_bytes: handledInputBytes,
        handled_output_bytes: handledOutputBytes,
        processed_count: processedCount,
        skipped_count: skippedCount,
        non_audio_count: nonAudioCount,
      }).catch(() => null);
    };

    await walkFilesRecursive({
      root: prepared.sourceResolved,
      shouldSkipDir,
      isStopRequested,
      onFile: async full => {
        if (isStopRequested()) return;
        const rel = path.relative(prepared.sourceResolved, full);
        const relDir = path.dirname(rel);
        const baseName = path.basename(full, path.extname(full));
        const outRel = path.join(relDir === '.' ? '' : relDir, `${baseName}${outExt}`);
        const outputPath = path.join(prepared.targetRootResolved, outRel);

        const inputBytes = await getFileSize(full);

        const isAud = isAudioExt(full);
        if (!isAud) {
          nonAudioCount += 1;
          if (prepared.nonAudioPolicy === tableMediaToolAudioTrans.NON_AUDIO_COPY) {
            const copyDst = path.join(prepared.targetRootResolved, rel);
            const existed = await fs.pathExists(copyDst).catch(() => false);
            if (!existed) {
              await fs.ensureDir(path.dirname(copyDst));
              await copyFileAtomic({ sourcePath: full, destPath: copyDst }).catch(() => null);
            }
            const outputBytes = await getFileSize(copyDst);
            handledOutputBytes += outputBytes;
          }
          skippedCount += 1;
          doneFiles += 1;
          handledInputBytes += inputBytes;
          await flush(false);
          return;
        }

        const existedOut = await fs.pathExists(outputPath).catch(() => false);
        if (existedOut) {
          const outputBytes = await getFileSize(outputPath);
          skippedCount += 1;
          doneFiles += 1;
          handledInputBytes += inputBytes;
          handledOutputBytes += outputBytes;
          await flush(false);
          return;
        }

        const ok = await this._handleOneFile({
          inputPath: full,
          outputPath,
          cfg,
          isStopRequested,
          relPath: rel,
        });
        if (!ok) return;

        const outputBytes = await getFileSize(outputPath);
        processedCount += 1;
        doneFiles += 1;
        handledInputBytes += inputBytes;
        handledOutputBytes += outputBytes;
        await flush(false);
      },
    });
    await flush(true);

    if (isStopRequested()) {
      await this._updateTask({
        status: tableMediaToolAudioTrans.STATUS_STOPPED,
        progress: '',
        last_end_time: new Date(),
      });
      return;
    }

    await this._updateTask({
      status: tableMediaToolAudioTrans.STATUS_STOPPED,
      last_error: null,
      progress: '',
      last_end_time: new Date(),
    });
  }

  async _handleOneFile({ inputPath, outputPath, cfg, isStopRequested, relPath }) {
    if (isStopRequested()) return false;

    let cmdRef = null;
    let timer = null;
    let latestProgress = '';
    let writing = false;

    const writeOnce = async () => {
      if (writing) return;
      if (!latestProgress) return;
      if (isStopRequested()) return;
      writing = true;
      try {
        await this._updateTask({ progress: safeTruncate(latestProgress, 800) });
      } finally {
        writing = false;
      }
    };

    try {
      timer = setInterval(() => {
        writeOnce().catch(() => null);
      }, 1000);
    } catch (_) {
      timer = null;
    }

    try {
      const res = await transcodeOne({
        inputPath,
        outputPath,
        cfg,
        stopSignal: isStopRequested,
        onCommand: cmd => {
          this._currentCommand = cmd;
          cmdRef = cmd;
          try {
            this._runningCommands.add(cmd);
          } catch (_) {}
        },
        onProgress: p => {
          const label = ensureString(relPath).trim() || path.basename(inputPath);
          const percent = p && p.percent !== undefined && p.percent !== null ? Number(p.percent) : null;
          const sec = p && p.sec !== undefined && p.sec !== null ? Number(p.sec) : null;
          const dur = p && p.durationSec !== undefined && p.durationSec !== null ? Number(p.durationSec) : null;
          const seg = sec !== null && Number.isFinite(sec) ? formatSeconds(sec) : '';
          const tot = dur !== null && Number.isFinite(dur) ? formatSeconds(dur) : '';
          const timePart = seg && tot ? `${seg}/${tot}` : seg ? seg : '';
          const percentPart = percent !== null && Number.isFinite(percent) ? `${percent.toFixed(1)}%` : '';
          const parts = [label, timePart, percentPart].filter(v => ensureString(v).trim().length > 0);
          latestProgress = parts.join(' ');
        },
      });
      this._currentCommand = null;
      if (cmdRef) {
        try {
          this._runningCommands.delete(cmdRef);
        } catch (_) {}
      }
      await writeOnce().catch(() => null);
      if (timer) {
        try {
          clearInterval(timer);
        } catch (_) {}
        timer = null;
      }
      await this._updateTask({ progress: '' }).catch(() => null);
      if (!res || !res.ok) return false;
      return true;
    } catch (e) {
      this._currentCommand = null;
      if (cmdRef) {
        try {
          this._runningCommands.delete(cmdRef);
        } catch (_) {}
      }
      if (timer) {
        try {
          clearInterval(timer);
        } catch (_) {}
        timer = null;
      }
      const msg = e && e.message ? String(e.message) : String(e);
      await this._updateTask({
        status: tableMediaToolAudioTrans.STATUS_ERROR,
        last_error: safeTruncate(msg, 800),
        progress: '',
        last_end_time: new Date(),
      });
      this.stopRequested = true;
      return false;
    }
  }

  _bindProcessEvents() {
    process.on('message', message => {
      if (!message || !message.type) return;
      if (message.type === 'start') {
        const requestId = message?.data?.requestId;
        const taskId = message?.data?.taskId;
        this.start({ requestId, taskId }).catch(err => {
          this._reply('audioTransStartResponse', {
            requestId,
            ok: false,
            error: err && err.message ? String(err.message) : String(err),
          });
        });
      } else if (message.type === 'stop') {
        const requestId = message?.data?.requestId;
        this.stop({ requestId }).catch(err => {
          this._reply('audioTransStopResponse', {
            requestId,
            ok: false,
            error: err && err.message ? String(err.message) : String(err),
          });
        });
      }
    });

    process.on('uncaughtException', err => {
      Logger.error('❌ audioTrans worker uncaughtException', err);
      this._scheduleExit();
    });

    process.on('unhandledRejection', reason => {
      Logger.error('❌ audioTrans worker unhandledRejection', reason);
      this._scheduleExit();
    });
  }
}

new AudioTransWorker();
