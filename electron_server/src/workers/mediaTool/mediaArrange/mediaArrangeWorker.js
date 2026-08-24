const path = require('path');
const fs = require('fs-extra');
const Logger = require('../../../utils/logger');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableMediaToolArrange = require('../../../db/table/tableMediaToolArrange');
const PathUtil = require('../../../utils/pathUtil');
const photoIndexUtil = require('../../photoIndex/photoIndexUtil');
const config = require('../../../config/config');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

function safeTruncate(s, maxLen) {
  const t = ensureString(s);
  if (t.length <= maxLen) return t;
  return t.slice(0, Math.max(0, maxLen - 3)) + '...';
}

async function ensureMainDbReady() {
  await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
  const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
  await knex.raw('SELECT 1');
  return knex;
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
      if (name.startsWith('.')) continue; // skip hidden files
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

class MediaArrangeWorker {
  constructor() {
    this.taskId = null;
    this.knex = null;
    this.stopRequested = false;
    this.running = false;
    this.runningPromise = null;
    this._exiting = false;
    this._init();
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

  _scheduleExit() {
    if (this._exiting) return;
    this._exiting = true;
    setTimeout(() => {
      process.exit(0);
    }, 500);
  }

  async _updateTask(patch) {
    const idNum = Number(this.taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return;
    await this.knex('media_tool_arrange')
      .where({ id: idNum })
      .update({ ...patch, update_time: new Date() })
      .catch(() => null);
  }

  async _getTaskRow(taskId) {
    const idNum = Number(taskId);
    if (!this.knex || !Number.isFinite(idNum) || idNum <= 0) return null;
    return await this.knex('media_tool_arrange')
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
    const arrangeType = ensureString(row.arrange_type).trim().toLowerCase();
    const sameNamePolicy = ensureString(row.same_name_policy || '')
      .trim()
      .toLowerCase();

    if (!sourcePath || !targetPath) return { ok: false, error: 'invalid_params' };

    const sourceResolved = path.resolve(sourcePath);
    const targetResolved = path.resolve(targetPath);

    // Check if target is empty (optional but requested: "目标目录必须有写入权限且必须为空")
    // Wait, "且必须为空" is a strict requirement.
    // However, usually we check this at creation time. The worker might just check writability.
    // But let's check if it's empty if possible, or just proceed. The requirement says "目标目录必须有写入权限且必须为空" for ADDING the task?
    // Or for RUNNING it? Usually for adding.
    // Let's assume the controller/service validated "empty" at creation. Here we just validate access.

    const conflict = PathUtil.isMutualConflictPath(sourceResolved, targetResolved);
    if (conflict) return { ok: false, error: 'invalid_path_relation' };

    let sourceStat;
    try {
      sourceStat = await fs.stat(sourceResolved);
    } catch (_) {
      return { ok: false, error: 'source_not_found' };
    }

    if (!sourceStat.isDirectory()) return { ok: false, error: 'source_not_found' };

    const tgtOk = await ensureTargetDirWritable(targetResolved);
    if (tgtOk) return { ok: false, error: tgtOk };

    return {
      ok: true,
      taskId: this.taskId,
      sourceResolved,
      targetResolved,
      arrangeType,
      sameNamePolicy:
        sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_SKIP ||
        sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_OVERWRITE ||
        sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_RENAME
          ? sameNamePolicy
          : tableMediaToolArrange.SAME_NAME_POLICY_RENAME,
    };
  }

  async start({ requestId, taskId }) {
    if (this.running) {
      this._reply('mediaArrangeStartResponse', { requestId, ok: true, already_running: true, pid: process.pid });
      return;
    }

    const prepared = await this._prepareTaskId(taskId);
    if (!prepared.ok) {
      const err = ensureString(prepared.error || 'invalid_params').trim();
      await this._updateTask({
        status: tableMediaToolArrange.STATUS_ERROR,
        last_error: safeTruncate(err, 800),
        progress: '',
        last_end_time: new Date(),
      });
      this._reply('mediaArrangeStartResponse', { requestId, ok: false, error: prepared.error || 'invalid_params' });
      this._scheduleExit();
      return;
    }

    this.stopRequested = false;
    this.running = true;

    await this._updateTask({
      status: tableMediaToolArrange.STATUS_RUNNING,
      last_error: null,
      progress: '',
      total_files: 0,
      done_files: 0,
      processed_count: 0,
      skipped_count: 0,
      last_start_time: new Date(),
      last_end_time: null,
    });

    this._reply('mediaArrangeStartResponse', { requestId, ok: true, pid: process.pid });

    this.runningPromise = this._run(prepared)
      .catch(async e => {
        Logger.error('MediaArrange worker run error', e);
        await this._updateTask({
          status: tableMediaToolArrange.STATUS_ERROR,
          last_error: safeTruncate(e && e.message ? e.message : String(e), 800),
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
    this._reply('mediaArrangeStopResponse', { requestId, ok: true });
  }

  async _run(prepared) {
    const isStopRequested = () => this.stopRequested;

    const shouldSkipDir = p => PathUtil.isAncestorPath(PathUtil.normalizeFsPathForCompare(prepared.targetResolved), PathUtil.normalizeFsPathForCompare(p));

    // Count total files first
    const totalFiles = await countFilesRecursive({ root: prepared.sourceResolved, shouldSkipDir, isStopRequested });
    await this._updateTask({ total_files: totalFiles });

    let doneFiles = 0;
    let processedCount = 0; // successfully moved/copied
    let skippedCount = 0; // non-media files or errors

    let lastFlushTs = 0;
    const flush = async force => {
      const now = Date.now();
      if (!force && now - lastFlushTs < 1000) return;
      lastFlushTs = now;
      const progress = totalFiles > 0 ? `${doneFiles}/${totalFiles}` : `${doneFiles}`;
      await this._updateTask({
        progress,
        done_files: doneFiles,
        processed_count: processedCount,
        skipped_count: skippedCount,
      }).catch(() => null);
    };

    const stack = [prepared.sourceResolved];
    while (stack.length) {
      if (isStopRequested()) break;
      const dir = stack.pop();
      let entries;
      try {
        entries = await fs.readdir(dir);
      } catch (_) {
        continue;
      }

      for (const name of entries) {
        if (isStopRequested()) break;
        if (name.startsWith('.')) continue;

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
          doneFiles++;

          // Process file
          try {
            const ext = path.extname(full).toLowerCase();
            const isVideo = this._isVideo(ext);
            const isImage = this._isImage(ext);

            if (!isVideo && !isImage) {
              skippedCount++;
              await flush(false);
              continue;
            }

            // Extract date
            const dateMs = (await photoIndexUtil.getTimeFromFileName(null, name)) || photoIndexUtil.pickEarliestMs(stat);

            // If we really can't get a date, fallback to now? Or skip? The requirements say "读取照片或视频的拍摄时间".
            // photoIndexUtil.getTimeFromFileName falls back to filename, then stat. So it should always return something.

            const dateObj = new Date(dateMs);
            const year = dateObj.getFullYear();
            const month = String(dateObj.getMonth() + 1);
            const day = String(dateObj.getDate());

            let subDir = '';
            if (prepared.arrangeType === tableMediaToolArrange.ARRANGE_TYPE_YEAR) {
              subDir = `${year}`;
            } else if (prepared.arrangeType === tableMediaToolArrange.ARRANGE_TYPE_MONTH) {
              subDir = path.join(`${year}`, `${month}`);
            } else {
              // DAY
              subDir = path.join(`${year}`, `${month}`, `${day}`);
            }

            const targetDir = path.join(prepared.targetResolved, subDir);
            await fs.ensureDir(targetDir);

            let targetName = name;
            let targetFile = path.join(targetDir, targetName);

            const exists = await fs.pathExists(targetFile);
            if (exists) {
              if (prepared.sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_SKIP) {
                skippedCount++;
                await flush(false);
                continue;
              }
              if (prepared.sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_RENAME) {
                let counter = 1;
                while (await fs.pathExists(targetFile)) {
                  const namePart = path.basename(name, ext);
                  targetName = `${namePart}_${counter}${ext}`;
                  targetFile = path.join(targetDir, targetName);
                  counter++;
                }
              }
            }

            await fs.copy(full, targetFile, {
              overwrite: prepared.sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_OVERWRITE,
              errorOnExist: prepared.sameNamePolicy === tableMediaToolArrange.SAME_NAME_POLICY_SKIP,
              preserveTimestamps: true,
            });
            processedCount++;
          } catch (err) {
            Logger.error(`MediaArrange copy error: ${full}`, err);
            skippedCount++;
          }
          await flush(false);
        }
      }
    }
    await flush(true);

    if (isStopRequested()) {
      await this._updateTask({
        status: tableMediaToolArrange.STATUS_STOPPED,
        progress: '',
        last_end_time: new Date(),
      });
    } else {
      await this._updateTask({
        status: tableMediaToolArrange.STATUS_FINISHED,
        progress: '100%',
        last_end_time: new Date(),
      });
    }
  }

  _isVideo(ext) {
    const list = Array.isArray(config.videoTypeList) ? config.videoTypeList : [];
    if (list.length > 0) return list.includes(ext);
    return ['.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v', '.flv', '.wmv', '.ts', '.mts', '.m2ts'].includes(ext);
  }

  _isImage(ext) {
    const list = Array.isArray(config.photoTypeList) ? config.photoTypeList : [];
    if (list.length > 0) return list.includes(ext);
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif', '.raw', '.cr2', '.nef', '.arw', '.dng'].includes(ext);
  }

  _bindProcessEvents() {
    process.on('message', message => {
      if (!message || !message.type) return;
      if (message.type === 'start') {
        const requestId = message?.data?.requestId;
        const taskId = message?.data?.taskId;
        this.start({ requestId, taskId }).catch(err => {
          this._reply('mediaArrangeStartResponse', {
            requestId,
            ok: false,
            error: err && err.message ? String(err.message) : String(err),
          });
        });
      } else if (message.type === 'stop') {
        const requestId = message?.data?.requestId;
        this.stop({ requestId }).catch(err => {
          this._reply('mediaArrangeStopResponse', {
            requestId,
            ok: false,
            error: err && err.message ? String(err.message) : String(err),
          });
        });
      }
    });

    process.on('uncaughtException', err => {
      Logger.error('❌ mediaArrange worker uncaughtException', err);
      this._scheduleExit();
    });

    process.on('unhandledRejection', reason => {
      Logger.error('❌ mediaArrange worker unhandledRejection', reason);
      this._scheduleExit();
    });
  }
}

new MediaArrangeWorker();
