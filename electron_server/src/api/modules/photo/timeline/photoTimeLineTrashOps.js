const knexUtil = require('../../../../db/knexUtil');
const dbUtil = require('../../../../db/dbUtil');
const path = require('path');
const Logger = require('../../../../utils/logger');
const tableFileLog = require('../../../../db/table/tableFileLog');
const { hasPermission } = require('../../../../utils/permissionUtil');
const FileUtil = require('../../../../utils/fileUtil');
const userUtil = require('../../../../utils/userUtil');
const { applyPathPrefixFilter } = require('./photoPathQueryUtil');

function createTrashOps({ getKnex, getValidPaths, indexFields }) {
  async function batchTrash(ids, in_trash, user) {
    if (!ids || ids.length === 0) return;

    const knex = getKnex();
    let idsToUpdate = ids;

    if (in_trash && user && !userUtil.isAdmin(user)) {
      const mainKnex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
      const rows = await knex('photo_index').whereIn('id', ids).select('id', 'path', 'filename');
      const allowedIds = [];
      for (const row of rows) {
        const fullPath = path.join(row.path, row.filename);
        if (FileUtil.isProtectedPath(fullPath)) continue;
        const canDelete = await hasPermission(mainKnex, user, 'delete', fullPath);
        if (canDelete) allowedIds.push(row.id);
      }
      if (ids.length > 0 && allowedIds.length === 0) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
      idsToUpdate = allowedIds;
      if (idsToUpdate.length === 0) return;
    }

    const updateData = {
      in_trash: in_trash ? 1 : 0,
    };

    if (in_trash) {
      updateData.in_trash_time = new Date();
    }

    await knex('photo_index').whereIn('id', idsToUpdate).update(updateData);
  }

  async function getTrashPhotoList(params, user) {
    const validPaths = await getValidPaths(user);
    if (validPaths.length === 0) {
      return { list: [], total: 0 };
    }

    const knex = getKnex();
    const query = knex('photo_index').where('photo_index.is_file', 1).where('photo_index.in_trash', 1);

    applyPathPrefixFilter(query, 'photo_index.path', validPaths);

    if (params.search) {
      const search = String(params.search || '').trim();
      if (search) {
        query.where(builder => {
          builder.where('photo_index.path', 'like', `%${search}%`).orWhere('photo_index.filename', 'like', `%${search}%`);
        });
      }
    }

    if (params.fileType) {
      if (params.fileType === 'photo') {
        query.where('photo_index.type', 1);
      } else if (params.fileType === 'video') {
        query.where('photo_index.type', 2);
      } else if (params.fileType === 'livephoto') {
        query.where('photo_index.is_lvp', 1);
      }
    }

    const sortField = params.sortField || 'in_trash_time';
    const sortOrder = params.sortOrder === 'asc' ? 'asc' : 'desc';
    query.orderBy(`photo_index.${sortField}`, sortOrder);

    const page = params.page || 1;
    const pageSize = params.pageSize || 20;
    const offset = (page - 1) * pageSize;

    const totalQuery = query.clone();
    const total = await totalQuery.count('* as count');

    const selectFields = indexFields.map(f => `photo_index.${f}`);
    query.select([...selectFields, 'photo_index.in_trash_time']);
    query.limit(pageSize).offset(offset);

    const list = await query;
    const result = list.map(item => ({
      ...item,
      fullpath: path.join(item.path, item.filename),
    }));

    return {
      list: result,
      total: total[0].count,
    };
  }

  async function deleteFromTrash(ids, recycle = false, user, options = {}) {
    if (!ids || ids.length === 0) return;

    const knex = getKnex();
    const mainKnex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const fileService = require('../../file/core/fileService');
    const { deleteLivePhotoFile = 0, deleteRawFile = 0 } = options;

    const filesToDelete = await knex('photo_index').whereIn('id', ids).where('in_trash', 1).select('id', 'path', 'filename', 'live_filename', 'raw_filename');

    if (user && !userUtil.isAdmin(user) && filesToDelete.length > 0) {
      for (const file of filesToDelete) {
        const fullPath = path.join(file.path, file.filename);
        if (FileUtil.isProtectedPath(fullPath)) {
          const err = new Error('auth.PERMISSION_DENIED');
          err.statusCode = 403;
          throw err;
        }
        const canDelete = await hasPermission(mainKnex, user, 'delete', fullPath);
        if (!canDelete) {
          const err = new Error('auth.PERMISSION_DENIED');
          err.statusCode = 403;
          throw err;
        }
      }
    }

    const pathsToDelete = [];
    for (const file of filesToDelete) {
      const fullPath = path.join(file.path, file.filename);

      if (FileUtil.isProtectedPath(fullPath)) {
        Logger.warn(`Skipping protected file: ${fullPath}`);
        continue;
      }

      const canDelete = await hasPermission(mainKnex, user, 'delete', fullPath);
      if (!canDelete) {
        Logger.warn(`Skipping file due to permission: ${fullPath}`);
        continue;
      }

      pathsToDelete.push(fullPath);

      if (deleteLivePhotoFile && file.live_filename) {
        const liveFullPath = path.join(file.path, file.live_filename);
        if (!FileUtil.isProtectedPath(liveFullPath) && (await hasPermission(mainKnex, user, 'delete', liveFullPath))) {
          pathsToDelete.push(liveFullPath);
        }
      }

      if (deleteRawFile && file.raw_filename) {
        const rawFullPath = path.join(file.path, file.raw_filename);
        if (!FileUtil.isProtectedPath(rawFullPath) && (await hasPermission(mainKnex, user, 'delete', rawFullPath))) {
          pathsToDelete.push(rawFullPath);
        }
      }
    }

    await knex('photo_index').whereIn('id', ids).where('in_trash', 1).del();

    if (pathsToDelete.length > 0) {
      await fileService.deleteEntries(pathsToDelete, recycle);

      const uid = user && user.id;
      await fileService.addFileLog(uid, tableFileLog.TYPE_DELETE, pathsToDelete, null, tableFileLog.STATE_SUCCESS, recycle ? 'RECYCLE' : 'DELETE');
    }
  }

  async function restoreFromTrash(ids) {
    if (!ids || ids.length === 0) return;

    const knex = getKnex();

    await knex('photo_index').whereIn('id', ids).where('in_trash', 1).update({
      in_trash: 0,
      in_trash_time: null,
    });
  }

  async function restoreAllFromTrash(user) {
    const validPaths = await getValidPaths(user);
    if (validPaths.length === 0) return;

    const knex = getKnex();
    const query = knex('photo_index').where('is_file', 1).where('in_trash', 1);
    applyPathPrefixFilter(query, 'path', validPaths);

    await query.update({
      in_trash: 0,
      in_trash_time: null,
    });
  }

  async function emptyTrash(user, recycle = false, options = {}) {
    const validPaths = await getValidPaths(user);
    if (validPaths.length === 0) return;

    const knex = getKnex();
    const mainKnex = knexUtil.getInstance(dbUtil.DB_PATHS.MAIN_DB);
    const fileService = require('../../file/core/fileService');
    const { deleteLivePhotoFile = 0, deleteRawFile = 0 } = options;

    const query = knex('photo_index').where('is_file', 1).where('in_trash', 1);
    applyPathPrefixFilter(query, 'path', validPaths);

    const filesToDelete = await query.select('path', 'filename', 'live_filename', 'raw_filename');

    const pathsToDelete = [];
    for (const file of filesToDelete) {
      const fullPath = path.join(file.path, file.filename);

      if (FileUtil.isProtectedPath(fullPath)) {
        Logger.warn(`Skipping protected file: ${fullPath}`);
        continue;
      }

      const canDelete = await hasPermission(mainKnex, user, 'delete', fullPath);
      if (!canDelete) {
        Logger.warn(`Skipping file due to permission: ${fullPath}`);
        continue;
      }

      pathsToDelete.push(fullPath);

      if (deleteLivePhotoFile && file.live_filename) {
        const liveFullPath = path.join(file.path, file.live_filename);
        if (!FileUtil.isProtectedPath(liveFullPath) && (await hasPermission(mainKnex, user, 'delete', liveFullPath))) {
          pathsToDelete.push(liveFullPath);
        }
      }

      if (deleteRawFile && file.raw_filename) {
        const rawFullPath = path.join(file.path, file.raw_filename);
        if (!FileUtil.isProtectedPath(rawFullPath) && (await hasPermission(mainKnex, user, 'delete', rawFullPath))) {
          pathsToDelete.push(rawFullPath);
        }
      }
    }

    if (user && !userUtil.isAdmin(user) && filesToDelete.length > 0 && pathsToDelete.length === 0) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    await query.del();

    if (pathsToDelete.length > 0) {
      await fileService.deleteEntries(pathsToDelete, recycle);

      const uid = user && user.id;
      await fileService.addFileLog(uid, tableFileLog.TYPE_DELETE, pathsToDelete, null, tableFileLog.STATE_SUCCESS, recycle ? 'RECYCLE' : 'DELETE');
    }
  }

  return {
    batchTrash,
    getTrashPhotoList,
    deleteFromTrash,
    restoreFromTrash,
    restoreAllFromTrash,
    emptyTrash,
  };
}

module.exports = { createTrashOps };
