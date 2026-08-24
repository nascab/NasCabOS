'use strict';

const fs = require('fs');
const path = require('path');
const Watchpack = require('watchpack');

const Logger = require('../../utils/logger');
const FileUtil = require('../../utils/fileUtil');
const dbUtil = require('../../db/dbUtil');
const knexUtil = require('../../db/knexUtil');
const videoIndexIndexUtil = require('./videoIndexIndexUtil');
const {
  isVideoFileExt,
  isSeasonFolderOfShow,
  detectBdmvMovieFolder,
  detectBdmvMovieFolderFromPath,
  detectVideoTsMovieFolder,
  detectVideoTsMovieFolderFromPath,
} = require('./videoIndexUtil');
const fileUtil = require('../../utils/fileUtil');

class VideoWatchWorker {
  constructor() {
    this.knex = null;
    this.watchpack = null;
    this.watchedRoots = [];
    this.sourceMediaTypeByRoot = new Map();
    this.pendingChangedPaths = new Set();
    this.pendingRemovedPaths = new Set();
    this.flushTimer = null;
    this.newVideoDebounceTimer = null;
    this.newVideoDebounceMs = 10 * 1000;
    this.processing = false;
    this.reflushRequested = false;
    this.init();
  }

  sendMessage(type, data = undefined) {
    if (typeof process.send !== 'function') return;
    try {
      process.send({ type, data });
    } catch (_) {}
  }

  scheduleNewVideoCome() {
    if (this.newVideoDebounceTimer) clearTimeout(this.newVideoDebounceTimer);
    this.newVideoDebounceTimer = setTimeout(() => {
      this.newVideoDebounceTimer = null;
      this.sendMessage('newVideoCome');
    }, this.newVideoDebounceMs);
  }

  async init() {
    try {
      await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);
      this.knex = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
      await this.resetWatchers();

    } catch (err) {
      Logger.error('❌ videoWatchWorker init failed:', err);
      process.exit(1);
    }
  }

  async getWatchedSourcePaths() {
    const rows = await this.knex('video_source')
      .select('path', 'media_type')
      .where({ scan_when_change: 1 })
      .catch(() => []);

    this.sourceMediaTypeByRoot.clear();
    const unique = new Set();
    for (const r of rows || []) {
      const p = r && r.path ? String(r.path) : '';
      if (!p) continue;
      unique.add(p);
      const resolved = path.resolve(p);
      const mt = r && r.media_type ? String(r.media_type) : '';
      this.sourceMediaTypeByRoot.set(resolved, mt === 'tv' ? 'tv' : 'movie');
    }

    const res = [];
    for (const p of unique) {
      try {
        const stat = await fs.promises.stat(p);
        if (stat && stat.isDirectory()) res.push(p);
      } catch (_) {}
    }
    return res;
  }

  buildWatchedRoots(paths) {
    const roots = [];
    for (const p of paths) {
      const rp = path.resolve(p);
      const prefix = rp.endsWith(path.sep) ? rp : `${rp}${path.sep}`;
      roots.push({ root: rp, prefix });
    }
    roots.sort((a, b) => a.prefix.length - b.prefix.length);
    return roots;
  }

  isWithinWatchedRoot(targetPath) {
    if (!targetPath) return false;
    const rp = path.resolve(targetPath);
    for (const r of this.watchedRoots) {
      if (rp === r.root) return true;
      if (rp.startsWith(r.prefix)) return true;
    }
    return false;
  }

  checkRootPathExist(targetPath) {
    if (!targetPath) return false;
    const rp = path.resolve(targetPath);
    let rootPath = null;
    for (const r of this.watchedRoots) {
      if (rp === r.root) {
        rootPath = r.root;
        break;
      }
      if (rp.startsWith(r.prefix)) {
        rootPath = r.root;
        break;
      }
    }
    return fs.existsSync(rootPath);
  }

  isWatchedRoot(targetPath) {
    if (!targetPath) return false;
    const rp = path.resolve(targetPath);
    for (const r of this.watchedRoots) {
      if (rp === r.root) return true;
    }
    return false;
  }

  getMatchedRootForPath(targetPath) {
    if (!targetPath) return '';
    const rp = path.resolve(targetPath);
    let best = '';
    for (const r of this.watchedRoots) {
      if (rp === r.root || rp.startsWith(r.prefix)) {
        if (!best || r.root.length > best.length) best = r.root;
      }
    }
    return best;
  }

  getSourceMediaTypeForPath(targetPath) {
    const root = this.getMatchedRootForPath(targetPath);
    if (!root) return 'movie';
    // 不再依赖目录结构猜测类型：统一以 video_source.media_type 为准
    return this.sourceMediaTypeByRoot.get(root) || 'movie';
  }

  closeWatchpack() {
    if (!this.watchpack) return;
    try {
      this.watchpack.close();
    } catch (_) {}
    this.watchpack = null;
  }

  async resetWatchers() {
    this.closeWatchpack();
    this.pendingChangedPaths.clear();
    this.pendingRemovedPaths.clear();

    const sourcePaths = await this.getWatchedSourcePaths();
    this.watchedRoots = this.buildWatchedRoots(sourcePaths);

    if (!sourcePaths || sourcePaths.length === 0) {
      Logger.info('ℹ️ scan_when_change=1 but no sources, videoWatchWorker exiting');
      return process.exit(0);
    }

    const wp = new Watchpack({
      aggregateTimeout: 1000,
      poll: false,
      ignored: fileUtil.watchIgnoredList,
    });

    wp.on('change', p => {
      this.scheduleFromPath(String(p || ''), false);
    });
    wp.on('remove', p => {
      this.scheduleFromPath(String(p || ''), true);
    });
    wp.watch({ directories: sourcePaths, startTime: Date.now() });
    this.watchpack = wp;
  }

  scheduleFromPath(p, isRemove) {
    if (!p) return;
    const resolved = path.resolve(p);
    if (!this.isWithinWatchedRoot(resolved)) return;

    if (isRemove) {
      this.pendingRemovedPaths.add(resolved);
    } else {
      this.pendingChangedPaths.add(resolved);
    }

    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.flushPending().catch(err => Logger.error('❌ videoWatchWorker flushPending error:', err));
    }, 800);
  }

  async flushPending() {
    if (this.processing) {
      this.reflushRequested = true;
      return;
    }
    this.processing = true;

    const removedPaths = Array.from(this.pendingRemovedPaths);
    const changedPaths = Array.from(this.pendingChangedPaths);
    this.pendingRemovedPaths.clear();
    this.pendingChangedPaths.clear();
    console.log('影音：处理变动路径:', changedPaths);
    console.log('影音：处理删除路径:', removedPaths);
    try {
      for (const p of removedPaths) {
        if (!this.isWithinWatchedRoot(p)) continue;
        if (p.endsWith('.tmp')) continue;
        await this.handleRemovedPath(p);
      }

      for (const p of changedPaths) {
        if (!this.isWithinWatchedRoot(p)) continue;
        if (p.endsWith('.tmp')) continue;
        await this.handleChangedPath(p);
      }
    } finally {
      this.processing = false;
    }

    if (this.reflushRequested) {
      this.reflushRequested = false;
      await this.flushPending();
    }
  }

  async deleteFileIndex(dirPath, filename) {
    if (!dirPath || !filename) return;
    await this.knex('video_index')
      .where({ path: dirPath, filename, is_file: 1 })
      .delete()
      .catch(() => {});
  }

  async deleteDirectoryIndexes(dirPath) {
    if (!dirPath) return;
    const resolved = path.resolve(dirPath);
    const scanPrefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;

    await this.knex('video_index')
      .where(qb => {
        qb.where('path', resolved).orWhere('path', 'like', `${scanPrefix}%`);
      })
      .delete()
      .catch(() => {});

    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (parentDir && folderName) {
      await this.knex('video_index')
        .where({ path: parentDir, filename: folderName, is_file: 0 })
        .delete()
        .catch(() => {});
    }
  }

  getEpisodeFoldersFromPath(fullPath) {
    return videoIndexIndexUtil.getTvFoldersFromEpisode({ fullPath });
  }

  async countEpisodesUnderFolder(rootFolder) {
    const resolved = path.resolve(String(rootFolder || ''));
    if (!resolved) return 0;
    const prefix = resolved.endsWith(path.sep) ? resolved : `${resolved}${path.sep}`;
    const row = await this.knex('video_index')
      .count({ c: '*' })
      .where({ is_file: 1, media_type: 'episod' })
      .andWhere(qb => {
        qb.where('path', resolved).orWhere('path', 'like', `${prefix}%`);
      })
      .first()
      .catch(() => null);
    const v = row && (row.c ?? row['count(*)'] ?? row['COUNT(*)']);
    return Number(v || 0) || 0;
  }

  async countDistinctSeasonFoldersInShow(showFolder) {
    const resolvedShow = path.resolve(String(showFolder || ''));
    if (!resolvedShow) return 0;
    const prefix = resolvedShow.endsWith(path.sep) ? resolvedShow : `${resolvedShow}${path.sep}`;
    const rows = await this.knex('video_index')
      .select('path')
      .where({ is_file: 1, media_type: 'episod' })
      .andWhere(qb => {
        qb.where('path', resolvedShow).orWhere('path', 'like', `${prefix}%`);
      })
      .groupBy('path')
      .catch(() => []);

    const seasonFolders = new Set();
    const showName = path.basename(resolvedShow);
    for (const r of rows || []) {
      const p = r && r.path ? String(r.path) : '';
      if (!p) continue;
      const name = path.basename(p);
      if (!isSeasonFolderOfShow(name, showName)) continue;
      if (path.dirname(p) !== resolvedShow) continue;
      seasonFolders.add(p);
    }

    return seasonFolders.size;
  }

  async deleteSeasonFolderIndex(seasonFolder) {
    const resolved = path.resolve(String(seasonFolder || ''));
    if (!resolved) return;
    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (!parentDir || !folderName) return;

    await this.knex('video_index')
      .where({ path: parentDir, filename: folderName, is_file: 0, media_type: 'season' })
      .delete()
      .catch(() => {});
  }

  async deleteShowFolderIndex(showFolder) {
    const resolved = path.resolve(String(showFolder || ''));
    if (!resolved) return;
    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (!parentDir || !folderName) return;

    await this.knex('video_index')
      .where({ path: parentDir, filename: folderName, is_file: 0, media_type: 'tv' })
      .delete()
      .catch(() => {});

    await this.knex('video_index')
      .where({ path: resolved, is_file: 0, media_type: 'season' })
      .delete()
      .catch(() => {});
  }

  async findIndexedDiscFolderForPath(targetPath) {
    let cursor = targetPath ? path.resolve(String(targetPath)) : '';
    if (!cursor) return '';
    try {
      const stat = await fs.promises.stat(cursor);
      if (stat.isFile()) cursor = path.dirname(cursor);
    } catch (_) {
      cursor = path.dirname(cursor);
    }

    const matchedRoot = this.getMatchedRootForPath(cursor);
    const rootBoundary = matchedRoot ? path.resolve(matchedRoot) : '';
    for (let i = 0; i < 12; i += 1) {
      const parentDir = path.dirname(cursor);
      const folderName = path.basename(cursor);
      if (!parentDir || !folderName) break;
      const row = await this.knex('video_index')
        .where({ path: parentDir, filename: folderName, is_file: 0 })
        .whereIn('media_type', ['bdmv', 'video_ts'])
        .first('id', 'media_type')
        .catch(() => null);
      if (row && row.id) {
        return {
          folderPath: cursor,
          mediaType: row.media_type ? String(row.media_type) : '',
        };
      }
      if (!rootBoundary || cursor === rootBoundary) break;
      const next = path.dirname(cursor);
      if (!next || next === cursor) break;
      cursor = next;
    }
    return null;
  }

  async detectDiscFolderFromDirectory(dirPath) {
    const resolved = dirPath ? path.resolve(String(dirPath)) : '';
    if (!resolved) return '';
    try {
      const entries = await fs.promises.readdir(resolved, { withFileTypes: true });
      const found = detectBdmvMovieFolder(resolved, entries) || detectVideoTsMovieFolder(resolved, entries);
      return found && found.folderPath ? found : null;
    } catch (_) {
      return null;
    }
  }

  async syncDiscFolder(folderPath, mediaType = '') {
    const resolved = folderPath ? path.resolve(String(folderPath)) : '';
    if (!resolved) return false;
    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (!parentDir || !folderName) return false;

    try {
      const stat = await fs.promises.stat(resolved);
      if (!stat.isDirectory()) {
        await this.deleteDirectoryIndexes(resolved);
        return false;
      }
    } catch (_) {
      await this.deleteDirectoryIndexes(resolved);
      return false;
    }

    const ok = String(mediaType || '') === 'video_ts'
      ? await videoIndexIndexUtil.indexVideoTsFolder({
          knex: this.knex,
          folderPath: resolved,
          dirPath: parentDir,
          filename: folderName,
        })
      : await videoIndexIndexUtil.indexBdmvFolder({
          knex: this.knex,
          folderPath: resolved,
          dirPath: parentDir,
          filename: folderName,
        });
    if (!ok) {
      await this.deleteDirectoryIndexes(resolved);
    }
    return ok;
  }

  async recomputeAndUpsertTvIndexes({ showFolder, seasonFolder }) {
    const showResolved = showFolder ? path.resolve(String(showFolder)) : '';
    if (!showResolved) return;

    if (seasonFolder) {
      const seasonResolved = path.resolve(String(seasonFolder));
      const seasonEpisodeCount = await this.countEpisodesUnderFolder(seasonResolved);
      if (seasonEpisodeCount <= 0) {
        await this.deleteSeasonFolderIndex(seasonResolved);
      } else {
        await videoIndexIndexUtil.indexSeasonFolder({ knex: this.knex, seasonFolder: seasonResolved, episodCount: seasonEpisodeCount });
      }
    }

    const showEpisodeCount = await this.countEpisodesUnderFolder(showResolved);
    if (showEpisodeCount <= 0) {
      await this.deleteShowFolderIndex(showResolved);
      return;
    }

    const seasonCount = await this.countDistinctSeasonFoldersInShow(showResolved);
    await videoIndexIndexUtil.indexTvShowFolder({ knex: this.knex, showFolder: showResolved, seasonCount, episodCount: showEpisodeCount });
  }

  async markTvShowNfoPending(showFolder) {
    const resolved = showFolder ? path.resolve(String(showFolder)) : '';
    if (!resolved) return;
    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (!parentDir || !folderName) return;
    await this.knex('video_index')
      .where({ path: parentDir, filename: folderName, is_file: 0, media_type: 'tv' })
      .update({ nfo_get_state: 0 })
      .catch(() => {});
  }

  async markSeasonNfoPending(seasonFolder) {
    const resolved = seasonFolder ? path.resolve(String(seasonFolder)) : '';
    if (!resolved) return;
    const parentDir = path.dirname(resolved);
    const folderName = path.basename(resolved);
    if (!parentDir || !folderName) return;
    await this.knex('video_index')
      .where({ path: parentDir, filename: folderName, is_file: 0, media_type: 'season' })
      .update({ nfo_get_state: 0 })
      .catch(() => {});
  }

  async markNfoPendingForEpisode({ showFolder, seasonFolder }) {
    if (showFolder) await this.markTvShowNfoPending(showFolder);
    if (seasonFolder) await this.markSeasonNfoPending(seasonFolder);
  }

  async syncArtworkForDirectory(dirPath) {
    const resolvedDir = dirPath ? path.resolve(String(dirPath)) : '';
    if (!resolvedDir) return;
    if (!this.isWithinWatchedRoot(resolvedDir)) return;

    const fileRows = await this.knex('video_index')
      .select('id', 'path', 'filename', 'media_type', 'poster_path', 'fanart_path', 'logo_path')
      .where({ path: resolvedDir, is_file: 1 })
      .catch(() => []);

    for (const r of fileRows || []) {
      const mediaType = r && r.media_type ? String(r.media_type) : '';
      const current = {
        poster_path: r && r.poster_path ? String(r.poster_path) : '',
        fanart_path: r && r.fanart_path ? String(r.fanart_path) : '',
        logo_path: r && r.logo_path ? String(r.logo_path) : '',
      };
      const next = await videoIndexIndexUtil.resolveArtworkPaths({
        baseDir: resolvedDir,
        searchDir: resolvedDir,
        current,
        videoBaseName: r && r.filename ? path.parse(String(r.filename)).name : '',
        onlyVideoBase: mediaType === 'episod',
      });
      if (next.poster_path !== current.poster_path || next.fanart_path !== current.fanart_path || next.logo_path !== current.logo_path) {
        await this.knex('video_index')
          .where({ id: r.id })
          .update({
            poster_path: next.poster_path,
            fanart_path: next.fanart_path,
            logo_path: next.logo_path,
          })
          .catch(() => {});
      }
    }

    const parentDir = path.dirname(resolvedDir);
    const folderName = path.basename(resolvedDir);
    if (!parentDir || !folderName) return;

    const folderRows = await this.knex('video_index')
      .select('id', 'path', 'filename', 'media_type', 'poster_path', 'fanart_path', 'logo_path')
      .where({ path: parentDir, filename: folderName, is_file: 0 })
      .catch(() => []);

    for (const r of folderRows || []) {
      const mediaType = r && r.media_type ? String(r.media_type) : '';
      const current = {
        poster_path: r && r.poster_path ? String(r.poster_path) : '',
        fanart_path: r && r.fanart_path ? String(r.fanart_path) : '',
        logo_path: r && r.logo_path ? String(r.logo_path) : '',
      };
      let next = null;
      if (mediaType === 'season') {
        const seasonNumber = videoIndexIndexUtil.parseSeasonNumberFromName(r && r.filename ? String(r.filename) : '');
        const fromShowFolder = await videoIndexIndexUtil.resolveArtworkPaths({
          baseDir: parentDir,
          searchDir: parentDir,
          current,
          seasonNumber,
        });
        const fromSeasonFolder = await videoIndexIndexUtil.resolveArtworkPaths({
          baseDir: parentDir,
          searchDir: resolvedDir,
          current: fromShowFolder,
          seasonNumber: 0,
        });
        next = fromSeasonFolder;
      } else {
        next = await videoIndexIndexUtil.resolveArtworkPaths({
          baseDir: parentDir,
          searchDir: resolvedDir,
          current,
          seasonNumber: 0,
        });
      }
      if (next.poster_path !== current.poster_path || next.fanart_path !== current.fanart_path || next.logo_path !== current.logo_path) {
        await this.knex('video_index')
          .where({ id: r.id })
          .update({
            poster_path: next.poster_path,
            fanart_path: next.fanart_path,
            logo_path: next.logo_path,
          })
          .catch(() => {});
      }
    }

    const sourceMediaType = this.getSourceMediaTypeForPath(resolvedDir);
    if (sourceMediaType !== 'tv') return;

    const seasonRows = await this.knex('video_index')
      .select('id', 'filename', 'poster_path', 'fanart_path', 'logo_path')
      .where({ path: resolvedDir, is_file: 0, media_type: 'season' })
      .catch(() => []);

    for (const r of seasonRows || []) {
      const seasonName = r && r.filename ? String(r.filename) : '';
      const seasonFolder = seasonName ? path.join(resolvedDir, seasonName) : '';
      const seasonNumber = videoIndexIndexUtil.parseSeasonNumberFromName(seasonName);
      if (!seasonNumber || !seasonFolder) continue;

      const current = {
        poster_path: r && r.poster_path ? String(r.poster_path) : '',
        fanart_path: r && r.fanart_path ? String(r.fanart_path) : '',
        logo_path: r && r.logo_path ? String(r.logo_path) : '',
      };

      const fromShowFolder = await videoIndexIndexUtil.resolveArtworkPaths({
        baseDir: resolvedDir,
        searchDir: resolvedDir,
        current,
        seasonNumber,
      });
      const next = await videoIndexIndexUtil.resolveArtworkPaths({
        baseDir: resolvedDir,
        searchDir: seasonFolder,
        current: fromShowFolder,
        seasonNumber: 0,
      });

      if (next.poster_path !== current.poster_path || next.fanart_path !== current.fanart_path || next.logo_path !== current.logo_path) {
        await this.knex('video_index')
          .where({ id: r.id })
          .update({
            poster_path: next.poster_path,
            fanart_path: next.fanart_path,
            logo_path: next.logo_path,
          })
          .catch(() => {});
      }
    }
  }

  async handleRemovedPath(p) {
    try {
      const exists = fs.existsSync(p);
      if (exists) return;
    } catch (_) {}

    const discFolder = await this.findIndexedDiscFolderForPath(p);
    if (discFolder && discFolder.folderPath) {
      const folderExists = fs.existsSync(discFolder.folderPath);
      if (!folderExists) {
        await this.deleteDirectoryIndexes(discFolder.folderPath);
        return;
      }
      await this.syncDiscFolder(discFolder.folderPath, discFolder.mediaType);
      return;
    }

    if (videoIndexIndexUtil.isArtworkImageFilePath(p)) {
      await this.syncArtworkForDirectory(path.dirname(p));
      return;
    }

    const filename = path.basename(p);
    if (FileUtil.shouldSkipIndexingFilename(filename)) {
      const dirPath = path.dirname(p);
      await this.deleteFileIndex(dirPath, filename);
      const sourceMediaType = this.getSourceMediaTypeForPath(p);
      if (sourceMediaType === 'tv') {
        const { showFolder, seasonFolder } = this.getEpisodeFoldersFromPath(p);
        await this.recomputeAndUpsertTvIndexes({ showFolder, seasonFolder: seasonFolder || '' });
      }
      return;
    }

    const ext = path.extname(filename).toLowerCase();
    if (isVideoFileExt(ext)) {
      const dirPath = path.dirname(p);
      await this.deleteFileIndex(dirPath, filename);

      const sourceMediaType = this.getSourceMediaTypeForPath(p);
      if (sourceMediaType === 'tv') {
        const { showFolder, seasonFolder } = this.getEpisodeFoldersFromPath(p);
        await this.recomputeAndUpsertTvIndexes({ showFolder, seasonFolder: seasonFolder || '' });
      }
      return;
    }

    await this.deleteDirectoryIndexes(p);

    const removedDirName = path.basename(p);
    const sourceMediaType = this.getSourceMediaTypeForPath(p);
    if (sourceMediaType === 'tv') {
      const showFolder = path.dirname(p);
      const showName = path.basename(showFolder);
      if (isSeasonFolderOfShow(removedDirName, showName)) {
        await this.recomputeAndUpsertTvIndexes({ showFolder, seasonFolder: p });
      }
    }
  }

  async handleChangedPath(p) {
    if (!this.checkRootPathExist(p)) {
      Logger.info('File event: root missing, skip', p);
      return;
    }

    let stat;
    try {
      stat = fs.statSync(p);
    } catch (_) {
      await this.handleRemovedPath(p);
      return;
    }

    const indexedDiscFolder = await this.findIndexedDiscFolderForPath(p);
    if (indexedDiscFolder && indexedDiscFolder.folderPath) {
      await this.syncDiscFolder(indexedDiscFolder.folderPath, indexedDiscFolder.mediaType);
      return;
    }

    if (stat.isDirectory()) {
      const discFolder = await this.detectDiscFolderFromDirectory(p);
      if (discFolder && discFolder.folderPath) {
        const existed = await this.findIndexedDiscFolderForPath(discFolder.folderPath);
        const ok = await this.syncDiscFolder(discFolder.folderPath, discFolder.mediaType);
        if (ok && !existed) this.scheduleNewVideoCome();
        return;
      }
      await this.syncDirectory(p);
      return;
    }

    if (!stat.isFile()) return;
    const filename = path.basename(p);
    if (FileUtil.shouldSkipIndexingFilename(filename)) return;

    const ext = path.extname(filename).toLowerCase();
    if (videoIndexIndexUtil.isArtworkImageFilePath(p)) {
      await this.syncArtworkForDirectory(path.dirname(p));
      return;
    }
    if (!isVideoFileExt(ext)) return;

    const dirPath = path.dirname(p);
    const discMovie = this.getSourceMediaTypeForPath(p) === 'movie'
      ? (detectBdmvMovieFolderFromPath(p) || detectVideoTsMovieFolderFromPath(p))
      : null;
    if (discMovie && discMovie.folderPath) {
      const existed = await this.findIndexedDiscFolderForPath(discMovie.folderPath);
      const ok = await this.syncDiscFolder(discMovie.folderPath, discMovie.mediaType);
      if (ok && !existed) this.scheduleNewVideoCome();
      return;
    }

    // 根据 Jellyfin 约定：Sample 文件夹下的样片不纳入索引
    if (String(path.basename(dirPath) || '').toLowerCase() === 'sample') {
      await this.deleteFileIndex(dirPath, filename);
      return;
    }

    const existed = await this.knex('video_index')
      .where({ path: dirPath, filename, is_file: 1 })
      .first('id', 'size', 'media_type')
      .catch(() => null);

    if (existed && existed.id) {
      const oldSize = Number(existed.size || 0) || 0;
      if (oldSize === Number(stat.size || 0)) return;
      await this.knex('video_index')
        .where({ id: existed.id })
        .delete()
        .catch(() => {});
    }

    const sourceMediaType = this.getSourceMediaTypeForPath(p);

    const isNew = !(existed && existed.id);
    if (sourceMediaType === 'tv') {
      const ok = await videoIndexIndexUtil.indexEpisodeFile({ knex: this.knex, fullPath: p, dirPath, filename, ext });
      const { showFolder, seasonFolder } = this.getEpisodeFoldersFromPath(p);
      await this.recomputeAndUpsertTvIndexes({ showFolder, seasonFolder: seasonFolder || '' });
      if (isNew && ok) {
        await this.markNfoPendingForEpisode({ showFolder, seasonFolder: seasonFolder || '' });
        this.scheduleNewVideoCome();
      }
    } else {
      const ok = await videoIndexIndexUtil.indexMovieFile({ knex: this.knex, fullPath: p, dirPath, filename, ext });
      if (isNew && ok) this.scheduleNewVideoCome();
    }
  }

  async syncDirectory(dirPath) {
    if (!dirPath) return;
    let stat;
    try {
      stat = await fs.promises.stat(dirPath);
    } catch (_) {
      await this.deleteDirectoryIndexes(dirPath);
      return;
    }
    if (!stat.isDirectory()) return;

    const sourceMediaType = this.getSourceMediaTypeForPath(dirPath);

    const stack = [dirPath];
    const seenDirs = new Set();
    const affectedShows = new Map();
    const pendingNfoShowFolders = new Set();
    const pendingNfoSeasonFolders = new Set();

    while (stack.length > 0) {
      const currentDir = stack.pop();
      const resolvedDir = path.resolve(currentDir);
      if (seenDirs.has(resolvedDir)) continue;
      seenDirs.add(resolvedDir);

      let entries;
      try {
        entries = await fs.promises.readdir(currentDir, { withFileTypes: true });
      } catch (_) {
        continue;
      }

      const discMovie = sourceMediaType === 'movie'
        ? (detectBdmvMovieFolder(currentDir, entries) || detectVideoTsMovieFolder(currentDir, entries))
        : null;
      if (discMovie && discMovie.folderPath) {
        const existed = await this.findIndexedDiscFolderForPath(discMovie.folderPath);
        const ok = await this.syncDiscFolder(discMovie.folderPath, discMovie.mediaType);
        if (ok && !existed) this.scheduleNewVideoCome();
        continue;
      }

      for (const ent of entries) {
        const name = ent.name;
        if (FileUtil.isSystemFile(name)) continue;
        if (FileUtil.isHideFile(name)) continue;
        if (FileUtil.isTemporaryOrDownloadingFile(name)) continue;
        const fullPath = path.join(currentDir, name);

        if (ent.isDirectory()) {
          stack.push(fullPath);
          continue;
        }

        if (!ent.isFile()) continue;
        const ext = path.extname(name).toLowerCase();
        if (!isVideoFileExt(ext)) continue;
        const discFromFile = sourceMediaType === 'movie'
          ? (detectBdmvMovieFolderFromPath(fullPath) || detectVideoTsMovieFolderFromPath(fullPath))
          : null;
        if (discFromFile && discFromFile.folderPath) {
          const existed = await this.findIndexedDiscFolderForPath(discFromFile.folderPath);
          const ok = await this.syncDiscFolder(discFromFile.folderPath, discFromFile.mediaType);
          if (ok && !existed) this.scheduleNewVideoCome();
          continue;
        }

        // 根据 Jellyfin 约定：Sample 文件夹下的样片不纳入索引
        if (String(path.basename(currentDir) || '').toLowerCase() === 'sample') {
          await this.deleteFileIndex(currentDir, name);
          continue;
        }

        let fileStat;
        try {
          fileStat = await fs.promises.stat(fullPath);
        } catch (_) {
          continue;
        }
        if (!fileStat.isFile()) continue;

        const existed = await this.knex('video_index')
          .where({ path: currentDir, filename: name, is_file: 1 })
          .first('id', 'size')
          .catch(() => null);

        if (existed && existed.id) {
          const oldSize = Number(existed.size || 0) || 0;
          if (oldSize === Number(fileStat.size || 0)) continue;
          await this.knex('video_index')
            .where({ id: existed.id })
            .delete()
            .catch(() => {});
        }

        const isNew = !(existed && existed.id);
        if (sourceMediaType === 'tv') {
          const ok = await videoIndexIndexUtil.indexEpisodeFile({ knex: this.knex, fullPath, dirPath: currentDir, filename: name, ext });
          const { showFolder, seasonFolder } = this.getEpisodeFoldersFromPath(fullPath);
          if (showFolder) {
            const key = path.resolve(showFolder);
            const prev = affectedShows.get(key) || { showFolder: key, seasons: new Set() };
            if (seasonFolder) prev.seasons.add(path.resolve(seasonFolder));
            affectedShows.set(key, prev);
          }
          if (isNew && ok) {
            if (showFolder) pendingNfoShowFolders.add(path.resolve(showFolder));
            if (seasonFolder) pendingNfoSeasonFolders.add(path.resolve(seasonFolder));
            this.scheduleNewVideoCome();
          }
        } else {
          const ok = await videoIndexIndexUtil.indexMovieFile({ knex: this.knex, fullPath, dirPath: currentDir, filename: name, ext });
          if (isNew && ok) this.scheduleNewVideoCome();
        }
      }
    }

    if (sourceMediaType === 'tv') {
      for (const showFolder of pendingNfoShowFolders) {
        await this.markTvShowNfoPending(showFolder);
      }
      for (const seasonFolder of pendingNfoSeasonFolders) {
        await this.markSeasonNfoPending(seasonFolder);
      }

      for (const s of affectedShows.values()) {
        const showFolder = s.showFolder;
        const seasons = Array.from(s.seasons || []);
        if (seasons.length === 0) {
          await this.recomputeAndUpsertTvIndexes({ showFolder, seasonFolder: '' });
          continue;
        }
        for (const seasonFolder of seasons) {
          await this.recomputeAndUpsertTvIndexes({ showFolder, seasonFolder });
        }
      }
    }
  }
}

const worker = new VideoWatchWorker();

process.on('message', message => {
  if (!message || !message.type) return;
  if (message.type === 'reset') {
    worker.resetWatchers().catch(err => Logger.error('❌ videoWatchWorker reset failed:', err));
  }
  if (message.type === 'stop') {
    process.exit(0);
  }
});

process.on('uncaughtException', err => {
  Logger.error('❌ videoWatchWorker uncaughtException', err);
  process.exit(0);
});

process.on('unhandledRejection', reason => {
  Logger.error('❌ videoWatchWorker unhandledRejection', reason);
  process.exit(0);
});
