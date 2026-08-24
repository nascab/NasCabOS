const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const config = require('../../../../config/config');
const sharpUtils = require('../../../../utils/sharpUtils');
const dbUtil = require('../../../../db/dbUtil');
const knexUtil = require('../../../../db/knexUtil');
const tableFileLog = require('../../../../db/table/tableFileLog');
const { isSlowIoPathForTiny } = require('../../../../utils/slowIoPathUtil');

class FileService {
  _buildListPayload(base, items) {
    const sep = path.sep;
    const segments = base ? this._buildSegments(base) : [];
    return { base, items, segments, sep };
  }

  async _pathToItem(fullPath, opts = {}) {
    const resolved = path.resolve(fullPath);
    const includeExists = !!opts.includeExists;
    const isDirHint = typeof opts.isDirHint === 'boolean' ? opts.isDirHint : null;
    const nameHint = typeof opts.name === 'string' ? opts.name : null;

    let exists = false;
    let size = null;
    let mtimeMs = null;
    let isDir = isDirHint !== null ? isDirHint : true;

    try {
      const st = await fs.promises.stat(resolved);
      exists = true;
      isDir = st.isDirectory();
      mtimeMs = st.mtimeMs;
      size = isDir ? null : st.size;
    } catch (_) {}

    let name = nameHint || path.basename(resolved) || resolved;
    if (process.platform === 'win32') {
      const m = resolved.match(/^([A-Za-z]:)[\\/]*$/);
      if (m) name = m[1];
    }

    const ext = isDir ? '' : path.extname(resolved).toLowerCase();
    const type = isDir ? 'dir' : config.getFileType(ext);

    const item = { name, path: resolved, type, size, mtimeMs, ext };
    if (includeExists) item.exists = exists;
    return item;
  }

  async _ensureWritableForDelete(targetPath) {
    let st;
    try {
      st = await fs.promises.lstat(targetPath);
    } catch (_) {
      return;
    }

    if (st.isSymbolicLink()) return;

    if (st.isDirectory()) {
      let entries = [];
      try {
        entries = await fs.promises.readdir(targetPath, { withFileTypes: true });
      } catch (_) {
        entries = [];
      }
      for (const ent of entries) {
        const child = path.join(targetPath, ent.name);
        await this._ensureWritableForDelete(child);
      }
      try {
        await fs.promises.chmod(targetPath, 0o700);
      } catch (_) {}
      return;
    }

    try {
      await fs.promises.chmod(targetPath, 0o600);
    } catch (_) {}
  }

  async _deletePath(fullPath) {
    const st = await fs.promises.lstat(fullPath);
    const remove = async () => {
      if (st.isDirectory()) {
        await fs.promises.rm(fullPath, { recursive: true, force: true });
      } else {
        await fs.promises.unlink(fullPath);
      }
    };

    try {
      await remove();
    } catch (err) {
      const code = err && err.code ? String(err.code) : '';
      if (code !== 'EACCES' && code !== 'EPERM') throw err;
      await this._ensureWritableForDelete(fullPath);
      await remove();
    }
  }

  async getRoots() {
    const isWin = process.platform === 'win32';
    if (isWin) {
      const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');
      const roots = [];
      for (const l of letters) {
        const p = `${l}:\\`;
        try {
          if (fs.existsSync(p)) {
            let mtimeMs = null;
            try {
              const st = await fs.promises.stat(p);
              mtimeMs = st.mtimeMs;
            } catch (_) {}
            roots.push({ path: p, name: `${l}:`, type: 'dir', size: null, mtimeMs, ext: '' });
          }
        } catch (_) {}
      }
      return roots;
    }
    const candidates = ['/', '/Users', '/Volumes'];
    const exist = candidates.filter(p => {
      try {
        return fs.existsSync(p);
      } catch {
        return false;
      }
    });
    const result = [];
    for (const p of exist) {
      let mtimeMs = null;
      try {
        const st = await fs.promises.stat(p);
        mtimeMs = st.mtimeMs;
      } catch (_) {}
      result.push({
        path: p,
        name: path.basename(p) || p,
        type: 'dir',
        size: null,
        mtimeMs,
        ext: '',
      });
    }
    return result;
  }

  async listDirectory(dirPath, onlyDir = true, includeHidden = false) {
    if (!dirPath) throw new Error('file.INVALID_PATH');
    let resolved = path.resolve(dirPath);
    const st = await fs.promises.stat(resolved);
    if (st.isFile()) {
      resolved = path.dirname(resolved);
    }
    const entries = await fs.promises.readdir(resolved, { withFileTypes: true });
    const items = (
      await Promise.all(
        entries.map(ent =>
          this._pathToItem(path.join(resolved, ent.name), {
            name: ent.name,
            isDirHint: !ent.isFile(),
          })
        )
      )
    )
      .filter(i => (onlyDir ? i.type === 'dir' : true))
      .filter(i => {
        if (includeHidden) return true;
        const n = i.name || '';
        return !n.startsWith('.');
      });
    return this._buildListPayload(resolved, items);
  }

  async listPathList(pathList, onlyDir = true, includeHidden = false, base = '') {
    const input = Array.isArray(pathList) ? pathList : [];
    const unique = new Map();
    for (const p of input) {
      if (typeof p !== 'string') continue;
      const trimmed = p.trim();
      if (!trimmed) continue;
      const resolved = path.resolve(trimmed);
      unique.set(resolved, true);
    }

    const items = await Promise.all(Array.from(unique.keys()).map(p => this._pathToItem(p, { includeExists: true })));

    const filtered = items
      .filter(i => (onlyDir ? i.type === 'dir' : true))
      .filter(i => {
        if (includeHidden) return true;
        const n = i.name || '';
        return !n.startsWith('.');
      })
      .sort((a, b) => String(a.name || '').localeCompare(String(b.name || '')));

    const baseResolved = typeof base === 'string' && base.trim() ? path.resolve(base) : '';
    return this._buildListPayload(baseResolved, filtered);
  }

  _buildSegments(resolved) {
    const sep = path.sep;
    const isWin = process.platform === 'win32';
    const segs = [];
    if (isWin) {
      const m = resolved.match(/^([A-Za-z]:)(\\|\/)/);
      let acc = '';
      if (m) {
        acc = `${m[1]}${sep}`;
        segs.push({ name: m[1], path: acc });
      }
      const rest = resolved.replace(m ? m[0] : '', '');
      const parts = rest.split(/\\|\//).filter(Boolean);
      for (const part of parts) {
        acc = path.join(acc || '', part);
        segs.push({ name: part, path: acc });
      }
      return segs;
    } else {
      let acc = sep;
      segs.push({ name: sep, path: sep });
      const parts = resolved.split(sep).filter(Boolean);
      for (const part of parts) {
        acc = path.join(acc, part);
        segs.push({ name: part, path: acc });
      }
      return segs;
    }
  }

  getScrapeSidecarPathsForFilePath(p) {
    const raw = typeof p === 'string' ? p.trim() : '';
    if (!raw) return [];
    const ext = path.extname(raw);
    if (!ext) return [];

    const dir = path.dirname(raw);
    const baseName = path.parse(raw).name;
    if (!dir || !baseName) return [];

    return [
      path.join(dir, `${baseName}.nfo`),
      path.join(dir, `${baseName}.jpg`),
      path.join(dir, `${baseName}-logo.png`),
      path.join(dir, `${baseName}-poster.nfo`),
      path.join(dir, `${baseName}-post.jpg`),
      path.join(dir, `${baseName}-poster.jpg`),
      path.join(dir, `${baseName}-fanart.jpg`),
      path.join(dir, `${baseName}-fanart.png`),
    ];
  }

  mergeUniquePaths(paths) {
    const out = [];
    const seen = new Set();
    for (const p of paths || []) {
      const v = typeof p === 'string' ? p.trim() : '';
      if (!v) continue;
      const key = path.resolve(v);
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(v);
    }
    return out;
  }

  async mkdir(base, name) {
    const target = path.resolve(base, name);
    await fs.promises.mkdir(target, { recursive: true });
  }

  async createFile(base, name, content = '') {
    if (!base) throw new Error('file.INVALID_PATH');
    if (!name || name.trim() === '') throw new Error('file.INVALID_PATH');

    const resolvedBase = path.resolve(base);
    const resolvedPath = path.resolve(resolvedBase, name);

    try {
      await fs.promises.writeFile(resolvedPath, String(content || ''), { flag: 'wx' });
    } catch (e) {
      if (e && e.code === 'EEXIST') {
        throw new Error('file.PATH_ALREADY_EXISTS');
      }
      throw e;
    }

    const st = await fs.promises.stat(resolvedPath);
    const ext = path.extname(resolvedPath).toLowerCase();
    const type = config.getFileType(ext);

    return {
      name: path.basename(resolvedPath) || resolvedPath,
      path: resolvedPath,
      type,
      size: st && typeof st.size === 'number' ? st.size : null,
      mtimeMs: st && typeof st.mtimeMs === 'number' ? st.mtimeMs : null,
      ext,
    };
  }

  async deleteEntries(paths, recycle = false) {
    const exists = async p => {
      try {
        await fs.promises.access(p, fs.constants.F_OK);
        return true;
      } catch {
        return false;
      }
    };

    if (recycle) {
      if (process.send) {
        await Promise.all(
          paths.map(async p => {
            const full = path.resolve(p);
            if (await exists(full)) {
              process.send({
                type: 'shell',
                shellType: 'trash',
                path: full,
              });
            }
          })
        );
      } else {
        await this.deleteEntries(paths, false);
      }
    } else {
      for (const p of paths) {
        const full = path.resolve(p);
        if (!(await exists(full))) continue;
        await this._deletePath(full);
      }
    }
  }

  async listFavoritesByUid(knex, uid) {
    const rows = await knex('file_favorite').where({ uid }).select('path', 'create_time');
    const items = [];
    for (const r of rows) {
      const p = r.path;
      let st = null;
      try {
        st = await fs.promises.stat(p);
        let isDir = !st.isFile();
        const size = st && !isDir ? st.size : null;
        const mtimeMs = st ? st.mtimeMs : null;
        const ext = isDir ? '' : path.extname(p).toLowerCase();
        const type = config.getFileType(ext);
        items.push({
          path: p,
          name: path.basename(p) || p,
          type: isDir ? 'dir' : type,
          size,
          mtimeMs,
          ext,
        });
      } catch (_) {
        await knex('file_favorite').where({ uid, path: p }).del();
      }
    }
    return items;
  }

  async addFavoriteByUid(knex, uid, p) {
    await knex('file_favorite').insert({ uid, path: p }).onConflict(['uid', 'path']).ignore();
  }

  async removeFavoriteByUid(knex, uid, p) {
    await knex('file_favorite').where({ uid, path: p }).del();
  }

  _deferTinyToWorker(resolvedPath) {
    Promise.resolve()
      .then(async () => {
        try {
          if (!knexUtil.hasConnection(dbUtil.DB_PATHS.PHOTO_DB)) {
            await knexUtil.init(dbUtil.DB_PATHS.PHOTO_DB);
          }
          const knex = knexUtil.getInstance(dbUtil.DB_PATHS.PHOTO_DB);
          await knex('wait_gen_tiny').insert({ source_path: resolvedPath }).onConflict('source_path').ignore();
        } catch (_) {}
      })
      .catch(() => {});

    if (typeof process.send === 'function') {
      try {
        process.send({ type: 'ensureTinyImageWorker' });
      } catch (_) {}
    }

    throw new Error('file.TINY_PENDING');
  }

  async getTinyImgByPath(fullPath, size, opts = {}) {
    const resolvedPath = path.resolve(fullPath);

    let stat;
    try {
      stat = await fs.promises.stat(resolvedPath);
    } catch (e) {
      throw new Error('file.NOT_FOUND');
    }

    if (!stat.isFile()) {
      console.log(resolvedPath);
      throw new Error('file.NOT_FILE');
    }

    const hashStr = path.basename(resolvedPath) + stat.size + stat.mtimeMs;
    const hash = crypto.createHash('sha256').update(hashStr).digest('hex');

    const cachePath = config.getTinyCachePath();
    const targetTinyPath = path.join(cachePath, hash) + '.webp';

    try {
      const cacheStat = await fs.promises.stat(targetTinyPath);
      if (cacheStat.isFile() && cacheStat.size > 0) {
        return targetTinyPath;
      }
    } catch (e) {}

    const ext = path.extname(resolvedPath).toLowerCase();
    let type = null;

    const imgTypeList = config.imgTypeList;
    const rawImgTypeList = config.rawImgTypeList;
    const videoTypeList = config.videoTypeList;

    if (imgTypeList.includes(ext) || rawImgTypeList.includes(ext)) {
      type = 'image';
    } else if (videoTypeList.includes(ext)) {
      type = 'video';
    }

    if (!type) {
      throw new Error(`file.UNSUPPORTED_TYPE:${ext}`);
    }

    const deferLargeVideo = typeof opts?.deferLargeVideo === 'boolean' ? opts.deferLargeVideo : true;
    if (deferLargeVideo && type === 'video' && Number(stat.size || 0) > 100 * 1024 * 1024) {
      this._deferTinyToWorker(resolvedPath);
    }

    const deferSlowIo = typeof opts?.deferSlowIo === 'boolean' ? opts.deferSlowIo : true;
    if (deferSlowIo && (await isSlowIoPathForTiny(resolvedPath))) {
      this._deferTinyToWorker(resolvedPath);
    }

    await sharpUtils.genTinyFile(resolvedPath, cachePath, hash, type, size);

    return targetTinyPath;
  }

  async addFileLog(uid, type, sourcePath, targetPath, state, message = '') {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    await knex('file_log').insert({
      uid,
      type,
      source_path: JSON.stringify(sourcePath),
      target_path: targetPath,
      state: state,
      message: message,
      create_time: new Date(),
    });
  }

  async getFileLogs(uid, types, page = 1, pageSize = 20, stateList = null, keyword = null) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    let query = knex('file_log').where('uid', uid);

    if (types && Array.isArray(types) && types.length > 0) {
      query = query.whereIn('type', types);
    }

    if (stateList && Array.isArray(stateList) && stateList.length > 0) {
      query = query.whereIn('state', stateList);
    }

    if (keyword && typeof keyword === 'string' && keyword.trim() !== '') {
      const k = `%${keyword.trim()}%`;
      query = query.andWhere(function () {
        this.where('source_path', 'like', k).orWhere('target_path', 'like', k).orWhere('message', 'like', k);
      });
    }

    const countQuery = query.clone().count('id as total');
    const totalResult = await countQuery;
    const total = totalResult[0].total || 0;

    const rows = await query
      .orderBy('create_time', 'desc')
      .limit(pageSize)
      .offset((page - 1) * pageSize);

    return {
      list: rows,
      total,
      page,
      pageSize,
    };
  }

  async clearFileLogs(uid, stateList) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    let query = knex('file_log').where('uid', uid);

    if (stateList && Array.isArray(stateList) && stateList.length > 0) {
      query = query.whereIn('state', stateList);
    } else {
    }

    await query.del();
  }

  async checkTargetConflict(sourcePaths, targetDir) {
    if (!sourcePaths || !Array.isArray(sourcePaths) || !targetDir) return;
    try {
      await fs.promises.access(targetDir, fs.constants.F_OK);
    } catch {
      return;
    }

    for (const src of sourcePaths) {
      const basename = path.basename(src);
      const dest = path.join(targetDir, basename);
      try {
        await fs.promises.access(dest, fs.constants.F_OK);
        throw new Error(`${basename}`);
      } catch (err) {
        if (err.message.startsWith(`${basename}`)) {
          throw err;
        }
      }
    }
  }

  checkSourceContainTarget(sourcePaths, targetDir) {
    if (!sourcePaths || !Array.isArray(sourcePaths) || !targetDir) return;
    const target = path.resolve(targetDir);
    for (const src of sourcePaths) {
      const source = path.resolve(src);
      if (target === source) {
        throw new Error(`file.TARGET_IS_SOURCE`);
      }
      const relative = path.relative(source, target);
      if (relative && !relative.startsWith('..') && !path.isAbsolute(relative)) {
        throw new Error(`file.TARGET_IS_SUBDIRECTORY`);
      }
    }
  }

  /**
   * 取消文件操作任务
   * @param {string} operatorUid - 操作者用户 ID
   * @param {string|number} id - 任务 ID
   * @param {{ allowAnyUser?: boolean }} [opts] - allowAnyUser 为 true 时（管理员）可取消任意用户的任务
   */
  async cancelFileLog(operatorUid, id, opts = {}) {
    const knex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const where = opts.allowAnyUser ? { id } : { id, uid: operatorUid };
    const row = await knex('file_log').where(where).first();
    if (!row) throw new Error('file.LOG_NOT_FOUND');

    if (row.state === tableFileLog.STATE_WAIT || row.state === tableFileLog.STATE_PROCESSING) {
      await knex('file_log').where({ id }).update({ state: tableFileLog.STATE_CANCELLED, message: 'Cancelled by user' });
    } else {
      throw new Error('file.LOG_CANNOT_CANCEL');
    }
  }

  async rename(oldPath, newName) {
    if (!oldPath) throw new Error('file.INVALID_PATH');
    if (!newName || newName.trim() === '') throw new Error('file.INVALID_PATH');

    const resolvedOldPath = path.resolve(oldPath);
    const dir = path.dirname(resolvedOldPath);
    const resolvedNewPath = path.join(dir, newName);

    try {
      await fs.promises.access(resolvedNewPath, fs.constants.F_OK);
      throw new Error('file.PATH_ALREADY_EXISTS');
    } catch (e) {
      if (e.code !== 'ENOENT') {
        throw e;
      }
    }

    await fs.promises.rename(resolvedOldPath, resolvedNewPath);

    const st = await fs.promises.stat(resolvedNewPath);
    const isDir = st.isDirectory();
    const ext = isDir ? '' : path.extname(newName).toLowerCase();
    const type = isDir ? 'dir' : config.getFileType(ext);

    return {
      name: newName,
      path: resolvedNewPath,
      type,
      size: isDir ? null : st.size,
      mtimeMs: st.mtimeMs,
      ext,
    };
  }
}

module.exports = new FileService();
