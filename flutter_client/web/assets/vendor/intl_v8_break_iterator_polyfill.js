/**
 * Flutter Web 3.41+ 在 lib/web_ui 中于模块加载时调用 Intl.v8BreakIterator（仅 Chromium 提供）。
 * Safari / WebKit 无该 API，会抛出 UnimplementedError 导致白屏。
 * 必须在 flutter_bootstrap.js 之前执行。
 *
 * 使用 Intl.Segmenter(grapheme) 做近似折行，与 Chrome 的 UAX#14 结果不完全一致，但可正常排版。
 */
(function () {
  if (typeof Intl === 'undefined') return;
  if (typeof Intl.v8BreakIterator === 'function') return;

  function isCjkCodePoint(cp) {
    if (cp === undefined) return false;
    return (
      (cp >= 0x4e00 && cp <= 0x9fff) ||
      (cp >= 0x3400 && cp <= 0x4dbf) ||
      (cp >= 0x20000 && cp <= 0x2a6df) ||
      (cp >= 0x3000 && cp <= 0x303f)
    );
  }

  function firstCodePoint(s) {
    if (!s) return undefined;
    return s.codePointAt(0);
  }

  function lineBreakEndIndices(str) {
    if (!str) return [];
    const ends = [];
    function pushEnd(e) {
      if (e <= 0) return;
      if (ends.length === 0 || ends[ends.length - 1] !== e) ends.push(e);
    }

    if (typeof Intl.Segmenter === 'function') {
      try {
        const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
        const graphemes = [];
        for (const { segment, index } of seg.segment(str)) {
          graphemes.push({ i: index, s: segment });
        }
        for (let k = 0; k < graphemes.length - 1; k++) {
          const a = graphemes[k].s;
          const b = graphemes[k + 1].s;
          const end = graphemes[k].i + a.length;
          const ca = firstCodePoint(a);
          const cb = firstCodePoint(b);

          if (/\n|\r/.test(a)) {
            pushEnd(end);
            continue;
          }
          if (cb === 0x0a || cb === 0x0d) {
            pushEnd(end);
            continue;
          }
          if (a === ' ' || a === '\t' || a === '\f' || a === '\u200b') {
            pushEnd(end);
            continue;
          }
          if (a === '-') {
            pushEnd(end);
            continue;
          }
          if (ca !== undefined && cb !== undefined) {
            if (isCjkCodePoint(ca) && isCjkCodePoint(cb)) {
              pushEnd(end);
              continue;
            }
            if (isCjkCodePoint(ca) !== isCjkCodePoint(cb)) {
              pushEnd(end);
              continue;
            }
          }
        }
        pushEnd(str.length);
        return ends;
      } catch (err) {
        console.warn('[intl_v8_break_iterator_polyfill] Intl.Segmenter failed, using ASCII fallback', err);
      }
    }

    for (let i = 0; i < str.length; i++) {
      const c = str.charCodeAt(i);
      if (c === 0x0a || c === 0x0d) {
        let j = i + 1;
        if (c === 0x0d && str.charCodeAt(i + 1) === 0x0a) j++;
        pushEnd(j);
        i = j - 1;
        continue;
      }
      if (c === 0x20 || c === 0x09) pushEnd(i + 1);
      if (c === 0x2d) pushEnd(i + 1);
    }
    pushEnd(str.length);
    return ends;
  }

  function V8LineBreakIterator() {
    this._text = '';
    this._ends = [];
    this._cursor = 0;
  }

  V8LineBreakIterator.prototype.adoptText = function (text) {
    this._text = text != null ? String(text) : '';
    this._ends = lineBreakEndIndices(this._text);
    this._cursor = 0;
  };

  V8LineBreakIterator.prototype.first = function () {
    this._cursor = 0;
    return 0;
  };

  V8LineBreakIterator.prototype.next = function () {
    if (!this._ends.length) return -1;
    if (this._cursor >= this._ends.length) return -1;
    const v = this._ends[this._cursor];
    this._cursor++;
    return v;
  };

  V8LineBreakIterator.prototype.current = function () {
    if (this._cursor === 0) return 0;
    return this._ends[this._cursor - 1];
  };

  V8LineBreakIterator.prototype.breakType = function () {
    return 'soft';
  };

  Intl.v8BreakIterator = function () {
    return new V8LineBreakIterator();
  };
})();
