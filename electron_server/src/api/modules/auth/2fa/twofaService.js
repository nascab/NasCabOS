const crypto = require('crypto');
const { authenticator } = require('otplib');
const qrcode = require('qrcode');
const Logger = require('../../../../utils/logger');

const ENC_PREFIX = 'enc2fa.v1';
const CONFIG_TABLE = 'config';
const CONFIG_UID = 0;
const KEY_2FA_SECRET = 'twofaSecret';

function deriveKeyFromText(text) {
  const s = text === undefined || text === null ? '' : String(text);
  if (!s.trim()) return null;
  return crypto.createHash('sha256').update(s, 'utf8').digest();
}

const _decryptFailSigCache = new Set();
const _DECRYPT_FAIL_SIG_CACHE_MAX = 200;

function _rememberDecryptFailSig(sig) {
  if (!sig) return false;
  if (_decryptFailSigCache.has(sig)) return false;
  _decryptFailSigCache.add(sig);
  if (_decryptFailSigCache.size > _DECRYPT_FAIL_SIG_CACHE_MAX) {
    const oldest = _decryptFailSigCache.values().next().value;
    if (oldest) _decryptFailSigCache.delete(oldest);
  }
  return true;
}

function fingerprintFromText(text) {
  const s = text === undefined || text === null ? '' : String(text);
  if (!s.trim()) return '';
  return crypto.createHash('sha256').update(s, 'utf8').digest('hex').slice(0, 12);
}

function _decodeBase64Flexible(input) {
  const raw = input === undefined || input === null ? '' : String(input);
  let s = raw.trim().replace(/\s+/g, '');
  if (!s) return null;

  const hadUrlChars = s.includes('-') || s.includes('_');
  const hadSpaces = s.includes(' ');
  if (hadSpaces) s = s.replace(/ /g, '+');
  if (hadUrlChars) s = s.replace(/-/g, '+').replace(/_/g, '/');

  const mod = s.length % 4;
  if (mod === 2) s += '==';
  else if (mod === 3) s += '=';
  else if (mod === 1) return null;

  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(s)) return null;

  try {
    const buf = Buffer.from(s, 'base64');
    if (!buf || buf.length <= 0) return null;
    return buf;
  } catch (_) {
    return null;
  }
}

function encryptSecret(plain, key) {
  if (!key) throw new Error('twofa.MASTER_KEY_MISSING');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const cipherText = Buffer.concat([cipher.update(String(plain), 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `${ENC_PREFIX}.${iv.toString('base64')}.${tag.toString('base64')}.${cipherText.toString('base64')}`;
}

function normalizeSecretText(input) {
  return String(input || '')
    .trim()
    .replace(/\s+/g, '')
    .toUpperCase();
}

function looksLikeBase32Secret(secret) {
  const s = normalizeSecretText(secret);
  if (s.length < 16 || s.length > 128) return false;
  return /^[A-Z2-7]+=*$/.test(s);
}

function normalizeStoredSecretEnc(stored) {
  if (stored === undefined || stored === null) return '';
  let raw = Buffer.isBuffer(stored) ? stored.toString('utf8') : String(stored);
  if (!raw) return '';
  let trimmed = raw.trim();
  if (!trimmed) return '';

  const first = trimmed[0];
  const last = trimmed[trimmed.length - 1];
  if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
    trimmed = trimmed.slice(1, -1).trim();
    if (!trimmed) return '';
  }

  if (trimmed.startsWith(`${ENC_PREFIX}.`)) return trimmed;

  const decoded = _decodeBase64Flexible(trimmed);
  if (decoded) {
    const decodedText = decoded.toString('utf8').trim();
    if (decodedText.startsWith(`${ENC_PREFIX}.`)) return decodedText;
  }

  return trimmed;
}

function decryptSecretWithDiagnostics(stored, { userId, op, key, keyFp } = {}) {
  const rawInput = stored === undefined || stored === null ? '' : Buffer.isBuffer(stored) ? stored.toString('utf8') : String(stored);
  const inputTrim = rawInput.trim();
  const hasOuterQuotes = inputTrim.length >= 2 && ((inputTrim.startsWith('"') && inputTrim.endsWith('"')) || (inputTrim.startsWith("'") && inputTrim.endsWith("'")));
  const base64DecodedCandidate = !inputTrim.startsWith(`${ENC_PREFIX}.`) ? _decodeBase64Flexible(inputTrim) : null;
  const decodedCandidateText = base64DecodedCandidate ? base64DecodedCandidate.toString('utf8').trim() : '';
  const usedBase64Decode = !!decodedCandidateText && decodedCandidateText.startsWith(`${ENC_PREFIX}.`);
  const raw = normalizeStoredSecretEnc(stored);
  if (!raw.trim()) return '';
  if (!raw.startsWith(`${ENC_PREFIX}.`)) {
    const fp = keyFp || '';
    const sig = `legacy:${op || ''}:${userId || ''}:${fp}:${raw.length}`;
    if (_rememberDecryptFailSig(sig)) {
      Logger.warn('2FA secret decrypt failed: unrecognized format', {
        op: op || '',
        userId: userId || null,
        keyFp: fp,
        secretEncLen: raw.length,
        rawInputLen: rawInput.length,
        trimmedChanged: rawInput !== inputTrim,
        hasOuterQuotes,
        usedBase64Decode,
      });
    }
    return '';
  }
  if (!key) throw new Error('twofa.MASTER_KEY_MISSING');
  const rawPrefix = `${ENC_PREFIX}.`;
  const payload = raw.startsWith(rawPrefix) ? raw.slice(rawPrefix.length) : raw;
  const parts = payload.split('.');
  const fp = keyFp || '';
  if (parts.length !== 3) {
    const sig = `pcount:${op || ''}:${userId || ''}:${fp}:${raw.length}:${parts.length}`;
    if (_rememberDecryptFailSig(sig)) {
      Logger.warn('2FA secret decrypt failed: invalid parts count', {
        op: op || '',
        userId: userId || null,
        keyFp: fp,
        secretEncLen: raw.length,
        partsCount: parts.length,
        rawInputLen: rawInput.length,
        trimmedChanged: rawInput !== inputTrim,
        hasOuterQuotes,
        usedBase64Decode,
      });
    }
    return '';
  }
  try {
    const iv = _decodeBase64Flexible(parts[0]);
    const tag = _decodeBase64Flexible(parts[1]);
    const cipherText = _decodeBase64Flexible(parts[2]);

    const ivLen = iv ? iv.length : 0;
    const tagLen = tag ? tag.length : 0;
    const cipherLen = cipherText ? cipherText.length : 0;

    if (!iv || !tag || !cipherText) {
      const sig = `b64:${op || ''}:${userId || ''}:${fp}:${raw.length}:${ivLen}:${tagLen}:${cipherLen}`;
      if (_rememberDecryptFailSig(sig)) {
        Logger.warn('2FA secret decrypt failed: base64 decode failed', {
          op: op || '',
          userId: userId || null,
          keyFp: fp,
          secretEncLen: raw.length,
          ivLen,
          tagLen,
          cipherLen,
          rawInputLen: rawInput.length,
          trimmedChanged: rawInput !== inputTrim,
          hasOuterQuotes,
          usedBase64Decode,
        });
      }
      return '';
    }

    if (ivLen !== 12 || tagLen !== 16 || cipherLen <= 0) {
      const sig = `len:${op || ''}:${userId || ''}:${fp}:${raw.length}:${ivLen}:${tagLen}:${cipherLen}`;
      if (_rememberDecryptFailSig(sig)) {
        Logger.warn('2FA secret decrypt failed: invalid iv/tag/cipher length', {
          op: op || '',
          userId: userId || null,
          keyFp: fp,
          secretEncLen: raw.length,
          ivLen,
          tagLen,
          cipherLen,
          rawInputLen: rawInput.length,
          trimmedChanged: rawInput !== inputTrim,
          hasOuterQuotes,
          usedBase64Decode,
        });
      }
      return '';
    }

    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    const plain = Buffer.concat([decipher.update(cipherText), decipher.final()]);
    return plain.toString('utf8');
  } catch (e) {
    const sig = `dec:${op || ''}:${userId || ''}:${fp}:${raw.length}`;
    if (_rememberDecryptFailSig(sig)) {
      Logger.warn('2FA secret decrypt failed: decipher error', {
        op: op || '',
        userId: userId || null,
        keyFp: fp,
        secretEncLen: raw.length,
        errorName: e && e.name ? String(e.name) : '',
        rawInputLen: rawInput.length,
        trimmedChanged: rawInput !== inputTrim,
        hasOuterQuotes,
        usedBase64Decode,
      });
    }
    return '';
  }
}

function normalizeCode(input) {
  return String(input || '')
    .trim()
    .replace(/\s+/g, '')
    .replace(/-/g, '');
}

function makeBackupCode() {
  const bytes = crypto.randomBytes(8);
  const hex = bytes.toString('hex').toUpperCase();
  return `${hex.slice(0, 4)}-${hex.slice(4, 8)}-${hex.slice(8, 12)}`;
}

function hashBackupCode(key, userId, code) {
  const normalized = normalizeCode(code);
  if (!key) throw new Error('twofa.MASTER_KEY_MISSING');
  return crypto.createHmac('sha256', key).update(`2fa:${userId}:${normalized}`, 'utf8').digest('hex');
}

class TwoFAService {
  constructor(knexMain) {
    this.knexMain = knexMain;
    authenticator.options = { step: 30, window: 1, digits: 6 };
    this._cryptoKeysPromise = null;
  }

  async _ensureTwofaSecretText() {
    const existing = await this.knexMain(CONFIG_TABLE).where({ uid: CONFIG_UID, key: KEY_2FA_SECRET }).first('value');
    const val = existing && existing.value ? String(existing.value).trim() : '';
    if (val) return val;

    const generated = crypto.randomBytes(48).toString('base64');
    try {
      await this.knexMain(CONFIG_TABLE).insert({ uid: CONFIG_UID, key: KEY_2FA_SECRET, value: generated });
      return generated;
    } catch (_) {
      const again = await this.knexMain(CONFIG_TABLE).where({ uid: CONFIG_UID, key: KEY_2FA_SECRET }).first('value');
      const v2 = again && again.value ? String(again.value).trim() : '';
      if (v2) return v2;
      try {
        await this.knexMain(CONFIG_TABLE).where({ uid: CONFIG_UID, key: KEY_2FA_SECRET }).update({ value: generated });
      } catch (_) {}
      const finalRow = await this.knexMain(CONFIG_TABLE).where({ uid: CONFIG_UID, key: KEY_2FA_SECRET }).first('value');
      const v3 = finalRow && finalRow.value ? String(finalRow.value).trim() : '';
      if (v3) return v3;
      throw new Error('twofa.MASTER_KEY_MISSING');
    }
  }

  async _loadCryptoKeys() {
    const twofaSecretText = await this._ensureTwofaSecretText();
    const primaryKey = deriveKeyFromText(twofaSecretText);
    const primaryFp = fingerprintFromText(twofaSecretText);

    return {
      primary: { key: primaryKey, fp: primaryFp },
    };
  }

  async _getCryptoKeys() {
    if (this._cryptoKeysPromise) return await this._cryptoKeysPromise;
    this._cryptoKeysPromise = this._loadCryptoKeys().finally(() => {});
    return await this._cryptoKeysPromise;
  }

  async _decryptUserSecretEnc(stored, { userId, op } = {}) {
    const keys = await this._getCryptoKeys();
    const rawStored = stored === undefined || stored === null ? '' : Buffer.isBuffer(stored) ? stored.toString('utf8') : String(stored);
    const normalizedStored = normalizeStoredSecretEnc(rawStored);

    const primaryKey = keys && keys.primary ? keys.primary.key : null;
    const primaryFp = keys && keys.primary ? keys.primary.fp : '';

    return decryptSecretWithDiagnostics(normalizedStored, { userId, op, key: primaryKey, keyFp: primaryFp });
  }

  async _ensureRow(userId) {
    const exists = await this.knexMain('user_2fa').where({ user_id: userId }).first();
    if (exists) return exists;
    await this.knexMain('user_2fa').insert({
      user_id: userId,
      is_enabled: false,
      issuer: 'NasCabOS',
      period: 30,
      digits: 6,
      algorithm: 'sha1',
      create_time: new Date(),
      update_time: new Date(),
    });
    return await this.knexMain('user_2fa').where({ user_id: userId }).first();
  }

  async getStatus(userId) {
    const row = await this._ensureRow(userId);
    const remainingRow = await this.knexMain('user_2fa_backup_code').where({ user_id: userId, is_used: false }).count({ c: '*' }).first();
    const remaining = Number(remainingRow && remainingRow.c) || 0;
    return {
      enabled: row && row.is_enabled === 1,
      hasSecret: !!(row && row.secret_enc),
      issuer: row && row.issuer ? String(row.issuer) : 'NasCabOS',
      period: Number(row && row.period) || 30,
      digits: Number(row && row.digits) || 6,
      algorithm: row && row.algorithm ? String(row.algorithm) : 'sha1',
      secretCreatedAt: row && row.secret_created_at ? new Date(row.secret_created_at).getTime() : null,
      enabledAt: row && row.enabled_at ? new Date(row.enabled_at).getTime() : null,
      backupCodesRemaining: remaining,
    };
  }

  async isEnabled(userId) {
    const row = await this.knexMain('user_2fa').where({ user_id: userId }).first();
    return !!(row && row.is_enabled === 1);
  }

  async generateSecret(userId, { issuer = 'NasCabOS', accountName = '' } = {}) {
    await this._ensureRow(userId);
    const keys = await this._getCryptoKeys();
    const secret = authenticator.generateSecret();
    const enc = encryptSecret(secret, keys.primary.key);
    Logger.info('2FA secret generated', {
      userId,
      keyFp: keys.primary.fp,
      encLen: enc.length,
      encPrefix: enc.startsWith(`${ENC_PREFIX}.`),
    });

    await this.knexMain.transaction(async trx => {
      await trx('user_2fa').where({ user_id: userId }).update({
        is_enabled: false,
        secret_enc: enc,
        issuer,
        period: 30,
        digits: 6,
        algorithm: 'sha1',
        secret_created_at: new Date(),
        enabled_at: null,
        update_time: new Date(),
      });
      await trx('user_2fa_backup_code').where({ user_id: userId }).del();
    });

    const label = accountName ? String(accountName) : String(userId);
    const otpauthUrl = authenticator.keyuri(label, issuer, secret);
    return { secret, otpauthUrl, issuer, period: 30, digits: 6, algorithm: 'sha1' };
  }

  async getSecretPlain(userId) {
    const keys = await this._getCryptoKeys();
    const row = await this.knexMain('user_2fa').where({ user_id: userId }).first();
    if (!row || !row.secret_enc) throw new Error('twofa.NO_SECRET');
    const stored = String(row.secret_enc || '');
    Logger.info('2FA secret load', {
      userId,
      keyFp: keys.primary.fp,
      storedLen: stored.length,
      storedPrefix: stored.startsWith(`${ENC_PREFIX}.`),
    });
    const secret = await this._decryptUserSecretEnc(stored, { userId, op: 'getSecretPlain' });
    if (!secret) throw new Error('twofa.SECRET_DECRYPT_FAILED');
    return {
      secret,
      issuer: row.issuer ? String(row.issuer) : 'NasCabOS',
      period: Number(row.period) || 30,
      digits: Number(row.digits) || 6,
      algorithm: row.algorithm ? String(row.algorithm) : 'sha1',
    };
  }

  async getQrCodeDataUrl(userId, { accountName = '' } = {}) {
    const { secret, issuer } = await this.getSecretPlain(userId);
    const label = accountName ? String(accountName) : String(userId);
    const otpauthUrl = authenticator.keyuri(label, issuer, secret);
    const dataUrl = await qrcode.toDataURL(otpauthUrl, {
      errorCorrectionLevel: 'M',
      margin: 1,
      width: 280,
    });
    return { dataUrl, otpauthUrl };
  }

  async generateBackupCodes(userId, { count = 10 } = {}) {
    const keys = await this._getCryptoKeys();
    const n = Math.max(1, Math.min(30, Number(count) || 10));
    const codes = Array.from({ length: n }, () => makeBackupCode());

    await this.knexMain.transaction(async trx => {
      await trx('user_2fa_backup_code').where({ user_id: userId }).del();
      const rows = codes.map(code => ({
        user_id: userId,
        code_hash: hashBackupCode(keys.primary.key, userId, code),
        is_used: false,
        used_at: null,
        create_time: new Date(),
      }));
      await trx('user_2fa_backup_code').insert(rows);
    });

    return codes;
  }

  verifyTotp(secret, code) {
    const c = normalizeCode(code);
    if (!/^\d{6}$/.test(c)) return false;
    try {
      return authenticator.verify({ token: c, secret });
    } catch (_) {
      return false;
    }
  }

  async verifyBackupCodeOnce(userId, code) {
    const keys = await this._getCryptoKeys();
    const normalized = normalizeCode(code);
    const hash = hashBackupCode(keys.primary.key, userId, normalized);
    const row = await this.knexMain('user_2fa_backup_code').where({ user_id: userId, code_hash: hash, is_used: false }).first();
    if (!row) return false;
    await this.knexMain('user_2fa_backup_code').where({ id: row.id }).update({ is_used: true, used_at: new Date() });
    return true;
  }

  async enable(userId, code, { secret: secretOverride } = {}) {
    const keys = await this._getCryptoKeys();
    const row = await this.knexMain('user_2fa').where({ user_id: userId }).first();
    if (!row || !row.secret_enc) throw new Error('twofa.NO_SECRET');
    let secret = await this._decryptUserSecretEnc(row.secret_enc, { userId, op: 'enable' });
    if (!secret && secretOverride) {
      const normalizedOverride = normalizeSecretText(secretOverride);
      if (looksLikeBase32Secret(normalizedOverride) && this.verifyTotp(normalizedOverride, code)) {
        try {
          const enc = encryptSecret(normalizedOverride, keys.primary.key);
          await this.knexMain('user_2fa').where({ user_id: userId }).update({ secret_enc: enc, update_time: new Date() });
          secret = normalizedOverride;
        } catch (_) {}
      }
    }
    if (!secret) throw new Error('twofa.SECRET_DECRYPT_FAILED');

    const ok = this.verifyTotp(secret, code);
    if (!ok) throw new Error('twofa.INVALID_CODE');

    await this.knexMain('user_2fa').where({ user_id: userId }).update({ is_enabled: true, enabled_at: new Date(), last_verified_at: new Date(), update_time: new Date() });

    const backupCodes = await this.generateBackupCodes(userId, { count: 10 });
    return { backupCodes };
  }

  async disable(userId, code) {
    const row = await this.knexMain('user_2fa').where({ user_id: userId }).first();
    if (!row || !row.is_enabled) throw new Error('twofa.NOT_ENABLED');
    if (!row.secret_enc) throw new Error('twofa.NO_SECRET');
    const secret = await this._decryptUserSecretEnc(row.secret_enc, { userId, op: 'disable' });
    if (!secret) throw new Error('twofa.SECRET_DECRYPT_FAILED');

    const normalized = normalizeCode(code);
    const isTotp = /^\d{6}$/.test(normalized);
    let ok = false;
    if (isTotp) {
      ok = this.verifyTotp(secret, normalized);
    } else {
      ok = await this.verifyBackupCodeOnce(userId, normalized);
    }
    if (!ok) throw new Error('twofa.INVALID_CODE');

    await this.knexMain.transaction(async trx => {
      await trx('user_2fa').where({ user_id: userId }).update({
        is_enabled: false,
        secret_enc: null,
        secret_created_at: null,
        enabled_at: null,
        last_verified_at: new Date(),
        update_time: new Date(),
      });
      await trx('user_2fa_backup_code').where({ user_id: userId }).del();
    });

    return true;
  }

  async verifyForLogin(userId, code) {
    const row = await this.knexMain('user_2fa').where({ user_id: userId }).first();
    if (!row || row.is_enabled !== 1) throw new Error('twofa.NOT_ENABLED');
    if (!row.secret_enc) throw new Error('twofa.NO_SECRET');
    const secret = await this._decryptUserSecretEnc(row.secret_enc, { userId, op: 'verifyForLogin' });
    if (!secret) throw new Error('twofa.SECRET_DECRYPT_FAILED');

    const normalized = normalizeCode(code);
    const isTotp = /^\d{6}$/.test(normalized);
    let ok = false;
    if (isTotp) {
      ok = this.verifyTotp(secret, normalized);
    } else {
      ok = await this.verifyBackupCodeOnce(userId, normalized);
    }
    if (!ok) throw new Error('twofa.INVALID_CODE');

    await this.knexMain('user_2fa').where({ user_id: userId }).update({ last_verified_at: new Date(), update_time: new Date() });
    return { method: isTotp ? 'totp' : 'backup' };
  }

  async adminReset(userId) {
    await this.knexMain.transaction(async trx => {
      await trx('user_2fa').where({ user_id: userId }).update({
        is_enabled: false,
        secret_enc: null,
        secret_created_at: null,
        enabled_at: null,
        update_time: new Date(),
      });
      await trx('user_2fa_backup_code').where({ user_id: userId }).del();
    });
    return true;
  }

  async exportSecretAndRotateBackupCodes(userId, { count = 10 } = {}) {
    const secret = await this.getSecretPlain(userId);
    const backupCodes = await this.generateBackupCodes(userId, { count });
    return { ...secret, backupCodes };
  }
}

module.exports = { TwoFAService };
