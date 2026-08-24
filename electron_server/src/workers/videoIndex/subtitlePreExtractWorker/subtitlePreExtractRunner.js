'use strict';

const fs = require('fs');
const path = require('path');
const dbUtil = require('../../../db/dbUtil');
const knexUtil = require('../../../db/knexUtil');
const tableConfig = require('../../../db/table/tableConfig');
const VideoFfprobeUtil = require('../../../utils/videoFfprobeUtil');
const { extractAllToVtt } = require('../../../utils/subtitleVttExtractUtil');
const Logger = require('../../../utils/logger');

const PLAYABLE_MEDIA_TYPES = ['movie', 'episod', 'bdmv', 'video_ts'];

function resolvePlayableFilePath(row) {
  const baseDir = row && row.path ? String(row.path).trim() : '';
  const filename = row && row.filename ? String(row.filename).trim() : '';
  if (!baseDir || !filename) return '';
  const fullPath = path.join(baseDir, filename);
  const mediaType = row && row.media_type ? String(row.media_type).trim() : '';
  const playRelPath = row && row.play_rel_path ? String(row.play_rel_path).trim() : '';
  if ((mediaType === 'bdmv' || mediaType === 'video_ts') && playRelPath) {
    return path.resolve(fullPath, playRelPath);
  }
  return fullPath;
}

function getSubtitleCodecsFromStreams(streams) {
  const list = Array.isArray(streams) ? streams : [];
  return list
    .filter(s => s && s.codec_type === 'subtitle')
    .map(s => (s && s.codec_name ? String(s.codec_name) : ''));
}

async function sourceRootExists(rootPath) {
  const resolved = path.resolve(String(rootPath || '').trim());
  if (!resolved) return false;
  try {
    const st = await fs.promises.stat(resolved);
    return !!(st && st.isDirectory());
  } catch (_) {
    return false;
  }
}

function applySourceRootFilter(qb, roots) {
  qb.where(inner => {
    for (const root of roots) {
      const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
      inner.orWhere('path', root).orWhere('path', 'like', `${prefix}%`);
      inner.orWhere({ path: path.dirname(root), filename: path.basename(root) });
    }
  });
}

class SubtitlePreExtractRunner {
  async init() {
    if (!knexUtil.hasConnection(dbUtil.DB_PATHS.VIDEO_DB)) {
      await knexUtil.init(dbUtil.DB_PATHS.VIDEO_DB);
    }
    if (!knexUtil.hasConnection(dbUtil.DB_PATHS.MAIN_DB)) {
      await knexUtil.init(dbUtil.DB_PATHS.MAIN_DB);
    }
    this.knexVideo = knexUtil.getInstance(dbUtil.DB_PATHS.VIDEO_DB);
    this._existingSourceRoots = null;
    this._deferredIds = new Set();
  }

  async isEnabled() {
    const raw = await tableConfig.getConfigByKey('subtitlePreExtractEnable').catch(() => null);
    if (raw === null || raw === undefined || String(raw).trim() === '') return true;
    const s = String(raw).trim().toLowerCase();
    return s === '1' || s === 'true' || s === 'yes' || s === 'on';
  }

  /** 从 video_source 读取来源，仅保留当前磁盘上可访问的目录 */
  async getExistingSourceRoots({ refresh = false } = {}) {
    if (!refresh && Array.isArray(this._existingSourceRoots)) {
      return this._existingSourceRoots;
    }

    const rows = await this.knexVideo('video_source').select('path').orderBy('id', 'asc').catch(() => []);
    const existing = [];
    const seen = new Set();
    const skipped = [];

    for (const row of rows || []) {
      const raw = row && row.path ? String(row.path).trim() : '';
      if (!raw) continue;
      const resolved = path.resolve(raw);
      if (seen.has(resolved)) continue;
      seen.add(resolved);
      if (await sourceRootExists(resolved)) {
        existing.push(resolved);
      } else {
        skipped.push(resolved);
      }
    }

    if (skipped.length > 0) {
      Logger.info(`📝 subtitle pre-extract skip unavailable sources (${skipped.length}): ${skipped.slice(0, 3).join(', ')}${skipped.length > 3 ? '...' : ''}`);
    }

    this._existingSourceRoots = existing;
    return existing;
  }

  async getPendingRow(existingRoots) {
    const roots = Array.isArray(existingRoots) ? existingRoots : [];
    if (roots.length === 0) return null;

    const deferredIds = Array.from(this._deferredIds || []).filter(id => Number(id) > 0);

    const row = await this.knexVideo('video_index')
      .select('id', 'path', 'filename', 'media_type', 'is_file', 'file_hash', 'play_rel_path')
      .where({ gen_subtitle_vtt: 0 })
      .modify(qb => {
        if (deferredIds.length > 0) qb.whereNotIn('id', deferredIds);
      })
      .andWhere(qb => {
        qb.where(inner => {
          inner.where(inner2 => {
            inner2.where({ is_file: 1 }).whereIn('media_type', ['movie', 'episod']);
          }).orWhere(inner2 => {
            inner2
              .where({ is_file: 0 })
              .whereIn('media_type', ['bdmv', 'video_ts'])
              .whereNot('play_rel_path', '');
          });
        });
        applySourceRootFilter(qb, roots);
      })
      .whereNot('file_hash', '')
      .whereIn('media_type', PLAYABLE_MEDIA_TYPES)
      .orderBy('id', 'asc')
      .first()
      .catch(() => null);
    return row || null;
  }

  async markDone(row) {
    if (!row || !row.id) return;
    await this.knexVideo('video_index').where({ id: row.id }).update({ gen_subtitle_vtt: 1 }).catch(() => {});
  }

  async processRow(row) {
    const filePath = resolvePlayableFilePath(row);
    if (!filePath) {
      await this.markDone(row);
      return { processed: true };
    }
    try {
      const st = await fs.promises.stat(filePath);
      if (!st || !st.isFile()) {
        Logger.info(`📝 subtitle pre-extract skip (not a file) id=${row.id} path=${filePath}`);
        return { processed: false, retryLater: true };
      }
    } catch (e) {
      Logger.info(
        `📝 subtitle pre-extract skip (file inaccessible) id=${row.id} path=${filePath} err=${e && e.code ? e.code : 'stat_failed'}`
      );
      return { processed: false, retryLater: true };
    }

    const fileHash = row && row.file_hash ? String(row.file_hash).trim() : '';
    let subtitleCodecs = null;
    if (fileHash) {
      const cachedRow = await this.knexVideo('video_ffmpeg_info').where({ id: fileHash }).first().catch(() => null);
      const cached = cachedRow ? VideoFfprobeUtil.normalizeCacheRow(cachedRow) : null;
      if (cached && Array.isArray(cached.streams) && cached.streams.length > 0) {
        subtitleCodecs = getSubtitleCodecsFromStreams(cached.streams);
      }
    }

    try {
      const result = await extractAllToVtt({
        fileHash,
        filePath,
        subtitleCodecs,
      });
      if (result && result.code === 'NO_SUBTITLE') {
        Logger.info(`📝 subtitle pre-extract skipped (no subs) id=${row.id}`);
      } else if (result && result.ok) {
        Logger.info(`📝 subtitle pre-extract ok id=${row.id} hash=${result.fileHash || fileHash}`);
      } else {
        Logger.info(
          `📝 subtitle pre-extract done with issues id=${row.id} code=${result && result.code ? result.code : 'unknown'}`
        );
      }
    } catch (e) {
      Logger.error(`❌ subtitle pre-extract failed id=${row && row.id}`, e);
    }

    await this.markDone(row);
    return { processed: true };
  }

  async runOnce() {
    if (!(await this.isEnabled())) {
      return { processed: false, disabled: true };
    }

    const existingRoots = await this.getExistingSourceRoots({ refresh: true });
    if (existingRoots.length === 0) {
      return { processed: false, noAvailableSources: true };
    }

    const row = await this.getPendingRow(existingRoots);
    if (!row) return { processed: false };

    const outcome = await this.processRow(row);
    if (outcome && outcome.retryLater) {
      this._deferredIds.add(row.id);
      return { processed: false, skippedInaccessible: true, deferredId: row.id };
    }
    return { processed: true };
  }
}

async function hasPendingSubtitlePreExtractWork() {
  const runner = new SubtitlePreExtractRunner();
  await runner.init();
  const roots = await runner.getExistingSourceRoots({ refresh: true });
  if (roots.length === 0) return false;
  const row = await runner.getPendingRow(roots);
  return !!row;
}

module.exports = { SubtitlePreExtractRunner, hasPendingSubtitlePreExtractWork };
