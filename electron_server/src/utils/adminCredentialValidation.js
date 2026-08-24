/**
 * 管理员账号/密码复杂度校验（与 createSuperAdmin 接口规则一致）
 * 用于 IPC 修改管理员、前端预校验等，错误码与 HTTP API validation 对齐便于国际化
 */

function isAllSameChar(text) {
  return typeof text === 'string' && text.length > 1 && /^(.)\1+$/.test(text);
}

function isConsecutiveDigits(text) {
  if (typeof text !== 'string') return false;
  if (text.length < 3) return false;
  if (!/^\d+$/.test(text)) return false;
  let dir = 0;
  for (let i = 1; i < text.length; i += 1) {
    const diff = Number(text[i]) - Number(text[i - 1]);
    if (diff !== 1 && diff !== -1) return false;
    if (dir === 0) dir = diff;
    else if (diff !== dir) return false;
  }
  return true;
}

/**
 * 校验用户名（与 createSuperAdmin 一致：3-20 位，仅字母数字下划线）
 * @param {string} username
 * @returns {{ valid: true } | { valid: false, error: string }}
 */
function validateUsername(username) {
  if (username === undefined || username === null) {
    return { valid: false, error: 'USERNAME_REQUIRED' };
  }
  const s = String(username).trim();
  if (!s) return { valid: false, error: 'USERNAME_REQUIRED' };
  if (s.length < 3 || s.length > 20) return { valid: false, error: 'USERNAME_LENGTH_INVALID' };
  if (!/^[a-zA-Z0-9_]+$/.test(s)) return { valid: false, error: 'USERNAME_FORMAT_INVALID' };
  return { valid: true };
}

/**
 * 校验密码（与 createSuperAdmin 一致：至少 6 位，非全同字符、非连续数字、不与用户名/密保答案相同）
 * @param {string} passwordPlain - 明文密码
 * @param {{ username?: string, answer?: string }} options - 可选，用于校验不能与用户名/密保答案相同
 * @returns {{ valid: true } | { valid: false, error: string }}
 */
function validatePassword(passwordPlain, options = {}) {
  if (passwordPlain === undefined || passwordPlain === null) {
    return { valid: false, error: 'PASSWORD_REQUIRED' };
  }
  const p = String(passwordPlain);
  if (!p) return { valid: false, error: 'PASSWORD_REQUIRED' };
  if (p.length < 6) return { valid: false, error: 'PASSWORD_TOO_SHORT' };
  if (isAllSameChar(p)) return { valid: false, error: 'validation.PASSWORD_REPEATED_CHAR' };
  if (isConsecutiveDigits(p)) return { valid: false, error: 'validation.PASSWORD_CONSECUTIVE_NUMBERS' };
  const username = options.username !== undefined ? String(options.username).trim() : '';
  if (username && p === username) return { valid: false, error: 'validation.PASSWORD_SAME_AS_USERNAME' };
  const answer = options.answer !== undefined ? String(options.answer).trim() : '';
  if (answer && p === answer) return { valid: false, error: 'validation.PASSWORD_SAME_AS_SECURITY_ANSWER' };
  return { valid: true };
}

module.exports = {
  isAllSameChar,
  isConsecutiveDigits,
  validateUsername,
  validatePassword,
};
