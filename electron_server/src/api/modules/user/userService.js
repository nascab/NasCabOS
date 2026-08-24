const crypto = require('crypto');
const bcrypt = require('bcrypt');
const tableUser = require('../../../db/table/tableUser');
const tableUserPermission = require('../../../db/table/tableUserPermission');
const jwtUtil = require('../../../utils/jwtUtil');
const fs = require('fs-extra');
const path = require('path');
const config = require('../../../config/config');

function _normalizeIdList(ids) {
  const list = Array.isArray(ids) ? ids : [];
  const nums = list.map(v => Number(v)).filter(v => Number.isFinite(v) && v > 0);
  return Array.from(new Set(nums));
}

function _toRows(rawResult) {
  if (Array.isArray(rawResult)) return rawResult;
  const rows = rawResult && rawResult.rows ? rawResult.rows : rawResult;
  return Array.isArray(rows) ? rows : [];
}

async function _listTables(knex) {
  const rows = await knex('sqlite_master').select('name').where({ type: 'table' }).andWhere('name', 'not like', 'sqlite_%');
  return (rows || []).map(r => (r && r.name ? String(r.name) : '')).filter(Boolean);
}

async function _getColumnNameSet(knex, tableName) {
  const safe = String(tableName || '').replace(/'/g, "''");
  const raw = await knex.raw(`PRAGMA table_info('${safe}')`).catch(() => []);
  const rows = _toRows(raw);
  return new Set((rows || []).map(r => (r && r.name ? String(r.name) : '')).filter(Boolean));
}

async function _deleteUserKeyedRecordsInDb(knex, idList) {
  const tables = await _listTables(knex);
  for (const tableName of tables) {
    if (tableName === 'user') continue;
    const colNames = await _getColumnNameSet(knex, tableName);
    const hasUid = colNames.has('uid');
    const hasUserId = colNames.has('user_id');
    if (!hasUid && !hasUserId) continue;
    await knex(tableName)
      .where(function () {
        if (hasUid) this.whereIn('uid', idList);
        if (hasUserId) {
          if (hasUid) this.orWhereIn('user_id', idList);
          else this.whereIn('user_id', idList);
        }
      })
      .delete();
  }
}

async function _deleteUserCustomWallpapers(idList) {
  const baseDir = path.resolve(config.getCustomWallpaperPath());
  const prefix = baseDir.endsWith(path.sep) ? baseDir : baseDir + path.sep;
  for (const uidNum of idList) {
    const uid = String(uidNum).trim();
    if (!uid) continue;
    const userDir = path.resolve(path.join(baseDir, uid));
    if (!(userDir === baseDir || userDir.startsWith(prefix))) {
      throw new Error('user.USER_DELETE_FAILED');
    }
    await fs.remove(userDir);
  }
}

class UserService {
  constructor(knex) {
    this.knex = knex;
  }

  async listUsers(page = 1, limit = 20, keyword = '') {
    const offset = (page - 1) * limit;
    const applyKeyword = qb => {
      const k = String(keyword || '').trim();
      if (!k) return;
      const like = `%${k}%`;
      qb.where(function () {
        this.where('username', 'like', like).orWhere('phone', 'like', like).orWhere('user_remark', 'like', like);
      });
    };

    const baseQuery = this.knex('user')
      .select('id', 'username', 'type', 'is_active', 'create_time', 'phone', 'user_remark')
      .modify(applyKeyword)
      .orderByRaw("CASE WHEN type='super_admin' THEN 0 ELSE 1 END")
      .orderBy('id', 'asc');

    const items = await baseQuery.clone().offset(offset).limit(limit);
    const [{ count }] = await this.knex('user').modify(applyKeyword).count('* as count');

    return {
      items,
      total: Number(count || 0),
      page,
      limit,
    };
  }

  async createUser(payload) {
    const { username, password, user_remark: userRemark, phone } = payload;

    const exists = await this.knex('user').where({ username }).first();
    if (exists) {
      throw new Error('user.USERNAME_EXISTS');
    }
    const passwordPlain = jwtUtil.decodeClientPassword(password);
    const encryptedPassword = jwtUtil.encryptPassword(passwordPlain);
    const placeholderAnswerSecret = crypto.randomBytes(32).toString('hex');
    const hashedAnswer = await bcrypt.hash(placeholderAnswerSecret, 10);
    const remarkTrim =
      userRemark !== undefined && userRemark !== null ? String(userRemark).trim() : '';
    const phoneTrim = phone !== undefined && phone !== null ? String(phone).trim() : '';
    const [id] = await this.knex('user').insert({
      username,
      password: encryptedPassword,
      question: 'sub_user_no_security',
      answer: hashedAnswer,
      phone: phoneTrim || null,
      user_remark: remarkTrim || null,
      type: tableUser.TYPE_USER,
      is_active: true,
      create_time: new Date(),
    });
    return { id, username, type: tableUser.TYPE_USER };
  }

  async updateUser(id, payload) {
    const data = {};
    if (payload.username) {
      const username = String(payload.username).trim();
      if (username) {
        const exists = await this.knex('user').where({ username }).andWhereNot({ id }).first();
        if (exists) {
          throw new Error('user.USERNAME_EXISTS');
        }
        data.username = username;
      }
    }
    if (typeof payload.is_active === 'boolean') data.is_active = payload.is_active;
    if (payload.password) {
      const passwordPlain = jwtUtil.decodeClientPassword(payload.password);
      data.password = jwtUtil.encryptPassword(passwordPlain);
    }
    if (payload.user_remark !== undefined) {
      const t = payload.user_remark === null ? '' : String(payload.user_remark).trim();
      data.user_remark = t || null;
    }
    if (payload.phone !== undefined) {
      const t = payload.phone === null ? '' : String(payload.phone).trim();
      data.phone = t || null;
    }
    try {
      const affected = await this.knex('user').where({ id }).update(data);
      if (!affected) throw new Error('user.USER_NOT_FOUND');
    } catch (e) {
      const msg = e && e.message ? String(e.message) : '';
      const isUsernameConstraint = e && (e.code === 'SQLITE_CONSTRAINT' || e.code === 'SQLITE_CONSTRAINT_UNIQUE') && msg.includes('user.username');
      if (isUsernameConstraint) {
        throw new Error('user.USERNAME_EXISTS');
      }
      throw e;
    }
    return true;
  }

  async deleteUsers(ids = [], dbs = null) {
    const idList = _normalizeIdList(ids);
    if (idList.length === 0) return 0;

    const rows = await this.knex('user').whereIn('id', idList).select('id', 'type');
    const protectedIds = rows.filter(r => r.type === 'super_admin').map(r => r.id);
    if (protectedIds.length > 0) {
      throw new Error('user.CANNOT_DELETE_SUPER_ADMIN');
    }

    const dbListRaw = [
      dbs && dbs.dbMain ? dbs.dbMain : null,
      dbs && dbs.dbVideo ? dbs.dbVideo : null,
      dbs && dbs.dbBook ? dbs.dbBook : null,
      dbs && dbs.dbMusic ? dbs.dbMusic : null,
      dbs && dbs.dbPhoto ? dbs.dbPhoto : null,
    ].filter(Boolean);
    const dbList = dbListRaw.length > 0 ? dbListRaw : [this.knex];

    for (const knex of dbList) {
      await _deleteUserKeyedRecordsInDb(knex, idList);
    }
    await _deleteUserCustomWallpapers(idList);

    const affected = await this.knex('user').whereIn('id', idList).delete();
    return affected;
  }

  async getUserPermissions(uid) {
    const rows = await this.knex('user_permission').where({ uid }).select('id', 'res_type', 'res_path', 'action');
    return rows;
  }

  // 返回用户有权限的路径列表
  async getUserVisiablePath(uid) {
    const rows = await this.knex('user_permission')
      .where({ uid })
      .where('res_type', tableUserPermission.RES_TYPES.FILE)
      .whereIn('action', [tableUserPermission.ACTIONS.VIEW, tableUserPermission.ACTIONS.DOWNLOAD])
      .select('res_type', 'res_path');
    return rows.map(r => r.res_path);
  }

  async setUserPermissions(uid, permissions = []) {
    const incoming = Array.isArray(permissions) ? permissions : [];
    const normalized = incoming
      .filter(p => p && p.res_path && p.action)
      .map(p => ({
        res_type: p.res_type || tableUserPermission.RES_TYPES.FILE,
        res_path: String(p.res_path).trim(),
        action: String(p.action),
      }));

    const existing = await this.knex('user_permission').where({ uid }).select('res_type', 'res_path', 'action');

    const groupByKey = list => {
      const map = new Map();
      for (const it of list) {
        const key = `${it.res_type}|${it.action}`;
        const arr = map.get(key) || [];
        arr.push(it.res_path);
        map.set(key, arr);
      }
      return map;
    };

    const existingMap = groupByKey(existing);
    const incomingMap = groupByKey(normalized);

    const resultMap = new Map();
    for (const [key, paths] of incomingMap.entries()) {
      const set = new Set(paths);
      const compact = Array.from(set);
      compact.sort((a, b) => a.length - b.length);
      const kept = [];
      for (const p of compact) {
        let covered = false;
        for (const k of kept) {
          if (p.startsWith(k)) {
            covered = true;
            break;
          }
        }
        if (!covered) kept.push(p);
      }
      const existingParents = existingMap.get(key) || [];
      for (const p of kept) {
        for (const ep of existingParents) {
          if (p !== ep && p.startsWith(ep)) {
            const err = new Error('permission.PATH_PARENT_EXISTS');
            err.args = [ep, p];
            throw err;
          }
        }
      }
      resultMap.set(key, kept);
    }

    await this.knex.transaction(async trx => {
      await trx('user_permission').where({ uid }).delete();
      const rows = [];
      for (const [key, paths] of resultMap.entries()) {
        const [res_type, action] = key.split('|');
        for (const res_path of paths) {
          rows.push({
            uid,
            res_type,
            res_path,
            action,
            create_time: new Date(),
          });
        }
      }
      if (rows.length > 0) {
        await trx('user_permission').insert(rows);
      }
    });
    return true;
  }

  async getLoginRecords(uid, page = 1, limit = 20) {
    const offset = (page - 1) * limit;
    const items = await this.knex('user_token')
      .where({ user_id: uid, type: 'login' })
      .orderBy('create_time', 'desc')
      .offset(offset)
      .limit(limit)
      .select('id', 'client_ip', 'device_info', 'browser', 'os', 'create_time', 'last_active_time', 'is_valid');
    const [{ count }] = await this.knex('user_token').where({ user_id: uid }).count('* as count');
    return { items, total: Number(count || 0), page, limit };
  }

  async findUserByUsername(username) {
    const u = String(username || '').trim();
    if (!u) return null;
    const row = await this.knex('user').where({ username: u }).first();
    if (!row) return null;
    return { id: row.id, username: row.username, type: row.type, is_active: row.is_active };
  }
}

module.exports = UserService;
