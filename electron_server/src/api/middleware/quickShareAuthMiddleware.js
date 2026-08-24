const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const Logger = require('../../utils/logger');
const ResponseUtil = require('../apiUtils/responseUtil');
const QuickShareBinary = require('../modules/quickShare/quickShareBinary');

// ---------- 暴力破解防护 ----------
const BRUTE_MAX_ATTEMPTS = 5;
const BRUTE_LOCKOUT_MS = 1 * 60 * 1000; // 1分钟
const BRUTE_WINDOW_MS = 1 * 60 * 1000; // 失败计数窗口 1 分钟
const _bruteStore = new Map();

function _getClientIp(req) {
  const h = req.headers || {};
  const forwarded = h['x-forwarded-for'] || h['x-real-ip'];
  if (forwarded) {
    const first = typeof forwarded === 'string' ? forwarded.split(',')[0] : forwarded[0];
    return (first || '').trim();
  }
  return (req.socket && req.socket.remoteAddress) || req.connection?.remoteAddress || '';
}

function getQuickShareBruteKey(req, token) {
  const ip = _getClientIp(req);
  const t = typeof token === 'string' ? token.trim() : '';
  return `qs:${ip}:${t || 'unknown'}`;
}

function isQuickShareBruteLocked(key) {
  const entry = _bruteStore.get(key);
  if (!entry) return false;
  const now = Date.now();
  if (entry.lockedUntil && entry.lockedUntil > now) return true;
  if (now - entry.firstAt > BRUTE_WINDOW_MS) {
    _bruteStore.delete(key);
    return false;
  }
  return false;
}

function recordQuickShareBruteFailure(key) {
  const now = Date.now();
  let entry = _bruteStore.get(key);
  if (!entry) {
    entry = { count: 0, firstAt: now, lockedUntil: null };
    _bruteStore.set(key, entry);
  }
  if (now - entry.firstAt > BRUTE_WINDOW_MS) {
    entry.count = 0;
    entry.firstAt = now;
    entry.lockedUntil = null;
  }
  entry.count += 1;
  if (entry.count >= BRUTE_MAX_ATTEMPTS) {
    entry.lockedUntil = now + BRUTE_LOCKOUT_MS;
  }
}

function clearQuickShareBruteOnSuccess(key) {
  _bruteStore.delete(key);
}

// 定期清理过期条目，避免内存泄漏
function _bruteCleanup() {
  const now = Date.now();
  for (const [k, v] of _bruteStore.entries()) {
    if (v.lockedUntil && v.lockedUntil < now) _bruteStore.delete(k);
    else if (!v.lockedUntil && now - v.firstAt > BRUTE_WINDOW_MS) _bruteStore.delete(k);
  }
}
setInterval(_bruteCleanup, 60 * 1000).unref();

// ---------- 原有逻辑 ----------

function _getToken(req) {
  const q = req.query || {};
  const b = req.body || {};
  const v = q.qt ?? q.token ?? b.qt ?? b.token;
  return typeof v === 'string' ? v.trim() : String(v || '').trim();
}

function _getPwd(req) {
  const b = req.body || {};
  const h = req.headers || {};
  const v = b.pwd ?? b.password ?? h['x-qspwd'] ?? h['x-quickshare-password'];
  return typeof v === 'string' ? v : v == null ? '' : String(v);
}

function _getAccessToken(req) {
  const q = req.query || {};
  const b = req.body || {};
  const h = req.headers || {};
  const v = q.qsat ?? q.quickShareToken ?? b.qsat ?? b.quickShareToken ?? h['x-qsat'] ?? h['x-quickshare-token'];
  return typeof v === 'string' ? v.trim() : String(v || '').trim();
}

function _getRelPath(req) {
  const q = req.query || {};
  const b = req.body || {};
  const v = q.p ?? q.rel ?? q.pathRel ?? b.p ?? b.rel ?? b.pathRel;
  return typeof v === 'string' ? v : v == null ? '' : String(v);
}

function _isInsideRoot(rootPath, targetPath) {
  const rootResolved = path.resolve(String(rootPath || ''));
  const targetResolved = path.resolve(String(targetPath || ''));
  if (!rootResolved || !targetResolved) return false;
  if (rootResolved === targetResolved) return true;
  const rel = path.relative(rootResolved, targetResolved);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function _parsePwdHash(stored) {
  const raw = typeof stored === 'string' ? stored : stored == null ? '' : String(stored);
  const s = raw.trim();
  if (!s) return { mode: 'empty' };
  const parts = s.split('$');
  if (parts.length === 4 && parts[0] === 'pbkdf2') {
    const iter = Number(parts[1]) || 0;
    const salt = parts[2] || '';
    const hash = parts[3] || '';
    if (iter > 0 && salt && hash) return { mode: 'pbkdf2', iter, salt, hash };
  }
  return { mode: 'plain', value: s };
}

function _hashPwdPbkdf2(crypto, pwd, iter, salt) {
  const buf = crypto.pbkdf2Sync(String(pwd || ''), String(salt || ''), Number(iter || 0), 32, 'sha256');
  return buf.toString('hex');
}

function _sha256Hex(text) {
  return crypto
    .createHash('sha256')
    .update(String(text ?? ''), 'utf8')
    .digest('hex');
}

function verifyQuickSharePwd(stored, provided) {
  const parsed = _parsePwdHash(stored);
  if (parsed.mode === 'empty') return false;
  const pwd = typeof provided === 'string' ? provided : provided == null ? '' : String(provided);
  if (!pwd) return false;
  if (parsed.mode === 'plain') return pwd === parsed.value;
  const crypto = require('crypto');
  const actual = _hashPwdPbkdf2(crypto, pwd, parsed.iter, parsed.salt);
  return actual === parsed.hash;
}

function verifyQuickShareAccessToken(req, share, token, accessToken) {
  const raw = typeof accessToken === 'string' ? accessToken.trim() : '';
  if (!raw) return false;
  const secret = process.env.JWT_SECRET;
  if (!secret) return false;

  try {
    const decoded = jwt.verify(raw, secret);
    if (!decoded || decoded.type !== 'quickShare') return false;
    if (String(decoded.qt || '') !== String(token || '')) return false;
    const expectedPwdHash = _sha256Hex(share && share.pwd ? String(share.pwd) : '');
    if (String(decoded.pwdHash || '') !== expectedPwdHash) return false;
    return true;
  } catch (_) {
    return false;
  }
}

function requireQuickShareAccess({ getShareByToken }) {
  return async (req, res, next) => {
    try {
      const routePath = `${req.method} ${(req.originalUrl || req.url || '').split('?')[0]}`;

      const sendErr = (statusCode, reason, extra = {}) => {
        Logger.warn('[quickShare] requireQuickShareAccess: reject', {
          routePath,
          httpStatus: statusCode,
          reason,
          ...extra,
        });
        return res
          .status(statusCode)
          .set('content-type', 'application/octet-stream')
          .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_LIST_RES, code: statusCode }));
      };

      const token = _getToken(req);
      if (!token) return sendErr(400, 'missing_qt_query');

      const share = await getShareByToken(req, token);
      if (!share) return sendErr(404, 'share_not_in_db', { qt: token });

      const now = Date.now();
      const endTime = share.end_time ? new Date(share.end_time).getTime() : null;
      if (endTime && Number.isFinite(endTime) && endTime > 0 && endTime < now) {
        return sendErr(410, 'share_expired', { qt: token, endTime });
      }

      const needsPwd = true;
      const bruteKey = getQuickShareBruteKey(req, token);
      if (isQuickShareBruteLocked(bruteKey)) {
        return sendErr(429, 'brute_locked', { qt: token });
      }
      const providedPwd = _getPwd(req);
      if (needsPwd) {
        const accessToken = _getAccessToken(req);
        const okByToken = verifyQuickShareAccessToken(req, share, token, accessToken);
        if (!okByToken && !providedPwd) {
          const secret = process.env.JWT_SECRET;
          let qsatHint = 'missing_or_invalid';
          if (!secret) qsatHint = 'JWT_SECRET_not_set';
          else if (!accessToken) qsatHint = 'qsat_empty';
          else {
            try {
              const decoded = jwt.verify(accessToken, secret);
              if (!decoded || decoded.type !== 'quickShare') qsatHint = 'jwt_wrong_type';
              else if (String(decoded.qt || '') !== String(token || '')) qsatHint = 'jwt_qt_mismatch';
              else qsatHint = 'jwt_pwdHash_mismatch_or_other';
            } catch (e) {
              qsatHint = e && e.name === 'TokenExpiredError' ? 'jwt_expired' : 'jwt_verify_failed';
            }
          }
          return sendErr(ResponseUtil.CODE_PWD_REQUIRED, 'need_password_or_valid_qsat', {
            qt: token,
            hasQsat: !!accessToken,
            qsatHint,
          });
        }
        if (!okByToken && !verifyQuickSharePwd(share.pwd, providedPwd)) {
          recordQuickShareBruteFailure(bruteKey);
          return sendErr(ResponseUtil.CODE_PWD_ERROR, 'password_wrong', { qt: token });
        }
        clearQuickShareBruteOnSuccess(bruteKey);
      }

      const rel = _getRelPath(req);
      const rootPath = path.resolve(String(share.path || ''));
      const normalizedRel = String(rel || '')
        .replace(/\\/g, '/')
        .replace(/^\/+/, '');
      if (normalizedRel) {
        try {
          const st = await fs.promises.stat(rootPath);
          if (st && st.isFile()) {
            return sendErr(403, 'rel_path_on_file_share', { qt: token, rel: normalizedRel });
          }
        } catch (_) {}
      }
      const targetPath = normalizedRel ? path.resolve(rootPath, normalizedRel) : rootPath;
      if (!_isInsideRoot(rootPath, targetPath)) {
        return sendErr(403, 'path_outside_share_root', {
          qt: token,
          rootPath,
          targetPath,
          rel: normalizedRel,
        });
      }

      Logger.info('[quickShare] requireQuickShareAccess: ok', {
        routePath,
        qt: token,
        rel: normalizedRel || '(root)',
      });
      req.quickShare = { token, share, rootPath, relPath: normalizedRel, targetPath };
      next();
    } catch (e) {
      Logger.error('[quickShare] requireQuickShareAccess: exception', e, {
        routePath: `${req.method} ${(req.originalUrl || req.url || '').split('?')[0]}`,
      });
      return res
        .status(500)
        .set('content-type', 'application/octet-stream')
        .send(QuickShareBinary.encodeError({ msgType: QuickShareBinary.MSG_LIST_RES, code: 500 }));
    }
  };
}

module.exports = {
  requireQuickShareAccess,
  verifyQuickSharePwd,
  verifyQuickShareAccessToken,
  getQuickShareBruteKey,
  isQuickShareBruteLocked,
  recordQuickShareBruteFailure,
  clearQuickShareBruteOnSuccess,
};
