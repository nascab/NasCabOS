const path = require('path');
const fs = require('fs-extra');
const Logger = require('../../../utils/logger');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableMediaToolImgBatchCompress = require('../../../db/table/tableMediaToolImgBatchCompress');
const config = require('../../../config/config');
const { compressImageAtomic, copyFileAtomic } = require('../../../api/modules/mediaTool/imageCompressCore');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function safeTruncate(s, maxLen) {
  const t = ensureString(s);
  if (t.length <= maxLen) return t;
  return t.slice(0, Math.max(0, maxLen - 3)) + '...';
}

function isPathWithin(parent, child) {
  const parentResolved = path.resolve(parent);
  const childResolved = path.resolve(child);
  if (parentResolved === childResolved) return true;
  return childResolved.startsWith(parentResolved + path.sep);
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

async function checkSourceDirReadable(dirPath) {
  const p = ensureString(dirPath).trim();
  if (!p) return 'source_not_found';
  let stat;
  try {
    stat = await fs.stat(p);
  } catch (_) {
    return 'source_not_found';
  }
  if (!stat.isDirectory()) return 'source_not_dir';
  const mode = fs.constants.R_OK | (fs.constants.X_OK || 0);
  try {
    await fs.access(p, mode);
  } catch (_) {
    return 'source_no_access';
  }
  return '';
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

function buildOutputPath({ targetRoot, relativePath, outFormat }) {
  const parsed = path.parse(relativePath);
  const ext = `.${String(outFormat || 'jpeg').toLowerCase()}`;
  const outName = `${parsed.name}${ext}`;
  return path.join(targetRoot, parsed.dir || '', outName);
}

function isImageFileByExt(filePath) {
  const extLower = path.extname(filePath || '').toLowerCase();
  if (!extLower) return false;
  const imgList = Array.isArray(config.imgTypeList) ? config.imgTypeList : [];
  const rawList = Array.isArray(config.rawImgTypeList) ? config.rawImgTypeList : [];
  return imgList.includes(extLower) || rawList.includes(extLower);
}

class ImgBatchCompressWorker {
  constructor() {
    this.taskId = null;
    this.knex = null;
    this.stopRequested = false;
    this.running = false;
    this.runningPromise = null;
    this._exiting = false;
    this._init();
  }

  _scheduleExit(delayMs = 80) {
    if (this._exiting) return;
    this._exiting = true;
    const ms = Math.max(0, Number(delayMs || 0) || 0);
    setTimeout(() => {
      try {
        process.exit(0);
      } catch (_) {}
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
    await this.knex('media_tool_img_batch_compress')
      .where({ id: idNum })
      .update({ ...patch, update_time: new Date() })
      .catch(() => null);
  }

  async _getTaskRow() {
    const idNum = Number(this.taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return null;
    return await this.knex('media_tool_img_batch_compress')
      .where({ id: idNum })
      .first()
      .catch(() => null);
  }

  async _prepareTaskId(taskId) {
    const envId = Number(process.env.IMG_BATCH_COMPRESS_TASK_ID || 0) || 0;
    const msgId = Number(taskId || 0) || 0;
    const idNum = msgId || envId;
    if (!Number.isFinite(idNum) || idNum <= 0) return { ok: false, error: 'invalid_params' };
    this.taskId = idNum;
    const row = await this._getTaskRow();
    if (!row) return { ok: false, error: 'not_found' };

    const sourcePath = ensureString(row.source_path).trim();
    const targetPath = ensureString(row.target_path).trim();
    const outFormat = ensureString(row.out_format).trim().toLowerCase();
    const quality = Number(row.quality);
    const outSizeRaw = row.out_size === undefined || row.out_size === null ? null : Number(row.out_size);
    const outSize = Number.isFinite(outSizeRaw) && outSizeRaw > 0 ? outSizeRaw : null;
    const policy = ensureString(row.non_image_policy).trim().toLowerCase();

    if (!sourcePath || !targetPath) return { ok: false, error: 'invalid_params' };
    if (![tableMediaToolImgBatchCompress.OUT_FORMAT_JPEG, tableMediaToolImgBatchCompress.OUT_FORMAT_PNG, tableMediaToolImgBatchCompress.OUT_FORMAT_WEBP].includes(outFormat)) {
      return { ok: false, error: 'invalid_params' };
    }
    if (!Number.isFinite(quality) || quality < 1 || quality > 100) return { ok: false, error: 'invalid_params' };
    if (policy && ![tableMediaToolImgBatchCompress.NON_IMAGE_SKIP, tableMediaToolImgBatchCompress.NON_IMAGE_COPY].includes(policy)) {
      return { ok: false, error: 'invalid_params' };
    }

    const sourceResolved = path.resolve(sourcePath);
    const targetResolved = path.resolve(targetPath);
    if (isPathWithin(sourceResolved, targetResolved)) return { ok: false, error: 'invalid_params' };
    const targetRootResolved = path.join(targetResolved, path.basename(sourceResolved));

    const srcOk = await checkSourceDirReadable(sourceResolved);
    if (srcOk) return { ok: false, error: srcOk };
    const tgtOk = await ensureTargetDirWritable(targetResolved);
    if (tgtOk) return { ok: false, error: tgtOk };
    const tgtRootOk = await ensureTargetDirWritable(targetRootResolved);
    if (tgtRootOk) return { ok: false, error: tgtRootOk };

    return {
      ok: true,
      taskId: this.taskId,
      sourceResolved,
      targetResolved,
      targetRootResolved,
      outFormat,
      quality,
      outSize,
      nonImagePolicy: policy || tableMediaToolImgBatchCompress.NON_IMAGE_SKIP,
    };
  }

  async start({ requestId, taskId }) {
    if (this.running) {
      this._reply('imgBatchCompressStartResponse', { requestId, ok: true, already_running: true, pid: process.pid });
      return;
    }

    const prepared = await this._prepareTaskId(taskId);
    if (!prepared.ok) {
      const err = ensureString(prepared.error || 'invalid_params').trim();
      if (err === 'source_not_found' || err === 'target_not_found' || err === 'target_not_dir' || err === 'target_no_access') {
        await this._updateTask({
          status: tableMediaToolImgBatchCompress.STATUS_ERROR,
          last_error: safeTruncate(err, 800),
          progress: '',
          last_end_time: new Date(),
        });
      }
      this._reply('imgBatchCompressStartResponse', { requestId, ok: false, error: prepared.error || 'invalid_params' });
      this._scheduleExit();
      return;
    }

    this.stopRequested = false;
    this.running = true;

    await this._updateTask({
      status: tableMediaToolImgBatchCompress.STATUS_RUNNING,
      last_error: null,
      progress: '',
      total_files: 0,
      done_files: 0,
      handled_input_bytes: 0,
      handled_output_bytes: 0,
      processed_count: 0,
      skipped_count: 0,
      non_image_count: 0,
      last_start_time: new Date(),
      last_end_time: null,
    });

    this._reply('imgBatchCompressStartResponse', { requestId, ok: true, pid: process.pid });

    this.runningPromise = this._run(prepared)
      .catch(async err => {
        await this._updateTask({
          status: tableMediaToolImgBatchCompress.STATUS_STOPPED,
          last_error: null,
          progress: '',
          last_end_time: new Date(),
        });
      })
      .finally(async () => {
        this.running = false;
        this.runningPromise = null;
        this._scheduleExit();
      });
  }

  async stop({ requestId }) {
    this.stopRequested = true;
    this._reply('imgBatchCompressStopResponse', { requestId, ok: true });
    if (!this.running) this._scheduleExit();
  }

  async _run({ sourceResolved, targetResolved, targetRootResolved, outFormat, quality, outSize, nonImagePolicy }) {
    const shouldSkipDir = p => isPathWithin(targetResolved, p);
    const isStopRequested = () => !!this.stopRequested;

    const totalFiles = await countFilesRecursive({ root: sourceResolved, shouldSkipDir, isStopRequested });
    await this._updateTask({ total_files: totalFiles });

    let doneFiles = 0;
    let handledInputBytes = 0;
    let handledOutputBytes = 0;
    let processedCount = 0;
    let skippedCount = 0;
    let nonImageCount = 0;
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
        non_image_count: nonImageCount,
      });
    };

    await walkFilesRecursive({
      root: sourceResolved,
      shouldSkipDir,
      isStopRequested,
      onFile: async fullPath => {
        if (isStopRequested()) return;
        const rel = path.relative(sourceResolved, fullPath);
        if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) return;

        const isImage = isImageFileByExt(fullPath);
        if (!isImage) {
          nonImageCount += 1;
          if (nonImagePolicy === tableMediaToolImgBatchCompress.NON_IMAGE_COPY) {
            const copyDest = path.join(targetRootResolved, rel);
            try {
              const inputSize = await getFileSize(fullPath);
              const copyRes = await copyFileAtomic({ sourcePath: fullPath, destPath: copyDest });
              if (copyRes && copyRes.ok) {
                processedCount += 1;
                handledInputBytes += inputSize;
                handledOutputBytes += inputSize;
              } else {
                skippedCount += 1;
              }
            } catch (ee) {
              skippedCount += 1;
            } finally {
              doneFiles += 1;
              await flush(false);
            }
            return;
          }

          skippedCount += 1;
          doneFiles += 1;
          await flush(false);
          return;
        }

        const outputPath = buildOutputPath({ targetRoot: targetRootResolved, relativePath: rel, outFormat });
        let updated = false;

        try {
          const res = await compressImageAtomic({
            inputPath: fullPath,
            outputPath,
            outputFormat: outFormat,
            quality,
            outSize,
            withMeta: false,
            fallbackCopyIfLargerSameFormat: true,
          });
          if (res && res.ok) {
            processedCount += 1;
            handledInputBytes += Number(res.inputSize || 0) || 0;
            handledOutputBytes += Number(res.outputSize || 0) || 0;
            updated = true;
          } else if (res && res.skipped) {
            skippedCount += 1;
            updated = true;
          } else {
            skippedCount += 1;
            updated = true;
          }
        } catch (e) {
          nonImageCount += 1;
          if (nonImagePolicy === tableMediaToolImgBatchCompress.NON_IMAGE_COPY) {
            const copyDest = path.join(targetRootResolved, rel);
            try {
              const inputSize = await getFileSize(fullPath);
              const copyRes = await copyFileAtomic({ sourcePath: fullPath, destPath: copyDest });
              if (copyRes && copyRes.ok) {
                processedCount += 1;
                handledInputBytes += inputSize;
                handledOutputBytes += inputSize;
                updated = true;
              } else if (copyRes && copyRes.skipped) {
                skippedCount += 1;
                updated = true;
              } else {
                skippedCount += 1;
                updated = true;
              }
            } catch (ee) {
              skippedCount += 1;
              updated = true;
            }
          } else {
            skippedCount += 1;
            updated = true;
          }
        } finally {
          if (updated) {
            doneFiles += 1;
            await flush(false);
          }
        }
      },
    });

    await flush(true);

    if (this.stopRequested) {
      await this._updateTask({
        status: tableMediaToolImgBatchCompress.STATUS_STOPPED,
        last_error: null,
        progress: '',
        last_end_time: new Date(),
      });
      return;
    }

    await this._updateTask({
      status: tableMediaToolImgBatchCompress.STATUS_STOPPED,
      last_error: null,
      progress: '',
      last_end_time: new Date(),
    });
  }

  _bindProcessEvents() {
    process.on('message', message => {
      if (!message || !message.type) return;
      if (message.type === 'start') {
        const requestId = message?.data?.requestId;
        const taskId = message?.data?.taskId;
        this.start({ requestId, taskId }).catch(err => {
          this._reply('imgBatchCompressStartResponse', {
            requestId,
            ok: false,
            error: err && err.message ? String(err.message) : String(err),
          });
        });
      } else if (message.type === 'stop') {
        const requestId = message?.data?.requestId;
        this.stop({ requestId }).catch(err => {
          this._reply('imgBatchCompressStopResponse', {
            requestId,
            ok: false,
            error: err && err.message ? String(err.message) : String(err),
          });
        });
      }
    });
  }
}

new ImgBatchCompressWorker();
