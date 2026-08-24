const crypto = require('crypto');
const path = require('path');

function _toInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

function _hashPwd(pwd) {
  const raw = typeof pwd === 'string' ? pwd : pwd == null ? '' : String(pwd);
  const trimmed = raw.trim();
  if (!trimmed) return null;
  return trimmed;
}

function _genToken(length = 8) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  const n = Math.min(32, Math.max(1, Number(length) || 8));
  for (let i = 0; i < n; i++) {
    const idx = typeof crypto.randomInt === 'function' ? crypto.randomInt(0, alphabet.length) : crypto.randomBytes(1)[0] % alphabet.length;
    out += alphabet[idx];
  }
  return out;
}

function _calcEndTime({ durationValue, durationUnit, noLimit }) {
  const now = Date.now();
  if (noLimit) {
    return new Date(now + 99 * 365 * 24 * 3600 * 1000);
  }
  const v = _toInt(durationValue);
  if (v <= 0) {
    return new Date(now + 99 * 365 * 24 * 3600 * 1000);
  }
  const unit = typeof durationUnit === 'string' ? durationUnit.trim().toLowerCase() : '';
  if (unit === 'hour' || unit === 'hours' || unit === 'h') {
    return new Date(now + v * 3600 * 1000);
  }
  return new Date(now + v * 24 * 3600 * 1000);
}

class QuickShareService {
  constructor(knex) {
    this.knex = knex;
    this.table = 'quick_share';
  }

  async listByUid(uid) {
    const id = _toInt(uid);
    if (!id) return [];
    const rows = await this.knex(this.table).where({ uid: id }).select('id', 'uid', 'path', 'token', 'pwd', 'remark', 'create_time', 'end_time').orderBy('id', 'desc');
    return (rows || []).map(r => ({
      id: r.id,
      uid: r.uid,
      path: r.path,
      token: r.token,
      pwd: typeof r.pwd === 'string' && r.pwd.trim().startsWith('pbkdf2$') ? null : r.pwd,
      remark: r.remark,
      create_time: r.create_time,
      end_time: r.end_time,
      hasPwd: !!(r.pwd && String(r.pwd).trim()),
    }));
  }

  async getByToken(token) {
    const t = typeof token === 'string' ? token.trim() : '';
    if (!t) return null;
    return await this.knex(this.table).where({ token: t }).first();
  }

  async create({ uid, rawPath, pwd, remark, durationValue, durationUnit, noLimit }) {
    const userId = _toInt(uid);
    if (!userId) {
      const err = new Error('auth.AUTHENTICATION_REQUIRED');
      err.statusCode = 401;
      throw err;
    }

    const p = typeof rawPath === 'string' ? rawPath.trim() : '';
    if (!p) {
      const err = new Error('quickShare.INVALID_PATH');
      err.statusCode = 400;
      throw err;
    }

    const resolvedPath = path.resolve(p);
    const pwdHash = _hashPwd(pwd);
    const endTime = _calcEndTime({ durationValue, durationUnit, noLimit });
    const note = typeof remark === 'string' ? remark.trim() : '';

    let token = '';
    for (let i = 0; i < 50; i++) {
      const cand = _genToken(8);
      const existed = await this.knex(this.table).where({ token: cand }).first('id');
      if (!existed) {
        token = cand;
        break;
      }
    }
    if (!token) {
      const err = new Error('quickShare.TOKEN_GENERATE_FAILED');
      err.statusCode = 500;
      throw err;
    }

    const row = {
      uid: userId,
      path: resolvedPath,
      pwd: pwdHash,
      token,
      remark: note || null,
      end_time: endTime,
      create_time: new Date(),
      update_time: new Date(),
    };

    const inserted = await this.knex(this.table).insert(row);
    const id = Array.isArray(inserted) ? inserted[0] : inserted;
    return { id, ...row, hasPwd: !!pwdHash };
  }

  async deleteById({ uid, id }) {
    const userId = _toInt(uid);
    const shareId = _toInt(id);
    if (!userId || !shareId) {
      const err = new Error('common.PARAM_ERROR');
      err.statusCode = 400;
      throw err;
    }
    const affected = await this.knex(this.table).where({ id: shareId, uid: userId }).del();
    return { deleted: affected > 0 };
  }

  async deleteExpiredByUid(uid) {
    const userId = _toInt(uid);
    if (!userId) {
      const err = new Error('auth.AUTHENTICATION_REQUIRED');
      err.statusCode = 401;
      throw err;
    }
    const now = new Date();
    const affected = await this.knex(this.table).where({ uid: userId }).andWhere('end_time', '<', now).del();
    return { deleted: affected };
  }
}

module.exports = {
  QuickShareService,
};
