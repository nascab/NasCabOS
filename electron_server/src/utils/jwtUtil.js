const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const Logger = require('./logger');

class JwtUtil {
  /**
   * 验证JWT token
   * @param {string} token - JWT token
   * @returns {Object} 解码后的token数据
   */
  verifyToken(secret, token) {
    try {
      return jwt.verify(token, secret);
    } catch (err) {
      Logger.error(`JWT verify failed: ${err.message}`);
      throw err;
    }
  }

  /**
   * 密码加密
   * @param {string} password - 明文密码
   * @returns {string} 加密后的密码
   */
  async hashPassword(password) {
    return this.encryptPassword(password);
  }

  /**
   * 验证密码
   * @param {string} password - 明文密码
   * @param {string} hashedPassword - 加密后的密码
   * @returns {boolean} 是否匹配
   */
  async verifyPassword(password, hashedPassword) {
    if (this.isEncryptedPassword(hashedPassword)) {
      const decrypted = this.decryptPassword(hashedPassword);
      if (decrypted === null) return false;
      const a = Buffer.from(String(password));
      const b = Buffer.from(decrypted);
      return a.length === b.length && crypto.timingSafeEqual(a, b);
    }

    const ok = await bcrypt.compare(password, hashedPassword);
    if (ok) return true;

    const legacy = this.sha256Hex(String(password));
    return await bcrypt.compare(legacy, hashedPassword);
  }

  isClientPasswordObfuscated(value) {
    return typeof value === 'string' && value.startsWith('b64:');
  }

  decodeClientPassword(value) {
    try {
      if (!this.isClientPasswordObfuscated(value)) return String(value ?? '');
      const b64 = value.slice('b64:'.length);
      return Buffer.from(b64, 'base64').toString('utf8');
    } catch (_) {
      return String(value ?? '');
    }
  }

  sha256Hex(text) {
    return crypto.createHash('sha256').update(String(text), 'utf8').digest('hex');
  }

  isEncryptedPassword(value) {
    return typeof value === 'string' && value.startsWith('enc:v1:');
  }

  encryptPassword(password) {
    const serverId = process.env.SERVER_ID;
    if (!serverId) {
      throw new Error('SERVER_ID_MISSING');
    }

    const key = crypto.createHash('sha256').update(serverId).digest();
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
    const encrypted = Buffer.concat([cipher.update(String(password), 'utf8'), cipher.final()]);
    const combined = Buffer.concat([iv, encrypted]).toString('base64');
    return `enc:v1:${combined}`;
  }

  decryptPassword(stored) {
    try {
      if (!this.isEncryptedPassword(stored)) return null;

      const serverId = process.env.SERVER_ID;
      if (!serverId) {
        throw new Error('SERVER_ID_MISSING');
      }

      const key = crypto.createHash('sha256').update(serverId).digest();
      const ciphertextBase64 = stored.slice('enc:v1:'.length);
      const inputBuffer = Buffer.from(ciphertextBase64, 'base64');
      if (inputBuffer.length < 17) return null;

      const iv = inputBuffer.subarray(0, 16);
      const encrypted = inputBuffer.subarray(16);

      const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
      const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
      return decrypted.toString('utf8');
    } catch (_) {
      return null;
    }
  }

  /**
   * 从请求中提取token
   * @param {Object} req - Express请求对象
   * @returns {string|null} token或null
   */
  extractTokenFromRequest(req) {
    // 从Authorization header中提取
    const authHeader = req.headers ? req.headers.authorization : null;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }

    // 从cookie中提取
    // if (req.cookies && req.cookies.accessToken) {
    //   return req.cookies.accessToken;
    // }

    if (req.query && req.query.accessToken) {
      return req.query.accessToken;
    }

    return null;
  }
}

// 创建单例实例
const jwtUtilInstance = new JwtUtil();

module.exports = jwtUtilInstance;
