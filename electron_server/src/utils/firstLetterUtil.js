let pinyinPro;
try {
  pinyinPro = require('pinyin-pro');
} catch (_) {
  pinyinPro = null;
}

function _getPinyinFirstLetterChar(ch) {
  if (!pinyinPro) return '';
  try {
    const { firstLetter, pinyin } = pinyinPro;
    if (typeof firstLetter === 'function') {
      const fl = firstLetter(String(ch || ''), { toneType: 'none' });
      const c = Array.from(String(fl || '').trim())[0] || '';
      if (/[a-z]/i.test(c)) return c.toUpperCase();
    }
    if (typeof pinyin === 'function') {
      const fl = pinyin(String(ch || ''), { toneType: 'none', pattern: 'first', multiple: false });
      const c = Array.from(String(fl || '').trim())[0] || '';
      if (/[a-z]/i.test(c)) return c.toUpperCase();
    }
  } catch (_) {
    return '';
  }
  return '';
}

function getFirstLetter(input) {
  const s = input === undefined || input === null ? '' : String(input).trim();
  if (!s) return '#';
  const first = Array.from(s)[0] || '';
  if (!first) return '#';
  if (/[a-z]/i.test(first)) return first.toUpperCase();
  if (/[0-9]/.test(first)) return '#';
  const py = _getPinyinFirstLetterChar(first);
  if (py) return py;
  return '#';
}

module.exports = {
  getFirstLetter,
};
