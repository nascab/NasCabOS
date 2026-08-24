const jwtUtil = require('../../../utils/jwtUtil');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');
const { hasPermission } = require('../../../utils/permissionUtil');
const {
  folderSignString,
  folderSignFileName,
  configFolderName,
  encryptString,
  decryptString,
  resolveSpacePwdForSign,
  ensureSpaceFolderIsEmpty,
  ensureSpaceConfigFolders,
  getIndexDb,
  ensureIndexDbSchema,
} = require('./encryptedSpaceFileUtil');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

class EncryptedSpaceService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    this.tableName = 'encrypted_space';
    this.tokenTableName = 'encrypted_space_token';
    this.exportTableName = 'encrypted_space_export';
  }

  /**
   * 获取空间列表。管理员只返回自己创建的；普通用户只返回其有路径读取权限（view）的空间。
   */
  async list({ uid, isAdmin = false, user }) {
    const uidStr = ensureString(uid).trim();
    if (!uidStr) {
      const err = new Error('auth.AUTHENTICATION_REQUIRED');
      err.statusCode = 401;
      throw err;
    }

    const baseQuery = this.knexMain(this.tableName)
      .select('id', 'uid', 'space_name', 'folder_path', 'create_time', 'update_time')
      .orderBy('id', 'desc');

    if (isAdmin) {
      return await baseQuery.where({ uid: uidStr });
    }

    const rows = await baseQuery;
    if (!user) {
      return rows.filter(r => String(r.uid || '').trim() === uidStr);
    }

    const allowed = [];
    for (const row of rows) {
      const folderPath = typeof row.folder_path === 'string' ? row.folder_path.trim() : '';
      if (!folderPath) continue;
      const ok = await hasPermission(this.knexMain, user, 'view', folderPath);
      if (ok) allowed.push(row);
    }
    return allowed;
  }

  async addSpace({ uid, folderPath, spaceName, spacePwd }) {
    const uidStr = ensureString(uid).trim();
    const folderPathStr = ensureString(folderPath).trim();
    const spaceNameStr = ensureString(spaceName).trim();
    const pwdRaw = ensureString(spacePwd).trim();

    if (!uidStr || !folderPathStr || !spaceNameStr || !pwdRaw) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    const decodedPwd = jwtUtil.decodeClientPassword(pwdRaw);
    const encryptedPwd = jwtUtil.encryptPassword(decodedPwd);

    const now = new Date();
    try {
      await fs.promises.access(folderPathStr, fs.constants.R_OK | fs.constants.W_OK);
      await ensureSpaceFolderIsEmpty(folderPathStr);

      const existingName = await this.knexMain(this.tableName)
        .where({ uid: uidStr, space_name: spaceNameStr })
        .first();
      if (existingName) {
        const err = new Error('file_custom_path_name_exists');
        err.statusCode = 409;
        throw err;
      }

      const existingPath = await this.knexMain(this.tableName)
        .where({ uid: uidStr, folder_path: folderPathStr })
        .first();
      if (existingPath) {
        const err = new Error('file_custom_path_path_exists');
        err.statusCode = 409;
        throw err;
      }

      await ensureSpaceConfigFolders(folderPathStr);
      const privateIndexDb = getIndexDb(folderPathStr);
      ensureIndexDbSchema(privateIndexDb);

      const encryptedSign = await encryptString(decodedPwd, folderSignString);
      const signFilePath = path.join(folderPathStr, configFolderName, folderSignFileName);
      await fs.promises.writeFile(signFilePath, encryptedSign, 'utf8');

      const [newId] = await this.knexMain(this.tableName).insert({
        uid: uidStr,
        space_name: spaceNameStr,
        folder_path: folderPathStr,
        space_pwd: encryptedPwd,
        create_time: now,
        update_time: now,
      });
      return { id: newId };
    } catch (e) {
      const msg = e && e.message ? String(e.message) : '';
      if (msg.includes('SQLITE_CONSTRAINT')) {
        const err = new Error(
          msg.includes('space_name') ? 'file_custom_path_name_exists' : 'file_custom_path_path_exists',
        );
        err.statusCode = 409;
        throw err;
      }
      if (e && (e.code === 'EACCES' || e.code === 'EPERM')) {
        const err = new Error('auth.PERMISSION_DENIED');
        err.statusCode = 403;
        throw err;
      }
      throw e;
    }
  }

  async checkPwd({ uid, spaceId, spacePwd, isAdmin = false }) {
    const uidStr = ensureString(uid).trim();
    const idNum = Number(spaceId);
    const pwdRaw = ensureString(spacePwd).trim();

    if (!uidStr || !Number.isFinite(idNum) || idNum <= 0 || !pwdRaw) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    const row = await this.knexMain(this.tableName).where({ id: idNum }).first();

    if (!row) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    if (!isAdmin && String(row.uid || '').trim() !== uidStr) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const decodedPwd = jwtUtil.decodeClientPassword(pwdRaw);
    const signFilePath = path.join(String(row.folder_path || ''), configFolderName, folderSignFileName);
    const signExists = await fs.promises
      .stat(signFilePath)
      .then(st => (st && st.isFile() ? true : false))
      .catch(() => false);
    if (signExists) {
      const content = await fs.promises.readFile(signFilePath, 'utf8');
      const resolvedPwd = await resolveSpacePwdForSign(decodedPwd, content);
      if (!resolvedPwd) {
        const err = new Error('encryptedSpace.PASSWORD_INCORRECT');
        err.statusCode = 403;
        throw err;
      }
    } else {
      const ok = await jwtUtil.verifyPassword(decodedPwd, row.space_pwd);
      if (!ok) {
        const err = new Error('common.FAILED');
        err.statusCode = 403;
        throw err;
      }
    }

    const token = uuidv4();
    const now = new Date();
    await this.knexMain(this.tokenTableName)
      .insert({
        uid: uidStr,
        space_id: row.id,
        token,
        space_pwd: jwtUtil.encryptPassword(decodedPwd),
        create_time: now,
        update_time: now,
      })
      .onConflict(['uid', 'space_id'])
      .merge({ token, space_pwd: jwtUtil.encryptPassword(decodedPwd), update_time: now });

    return {
      id: row.id,
      uid: row.uid,
      space_name: row.space_name,
      folder_path: row.folder_path,
      token,
    };
  }

  async checkToken({ uid, token }) {
    const uidStr = ensureString(uid).trim();
    const tokenStr = ensureString(token).trim();
    if (!uidStr || !tokenStr) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    const tokenRow = await this.knexMain(this.tokenTableName).where({ uid: uidStr, token: tokenStr }).first();
    if (!tokenRow) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const spaceRow = await this.knexMain(this.tableName).where({ id: tokenRow.space_id }).first();
    if (!spaceRow) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    return {
      id: spaceRow.id,
      uid: spaceRow.uid,
      space_name: spaceRow.space_name,
      folder_path: spaceRow.folder_path,
      token: tokenRow.token,
    };
  }

  async getPwdFromToken({ uid, spaceId, token }) {
    const uidStr = ensureString(uid).trim();
    const tokenStr = ensureString(token).trim();
    const idNum = Number(spaceId);
    if (!uidStr || !tokenStr || !Number.isFinite(idNum) || idNum <= 0) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    const tokenRow = await this.knexMain(this.tokenTableName).where({ uid: uidStr, token: tokenStr, space_id: idNum }).first();
    if (!tokenRow) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    const pwd = jwtUtil.decryptPassword(tokenRow.space_pwd);
    if (!pwd) {
      const err = new Error('common.FAILED');
      err.statusCode = 403;
      throw err;
    }
    const spaceRow = await this.knexMain(this.tableName).where({ id: idNum }).first();
    if (!spaceRow) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    return { spaceRow, pwd };
  }

  async deleteToken({ uid, spaceId }) {
    const uidStr = ensureString(uid).trim();
    const idNum = Number(spaceId);
    if (!uidStr || !Number.isFinite(idNum) || idNum <= 0) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    await this.knexMain(this.tokenTableName).where({ uid: uidStr, space_id: idNum }).delete();
    return { ok: true };
  }

  async listExportTasks({ uid, isAdmin = false }) {
    const uidNum = Number(uid);
    if (!Number.isFinite(uidNum) || uidNum <= 0) {
      const err = new Error('auth.AUTHENTICATION_REQUIRED');
      err.statusCode = 401;
      throw err;
    }

    const base = this.knexMain(this.exportTableName)
      .select(
        'id',
        'uid',
        'space_id',
        'space_path',
        'target_path',
        'status',
        'last_error',
        'progress',
        'total_files',
        'done_files',
        'handled_input_bytes',
        'handled_output_bytes',
        'processed_count',
        'skipped_count',
        'create_time',
        'update_time',
        'last_start_time',
        'last_end_time'
      )
      .orderBy('update_time', 'desc')
      .orderBy('id', 'desc');

    const rows = isAdmin ? await base : await base.where({ uid: uidNum });
    return rows || [];
  }

  async addExportTask({ uid, spaceId, spacePwd, targetPath, isAdmin = false }) {
    const uidNum = Number(uid);
    const idNum = Number(spaceId);
    const pwdRaw = ensureString(spacePwd).trim();
    const targetPathRaw = ensureString(targetPath).trim();

    if (!Number.isFinite(uidNum) || uidNum <= 0 || !Number.isFinite(idNum) || idNum <= 0 || !pwdRaw || !targetPathRaw) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    const spaceRow = await this.knexMain(this.tableName).where({ id: idNum }).first();
    if (!spaceRow) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }

    const ownerUid = String(spaceRow.uid || '').trim();
    if (!isAdmin && ownerUid !== String(uidNum)) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    const decodedPwd = jwtUtil.decodeClientPassword(pwdRaw);
    const signFilePath = path.join(String(spaceRow.folder_path || ''), configFolderName, folderSignFileName);
    const signExists = await fs.promises
      .stat(signFilePath)
      .then(st => (st && st.isFile() ? true : false))
      .catch(() => false);

    if (signExists) {
      const content = await fs.promises.readFile(signFilePath, 'utf8').catch(() => '');
      const resolvedPwd = await resolveSpacePwdForSign(decodedPwd, content);
      if (!resolvedPwd) {
        const err = new Error('encryptedSpace.PASSWORD_INCORRECT');
        err.statusCode = 403;
        throw err;
      }
    } else {
      const ok = await jwtUtil.verifyPassword(decodedPwd, spaceRow.space_pwd);
      if (!ok) {
        const err = new Error('encryptedSpace.PASSWORD_INCORRECT');
        err.statusCode = 403;
        throw err;
      }
    }

    const resolvedSpacePath = path.resolve(String(spaceRow.folder_path || '').trim());
    const resolvedTargetPath = path.resolve(targetPathRaw);
    if (!resolvedSpacePath) {
      const err = new Error('common.NOT_FOUND');
      err.statusCode = 404;
      throw err;
    }
    if (resolvedTargetPath === resolvedSpacePath) {
      const err = new Error('file.TARGET_IS_SOURCE');
      err.statusCode = 400;
      throw err;
    }
    if (resolvedTargetPath.startsWith(resolvedSpacePath.endsWith(path.sep) ? resolvedSpacePath : resolvedSpacePath + path.sep)) {
      const err = new Error('file.TARGET_IS_SUBDIRECTORY');
      err.statusCode = 400;
      throw err;
    }

    await fs.promises.mkdir(resolvedTargetPath, { recursive: true });
    await ensureSpaceFolderIsEmpty(resolvedTargetPath);

    const now = new Date();
    const [newId] = await this.knexMain(this.exportTableName).insert({
      uid: uidNum,
      space_id: idNum,
      space_path: resolvedSpacePath,
      target_path: resolvedTargetPath,
      status: 'pending',
      last_error: null,
      progress: '',
      total_files: 0,
      done_files: 0,
      handled_input_bytes: 0,
      handled_output_bytes: 0,
      processed_count: 0,
      skipped_count: 0,
      create_time: now,
      update_time: now,
      last_start_time: null,
      last_end_time: null,
    });

    return { id: Number(newId) };
  }

  async deleteExportTask({ uid, id, isAdmin = false }) {
    const uidNum = Number(uid);
    const idNum = Number(id);
    if (!Number.isFinite(uidNum) || uidNum <= 0 || !Number.isFinite(idNum) || idNum <= 0) {
      const err = new Error('file.INVALID_PARAMS');
      err.statusCode = 400;
      throw err;
    }

    const row = await this.knexMain(this.exportTableName).where({ id: idNum }).first();
    if (!row) return { deleted: true };

    if (!isAdmin && Number(row.uid) !== uidNum) {
      const err = new Error('auth.PERMISSION_DENIED');
      err.statusCode = 403;
      throw err;
    }

    await this.knexMain(this.exportTableName).where({ id: idNum }).delete();
    return { deleted: true };
  }

  async clearFinishedExportTasks({ uid, isAdmin = false }) {
    const uidNum = Number(uid);
    if (!Number.isFinite(uidNum) || uidNum <= 0) {
      const err = new Error('auth.AUTHENTICATION_REQUIRED');
      err.statusCode = 401;
      throw err;
    }

    const base = this.knexMain(this.exportTableName).whereIn('status', ['success', 'error']);
    const query = isAdmin ? base : base.andWhere({ uid: uidNum });
    const affected = await query.delete();
    return { deletedCount: Number(affected || 0) };
  }
}

module.exports = { EncryptedSpaceService };
