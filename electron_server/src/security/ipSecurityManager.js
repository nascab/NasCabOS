const NetUtil = require('../utils/netUtil');

function normalizeIp(raw) {
  if (raw === undefined || raw === null) return '';
  let ip = String(raw).trim();
  if (!ip) return '';
  if (ip.startsWith('::ffff:')) ip = ip.slice('::ffff:'.length);
  return ip.trim();
}

class IpSecurityManager {
  constructor() {
    this._config = {
      banEnabled: true,
      maxFailedAttempts: 5,
      banMinutes: 1,
      bypassLanAuth: true,
    };
    this._blacklist = new Map();
    this._failures = new Map();
    this._cleanupTimer = setInterval(() => this.cleanupExpired(), 10 * 1000);
    try {
      if (typeof this._cleanupTimer.unref === 'function') this._cleanupTimer.unref();
    } catch (_) {}
  }

  getConfig() {
    return { ...this._config };
  }

  setConfig(next) {
    const banEnabled = next && typeof next.banEnabled === 'boolean' ? next.banEnabled : undefined;
    const maxFailedAttempts = Number(next && next.maxFailedAttempts);
    const banMinutes = Number(next && next.banMinutes);
    const bypassLanAuth = next && typeof next.bypassLanAuth === 'boolean' ? next.bypassLanAuth : undefined;
    if (banEnabled !== undefined) {
      this._config.banEnabled = banEnabled;
    }
    if (Number.isFinite(maxFailedAttempts) && maxFailedAttempts > 0) {
      this._config.maxFailedAttempts = Math.floor(maxFailedAttempts);
    }
    if (Number.isFinite(banMinutes) && banMinutes > 0) {
      this._config.banMinutes = Math.floor(banMinutes);
    }
    if (bypassLanAuth !== undefined) {
      this._config.bypassLanAuth = bypassLanAuth;
    }
    return this.getConfig();
  }

  shouldEnforceForIp(rawIp) {
    const ip = normalizeIp(rawIp);
    if (!ip) return false;
    if (!this._config.banEnabled) return false;
    if (this._config.bypassLanAuth && NetUtil.isPrivateIP(ip)) return false;
    return true;
  }

  cleanupExpired() {
    const now = Date.now();
    for (const [ip, entry] of this._blacklist.entries()) {
      const expiresAt = entry && Number(entry.expiresAt);
      if (Number.isFinite(expiresAt) && expiresAt > 0 && expiresAt <= now) {
        this._blacklist.delete(ip);
      }
    }
    for (const [ip, rec] of this._failures.entries()) {
      const lastAt = rec && Number(rec.lastAt);
      if (!Number.isFinite(lastAt) || lastAt <= 0) {
        this._failures.delete(ip);
        continue;
      }
      if (now - lastAt > 24 * 60 * 60 * 1000) {
        this._failures.delete(ip);
      }
    }
  }

  isBlacklisted(rawIp) {
    const ip = normalizeIp(rawIp);
    if (!ip) return { blacklisted: false, ip: '' };
    if (!this.shouldEnforceForIp(ip)) return { blacklisted: false, ip, ignored: true };
    this.cleanupExpired();
    const entry = this._blacklist.get(ip);
    if (!entry) return { blacklisted: false, ip };
    return { blacklisted: true, ip, entry: { ...entry } };
  }

  recordFailure(rawIp, { description = '' } = {}) {
    const ip = normalizeIp(rawIp);
    console.log('认证失败', ip, description);
    if (!ip) return { ok: false, ignored: true };
    if (!this.shouldEnforceForIp(ip)) {
      console.log('内网请求 认证失败忽略', ip, description);
      return { ok: true, ignored: true };
    }
    this.cleanupExpired();
    if (this._blacklist.has(ip)) return { ok: true, ip, blacklisted: true };

    const now = Date.now();
    const prev = this._failures.get(ip) || { count: 0, firstAt: now, lastAt: now };
    const count = Math.max(0, Number(prev.count) || 0) + 1;
    const rec = { count, firstAt: prev.firstAt || now, lastAt: now };

    const max = Math.max(1, Number(this._config.maxFailedAttempts) || 5);
    if (count >= max) {
      const banMinutes = Math.max(1, Number(this._config.banMinutes) || 1);
      const expiresAt = now + banMinutes * 60 * 1000;
      const entry = {
        ip,
        description: String(description || '').trim(),
        createTime: now,
        expiresAt,
      };
      this._blacklist.set(ip, entry);
      this._failures.delete(ip);
      return { ok: true, ip, blacklisted: true, entry: { ...entry }, count };
    }

    this._failures.set(ip, rec);
    return { ok: true, ip, blacklisted: false, count };
  }

  banIp(rawIp, { minutes = 1, description = '' } = {}) {
    const ip = normalizeIp(rawIp);
    if (!ip) return { ok: false, ignored: true };
    if (!this.shouldEnforceForIp(ip)) {
      return { ok: true, ignored: true };
    }
    const now = Date.now();
    const banMinutes = Math.max(1, Number(minutes) || 1);
    const expiresAt = now + banMinutes * 60 * 1000;
    const entry = {
      ip,
      description: String(description || '').trim(),
      createTime: now,
      expiresAt,
    };
    this._blacklist.set(ip, entry);
    this._failures.delete(ip);
    return { ok: true, ip, blacklisted: true, entry: { ...entry } };
  }

  clearFailures(rawIp) {
    const ip = normalizeIp(rawIp);
    if (!ip) return false;
    return this._failures.delete(ip);
  }

  listBlacklist() {
    this.cleanupExpired();
    const arr = Array.from(this._blacklist.values()).map(e => ({ ...e }));
    arr.sort((a, b) => (b.createTime || 0) - (a.createTime || 0));
    return arr;
  }

  deleteBlacklist(rawIp) {
    const ip = normalizeIp(rawIp);
    if (!ip) return false;
    return this._blacklist.delete(ip);
  }

  clearBlacklist() {
    const count = this._blacklist.size;
    this._blacklist.clear();
    return count;
  }
}

module.exports = new IpSecurityManager();
