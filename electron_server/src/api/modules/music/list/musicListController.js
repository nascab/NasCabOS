const fs = require('fs');
const path = require('path');
const ResponseUtil = require('../../../apiUtils/responseUtil');
const MusicListService = require('./musicListService');
const config = require('../../../../config/config');
const sharpUtils = require('../../../../utils/sharpUtils');
const fileService = require('../../file/core/fileService');
const tableFileLog = require('../../../../db/table/tableFileLog');
const { hasPermission } = require('../../../../utils/permissionUtil');
const FileUtil = require('../../../../utils/fileUtil');
const { getLocalizedMessage } = require('../../../../utils/i18nUtil');
const MusicTagReader = require('../../../../workers/musicIndex/musicTagReader');
const { buildMusicIndexRow } = require('../../../../workers/musicIndex/musicIndexRowBuilder');
const { regenerateCoverFromFile } = require('../../../../workers/musicIndex/musicCoverUtil');

class MusicListController {
  async getDetailByPath(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const rawPath = String(body.file_path ?? body.filePath ?? body.full_path ?? body.fullPath ?? body.path ?? '').trim();
      if (!rawPath) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const fullPath = path.resolve(rawPath);
      const canView = await hasPermission(req.dbMain, user, ['download', 'view'], fullPath);
      if (!canView) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      if (FileUtil.isProtectedPath(fullPath)) {
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH', 403);
      }

      let st = null;
      try {
        st = await fs.promises.stat(fullPath);
      } catch (_) {}
      if (!st || !st.isFile()) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const ext = path.extname(fullPath).toLowerCase();
      if (Array.isArray(config.musicTypeList) && !config.musicTypeList.includes(ext)) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      const dir = path.dirname(fullPath);
      const name = path.basename(fullPath);
      if (!dir || !name) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const coverCacheFolder = typeof config.getMusicCoverCachePath === 'function' ? config.getMusicCoverCachePath() : '';
      const ensureInnerCoverTiny = async ({ fileHash, coverBuffer, size = 500 }) => {
        const hash = String(fileHash || '').trim();
        if (!hash) return false;
        if (!coverCacheFolder) return false;
        if (!coverBuffer || !(Buffer.isBuffer(coverBuffer) || coverBuffer instanceof Uint8Array)) return false;

        const targetPath = path.join(coverCacheFolder, `${hash}.webp`);
        try {
          const stCover = await fs.promises.stat(targetPath);
          if (stCover && stCover.isFile() && stCover.size > 0) return true;
        } catch (_) {}

        await fs.promises.mkdir(coverCacheFolder, { recursive: true }).catch(() => {});
        try {
          await sharpUtils.genTinyFile(Buffer.from(coverBuffer), coverCacheFolder, hash, 'image', size);
          return true;
        } catch (_) {
          return false;
        }
      };

      const knex = req.dbMusic;
      const pick = await knex('music_index')
        .where({ path: dir, filename: name })
        .first(
          'id',
          'path',
          'filename',
          'ext',
          'size',
          'duration',
          'file_hash',
          'ctime',
          'mtime',
          'birthtime',
          'title',
          'artist',
          'album',
          'year',
          'genre',
          'lyrics',
          'stream_info',
          'bitrate',
          'sample_rate',
          'bit_depth',
          'lyrics_get_state',
          'has_inner_cover',
          'show_type',
          'music_count',
          'play_count'
        )
        .catch(() => null);
      const existedIndexId = Number(pick && pick.id) || 0;
      let row = pick;

      if (!row || !row.id) {
        const tagReader = new MusicTagReader();
        const [tags, probe] = await Promise.all([tagReader.readAudioTags(fullPath), tagReader.probeAudio(fullPath)]);
        const built = buildMusicIndexRow({ fullPath, stat: st, tags, probe, tagReader });
        if (!built) return ResponseUtil.error(req, res, 'common.ERROR', 500);

        const coverBuffer = tagReader.extractInnerCoverBuffer(tags);
        const hasCover = coverBuffer && built.file_hash ? await ensureInnerCoverTiny({ fileHash: built.file_hash, coverBuffer, size: 500 }) : false;

        const insertRow = {
          ...built,
          has_inner_cover: hasCover ? 1 : 0,
          show_type: 'music',
          music_count: 0,
        };

        await knex('music_index')
          .insert(insertRow)
          .onConflict(['path', 'filename'])
          .merge(insertRow)
          .catch(() => {});

        row = await knex('music_index')
          .where({ path: dir, filename: name })
          .first(
            'id',
            'path',
            'filename',
            'ext',
            'size',
            'duration',
            'file_hash',
            'ctime',
            'mtime',
            'birthtime',
            'title',
            'artist',
            'album',
            'year',
            'genre',
            'lyrics',
            'stream_info',
            'bitrate',
            'sample_rate',
            'bit_depth',
            'lyrics_get_state',
            'has_inner_cover',
            'show_type',
            'music_count',
            'play_count'
          )
          .catch(() => null);
      } else {
        const hasInner = Number(row.has_inner_cover || 0) === 1;
        const hash = row.file_hash ? String(row.file_hash).trim() : '';
        if (hasInner && hash && coverCacheFolder) {
          const coverPath = path.join(coverCacheFolder, `${hash}.webp`);
          let ok = false;
          try {
            const stCover = await fs.promises.stat(coverPath);
            ok = !!(stCover && stCover.isFile() && stCover.size > 0);
          } catch (_) {}

          if (!ok) {
            const tagReader = new MusicTagReader();
            const tags = await tagReader.readAudioTags(fullPath);
            const coverBuffer = tagReader.extractInnerCoverBuffer(tags);
            if (coverBuffer) {
              await ensureInnerCoverTiny({ fileHash: hash, coverBuffer, size: 500 });
            }
          }
        }
      }

      if (!row || !row.id) return ResponseUtil.error(req, res, 'common.ERROR', 500);

      let lyrics = row.lyrics ? String(row.lyrics) : '';
      lyrics = lyrics.trim();

      const normalizeLyricText = s => String(s ?? '').replace(/\r\n/g, '\n').trim();
      const lyricQuality = s => {
        const text = normalizeLyricText(s);
        if (!text) return { text: '', lineCount: 0, len: 0 };
        const lines = text
          .split('\n')
          .map(v => String(v || '').trim())
          .filter(Boolean);
        return { text, lineCount: lines.length, len: text.length };
      };
      const pickBetterLyric = (a, b) => {
        const qa = lyricQuality(a);
        const qb = lyricQuality(b);
        if (!qa.text) return qb.text;
        if (!qb.text) return qa.text;
        if (qb.lineCount >= qa.lineCount + 2) return qb.text;
        if (qb.len >= Math.max(qa.len + 30, Math.floor(qa.len * 1.5))) return qb.text;
        return qa.text;
      };

      const baseName = path.parse(name).name;
      const sidecarCandidates = [path.join(dir, `${baseName}.lrc`), path.join(dir, `${baseName}.lyc`)];
      for (const p of sidecarCandidates) {
        try {
          const content = await fs.promises.readFile(p, 'utf8');
          const s = content ? String(content) : '';
          lyrics = pickBetterLyric(lyrics, s);
        } catch (_) {}
      }

      const looksLikeSingleLrcLine =
        lyrics &&
        !lyrics.includes('\n') &&
        /^\s*\[\d{2}:\d{2}(?:\.\d{1,3})?\]/.test(lyrics) &&
        lyrics.includes(']');

      const looksLikeOnlyCreditLine =
        lyrics &&
        !lyrics.includes('\n') &&
        lyrics.length <= 80 &&
        /(作词|作曲|编曲|制作人|演唱)\s*[:：]/.test(lyrics);

      if (!lyrics || looksLikeSingleLrcLine || (ext === '.flac' && looksLikeOnlyCreditLine)) {
        const tagReader = new MusicTagReader();
        const [tags, probe] = await Promise.all([tagReader.readAudioTags(fullPath), tagReader.probeAudio(fullPath)]);
        const built = buildMusicIndexRow({ fullPath, stat: st, tags, probe, tagReader });
        const freshLyrics = built && built.lyrics ? String(built.lyrics).trim() : '';
        const picked = pickBetterLyric(lyrics, freshLyrics);
        if (picked && picked !== lyrics) {
          lyrics = picked;
          await knex('music_index')
            .where({ id: row.id })
            .update({ lyrics: lyrics.trim(), lyrics_get_state: 1 })
            .catch(() => {});
          row = { ...row, lyrics: lyrics.trim(), lyrics_get_state: 1 };
        }
      }

      const item = {
        ...row,
        full_path: row.path && row.filename ? path.join(String(row.path), String(row.filename)) : '',
      };

      return ResponseUtil.success(req, res, { item, lyrics }, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }

  async refreshHistory(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const indexId = Number(body.index_id ?? body.indexId ?? body.id) || 0;
      const rawPath = String(body.file_path ?? body.filePath ?? body.full_path ?? body.fullPath ?? body.path ?? '').trim();

      const knex = req.dbMusic;
      let targetIndexId = 0;
      let fullPath = '';

      if (indexId > 0) {
        const pick = await knex('music_index')
          .where({ id: indexId })
          .first('id', 'path', 'filename')
          .catch(() => null);
        if (!pick || !pick.id) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
        fullPath = pick.path && pick.filename ? path.join(String(pick.path), String(pick.filename)) : '';
        if (!fullPath) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
        targetIndexId = Number(pick.id) || 0;
      } else {
        if (!rawPath) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
        fullPath = path.resolve(rawPath);
        const dir = path.dirname(fullPath);
        const name = path.basename(fullPath);
        if (!dir || !name) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
        const pick = await knex('music_index')
          .where({ path: dir, filename: name })
          .first('id')
          .catch(() => null);
        targetIndexId = Number(pick && pick.id) || 0;
        if (!targetIndexId) {
          return ResponseUtil.success(req, res, { refreshed: false }, 'common.SUCCESS', 200);
        }
      }

      const canView = await hasPermission(req.dbMain, user, ['download', 'view'], fullPath);
      if (!canView) return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);

      if (FileUtil.isProtectedPath(fullPath)) {
        return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH', 403);
      }

      let st = null;
      try {
        st = await fs.promises.stat(fullPath);
      } catch (_) {}
      if (!st || !st.isFile()) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);

      const ext = path.extname(fullPath).toLowerCase();
      if (Array.isArray(config.musicTypeList) && !config.musicTypeList.includes(ext)) {
        return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);
      }

      const now = knex.fn.now();
      const where = { uid, index_id: targetIndexId };
      const updated = await knex('music_history')
        .where(where)
        .update({
          last_listen_at: now,
          play_count: knex.raw('coalesce(play_count, 0) + 1'),
        })
        .catch(() => 0);

      if (!updated) {
        const insertRow = {
          ...where,
          last_listen_at: now,
          create_time: now,
          play_count: 1,
        };
        await knex('music_history')
          .insert(insertRow)
          .catch(async () => {
            await knex('music_history')
              .where(where)
              .update({
                last_listen_at: now,
                play_count: knex.raw('coalesce(play_count, 0) + 1'),
              })
              .catch(() => 0);
          });
      }

      return ResponseUtil.success(
        req,
        res,
        {
          refreshed: true,
          index_id: targetIndexId,
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

  async list(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new MusicListService(req.dbMusic);
      const data = await service.listPaged(body, user);
      return ResponseUtil.success(req, res, data, 'music.MUSIC_LIST_FETCH_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'music.MUSIC_LIST_FETCH_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'music.MUSIC_LIST_FETCH_FAILED' : msgKey, statusCode);
    }
  }

  async listAlbums(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new MusicListService(req.dbMusic);
      const data = await service.listKeyGroupsPaged({ ...body, key_type: 'album' }, user);
      return ResponseUtil.success(req, res, data, 'music.MUSIC_LIST_FETCH_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'music.MUSIC_LIST_FETCH_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'music.MUSIC_LIST_FETCH_FAILED' : msgKey, statusCode);
    }
  }

  async listArtists(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new MusicListService(req.dbMusic);
      const data = await service.listKeyGroupsPaged({ ...body, key_type: 'artist' }, user);
      return ResponseUtil.success(req, res, data, 'music.MUSIC_LIST_FETCH_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'music.MUSIC_LIST_FETCH_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'music.MUSIC_LIST_FETCH_FAILED' : msgKey, statusCode);
    }
  }

  async getCover(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const q = req.query || {};
      const filePath = String(q.file_path ?? q.filePath ?? '').trim();
      const size = Math.max(50, Math.min(2000, Number(q.size || 500) || 500));
      if (!filePath) return ResponseUtil.error(req, res, 'validation.VALIDATION_ERROR', 400);

      const service = new MusicListService(req.dbMusic);
      const indexRow = await service.getIndexByFilePath({ filePath });
      if (!indexRow || !indexRow.id) return ResponseUtil.error(req, res, 'common.NOT_FOUND', 404);
      const canAccess = await service.canUserAccessIndex({ user, indexRow });
      if (!canAccess) return ResponseUtil.forbidden(req, res);

      const hasCover = Number(indexRow.has_inner_cover || 0) || 0;
      if (hasCover !== 1) {
        return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);
      }

      const coverHash = indexRow.file_hash ? String(indexRow.file_hash).trim() : '';
      if (!coverHash) return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);

      const folder = typeof config.getMusicCoverCachePath === 'function' ? config.getMusicCoverCachePath() : '';
      if (!folder) return ResponseUtil.error(req, res, 'music.MUSIC_COVER_FAILED', 500);
      const basePath = path.join(folder, `${coverHash}.webp`);
      let targetPath = basePath;

      let cacheExists = false;
      try {
        const st = await fs.promises.stat(basePath);
        cacheExists = !!(st && st.isFile() && st.size > 0);
      } catch (_) {}

      if (!cacheExists) {
        const fullPath = path.join(indexRow.path || '', indexRow.filename || '');
        const regenerated = await regenerateCoverFromFile({ fullPath, fileHash: coverHash, size: 500 });
        if (!regenerated) return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);
      }

      try {
        const st = await fs.promises.stat(basePath);
        if (!st || !st.isFile() || st.size <= 0) {
          return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);
        }
      } catch (_) {
        return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);
      }

      if (size && size !== 200) {
        try {
          targetPath = await sharpUtils.genTinyFile(basePath, folder, `${coverHash}_${size}`, 'image', size);
        } catch (_) {
          targetPath = basePath;
        }
      }

      try {
        const st = await fs.promises.stat(targetPath);
        if (!st || !st.isFile() || st.size <= 0) {
          return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);
        }
      } catch (_) {
        return ResponseUtil.error(req, res, 'music.MUSIC_COVER_NOT_AVAILABLE', 404);
      }

      return await res.sendFile(targetPath);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'music.MUSIC_COVER_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'music.MUSIC_COVER_FAILED' : msgKey, statusCode);
    }
  }

  async deleteEntries(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const inputPaths = body.paths;
      const recycleRaw = body.recycle ?? false;
      const recycle = recycleRaw === true || recycleRaw === 1 || recycleRaw === '1';

      if (!Array.isArray(inputPaths) || inputPaths.length === 0) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const rawTargets = inputPaths.map(v => String(v || '').trim()).filter(Boolean);
      const targets = Array.from(new Set(rawTargets))
        .map(p => path.resolve(p))
        .filter(Boolean);

      if (targets.length === 0) {
        return ResponseUtil.error(req, res, 'common.PARAM_ERROR', 400);
      }

      const service = new MusicListService(req.dbMusic);
      const roots = await service.getValidPaths(user);
      if (!roots || roots.length === 0) {
        return ResponseUtil.error(req, res, 'music.MUSIC_SOURCE_LIST_EMPTY', 400);
      }

      const isUnderAnyRoot = (filePath, rootList) => {
        const resolved = filePath ? path.resolve(String(filePath)) : '';
        if (!resolved) return false;
        const list = Array.isArray(rootList) ? rootList.map(p => path.resolve(String(p || ''))).filter(Boolean) : [];
        for (const root of list) {
          if (resolved === root) return true;
          const prefix = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
          if (resolved.startsWith(prefix)) return true;
        }
        return false;
      };

      for (const p of targets) {
        if (FileUtil.isProtectedPath(p)) {
          return ResponseUtil.error(req, res, 'file.SYSTEM_PROTECTED_PATH');
        }
        if (!isUnderAnyRoot(p, roots)) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
        const canDelete = await hasPermission(req.dbMain, user, 'delete', p);
        if (!canDelete) {
          return ResponseUtil.error(req, res, 'auth.PERMISSION_DENIED', 403);
        }
      }

      const existedTargets = [];
      const missingTargets = [];
      for (const p of targets) {
        try {
          await fs.promises.access(p, fs.constants.F_OK);
          existedTargets.push(p);
        } catch (_) {
          missingTargets.push(p);
        }
      }

      const deletedTargets = [];
      const failedTargets = [];
      if (existedTargets.length > 0) {
        await fileService.deleteEntries(existedTargets, recycle);

        const waitUntilNotExists = async (p, timeoutMs = 3000, intervalMs = 120) => {
          const full = path.resolve(p);
          const deadline = Date.now() + timeoutMs;
          while (Date.now() < deadline) {
            try {
              await fs.promises.access(full, fs.constants.F_OK);
            } catch (_) {
              return true;
            }
            await new Promise(resolve => setTimeout(resolve, intervalMs));
          }
          try {
            await fs.promises.access(full, fs.constants.F_OK);
            return false;
          } catch (_) {
            return true;
          }
        };

        if (recycle) {
          const checks = await Promise.all(
            existedTargets.map(async p => {
              const ok = await waitUntilNotExists(p);
              return ok ? p : null;
            })
          );
          deletedTargets.push(...checks.filter(Boolean));
        } else {
          for (const p of existedTargets) {
            try {
              await fs.promises.access(path.resolve(p), fs.constants.F_OK);
              failedTargets.push(p);
            } catch (_) {
              deletedTargets.push(p);
            }
          }
        }

        if (recycle) {
          const deletedSet = new Set(deletedTargets);
          for (const p of existedTargets) {
            if (!deletedSet.has(p)) failedTargets.push(p);
          }
        }
      }

      const cleanedTargets = Array.from(new Set([...missingTargets, ...deletedTargets]));
      const affected = cleanedTargets.length > 0 ? await service.deleteIndexesByFullPaths(cleanedTargets) : 0;

      const data = {
        cleaned_paths: cleanedTargets,
        failed_paths: failedTargets,
        affected,
      };

      if (failedTargets.length > 0) {
        const key = recycle ? 'music.MUSIC_TRASH_FAILED' : 'file.DELETE_FAILED';
        return res.status(400).json({
          success: false,
          message: getLocalizedMessage(req, key),
          code: key,
          data,
        });
      }

      if (deletedTargets.length > 0) {
        await fileService.addFileLog(uid, tableFileLog.TYPE_DELETE, deletedTargets, null, tableFileLog.STATE_SUCCESS, recycle ? 'RECYCLE' : 'DELETE');
      }

      return ResponseUtil.success(req, res, data, 'file.DELETE_SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'file.DELETE_FAILED';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 400;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'file.DELETE_FAILED' : msgKey, statusCode);
    }
  }

  async count(req, res) {
    try {
      const user = req.user;
      const uid = user && user.id ? Number(user.id) : 0;
      if (!uid) return ResponseUtil.unauthorized(req, res);

      const body = req.body || {};
      const service = new MusicListService(req.dbMusic);
      const data = await service.getLibraryCounts(body, user);
      return ResponseUtil.success(req, res, data, 'common.SUCCESS', 200);
    } catch (e) {
      const msgKey = e && e.message ? e.message : 'common.ERROR';
      const statusCode = e && e.statusCode ? Number(e.statusCode) : 500;
      return ResponseUtil.error(req, res, msgKey === 'common.ERROR' ? 'common.ERROR' : msgKey, statusCode);
    }
  }
}

module.exports = new MusicListController();
