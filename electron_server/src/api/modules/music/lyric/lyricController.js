const path = require('path');
const fs = require('fs-extra');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const LyricService = require('./lyricService');
const { hasPermission } = require('../../../../utils/permissionUtil');
const FileUtil = require('../../../../utils/fileUtil');
const config = require('../../../../config/config');
const LYRIC_SEARCH_LOG_TABLE = 'music_lyric_search_log';
const LYRIC_SEARCH_CACHE_TTL_MS = 90 * 24 * 60 * 60 * 1000;
const LYRIC_SEARCH_LOG_MAX_ROWS = 6000;

function _nowMs() {
  return Date.now();
}

function _normalizeSearchKeyword(input) {
  let text = String(input ?? '')
    .toLowerCase()
    .trim();
  const exts = Array.isArray(config.musicTypeList) ? config.musicTypeList : [];
  for (const extRaw of exts) {
    const ext = String(extRaw ?? '').toLowerCase();
    if (!ext) continue;
    if (text.includes(ext)) {
      text = text.split(ext).join('');
    }
  }
  return text.trim();
}

function _safeJsonParse(text) {
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

async function _trimLyricSearchLog(knex) {
  const row = await knex(LYRIC_SEARCH_LOG_TABLE).count({ cnt: 'id' }).first();
  const total = Number(row?.cnt ?? 0);
  const over = total - LYRIC_SEARCH_LOG_MAX_ROWS;
  if (over <= 0) return;

  const ids = await knex(LYRIC_SEARCH_LOG_TABLE).orderBy('searched_at', 'asc').orderBy('id', 'asc').limit(over).pluck('id');
  if (!Array.isArray(ids) || ids.length <= 0) return;
  await knex(LYRIC_SEARCH_LOG_TABLE).whereIn('id', ids).delete();
}

class LyricController {
  async search(req, res) {
    console.log('搜索歌词接口请求', req.body);
    try {
      const raw = String(req.body?.keyword ?? req.body?.q ?? '').trim();
      const keyword = _normalizeSearchKeyword(raw);
      if (!keyword || keyword.length > 100) {
        return ResponseUtil.error(req, res, 'validation.KEYWORD_LENGTH_INVALID', 400);
      }

      const knexMusic = req.dbMusic;
      if (knexMusic) {
        const cached = await knexMusic(LYRIC_SEARCH_LOG_TABLE)
          .where({ file_name: keyword })
          .first(['result_json', 'searched_at'])
          .catch(() => null);
        const searchedAt = Number(cached?.searched_at ?? 0);
        const withinTtl = searchedAt > 0 && _nowMs() - searchedAt <= LYRIC_SEARCH_CACHE_TTL_MS;
        if (withinTtl) {
          const parsed = _safeJsonParse(String(cached?.result_json ?? '[]'));
          if (Array.isArray(parsed)) {
            return ResponseUtil.success(req, res, parsed, 'common.SUCCESS', 200);
          }
        }
      }

      const service = new LyricService();
      const items = await service.search({ keyword });

      if (knexMusic) {
        const now = _nowMs();
        const list = Array.isArray(items) ? items : [];
        const row = {
          file_name: keyword,
          result_json: JSON.stringify(list),
          result_count: list.length,
          searched_at: now,
        };

        await knexMusic(LYRIC_SEARCH_LOG_TABLE)
          .insert(row)
          .onConflict('file_name')
          .merge({
            result_json: row.result_json,
            result_count: row.result_count,
            searched_at: row.searched_at,
          })
          .catch(async () => {
            const existing = await knexMusic(LYRIC_SEARCH_LOG_TABLE)
              .where({ file_name: keyword })
              .first('id')
              .catch(() => null);
            if (existing?.id) {
              await knexMusic(LYRIC_SEARCH_LOG_TABLE)
                .where({ id: existing.id })
                .update({
                  result_json: row.result_json,
                  result_count: row.result_count,
                  searched_at: row.searched_at,
                })
                .catch(() => {});
              return;
            }
            await knexMusic(LYRIC_SEARCH_LOG_TABLE)
              .insert(row)
              .catch(() => {});
          });

        await _trimLyricSearchLog(knexMusic).catch(() => {});
      }

      return ResponseUtil.success(req, res, items, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async setLyric(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const musicPath = String(req.body?.music_path ?? req.body?.musicPath ?? req.body?.file_path ?? req.body?.filePath ?? '').trim();
      const lrc = String(req.body?.lrc ?? req.body?.lyric ?? '');
      const lrcTrimmed = lrc.trim();

      if (!musicPath) return ResponseUtil.error(req, res, 'validation.FILE_REQUIRED', 400);

      const resolvedMusicPath = path.resolve(musicPath);
      if (FileUtil.isProtectedPath(resolvedMusicPath)) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }
      const exists = await fs.pathExists(resolvedMusicPath);
      if (!exists) {
        return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      }

      const canRead = await hasPermission(req.dbMain, req.user, 'view', resolvedMusicPath);
      if (!canRead) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }

      const lrcPath = LyricService.getLrcPathForMusicPath(resolvedMusicPath);
      const canWrite = await hasPermission(req.dbMain, req.user, 'upload', lrcPath);
      if (!canWrite) {
        return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
      }

      await fs.outputFile(lrcPath, lrc, { encoding: 'utf8' });

      const knexMusic = req.dbMusic;
      if (knexMusic) {
        const dir = path.dirname(resolvedMusicPath);
        const name = path.basename(resolvedMusicPath);
        const existingIndex = await knexMusic('music_index')
          .where({ path: dir, filename: name })
          .first('id')
          .catch(() => null);
        if (existingIndex && existingIndex.id) {
          await knexMusic('music_index')
            .where({ id: existingIndex.id })
            .update({ lyrics: lrcTrimmed, lyrics_get_state: lrcTrimmed ? 1 : 2 })
            .catch(() => {});
        }
      }

      return ResponseUtil.success(
        req,
        res,
        {
          music_path: resolvedMusicPath,
          lrc_path: lrcPath,
        },
        'common.SUCCESS',
        200
      );
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new LyricController();
