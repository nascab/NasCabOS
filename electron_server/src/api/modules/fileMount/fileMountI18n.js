const { getLocalizedMessage } = require('../../../utils/i18nUtil');

function ensureString(v) {
  if (v === undefined || v === null) return '';
  return String(v);
}

/**
 * 将 DB 中 last_error（fileMount.*|detail 或旧文本）转为界面展示文案
 */
function localizeFileMountLastError(req, lastErrorRaw) {
  const raw = ensureString(lastErrorRaw).trim();
  if (!raw) return '';
  if (raw === 'fileMount.RCLONE_UNKNOWN') {
    return getLocalizedMessage(req, 'fileMount.RCLONE_UNKNOWN_BRIEF');
  }

  const pipe = raw.indexOf('|');
  if (pipe > 0) {
    const code = raw.slice(0, pipe).trim();
    const rest = raw.slice(pipe + 1);
    const parts = rest.split('|').map(p => p.trim()).filter(Boolean);
    if (code.startsWith('fileMount.') || code.startsWith('common.')) {
      const args = parts.map(part => {
        if (part.startsWith('fileMount.') || part.startsWith('common.')) {
          return getLocalizedMessage(req, part);
        }
        return part;
      });
      return getLocalizedMessage(req, code, args);
    }
  }

  if (raw.startsWith('fileMount.') || raw.startsWith('common.')) {
    return getLocalizedMessage(req, raw);
  }
  return raw;
}

module.exports = { localizeFileMountLastError };
