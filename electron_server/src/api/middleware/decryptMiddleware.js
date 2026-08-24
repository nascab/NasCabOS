const crypto = require('crypto');
const Logger = require('../../utils/logger');
const tableConfig = require('../../db/table/tableConfig');

let _cachedServerId = '';
let _loadingServerId = null;

async function resolveServerId() {
  if (_cachedServerId) return _cachedServerId;
  if (_loadingServerId) return await _loadingServerId;

  _loadingServerId = (async () => {
    try {
      const env = process.env.SERVER_ID ? String(process.env.SERVER_ID).trim() : '';
      const dbIdRaw = await tableConfig.getServerId();
      const dbId = dbIdRaw ? String(dbIdRaw).trim() : '';

      let resolved = dbId || env;

      if (!resolved) {
        resolved = await tableConfig.generateAndSaveServerId();
        resolved = resolved ? String(resolved).trim() : '';
      } else if (!dbId && env) {
        try {
          await tableConfig.setServerId(env);
        } catch (_) {}
      }

      if (resolved) {
        _cachedServerId = resolved;
        process.env.SERVER_ID = resolved;
      }

      return resolved;
    } catch (e) {
      Logger.error('Resolve serverId failed:', e);
      return '';
    } finally {
      _loadingServerId = null;
    }
  })();

  return await _loadingServerId;
}

/**
 * Decrypts AES encrypted parameters in query or body
 * Expects 'aes' parameter containing Base64 encoded (IV + EncryptedData)
 * Key is SHA256(process.env.SERVER_ID)
 * Algorithm is AES-256-CBC
 */
const decryptMiddleware = async (req, res, next) => {
  try {
    const serverId = await resolveServerId();
    if (!serverId) {
      return next();
    }

    // Check query
    if (req.query && req.query.aes) {
      const decrypted = decrypt(req.query.aes, serverId);
      // console.log('decrypted', decrypted);
      if (decrypted) {
        // console.log("解密结果:", decrypted);
        // Merge decrypted params into query
        Object.assign(req.query, decrypted);
        // Remove aes param to keep it clean
        delete req.query.aes;
      }
    }

    // Check body
    if (req.body && req.body.aes) {
      const decrypted = decrypt(req.body.aes, serverId);
      if (decrypted) {
        // console.log("解密结果:", decrypted);
        // Merge decrypted params into body
        Object.assign(req.body, decrypted);
        delete req.body.aes;
      }
    }

    next();
  } catch (err) {
    Logger.error('Decryption middleware error:', err);
    // If decryption fails, we continue.
    // Routes expecting specific params will handle missing params errors.
    next();
  }
};

function decrypt(ciphertextBase64, serverId) {
  try {
    const normalizedInput = String(ciphertextBase64 || '')
      .trim()
      .replace(/ /g, '+')
      .replace(/-/g, '+')
      .replace(/_/g, '/');

    const paddedInput = normalizedInput.length % 4 === 0 ? normalizedInput : normalizedInput + '='.repeat(4 - (normalizedInput.length % 4));

    // Key derivation: SHA-256 hash of serverId
    const key = crypto.createHash('sha256').update(serverId).digest();

    const inputBuffer = Buffer.from(paddedInput, 'base64');

    // Extract IV (first 16 bytes)
    if (inputBuffer.length < 17) {
      return null;
    }

    const iv = inputBuffer.subarray(0, 16);
    const encrypted = inputBuffer.subarray(16);

    const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
    let decrypted = decipher.update(encrypted);
    decrypted = Buffer.concat([decrypted, decipher.final()]);

    return JSON.parse(decrypted.toString());
  } catch (e) {
    Logger.error('Decryption failed:', e.message);
    return null;
  }
}

module.exports = decryptMiddleware;
