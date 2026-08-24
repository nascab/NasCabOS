'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { fork } = require('child_process');
const Logger = require('../../utils/logger');
const FileUtil = require('../../utils/fileUtil');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const config = require('../../config/config');
const bookTinyUtil = require('./bookTinyUtil');
const { getFirstLetter } = require('../../utils/firstLetterUtil');

class BookIndexWorker {
  constructor() {
    this.init();
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.BOOK_DB);

      await this.runUntilEmpty();
      process.exit(0);
    } catch (err) {
      Logger.error('❌ book index worker init failed:', err);
      process.exit(1);
    }
  }

  async runUntilEmpty() {
    while (true) {
      const task = await this.getNextTask();
      if (!task) {
        Logger.info('✅ No pending book scan tasks, worker exiting');
        if (process.send) {
          try {
            process.send({ type: 'bookIndexingFinished' });
          } catch (_) {}
        }
        return;
      }
      try {
        await this.runTask(task);
      } catch (err) {
        Logger.error('❌ Book index task failed:', err && err.message ? err.message : err);
        await this.deleteTask(task);
      }
    }
  }

  async getNextTask() {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const tasks = await knex('book_scan_task').orderBy('create_time', 'asc').limit(1);
    if (!tasks || tasks.length === 0) return null;
    return tasks[0];
  }

  async deleteTask(task) {
    if (!task || !task.id) return;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    await knex('book_scan_task')
      .where({ id: task.id })
      .delete()
      .catch(() => {});
  }

  async getMatchedSourceByScanPath(scanPath) {
    const resolved = scanPath ? path.resolve(String(scanPath)) : '';
    if (!resolved) return null;
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const sources = await knex('book_source')
      .select('id', 'path', 'show_type')
      .orderBy('id', 'asc')
      .catch(() => []);
    let best = null;
    for (const s of sources || []) {
      const root = s && s.path ? path.resolve(String(s.path)) : '';
      if (!root) continue;
      const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
      const ok = resolved === root || resolved.startsWith(prefix);
      if (!ok) continue;
      if (!best) {
        best = s;
        continue;
      }
      const bestRoot = best && best.path ? path.resolve(String(best.path)) : '';
      if (bestRoot && root.length > bestRoot.length) best = s;
    }
    return best;
  }

  async deleteMissingIndexes({ knex, scanPath }) {
    const root = scanPath ? path.resolve(String(scanPath)) : '';
    if (!root) return;

    const deleteSubtreeByPathPrefix = async targetDir => {
      if (!targetDir) return;
      const prefix = targetDir.endsWith(path.sep) ? targetDir : `${targetDir}${path.sep}`;
      await knex('book_index')
        .where(qb => {
          qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
        })
        .delete()
        .catch(() => {});
    };

    try {
      fs.statSync(root);
    } catch (_) {
      await deleteSubtreeByPathPrefix(root);
      return;
    }

    let fileDeleteIds = [];

    const flushFileDeletes = async () => {
      if (fileDeleteIds.length === 0) return;
      const ids = fileDeleteIds;
      fileDeleteIds = [];
      await knex('book_index')
        .whereIn('id', ids)
        .delete()
        .catch(() => {});
    };

    const rootPrefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
    let lastId = 0;
    while (true) {
      const pageSize = 5000;
      const rows = await knex('book_index')
        .select('id', 'path', 'filename', 'is_file')
        .andWhere(qb => {
          qb.where('path', root).orWhere('path', 'like', `${rootPrefix}%`);
        })
        .andWhere('id', '>', lastId)
        .orderBy('id', 'asc')
        .limit(pageSize)
        .catch(() => []);

      if (!rows || rows.length === 0) break;

      for (const r of rows) {
        const id = r && r.id ? Number(r.id) : 0;
        if (id > lastId) lastId = id;

        const parent = r && r.path ? String(r.path) : '';
        const name = r && r.filename ? String(r.filename) : '';
        if (!parent || !name) {
          if (id) fileDeleteIds.push(id);
          if (fileDeleteIds.length >= 1000) await flushFileDeletes();
          continue;
        }
        const targetPath = path.join(parent, name);
        try {
          fs.statSync(targetPath);
        } catch (err) {
          if (err && err.code && err.code !== 'ENOENT') continue;
          const isFile = Number(r.is_file) === 1;
          if (isFile) {
            if (id) fileDeleteIds.push(id);
            if (fileDeleteIds.length >= 1000) await flushFileDeletes();
          } else {
            if (id) {
              await knex('book_index')
                .where({ id })
                .delete()
                .catch(() => {});
            }
            await deleteSubtreeByPathPrefix(targetPath);
          }
        }
      }

      if (rows.length < pageSize) break;
      if (fileDeleteIds.length >= 1000) await flushFileDeletes();
    }

    await flushFileDeletes();
  }

  async deleteIndexesByPathPrefix({ knex, targetPath }) {
    const targetDir = targetPath ? path.resolve(String(targetPath)) : '';
    if (!targetDir) return 0;
    const prefix = targetDir.endsWith(path.sep) ? targetDir : `${targetDir}${path.sep}`;
    const affected = await knex('book_index')
      .where(qb => {
        qb.where('path', targetDir).orWhere('path', 'like', `${prefix}%`);
      })
      .delete()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  async deleteIndexByFullPath({ knex, fullPath }) {
    const p = fullPath ? path.resolve(String(fullPath)) : '';
    if (!p) return 0;
    const dir = path.dirname(p);
    const name = path.basename(p);
    if (!dir || !name) return 0;
    const affected = await knex('book_index')
      .where({ path: dir, filename: name })
      .delete()
      .catch(() => 0);
    return Number(affected || 0) || 0;
  }

  isBookFileExt(ext) {
    const e = String(ext || '').toLowerCase();
    if (!e) return false;
    return Array.isArray(config.bookTypeList) && config.bookTypeList.includes(e);
  }

  shouldExtractMetadata(ext) {
    const e = String(ext || '').toLowerCase();
    return e === '.epub' || e === '.mobi' || e === '.azw3' || e === '.azw' || e === '.cbz' || e === '.cbr' || e === '.rar' || e === '.zip';
  }

  getIndexTypeByExt(ext) {
    const e = String(ext || '').toLowerCase();
    if (e === '.cbz' || e === '.cbr' || e === '.rar' || e === '.zip') return 'comic';
    return 'book';
  }

  computeFileHash(fullPath, stat) {
    const resolvedPath = path.resolve(fullPath);
    const hashStr = path.basename(resolvedPath) + (stat && stat.size ? stat.size : 0) + (stat && stat.mtimeMs ? stat.mtimeMs : 0);
    return crypto.createHash('sha256').update(hashStr).digest('hex');
  }

  async upsertIndex(knex, row) {
    if (!row || !row.path || !row.filename) return 0;
    await knex('book_index').insert(row).onConflict(['path', 'filename']).merge(row);
    const existed = await knex('book_index')
      .where({ path: row.path, filename: row.filename })
      .first('id')
      .catch(() => null);
    return existed && existed.id ? Number(existed.id || 0) || 0 : 0;
  }

  async upsertFolderIndex(knex, dirPath, options = {}) {
    const fullDir = dirPath ? path.resolve(String(dirPath)) : '';
    if (!fullDir) return 0;
    const parentDir = path.dirname(fullDir);
    const folderName = path.basename(fullDir);
    if (!parentDir || !folderName) return 0;
    let st = null;
    try {
      st = await fs.promises.stat(fullDir);
    } catch (_) {}

    const providedCount = options.bookCount === undefined || options.bookCount === null ? null : Number(options.bookCount || 0) || 0;
    const countRow =
      providedCount !== null
        ? null
        : await knex('book_index')
            .count({ cnt: 'id' })
            .where({ show_type: 'subbook', is_file: 1, path: fullDir })
            .first()
            .catch(() => null);
    const bookCount = providedCount !== null ? Math.max(0, providedCount) : Math.max(0, Number((countRow && (countRow.cnt ?? countRow['count(`id`)'] ?? countRow['count(*)'])) || 0) || 0);

    if (!bookCount) {
      await knex('book_index')
        .where({ path: parentDir, filename: folderName, is_file: 0, show_type: 'series' })
        .delete()
        .catch(() => {});
      return 0;
    }

    let seriesType = options.type ? String(options.type) : '';
    if (!seriesType) {
      const typeRows = await knex('book_index')
        .select('type')
        .where({ show_type: 'subbook', is_file: 1, path: fullDir })
        .groupBy('type')
        .catch(() => []);
      const typeSet = new Set((typeRows || []).map(r => (r && r.type ? String(r.type) : '')).filter(Boolean));
      seriesType = typeSet.has('book') ? 'book' : typeSet.has('comic') ? 'comic' : '';
    }

    const base = {
      path: parentDir,
      is_file: 0,
      file_hash: '',
      ctime: st ? new Date(st.ctimeMs) : null,
      mtime: st ? new Date(st.mtimeMs) : null,
      birthtime: st ? new Date(st.birthtimeMs) : null,
      filename: folderName,
      filename_fl: getFirstLetter(folderName),
      ext: '',
      size: 0,
      type: seriesType,
      cover_path: '',
      cover_state: 0,
      metadata_state: 0,
      language: '',
      title: '',
      title_fl: '',
      artist: '',
      artist_fl: '',
      year: '',
      genre: '',
      isbn: '',
      tag: '',
      publish_date: '',
      publisher: '',
      introduction: '',
      remark: '',
      total_page: 0,
      book_count: bookCount,
      show_type: 'series',
    };
    return await this.upsertIndex(knex, base);
  }

  extractMetadataWithTimeout(filePath, timeoutMs = 30000) {
    const workerPath = path.resolve(__dirname, 'bookMetaExtractWorker.js');
    const foliateRoot = config.getFoliateRootPath();
    return new Promise(resolve => {
      let done = false;
      const child = fork(workerPath, [], {
        env: {
          ...process.env,
          WORKER_TYPE: 'bookMetaExtract',
          PATH_DATABASE: process.env.PATH_DATABASE,
          PATH_CACHE: process.env.PATH_CACHE,
          userDataFolder: process.env['userDataFolder'] || (typeof config.getUserDataPath === 'function' ? config.getUserDataPath() : ''),
        },
        windowsHide: true,
      });

      const timer = setTimeout(
        () => {
          if (done) return;
          done = true;
          try {
            child.kill('SIGKILL');
          } catch (_) {}
          resolve({ ok: false, error: 'timeout' });
        },
        Math.max(1000, Number(timeoutMs || 0) || 0)
      );

      const finish = res => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(res || { ok: false, error: 'no_result' });
        try {
          child.kill();
        } catch (_) {}
      };

      child.on('message', msg => {
        if (!msg || msg.type !== 'result') return;
        finish(msg.data);
      });
      child.on('exit', () => {
        if (done) return;
        finish({ ok: false, error: 'exit_without_result' });
      });
      child.on('error', () => {
        finish({ ok: false, error: 'worker_error' });
      });

      try {
        child.send({ type: 'extract', data: { filePath, foliateRoot } });
      } catch (_) {
        finish({ ok: false, error: 'send_failed' });
      }
    });
  }

  async walkBookFiles(rootPath, onFile) {
    const cachePath = typeof config.getCachePath === 'function' ? config.getCachePath() : '';
    const cachePrefix = cachePath && cachePath.endsWith(path.sep) ? cachePath : cachePath ? `${cachePath}${path.sep}` : '';

    const resolvedRoot = rootPath ? path.resolve(rootPath) : '';
    if (cachePath && (resolvedRoot === cachePath || resolvedRoot.startsWith(cachePrefix))) {
      return true;
    }

    const stack = [rootPath];
    while (stack.length > 0) {
      const current = stack.pop();
      const resolvedCurrent = current ? path.resolve(current) : '';
      if (cachePath && (resolvedCurrent === cachePath || resolvedCurrent.startsWith(cachePrefix))) continue;

      let entries;
      try {
        entries = await fs.promises.readdir(current, { withFileTypes: true });
      } catch (_) {
        continue;
      }

      for (const ent of entries) {
        const name = ent.name;
        if (FileUtil.isSystemFile(name)) continue;
        const fullPath = path.join(current, name);
        const resolvedFull = path.resolve(fullPath);
        if (cachePath && (resolvedFull === cachePath || resolvedFull.startsWith(cachePrefix))) continue;

        if (ent.isDirectory()) {
          stack.push(fullPath);
          continue;
        }
        if (!ent.isFile()) continue;
        if (FileUtil.isHideFile(name)) continue;
        if (FileUtil.isTemporaryOrDownloadingFile(name)) continue;

        const ext = path.extname(name).toLowerCase();
        if (!this.isBookFileExt(ext)) continue;
        const res = await onFile({ fullPath, dirPath: current, filename: name, ext });
        if (res === false) return false;
      }
    }
    return true;
  }

  async runTask(task) {
    const scanPath = task && task.scan_path ? String(task.scan_path) : '';
    if (!scanPath) {
      await this.deleteTask(task);
      return;
    }

    const start = Date.now();
    Logger.info('Book library: start scan', scanPath);

    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.BOOK_DB);
    const source = await this.getMatchedSourceByScanPath(scanPath);
    if (!source) {
      Logger.info('Book library: source missing, cancel scan', scanPath);
      await this.deleteTask(task);
      return;
    }

    const sourceId = Number(source.id || 0) || 0;
    const showTypeRaw = source && source.show_type ? String(source.show_type).trim().toLowerCase() : 'book';
    const isSeriesMode = showTypeRaw === 'series';
    await knex('book_source')
      .where({ id: sourceId })
      .update({ last_scan_time: Date.now() })
      .catch(() => {});

    let indexed = 0;
    let metaOk = 0;
    let metaFail = 0;
    const scanResolved = path.resolve(String(scanPath));

    const indexOneFile = async ({ fullPath, dirPath, filename, ext, showType }) => {
      let st;
      try {
        st = await fs.promises.stat(fullPath);
      } catch (_) {
        return { ok: false, type: '' };
      }
      if (!st || !st.isFile()) return { ok: false, type: '' };

      const fileHash = this.computeFileHash(fullPath, st);
      const tinyCachePath = typeof config.getTinyCachePath === 'function' ? config.getTinyCachePath() : '';
      const tinyTargetPath = tinyCachePath && fileHash ? path.join(tinyCachePath, fileHash) + '.webp' : '';
      let hasTiny = false;
      if (tinyTargetPath) {
        try {
          const tinyStat = await fs.promises.stat(tinyTargetPath);
          hasTiny = !!(tinyStat && tinyStat.isFile() && tinyStat.size > 0);
        } catch (_) {}
      }

      const existed = await knex('book_index')
        .where({ path: dirPath, filename, is_file: 1 })
        .first('id', 'size', 'mtime', 'metadata_state', 'cover_state')
        .catch(() => null);

      const sameSize = existed && existed.size !== undefined ? Number(existed.size || 0) === Number(st.size || 0) : false;
      const oldMtimeMs = existed && existed.mtime ? new Date(existed.mtime).getTime() : 0;
      const sameMtime = oldMtimeMs ? Math.abs(oldMtimeMs - Number(st.mtimeMs || 0)) < 5 : false;
      const changed = !(sameSize && sameMtime);

      const base = {
        path: dirPath,
        is_file: 1,
        file_hash: fileHash,
        ctime: new Date(st.ctimeMs),
        mtime: new Date(st.mtimeMs),
        birthtime: new Date(st.birthtimeMs),
        filename,
        filename_fl: getFirstLetter(filename),
        ext,
        size: Number(st.size || 0) || 0,
        type: this.getIndexTypeByExt(ext),
        show_type: showType,
        book_count: 0,
      };

      if (!existed || !existed.id || changed) {
        Object.assign(base, {
          cover_path: '',
          cover_state: 0,
          metadata_state: 0,
          language: '',
          title: '',
          title_fl: '',
          artist: '',
          artist_fl: '',
          year: '',
          genre: '',
          isbn: '',
          tag: '',
          publish_date: '',
          publisher: '',
          introduction: '',
          remark: '',
          total_page: 0,
          book_count: 0,
        });
      }

      const indexId = await this.upsertIndex(knex, base);
      if (!indexId) return { ok: false, type: base.type };
      indexed += 1;

      if (ext === '.txt') {
        const title = path.parse(filename).name || filename;
        await knex('book_index')
          .where({ id: indexId })
          .update({
            title,
            title_fl: getFirstLetter(title),
            metadata_state: 1,
            cover_state: 2,
            total_page: 0,
            book_count: 0,
          })
          .catch(() => {});
        metaOk += 1;
        return { ok: true, type: base.type };
      }

      const currentState = existed && existed.metadata_state !== undefined ? Number(existed.metadata_state || 0) : 0;
      const currentCoverState = existed && existed.cover_state !== undefined ? Number(existed.cover_state || 0) : 0;
      if (!changed && currentState === 1 && hasTiny) {
        if (currentCoverState !== 1) {
          await knex('book_index')
            .where({ id: indexId })
            .update({ cover_state: 1 })
            .catch(() => {});
        }
        return { ok: true, type: base.type };
      }

      if (!changed && currentState === 1 && !hasTiny && fileHash && currentCoverState !== 1) {
        const ok = await bookTinyUtil
          .ensureBookTiny({
            filePath: fullPath,
            fileHash,
            coverBuffer: null,
            size: 500,
            timeoutMs: 30000,
          })
          .catch(() => false);
        await knex('book_index')
          .where({ id: indexId })
          .update({ cover_state: ok ? 1 : 2 })
          .catch(() => {});
        return { ok: true, type: base.type };
      }

      if (!this.shouldExtractMetadata(ext)) {
        await knex('book_index')
          .where({ id: indexId })
          .update({ metadata_state: 2, cover_state: 2 })
          .catch(() => {});
        metaFail += 1;
        return { ok: true, type: base.type };
      }

      const res = await this.extractMetadataWithTimeout(fullPath, 30000);
      if (!res || !res.ok || !res.data) {
        let coverOk = false;
        if (!hasTiny && fileHash) {
          coverOk = await bookTinyUtil
            .ensureBookTiny({
              filePath: fullPath,
              fileHash,
              coverBuffer: null,
              size: 500,
              timeoutMs: 30000,
            })
            .catch(() => false);
        }
        await knex('book_index')
          .where({ id: indexId })
          .update({ metadata_state: 2, cover_state: coverOk || hasTiny ? 1 : 2 })
          .catch(() => {});
        metaFail += 1;
        return { ok: true, type: base.type };
      }

      const m = res.data;
      const fallbackTitle = path.parse(filename).name || filename;
      const titleRaw = m.title ? String(m.title) : '';
      const title = titleRaw.trim() || fallbackTitle;
      const author = m.author ? String(m.author) : '';
      const publisher = m.publisher ? String(m.publisher) : '';
      const language = m.language ? String(m.language) : '';
      const publishDate = m.publishDate ? String(m.publishDate) : '';
      const year = m.year ? String(m.year) : '';
      const genre = m.genre ? String(m.genre) : '';
      const tag = m.tag ? String(m.tag) : '';
      const isbn = m.isbn ? String(m.isbn) : '';
      const introduction = m.description ? String(m.description) : '';
      const coverBuffer = m.coverBuffer;
      const totalPageRaw = m.totalPage ?? m.total_page;
      const totalPage = Math.max(0, Number(totalPageRaw || 0) || 0);

      await knex('book_index')
        .where({ id: indexId })
        .update({
          title,
          title_fl: getFirstLetter(title || fallbackTitle),
          artist: author,
          artist_fl: getFirstLetter(author),
          publisher,
          language,
          publish_date: publishDate,
          year,
          genre,
          tag,
          isbn,
          introduction,
          metadata_state: 1,
          total_page: totalPage,
          book_count: 0,
        })
        .catch(() => {});

      if (!hasTiny && fileHash) {
        const ok = await bookTinyUtil
          .ensureBookTiny({
            filePath: fullPath,
            fileHash,
            coverBuffer,
            size: 500,
            timeoutMs: 30000,
          })
          .catch(() => false);
        await knex('book_index')
          .where({ id: indexId })
          .update({ cover_state: ok ? 1 : 2 })
          .catch(() => {});
      } else if (hasTiny) {
        await knex('book_index')
          .where({ id: indexId })
          .update({ cover_state: 1 })
          .catch(() => {});
      }
      metaOk += 1;
      return { ok: true, type: base.type };
    };

    let stat = null;
    try {
      stat = await fs.promises.stat(scanResolved);
    } catch (_) {}

    if (!stat) {
      await Promise.all([this.deleteIndexByFullPath({ knex, fullPath: scanResolved }), this.deleteIndexesByPathPrefix({ knex, targetPath: scanResolved })]).catch(() => {});

      if (isSeriesMode) {
        const parentDir = path.dirname(scanResolved);
        const baseName = path.basename(scanResolved);
        if (parentDir && baseName) {
          await knex('book_index')
            .where({ path: parentDir, filename: baseName, is_file: 0, show_type: 'series' })
            .delete()
            .catch(() => {});
          await this.upsertFolderIndex(knex, parentDir).catch(() => 0);
        }
      }

      const cost = Date.now() - start;
      Logger.info(`Book library: scan done ${scanPath}, indexed=${indexed}, meta_ok=${metaOk}, meta_fail=${metaFail}, cost=${cost}ms`);
      await this.deleteTask(task);
      return;
    }

    const isDir = stat.isDirectory();
    const isFile = stat.isFile();
    if (!isDir && !isFile) {
      Logger.info('Scan path is neither file nor directory', scanPath);
      await this.deleteTask(task);
      return;
    }

    if (isFile) {
      const ext = path.extname(scanResolved).toLowerCase();
      if (!this.isBookFileExt(ext)) {
        await this.deleteIndexByFullPath({ knex, fullPath: scanResolved });
      } else {
        const dirPath = path.dirname(scanResolved);
        const filename = path.basename(scanResolved);
        const showType = isSeriesMode ? 'subbook' : 'book';
        await indexOneFile({ fullPath: scanResolved, dirPath, filename, ext, showType });
        if (isSeriesMode) {
          await this.upsertFolderIndex(knex, dirPath).catch(() => 0);
        }
      }

      const cost = Date.now() - start;
      Logger.info(`Book library: scan done ${scanPath}, indexed=${indexed}, meta_ok=${metaOk}, meta_fail=${metaFail}, cost=${cost}ms`);
      await this.deleteTask(task);
      return;
    }

    await this.deleteMissingIndexes({ knex, scanResolved });

    const cachePath = typeof config.getCachePath === 'function' ? config.getCachePath() : '';
    const cachePrefix = cachePath && cachePath.endsWith(path.sep) ? cachePath : cachePath ? `${cachePath}${path.sep}` : '';
    const isUnderCache = p => {
      const resolved = p ? path.resolve(String(p)) : '';
      if (!resolved || !cachePath) return false;
      return resolved === cachePath || (cachePrefix && resolved.startsWith(cachePrefix));
    };

    const keepDirSet = new Set();
    const stack = [scanResolved];
    while (stack.length > 0) {
      const rawDir = stack.pop();
      const dir = rawDir ? path.resolve(String(rawDir)) : '';
      if (!dir) continue;
      if (isUnderCache(dir)) continue;

      let entries = [];
      try {
        entries = await fs.promises.readdir(dir, { withFileTypes: true });
      } catch (_) {
        continue;
      }

      let directCount = 0;
      let directType = '';
      const subDirs = [];

      for (let i = entries.length - 1; i >= 0; i -= 1) {
        const ent = entries[i];
        const name = ent && ent.name ? String(ent.name) : '';
        if (!name) continue;
        if (FileUtil.isSystemFile(name)) continue;
        if (FileUtil.isHideFile(name)) continue;
        if (FileUtil.isTemporaryOrDownloadingFile(name)) continue;

        const fullPath = path.join(dir, name);
        if (isUnderCache(fullPath)) continue;

        if (ent.isDirectory()) {
          subDirs.push(fullPath);
          continue;
        }
        if (!ent.isFile()) continue;

        const ext = path.extname(name).toLowerCase();
        if (!this.isBookFileExt(ext)) continue;

        const showType = isSeriesMode ? 'subbook' : 'book';
        const res = await indexOneFile({ fullPath, dirPath: dir, filename: name, ext, showType });
        if (res && res.ok) {
          directCount += 1;
          if (!directType || directType === 'comic') {
            const t = res.type ? String(res.type) : '';
            if (t) directType = t;
          }
        }
      }

      if (isSeriesMode) {
        if (directCount > 0) keepDirSet.add(dir);
        await this.upsertFolderIndex(knex, dir, { bookCount: directCount, type: directType }).catch(() => 0);
      }

      for (let i = subDirs.length - 1; i >= 0; i -= 1) {
        const d = subDirs[i];
        if (d) stack.push(d);
      }
    }

    if (isSeriesMode) {
      const scanPrefix = scanResolved.endsWith(path.sep) ? scanResolved : `${scanResolved}${path.sep}`;
      try {
        const scanParent = path.dirname(scanResolved);
        const scanBase = path.basename(scanResolved);
        const folderRows = await knex('book_index')
          .select('id', 'path', 'filename')
          .where({ is_file: 0, show_type: 'series' })
          .andWhere(qb => {
            qb.where('path', scanResolved).orWhere('path', 'like', `${scanPrefix}%`);
            if (scanParent && scanBase) qb.orWhere({ path: scanParent, filename: scanBase });
          })
          .catch(() => []);
        for (const r of folderRows || []) {
          const id = r && r.id ? Number(r.id) : 0;
          const parent = r && r.path ? String(r.path) : '';
          const name = r && r.filename ? String(r.filename) : '';
          if (!id || !parent || !name) continue;
          const full = path.resolve(path.join(parent, name));
          const inside = full === scanResolved || full.startsWith(scanPrefix);
          if (!inside) continue;
          if (!keepDirSet.has(full)) {
            await knex('book_index')
              .where({ id })
              .delete()
              .catch(() => {});
          }
        }
      } catch (_) {}
    }

    const cost = Date.now() - start;
    Logger.info(`Book library: scan done ${scanPath}, indexed=${indexed}, meta_ok=${metaOk}, meta_fail=${metaFail}, cost=${cost}ms`);

    await this.deleteTask(task);
  }
}

new BookIndexWorker();

process.on('message', message => {
  if (message && message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ bookIndex worker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ bookIndex worker unhandledRejection', reason);
  process.exit(0);
});
